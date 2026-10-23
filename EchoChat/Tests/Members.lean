/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import EchoChat.Presentation
import GroupChatClient.GroupChatKatzenqt1.Shell
import EchoChat.Tests.App
import GroupChatClient.GroupChatKatzenqt1.Sim

/-! # Two members, each with a window

Alice and Bob in one process over the simulated Pigeonhole, each with a `Shell`, as echo-chat runs
it, and an echo-chat window driven by clicks and typing. What each shell displays reaches its window as
the producer's messages do, through `Runtime.results`. The shells run on real time, so this takes
a while. -/

namespace EchoChat.Tests.Members

open EchoChat EchoChat.Tests Paw Logger
open GroupChatClient GroupChatClient.GroupChatKatzenqt1

/-- Calls to `b` one at a time, as the daemon takes them. -/
def serialized (b : Backend) : IO Backend := do
  let m ← Std.BaseMutex.new
  let one {α : Type} (x : IO α) : IO α := do m.lock; try x finally m.unlock
  return { b with
    newKeypair := one b.newKeypair
    writeBox := fun wc i p => one (b.writeBox wc i p)
    readBox := fun rc i => one (b.readBox rc i)
    nextIndex := fun i => one (b.nextIndex i)
    voucherMint := fun wc n => one (b.voucherMint wc n)
    voucherDeriveStream := fun v => one (b.voucherDeriveStream v)
    voucherInduct := fun v p w => one (b.voucherInduct v p w)
    voucherOpen := fun s r w => one (b.voucherOpen s r w)
    replicaEpoch := one b.replicaEpoch
    maxPlaintext := one b.maxPlaintext }

def memberApp (sh : Shell) (me : String) : Paw.App App.caps :=
  App.app sh.post AppTests.fakeAudio { state := { me }, network := "sim" }

structure Member where
  me : String
  shell : Shell
  latest : IO.Ref State
  rt : IO.Ref (Runtime (memberApp shell me))
  now : IO.Ref Nat
  clipboard : IO.Ref (List String)

def start (backend : Backend) (me : String) (dir : System.FilePath) (log : Logger) (stop : IO.Ref Bool) :
    IO Member := do
  let latest ← IO.mkRef ({ me } : State)
  let (core, resumed) := resume presentation { me } (← backend.maxPlaintext)
  let shell : Shell :=
    { backend, core := ← IO.mkRef core, inbox := ← Std.CloseableChannel.new,
      log := log.withModule s!"echo-chat/{me}", statePath := dir / s!"{me}.cbor",
      display := latest.set, stop, app := "echo-chat" }
  shell.start resumed
  let rt := (Paw.Runtime.start (memberApp shell me) (Rect.ofXYWH 0 0 (px 1000) (px 700)) 0 Env.mock.measure).1
  return { me, shell, latest, rt := ← IO.mkRef rt, now := ← IO.mkRef 0, clipboard := ← IO.mkRef [] }

namespace Member

/-- Carry out what a step asked: run its tasks, which post to the shell, and keep what it copied. -/
partial def carry (m : Member) (outs : List (Output (memberApp m.shell m.me).Msg)) : IO Unit := do
  for o in outs do
    match o with
    | .task io =>
      let msg ← io
      let (rt, outs) := (← m.rt.get).taskResult msg (← m.now.get)
      m.rt.set rt
      carry m outs
    | .request (.setClipboard t) => m.clipboard.modify (· ++ [t.text])
    | _ => pure ()

def advance (m : Member) (dt : Nat) : IO Nat := m.now.modifyGet fun t => (t + dt, t + dt)

/-- The shell's latest state, to the window. -/
def refresh (m : Member) : IO Unit := do
  let now ← m.advance 50
  let (rt, outs) := (← m.rt.get).results [App.Msg.state (← m.latest.get)] now
  m.rt.set rt
  m.carry outs

def input (m : Member) (k : InputKind) (dt : Nat := 600) : IO Unit := do
  let now ← m.advance dt
  let (rt, outs) := (← m.rt.get).step (.input { kind := k, time := now }) now
  m.rt.set rt
  m.carry outs

def click (m : Member) (key : String) : IO Unit := do
  let p := match (← m.rt.get).tree.findKey? key with
    | some n => (⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩ : Point)
    | none => ⟨-1, -1⟩
  m.input (.press p .primary)
  m.input (.release p .primary) 50

def typeText (m : Member) (s : String) : IO Unit := m.input (.text s)

def model (m : Member) : IO App.Model := return (← m.rt.get).model

/-- The texts the widget keyed `key` draws. -/
def texts (m : Member) (key : String) : IO (List String) := do
  let rt ← m.rt.get
  return match rt.tree.findKey? key with
    | some n => (n.render rt.env).items.filterMap fun
        | (_, .text _ t _) => some t.text
        | _ => none
    | none => []

end Member

/-- Refresh both windows until `p` holds, up to `deadline` (monotonic ms). -/
partial def waitFor (ms : List Member) (deadline : Nat) (p : IO Bool) : IO Bool := do
  for m in ms do m.refresh
  if ← p then return true
  if (← IO.monoMsNow) > deadline then return false
  IO.sleep 200
  waitFor ms deadline p

def lineOf (m : Member) (text : String) : IO (Option (List String)) := do
  let some c := (← m.model).current | return none
  let some l := c.log.find? (·.text == text) | return none
  return some (← m.texts s!"line:{l.id}")

def tests : TestM Unit := do
  let world ← IO.mkRef ({} : Sim.World)
  let backend ← serialized (Sim.backend world)
  let dir : System.FilePath := ".lake/echo-chat-members"
  IO.FS.createDirAll dir
  for f in ["alice.cbor", "bob.cbor"] do
    try IO.FS.removeFile (dir / f) catch _ => pure ()
  let log ← Logger.new .stderr .warning
  let stop ← IO.mkRef false
  let alice ← start backend "alice" dir log stop
  let bob ← start backend "bob" dir log stop
  let both := [alice, bob]
  let deadline := (← IO.monoMsNow) + 300000
  let wait (what : String) (p : IO Bool) : TestM Bool := do
    let ok ← waitFor both deadline p
    check what ok
    return ok
  let run : TestM Unit := do
    alice.click "new-group"
    alice.click "dialog-field"
    alice.typeText "g"
    alice.click "accept"
    let founded : IO Bool := do return (← alice.model).current.any fun (c : Chat) => c.group.isSome
    unless ← wait "alice founds a group" founded do return
    bob.click "join-group"
    bob.click "dialog-field"
    bob.typeText "g"
    bob.click "accept"
    let shown : IO Bool := do return !(← bob.texts "voucher-code").isEmpty
    unless ← wait "bob's window shows a voucher code" shown do return
    bob.click "copy-voucher"
    let some code := (← bob.clipboard.get).getLast? | check "Copy gives the voucher code" false
    check "Copy gives the voucher code" (code.length > 8)
    alice.click "invite"
    alice.click "dialog-field"
    alice.typeText code
    alice.click "accept"
    let joined : IO Bool := do
      return (← bob.model).current.any (fun (c : Chat) => c.group.isSome) &&
        (← alice.texts "inner").any (· == "~bob")
    unless ← wait "bob joins, and alice lists him" joined do return
    bob.click "draft"
    bob.typeText "hello from bob"
    bob.click "send"
    alice.click "draft"
    alice.typeText "hello from alice"
    alice.click "send"
    discard <| wait "alice reads bob" do return (← lineOf alice "hello from bob").any (·.head? == some "hello from bob")
    discard <| wait "bob reads alice" do return (← lineOf bob "hello from alice").any (·.head? == some "hello from alice")
    discard <| wait "alice's message is written: ✓" do
      return (← lineOf alice "hello from alice").any (· == ["hello from alice", "✓"])
    bob.click "draft"
    bob.typeText "bob read you"
    bob.click "send"
    discard <| wait "bob's next message acknowledges it: ✓✓" do
      return (← lineOf alice "hello from alice").any (· == ["hello from alice", "✓✓"])
  try run finally
    stop.set true
    for m in both do discard <| m.shell.inbox.close

end EchoChat.Tests.Members
