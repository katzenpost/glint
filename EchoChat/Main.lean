/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Linux
import EchoChat.App
import EchoChat.Presentation
import GroupChatClient.LogPane
import GroupChatClient.GroupChatKatzenqt1.Daemon
import GroupChatClient.GroupChatKatzenqt1.Shell

/-! # echo-chat

A desktop group chat over the Katzenpost mixnet that speaks katzenqt's group chat. -/

open EchoChat Logger
open GroupChatClient.GroupChatKatzenqt1.Persist
open GroupChatClient GroupChatClient.GroupChatKatzenqt1

structure Config where
  /-- The daemon's socket: a path, `@name` for an abstract one, or `HOST:PORT` over TCP. -/
  daemon : String := "@katzenpost"
  stateDir : Option System.FilePath := none
  logFile : Option System.FilePath := none
  name : Option String := none
  /-- Show the saved state, without a daemon. -/
  offline : Bool := false

def usage : String :=
  "usage: echo-chat [--daemon @katzenpost | PATH | HOST:PORT] [--state DIR] [--name NAME] [--log FILE] [--offline]
The state directory is $XDG_DATA_HOME/echo-chat/$ECHO_CHAT_STATE (default: default).
The log level is ECHO_CHAT_LOG: critical, error, warning, notice, info (the default) or debug."

def parseArgs : Config → List String → Except String Config
  | c, [] => pure c
  | c, "--daemon" :: d :: rest => parseArgs { c with daemon := d } rest
  | c, "--state" :: d :: rest => parseArgs { c with stateDir := some d } rest
  | c, "--log" :: f :: rest => parseArgs { c with logFile := some f } rest
  | c, "--name" :: n :: rest => parseArgs { c with name := some n } rest
  | c, "--offline" :: rest => parseArgs { c with offline := true } rest
  | _, a :: _ => throw s!"unknown argument: {a}"

def defaultStateDir : IO System.FilePath := do
  let base ← match ← IO.getEnv "XDG_DATA_HOME" with
    | some d => pure (d : System.FilePath)
    | none => pure ((← IO.getEnv "HOME").getD "." / ".local" / "share")
  -- echo-chat was called glint before; a state kept under the old name moves over, once.
  let old := base / "glint"
  if !(← (base / "echo-chat").pathExists) && (← old.pathExists) then
    IO.FS.rename old (base / "echo-chat")
  pure (base / "echo-chat" / ((← IO.getEnv "ECHO_CHAT_STATE").getD "default"))

def connect (daemon : String) : IO ThinClient.Client := do
  let dial ← if daemon.startsWith "@" || daemon.startsWith "/" then
      pure (ThinClient.Client.connectUnix daemon)
    else
      match daemon.splitOn ":" with
      | [host, port] =>
        let some addr := Std.Net.IPv4Addr.ofString host
          | throw (IO.userError s!"not an IPv4 address: {host}")
        pure (ThinClient.Client.connect (.v4 addr) port.toNat!.toUInt16)
      | _ => throw (IO.userError s!"not a socket or HOST:PORT: {daemon}")
  match ← dial.run.block with
  | .ok c => pure c
  | .error e => throw (IO.userError s!"connecting to the daemon at {daemon}: {e}")

/-- This machine's time zone now, in seconds from UTC. -/
def localZone : IO Int := do
  try
    let rules ← Std.Time.Database.defaultGetLocalZoneRules
    return (rules.timezoneAt (← Std.Time.Timestamp.now)).offset.second.val
  catch _ => return 0

def onSignals (log : Logger) : IO Unit := do
  for (sig, n) in [(Std.Async.Signal.sigterm, 15), (.sighup, 1), (.sigquit, 3)] do
    let w ← Std.Async.Signal.Waiter.mk sig false
    let t ← w.wait
    discard <| IO.asTask (prio := .dedicated) do
      discard <| IO.wait t
      log.notice s!"stopped by signal {n}"
      (IO.Process.exit (128 + n).toUInt8 : IO Unit)

/-- Hand the window the latest state at most every `ms` milliseconds, however often it changes.
Once `post` throws, as it does after the window closes, it stops. -/
def coalesce (post : State → IO Unit) (stop : IO.Ref Bool) (ms : UInt32 := 33) :
    IO (State → IO Unit) := do
  let latest ← IO.mkRef (none : Option State)
  discard <| IO.asTask (prio := .dedicated) do
    while !(← stop.get) do
      IO.sleep ms
      if let some s ← latest.modifyGet (·, none) then post s
  return fun s => latest.set (some s)

/-- One line per step for the end-to-end tests: groups, their lines, and what is open. -/
def describe (m : App.Model) : String :=
  let chats := m.state.chats.map fun c =>
    let lines := c.log.map fun l =>
      let who := if l.sender.size == 0 then "—" else (Display.who m.state.me c l.sender).text
      s!"{who}{App.markOf c l}:{(l.text.replace "\n" "|")}"
    let code := (App.Model.voucher? c).getD ""
    s!"{c.name}[joined={c.group.isSome} code={code} members={(c.group.map (·.readers.size)).getD 0} lines={lines}]"
  let voice := match m.voice with
    | .idle => "idle"
    | .starting .. => "starting"
    | .recording .. => "recording"
    | .stopping _ => "stopping"
    | .draft _ clip => s!"draft:{clip.durationMs}"
  s!"selected={m.selected.getD ""} dialog={(m.dialog.map (repr ·.kind)).getD (repr "")} draft={m.draft.replace "\n" "|"} voice={voice} playing={m.playing.isSome} chats={chats}"

def main (args : List String) : IO UInt32 := do
  try run args
  catch e =>
    IO.eprintln (Display.logLine (toString e))
    return 1
where
  run (args : List String) : IO UInt32 := do
  let cfg ← match parseArgs {} args with
    | .ok c => pure c
    | .error e => IO.eprintln s!"{e}\n{usage}"; return 2
  let dir ← match cfg.stateDir with
    | some d => pure d
    | none => defaultStateDir
  IO.FS.createDirAll dir
  IO.setAccessRights dir { user := { read := true, write := true, execution := true } }
  let logPath := cfg.logFile.getD (dir / "echo-chat.log")
  let logFile ← Logger.Output.open (.file logPath)
  IO.setAccessRights logPath GroupChatClient.private_
  let logLines ← IO.mkRef (#[] : Array String)
  -- The pane shows the log once the window is up; until then lines only go to the file.
  let showLogs ← IO.mkRef (fun (_ : Array String) => (pure () : IO Unit))
  let log ← Logger.new (.stream (LogPane.stream Display.logLine logFile logLines fun ls => do (← showLogs.get) ls))
    (← Level.fromEnv "ECHO_CHAT_LOG" .info) "echo-chat"
  let statePath := dir / "state.cbor"
  let saved : Option State ← if ← statePath.pathExists then
      pure (load (← IO.FS.readBinFile statePath))
    else pure none
  if (← statePath.pathExists) && saved.isNone then
    IO.eprintln s!"{statePath} cannot be read"; return 1
  let me := cfg.name.getD ((saved.map (·.me)).getD ((← IO.getEnv "USER").getD "me"))
  let state := { (saved.getD { me }) with me }
  onSignals log
  let title := "echo-chat"
  let dark := (← IO.getEnv "PAW_THEME") != some "light"
  let zone ← localZone
  let home := (← IO.getEnv "HOME").getD dir.toString
  let downloads := System.FilePath.mk home / "Downloads"
  let downloads := if ← downloads.isDir then downloads.toString else home
  let base : App.Model := { state, dark, zone, stateDir := dir, home, downloads }
  let audio ← Voice.Audio.open (dir / "audio" / "drafts")
  if let some why := audio.off then log.warning why
  if cfg.offline then
    let init := App.Model.take { base with network := "offline" } state
    try Paw.Linux.run (App.app (fun _ => pure ()) audio init) title 1000 700 describe
    finally audio.cancel
    IO.Process.exit 0
  IO.println s!"connecting to the client daemon at {cfg.daemon}"
  let client ← connect cfg.daemon
  let backend := Daemon.backend client
  log.notice s!"started as {me}, state in {dir}"
  let (core, resumed) := resume presentation state (← backend.maxPlaintext) (← wallMs)
  let stop ← IO.mkRef false
  let inbox ← Std.CloseableChannel.new (α := Msg)
  let post (m : Msg) : IO Unit := discard (inbox.send m)
  let producer (send : App.Msg → IO Unit) : IO Unit := do
    showLogs.set fun ls => try send (.logs ls) catch _ => pure ()
    let display ← coalesce (send ∘ .state) stop
    let sh : Shell := { backend, core := ← IO.mkRef core, inbox, log, statePath, display, stop, app := "echo-chat" }
    sh.start resumed
  let logs ← logLines.get
  let network := s!"daemon {cfg.daemon}"
  let init := App.Model.take { base with state := core.state, network, logs } core.state
  try
    Paw.Linux.run (App.app post audio init [.producer producer (by decide)]) title 1000 700 describe
  finally
    audio.cancel
    showLogs.set fun _ => pure ()
    stop.set true
    discard <| inbox.close
    discard <| (client.close false).block
  log.notice "stopped"
  -- Tasks still blocked in daemon calls would keep the process alive.
  IO.Process.exit 0
