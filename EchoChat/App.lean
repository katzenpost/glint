/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw
import EchoChat.Command
import EchoChat.Display
import EchoChat.Disk
import EchoChat.Voice

/-! # The window

The groups on the left, the selected conversation in the middle, and on the right everyone who
reads what is written there, each with the start of their key. Below, a status row, and the log
when F2 shows it.

echo-chat, not the sender, decides what each part of the window says:

- Text from elsewhere reaches a widget only through `EchoChat.Display`.
- A member is named `me` or `~name`; a name that could be taken for another's also shows the start
  of its key. Delivery marks sit in a column of their own, and a name cannot hold them.
- A run of messages begins with a header echo-chat draws, the sender in bold and flush left; every row
  of a message is indented under it in regular weight, so none can pass for a header. echo-chat's own
  notices are small, muted and centered, as no message is.
- The message box only sends text. Everything else is a button, and what uses authority (a dialog,
  copying, reading or writing a file) happens only for the user's own click. The window's title is
  always "echo-chat".
- A file is read only once the user chose it and clicked Send, and one received is written out only
  where they chose to save it; a picture received is shown from echo-chat's own copy.
- The microphone records only while the user holds the Hold to talk button or Ctrl+Space, and what
  it recorded is sent only once they click Send. -/

namespace EchoChat.App

open Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1
open Cryptlib.Protocols.GroupComm.Common
open Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member

abbrev caps : List Cap := [.clipboardWrite, .io]

inductive DialogKind
  | newGroup
  | join
  | invite
  | remove
  | leave
  | clear
  | rename
  /-- Choose a file to send. -/
  | attach
  /-- Choose where to save a line's file. -/
  | save
  /-- A line's picture, large. -/
  | view
  deriving BEq, Repr, Inhabited

structure Dialog where
  kind : DialogKind
  modal : Modal
  /-- The group it is about. -/
  chat : Option String := none
  field : String := ""
  /-- The member chosen, by the hex of their key; or the entry of the folder shown. -/
  pick : Option String := none
  note : String := ""
  /-- The folder shown, and what it holds. -/
  dir : String := ""
  entries : List Disk.Entry := []
  /-- The line whose file it is about. -/
  line : Option Nat := none
  deriving BEq

/-- A voice note being recorded, or recorded and not yet sent, for a group. -/
inductive Recording
  | idle
  /-- Asked to start; `released` once let go before it had. -/
  | starting (chat : String) (released : Bool)
  | recording (chat : String) (since : Nat)
  | stopping (chat : String)
  | draft (chat : String) (clip : RusticAudio.Clip)
  deriving BEq, Inhabited

def Recording.chat? : Recording → Option String
  | .idle => none
  | .starting c _ | .recording c _ | .stopping c | .draft c _ => some c

/-- The same, for the group `old` renamed `new`. -/
def Recording.rename (r : Recording) (old new : String) : Recording :=
  let n (c : String) := if c == old then new else c
  match r with
  | .idle => .idle
  | .starting c released => .starting (n c) released
  | .recording c since => .recording (n c) since
  | .stopping c => .stopping (n c)
  | .draft c clip => .draft (n c) clip

/-- A picture a line carries, as far as it has been read. -/
inductive Picture
  | loading
  | shown (img : Image)
  | refused (why : String)
  deriving BEq

inductive Msg
  /-- The core's state, from the shell. -/
  | state (s : State)
  | logs (lines : Array String)
  | select (chat : String)
  | draft (s : String)
  | send
  | scan
  | ask (d : DialogKind)
  | field (s : String)
  | pick (key : String)
  | confirm
  | dismiss
  | copyVoucher
  | toggleLog
  | toggleBlank
  /-- The share of the groups pane, or of the conversation beside the members. -/
  | ratio (outer : Bool) (n : Nat)
  | next (forward : Bool)
  | quit
  /-- A message reached the core. -/
  | posted
  | browse (dir : String)
  | listed (dir : String) (entries : Except String (List Disk.Entry))
  /-- An entry of the folder shown, clicked. -/
  | entry (e : Disk.Entry)
  /-- The folder above the one shown. -/
  | up
  | fileRead (chat : String) (r : Except String (String × ByteArray))
  | saveAs (line : Nat)
  | view (line : Nat)
  | saved (r : Except String String)
  | picture (file : String) (r : Except Disk.Unshown Image)
  /-- The Hold to talk button or Ctrl+Space, pressed and let go. -/
  | holdStart
  | holdEnd
  /-- Recording began, at this time. -/
  | started (r : Except String Nat)
  | captured (r : Except String RusticAudio.Clip)
  | playDraft
  | discardDraft
  | sendDraft
  | voiceRead (chat : String) (r : Except String (String × ByteArray))
  /-- Play the voice note a line carries. -/
  | playLine (line : Nat)
  | playStarted (path : String) (r : Except String Unit)
  | stopPlay
  | poll
  | polled (now : Nat) (playing : Bool) (error : Option String)
  | audioDone (r : Except String Unit)

structure Model where
  state : State
  /-- How many states have arrived, so that a new one is a change. -/
  version : Nat := 0
  selected : Option String := none
  /-- Lines of each conversation seen, for unread counts. -/
  seen : List (String × Nat) := []
  logs : Array String := #[]
  showLog : Bool := false
  /-- The window blanked, for someone looking over your shoulder. -/
  blank : Bool := false
  draft : String := ""
  note : String := ""
  /-- A group asked for, to select once it appears. -/
  want : Option String := none
  dialog : Option Dialog := none
  outer : Nat := 220
  inner : Nat := 760
  /-- What echo-chat is connected to. -/
  network : String := ""
  /-- The dark theme, echo-chat's own default; the light one only when asked for. -/
  dark : Bool := true
  /-- The local time zone, in seconds from UTC, for showing when lines were said. -/
  zone : Int := 0
  /-- Where the core keeps its files, and where to look for files to send and save them. -/
  stateDir : System.FilePath := "."
  home : String := "."
  downloads : String := "."
  /-- The folder a file was last sent from. -/
  lastDir : Option String := none
  /-- The pictures lines carry, by their file. -/
  pictures : List (String × Picture) := []
  voice : Recording := .idle
  /-- The voice note playing, by its path. -/
  playing : Option String := none
  /-- The time of the last poll of the sound system, in milliseconds. -/
  clock : Nat := 0
  /-- Why there is no sound, when there is none. -/
  soundOff : Option String := none
  deriving Inhabited

instance : BEq Model where
  beq a b := a.version == b.version && a.selected == b.selected && a.seen == b.seen &&
    a.logs == b.logs && a.showLog == b.showLog && a.blank == b.blank && a.draft == b.draft &&
    a.note == b.note && a.want == b.want && a.dialog == b.dialog && a.outer == b.outer &&
    a.inner == b.inner && a.network == b.network && a.dark == b.dark && a.zone == b.zone &&
    a.lastDir == b.lastDir && a.pictures == b.pictures && a.voice == b.voice &&
    a.playing == b.playing && a.clock == b.clock && a.soundOff == b.soundOff

namespace Model

def current (m : Model) : Option Chat := m.selected.bind m.state.chat?

/-- Count the selected conversation as read. -/
def markSeen (m : Model) : Model :=
  match m.current with
  | some c => { m with seen := (c.name, c.log.length) :: m.seen.filter (·.1 != c.name) }
  | none => m

/-- Take a new state: keep the selection while its group exists, and select a group asked for
once it appears. -/
def take (m : Model) (s : State) : Model :=
  let has (n : String) := s.chats.any (·.name == n)
  let selected := match m.want with
    | some w => if has w then some w else m.selected
    | none => m.selected
  let selected := (selected.filter has).orElse fun _ => s.chats.head?.map (·.name)
  markSeen { m with state := s, version := m.version + 1, selected,
                    want := m.want.filter (!has ·) }

/-- Keep what is kept of the group `old` for it as `new`. -/
def rename (m : Model) (old new : String) : Model :=
  { m with seen := m.seen.map fun (c, n) => (if c == old then new else c, n),
           voice := m.voice.rename old new }

def voucher? (c : Chat) : Option String :=
  match c.joining with
  | some (.awaiting code ..) => some code
  | _ => none

/-- A line of the selected group, by id. -/
def line? (m : Model) (id : Nat) : Option Line := m.current.bind (·.log.find? (·.id == id))

def pictureOf (m : Model) (a : Attachment) : Option Picture := m.pictures.lookup a.file

def isPicture (a : Attachment) : Bool := Files.isImage a.filetype a.name

def isVoice (a : Attachment) : Bool := Voice.isVoice a.filetype

/-- The member of the selected group whose key is `hex`. -/
def memberByHex (m : Model) (hex : String) : Option Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member.Key :=
  (m.current.bind (·.group)).bind fun g => g.readers.keys.find? (Display.hex · == hex)

end Model

/-- What the core is asked, and echo-chat's note on it; the message goes to the core on a task. -/
def perform {o : Origin} (post : GroupChatKatzenqt1.Msg → IO Unit) (a : Command.Asked) :
    UpdateM Model Msg caps o Unit := do
  modify fun (m, cs) => ({ m with note := a.note, want := a.want.orElse fun _ => m.want }, cs)
  if let some msg := a.msg then emit (.task (do post msg; pure .posted) (by decide))

/-- What the open dialog asks for, when confirmed. -/
def confirmed (m : Model) (d : Dialog) : Command.Asked :=
  match d.kind with
  | .newGroup => Command.newGroup m.state d.field
  | .join => Command.joinGroup m.state d.field
  | .invite => Command.invite d.chat d.field
  | .leave => Command.leave d.chat d.field
  | .clear => Command.clear d.chat
  | .rename => Command.rename m.state d.chat d.field
  | .attach | .save | .view => {}
  | .remove => match d.pick.bind m.memberByHex with
    | some k => Command.remove m.state d.chat k
    | none => { note := "choose a member first" }

def needsGroup : DialogKind → Bool
  | .newGroup | .join => false
  | _ => true

def browse {o : Origin} (dir : String) : UpdateM Model Msg caps o Unit := do
  let home := (← get).1.home
  emit (.task (return .listed dir (← Disk.list (Disk.expand home dir))) (by decide))

/-- Read the pictures of the selected conversation not read yet. A file not there yet is tried
again with the next state. -/
def wantPictures {o : Origin} : UpdateM Model Msg caps o Unit := do
  let m := (← get).1
  let some c := m.current | return
  for l in c.log do
    let some a := l.attachment | continue
    if !Model.isPicture a || (m.pictureOf a).isSome then continue
    modify fun (m, cs) => ({ m with pictures := (a.file, .loading) :: m.pictures }, cs)
    let path := m.stateDir / a.file
    emit (.task (return .picture a.file (← Disk.picture path)) (by decide))

def attempt {α : Type} (io : IO α) : IO (Except String α) := do
  try return .ok (← io) catch e => return .error (toString e)

def note {o : Origin} (s : String) : UpdateM Model Msg caps o Unit :=
  modify fun (m, cs) => ({ m with note := s }, cs)

def stopRecording {o : Origin} (audio : Voice.Audio) (chat : String) : UpdateM Model Msg caps o Unit := do
  modify fun (m, cs) => ({ m with voice := .stopping chat, note := "" }, cs)
  emit (.task (return .captured (← attempt audio.stop)) (by decide))

/-- Stop recording without keeping it, as when another group is selected. -/
def cancelRecording {o : Origin} (audio : Voice.Audio) : UpdateM Model Msg caps o Unit := do
  match (← get).1.voice with
  | .starting c _ => modify fun (m, cs) => ({ m with voice := .starting c true }, cs)
  | .recording .. =>
    modify fun (m, cs) => ({ m with voice := .idle, note := "" }, cs)
    emit (.task (return .audioDone (← attempt audio.cancel)) (by decide))
  | _ => pure ()

def play {o : Origin} (audio : Voice.Audio) (path : String) : UpdateM Model Msg caps o Unit :=
  emit (.task (return .playStarted path (← attempt (audio.play path))) (by decide))

/-- Whether the sound system is to be polled: while recording or playing. -/
def busy (m : Model) : Bool :=
  m.playing.isSome || match m.voice with | .recording .. => true | _ => false

def sendFile {o : Origin} (post : GroupChatKatzenqt1.Msg → IO Unit) (chat name : String) (bytes : ByteArray)
    (note : String) : UpdateM Model Msg caps o Unit :=
  perform post { msg := some (.sendFile chat name bytes), note }

/-- The path in the folder shown of the entry `name`. -/
def inDir (d : Dialog) (name : String) : String := (System.FilePath.mk d.dir / name).toString

def update (post : GroupChatKatzenqt1.Msg → IO Unit) (audio : Voice.Audio) :
    (o : Origin) → Msg → UpdateM Model Msg caps o Unit
  | _, .state s => do
    modify fun (m, cs) => (m.take s, cs)
    wantPictures
  | _, .logs lines => modify fun (m, cs) => ({ m with logs := lines }, cs)
  | _, .select chat => do
    if (← get).1.selected != some chat then cancelRecording audio
    modify fun (m, cs) =>
      if m.state.chats.any (·.name == chat) then ((({ m with selected := some chat } : Model)).markSeen, cs)
      else (m, cs)
    wantPictures
  | _, .next forward => do
    cancelRecording audio
    modify fun (m, cs) =>
      let names := m.state.chats.map (·.name)
      let n := names.length
      if n == 0 then (m, cs) else
      let i := ((m.selected.bind fun s => names.idxOf? s)).getD 0
      let j := if forward then (i + 1) % n else (i + n - 1) % n
      ((({ m with selected := names[j]? } : Model)).markSeen, cs)
    wantPictures
  | _, .draft s => modify fun (m, cs) => ({ m with draft := s }, cs)
  | _, .send => do
    let m := (← get).1
    let a := Command.send m.selected m.draft
    if a.msg.isSome then modify fun (m, cs) => ({ m with draft := "" }, cs)
    perform post a
  | _, .scan => do perform post (Command.scan (← get).1.selected)
  | .user d, .ask kind => do
    let m := (← get).1
    if needsGroup kind && m.current.isNone then
      modify fun (m, cs) => ({ m with note := "select a group first" }, cs)
      return
    let dir := m.lastDir.getD m.home
    let field := if kind == .rename then m.selected.getD "" else ""
    modify fun (m, cs) => ({ m with dialog := some { kind, modal := Modal.open d, chat := m.selected, dir, field } }, cs)
    if kind == .attach then browse dir
  | .other, .ask _ => pure ()
  | .user d, .saveAs id => do
    let m := (← get).1
    let some a := (m.line? id).bind (·.attachment) | return
    let dir := m.downloads
    let field := (System.FilePath.mk dir / a.name).toString
    let dialog : Dialog := { kind := .save, modal := Modal.open d, chat := m.selected, line := some id, dir, field }
    modify fun (m, cs) => ({ m with dialog := some dialog }, cs)
    browse dir
  | .other, .saveAs _ => pure ()
  | .user d, .view id => modify fun (m, cs) =>
    if ((m.line? id).bind (·.attachment)).isNone then (m, cs)
    else ({ m with dialog := some { kind := .view, modal := Modal.open d, chat := m.selected, line := some id } }, cs)
  | .other, .view _ => pure ()
  | _, .browse dir => browse dir
  | _, .listed dir r => modify fun (m, cs) =>
    let name := ((m.dialog.bind (·.line)).bind m.line? |>.bind (·.attachment)).map (·.name)
    ({ m with dialog := m.dialog.map fun d =>
        match r with
        | .ok entries =>
          let field := match d.kind, name with
            | .save, some n => (System.FilePath.mk dir / n).toString
            | _, _ => d.field
          { d with dir, entries, pick := none, note := "", field }
        | .error e => { d with note := Display.logLine e } }, cs)
  | _, .entry e => do
    let some d := (← get).1.dialog | return
    if e.dir then browse (inDir d e.name)
    else modify fun (m, cs) => ({ m with dialog := some { d with pick := some e.name, field := inDir d e.name } }, cs)
  | _, .up => do
    let some d := (← get).1.dialog | return
    let some parent := (System.FilePath.mk d.dir).parent | return
    browse parent.toString
  | _, .fileRead chat r => do
    let some d := (← get).1.dialog | return
    match r with
    | .ok (name, bytes) =>
      modify fun (m, cs) => ({ m with dialog := none, lastDir := some d.dir }, cs)
      sendFile post chat name bytes s!"sending {Files.safeName name}"
    | .error e => modify fun (m, cs) => ({ m with dialog := some { d with note := Display.logLine e } }, cs)
  | _, .saved r => modify fun (m, cs) =>
    match r with
    | .ok path => ({ m with dialog := none, note := s!"saved {path}" }, cs)
    | .error e => ({ m with dialog := m.dialog.map ({ · with note := Display.logLine e }) }, cs)
  | _, .picture file r => modify fun (m, cs) =>
    let rest := m.pictures.filter (·.1 != file)
    let pictures := match r with
      | .ok img => (file, .shown img) :: rest
      | .error .missing => rest
      | .error (.refused why) => (file, .refused why) :: rest
    ({ m with pictures }, cs)
  | _, .field s => modify fun (m, cs) => ({ m with dialog := m.dialog.map ({ · with field := s }) }, cs)
  | _, .pick k => modify fun (m, cs) => ({ m with dialog := m.dialog.map ({ · with pick := some k }) }, cs)
  | _, .confirm => do
    let m := (← get).1
    let some d := m.dialog | return
    match d.kind with
    | .attach =>
      let some chat := d.chat | return
      if d.field.trimAscii.isEmpty then
        modify fun (m, cs) => ({ m with dialog := some { d with note := "choose a file first" } }, cs)
        return
      let path := Disk.expand m.home d.field.trimAscii.toString
      emit (.task (return .fileRead chat (← Disk.readUpload path)) (by decide))
      return
    | .save =>
      let some a := (d.line.bind m.line?).bind (·.attachment) | return
      if d.field.trimAscii.isEmpty then
        modify fun (m, cs) => ({ m with dialog := some { d with note := "say where to save it" } }, cs)
        return
      let dst := Disk.expand m.home d.field.trimAscii.toString
      let src := m.stateDir / a.file
      emit (.task (return .saved ((← Disk.copyOut src dst).map fun _ => dst.toString)) (by decide))
      return
    | .view =>
      modify fun (m, cs) => ({ m with dialog := none }, cs)
      return
    | _ => pure ()
    let a := confirmed m d
    if a.msg.isNone then
      modify fun (m, cs) => ({ m with dialog := some { d with note := a.note } }, cs)
    else
      modify fun (m, cs) => ({ m with dialog := none }, cs)
      if let some (.rename old new) := a.msg then modify fun (m, cs) => (m.rename old new, cs)
      perform post a
  | _, .dismiss => modify fun (m, cs) => ({ m with dialog := none }, cs)
  | .user d, .copyVoucher => do
    let some code := (← get).1.current.bind Model.voucher? | return
    let e := Effect.setClipboard "copy-voucher" (SafeText.filter code)
    if h : e.DesignatedBy d then emit (.effect d e (by decide) h)
  | .other, .copyVoucher => pure ()
  | _, .toggleLog => modify fun (m, cs) => ({ m with showLog := !m.showLog }, cs)
  | _, .toggleBlank => modify fun (m, cs) => ({ m with blank := !m.blank }, cs)
  | _, .ratio outer n => modify fun (m, cs) =>
    let n := max 100 (min 900 n)
    (if outer then { m with outer := n } else { m with inner := n }, cs)
  | _, .quit => emit .quit
  | _, .posted => pure ()
  -- A press is not designated, as a click is; what is recorded leaves only with a click on Send.
  | _, .holdStart => do
    let m := (← get).1
    if m.dialog.isSome then return
    match m.voice with
    | .idle =>
      let some c := m.current | return
      if c.group.isNone then return
      if let some why := m.soundOff then note why; return
      modify fun (m, cs) => ({ m with voice := .starting c.name false, note := "" }, cs)
      emit (.task (return .started (← attempt (do audio.start; IO.monoMsNow))) (by decide))
    | .draft .. => note "send or discard the voice note first"
    | _ => pure ()
  | _, .holdEnd => do
    match (← get).1.voice with
    | .starting c _ => modify fun (m, cs) => ({ m with voice := .starting c true }, cs)
    | .recording c _ => stopRecording audio c
    | _ => pure ()
  | _, .started r => do
    match (← get).1.voice, r with
    | .starting c false, .ok t =>
      -- Recording stops whatever was playing.
      modify fun (m, cs) => ({ m with voice := .recording c t, clock := t, playing := none }, cs)
      emit (.after 250 .poll)
    | .starting _ true, .ok _ =>
      modify fun (m, cs) => ({ m with voice := .idle, note := "hold to record a voice note" }, cs)
      emit (.task (return .audioDone (← attempt audio.cancel)) (by decide))
    | .starting .., .error e => modify fun (m, cs) => ({ m with voice := .idle, note := Display.logLine e }, cs)
    | _, .ok _ => emit (.task (return .audioDone (← attempt audio.cancel)) (by decide))
    | _, .error _ => pure ()
  | _, .captured r => do
    let .stopping c := (← get).1.voice | return
    match r with
    | .ok clip =>
      if clip.durationMs < Voice.shortest then
        modify fun (m, cs) => ({ m with voice := .idle, note := "hold to record a voice note" }, cs)
        emit (.task (return .audioDone (← attempt (IO.FS.removeFile clip.path))) (by decide))
      else modify fun (m, cs) => ({ m with voice := .draft c clip }, cs)
    | .error e => modify fun (m, cs) => ({ m with voice := .idle, note := Display.logLine e }, cs)
  | .user _, .playDraft => do
    let .draft _ clip := (← get).1.voice | return
    play audio clip.path
  | .other, .playDraft => pure ()
  | _, .discardDraft => do
    let m := (← get).1
    let .draft _ clip := m.voice | return
    modify fun (m, cs) => ({ m with voice := .idle }, cs)
    if m.playing == some clip.path then
      modify fun (m, cs) => ({ m with playing := none }, cs)
      emit (.task (return .audioDone (← attempt audio.stopPlay)) (by decide))
    emit (.task (return .audioDone (← attempt (IO.FS.removeFile clip.path))) (by decide))
  | .user _, .sendDraft => do
    let m := (← get).1
    let .draft c clip := m.voice | return
    modify fun (m, cs) => ({ m with voice := .idle }, cs)
    if m.playing == some clip.path then
      modify fun (m, cs) => ({ m with playing := none }, cs)
      emit (.task (return .audioDone (← attempt audio.stopPlay)) (by decide))
    emit (.task (return .voiceRead c (← attempt do
      let bytes ← IO.FS.readBinFile clip.path
      IO.FS.removeFile clip.path
      return (Voice.nameOf bytes, bytes))) (by decide))
  | .other, .sendDraft => pure ()
  | _, .voiceRead chat r => match r with
    | .ok (name, bytes) => sendFile post chat name bytes "sending a voice note"
    | .error e => note (Display.logLine e)
  | .user _, .playLine id => do
    let m := (← get).1
    let some a := (m.line? id).bind (·.attachment) | return
    if Model.isVoice a then play audio (m.stateDir / a.file).toString
  | .other, .playLine _ => pure ()
  | _, .playStarted path r => match r with
    | .ok () => do
      let was := busy (← get).1
      modify fun (m, cs) => ({ m with playing := some path }, cs)
      if !was then emit (.after 250 .poll)
    | .error e => note (Display.logLine e)
  | _, .stopPlay => do
    modify fun (m, cs) => ({ m with playing := none }, cs)
    emit (.task (return .audioDone (← attempt audio.stopPlay)) (by decide))
  | _, .poll => do
    if busy (← get).1 then
      emit (.task (return .polled (← IO.monoMsNow) (← audio.playing) (← audio.error)) (by decide))
  | _, .polled now playing error => do
    modify fun (m, cs) => ({ m with clock := now, playing := if playing then m.playing else none }, cs)
    if let some e := error then note (Display.logLine e)
    if let .recording c since := (← get).1.voice then
      if now ≥ since + Voice.longest then stopRecording audio c
    if busy (← get).1 then emit (.after 250 .poll)
  | _, .audioDone r => match r with
    | .ok () => pure ()
    | .error e => note (Display.logLine e)

/-! ## The view

Spacing follows GNOME's steps of 6, 12 and 18 pixels: 6 within a group of controls, 12 between
things and around a pane, 18 between groups. -/

/-- Our mark on a line of ours: `…` until written, `✓` once written, `✓✓` once a member has
acknowledged it; nothing on another's. -/
def markOf (c : Chat) (l : Line) : String :=
  if !c.group.any (·.me == l.sender) then "" else match l.status with
    | .pending => "…"
    | .sent => if acknowledged c l then "✓✓" else "✓"

/-- The largest a picture is shown in a conversation, and in its own dialog. -/
def thumbW : Nat := 320
def thumbH : Nat := 240
def largeW : Nat := 760
def largeH : Nat := 480

/-- A file a message carries, as drawn: its picture, at the size shown, if it is one. -/
structure FileRow where
  line : Nat
  name : SafeText
  detail : String
  picture : Option (Image × Nat × Nat) := none
  /-- A voice note's, and whether it is playing. -/
  voice : Option Bool := none
  deriving BEq

/-- A message as drawn: its lines or its file, and our mark, so that one that did not change is
not built again. -/
structure MessageRow where
  lines : List SafeText
  mark : String
  file : Option FileRow := none
  deriving BEq, TypeName

def pictureView (img : Image) (w h : Nat) (name : SafeText) (key : String) : Node Msg :=
  Ui.width (px w) <| Ui.height (px h) <|
    Ui.image img (.text (SafeName.filter name.text)) .either (key := some key)

/-- A file: its picture, then its name, size and buttons. -/
def fileView (f : FileRow) : List (Node Msg) :=
  let picture := f.picture.toList.map fun (img, w, h) =>
    Ui.row [pictureView img w h f.name s!"picture:{f.line}", Ui.spacer]
  let viewButton := if f.picture.isSome then [Ui.flatButton "View" (.view f.line) s!"view:{f.line}"] else []
  let viewButton := match f.voice with
    | some true => [Ui.flatButton "Stop" .stopPlay s!"stop:{f.line}"]
    | some false => [Ui.flatButton "Play" (.playLine f.line) s!"play:{f.line}"]
    | none => viewButton
  picture ++ [Ui.row ([Ui.text f.name, Ui.text (SafeText.trusted f.detail) (tone := .muted) (size := .caption)] ++
    viewButton ++ [Ui.flatButton "Save…" (.saveAs f.line) s!"save:{f.line}", Ui.spacer]) (px 6)]

/-- Every row of a message is indented under its run's header and to the left of its mark, so no
row of it can pass for a header, which is bold and flush, or for a notice, which is centered. -/
def messageView (r : MessageRow) : Node Msg :=
  let body := match r.file with
    | some f => fileView f
    | none => r.lines.map fun t => Ui.text t (maxLines := 40)
  Ui.row [Ui.width (px 12) Ui.spacer, Ui.col (spacing := px 4) body, Ui.spacer,
    Ui.width (px 24) (Ui.caption (SafeText.trusted r.mark))] (px 6)

/-- A notice of echo-chat's as drawn. -/
structure NoticeRow where
  lines : List SafeText
  deriving BEq, TypeName

/-- echo-chat's own notice: small and muted, centered, as no message is. -/
def noticeView (r : NoticeRow) : Node Msg :=
  Ui.row [Ui.spacer, Ui.col (spacing := 0) (r.lines.map fun t =>
    Ui.text t (maxLines := 4) (tone := .muted) (size := .caption)), Ui.spacer]

/-- Who said a run of messages, bold, and when, muted. -/
def headerView (who : SafeText) (time : String) : Node Msg :=
  Ui.row [Ui.text who (overflow := .ellipsis) (bold := true), Ui.caption (SafeText.trusted time)] (px 6)

/-- A line between regions, a pixel thick. -/
def rule : Node Msg := Ui.height (px 1) Ui.separator

def timeOf (m : Model) (l : Line) : String := (l.time.map (Display.clock m.zone)).getD ""

/-- How far our upload of line `l` has gone, while it is under way. -/
def sending (c : Chat) (l : Line) : Option String := do
  let j ← c.jobs.find? (·.line == some l.id)
  let u ← j.upload
  if u.sent < u.total then some s!"sending, {u.sent * 100 / max u.total 1}%" else none

def fileRow (m : Model) (c : Chat) (l : Line) (a : Attachment) : FileRow :=
  let size := Core.sizeText a.size
  let (picture, note) := match m.pictureOf a with
    | some (.shown img) => let (w, h) := Disk.fit img.w img.h thumbW thumbH; (some (img, w, h), none)
    | some (.refused why) => (none, some s!"picture {why}")
    | some .loading => (none, none)
    | none => (none, if Model.isPicture a then some "not received yet" else none)
  let detail := " · ".intercalate ([size] ++ (sending c l).toList ++ note.toList)
  if Model.isVoice a then
    let playing := m.playing == some (m.stateDir / a.file).toString
    { line := l.id, name := SafeText.trusted "Voice note", detail, voice := some playing }
  else { line := l.id, name := Display.text a.name, detail, picture }

/-- A conversation as runs: each run of one sender's messages under one header, echo-chat's notices
alone, and a date between runs of different days. -/
def conversation (m : Model) (c : Chat) : Node Msg :=
  let me := m.state.me
  let runs := Display.runs c.log
  let (_, items) := runs.foldl (fun (acc : Option Int × List (Node Msg)) run =>
    let (day, items) := acc
    let first := run.first
    let thisDay := (first.bind (·.time)).map (Display.dayOf m.zone)
    let dated := match thisDay, day with
      | some d, some p => if d != p then [Ui.row [Ui.spacer, Ui.caption (SafeText.trusted (Display.date d)) s!"day:{d}", Ui.spacer]] else []
      | _, _ => []
    let node := match run with
      | .notice l => Ui.lazy ({ lines := Display.body l.text } : NoticeRow) noticeView (key := some s!"line:{l.id}")
      | .messages sender ls =>
        let head := headerView (Display.who me c sender) ((ls.head?.map (timeOf m)).getD "")
        Ui.col (spacing := px 2) (head :: ls.map fun l =>
          Ui.lazy ({ lines := Display.body l.text, mark := markOf c l,
                     file := l.attachment.map (fileRow m c l) } : MessageRow) messageView
            (key := some s!"line:{l.id}")) (key := s!"run:{(ls.head?.map (·.id)).getD 0}")
    (thisDay.orElse fun _ => day, items ++ dated ++ [node])) (none, [])
  let arriving := c.downloads.map fun d =>
    Ui.lazy ({ lines := [Display.who me c d.stream ++ SafeText.trusted " is sending a file or a long message…"] } : NoticeRow)
      noticeView (key := some s!"arriving:{Display.hex d.stream}")
  Ui.scroll (Ui.pad (px 12) (Ui.col (items ++ arriving) (px 12))) "conversation" (follow := true)

def groupRowView (m : Model) (c : Chat) : Node Msg :=
  let n := Display.unread m.seen c
  let state := if c.joining.isSome then "joining…" else if c.inducting.isSome then "adding…"
    else if c.group.isNone then "starting…" else ""
  Ui.row ([Ui.text (Display.name c.name).toText (overflow := .ellipsis) (bold := n > 0)] ++
    (if state.isEmpty then [] else [Ui.caption (SafeText.trusted state)]) ++ [Ui.spacer] ++
    (if n > 0 then [Ui.badge n] else [])) (px 6)

def groupsPane (m : Model) : Node Msg :=
  let names := m.state.chats.map (·.name)
  let row (n : String) := ((m.state.chat? n).map (groupRowView m)).getD (Ui.label n)
  Ui.surface <| Ui.pad (px 12) <| Ui.col [
    Ui.row [Ui.heading "Groups", Ui.spacer, Ui.flatButton "New" (.ask .newGroup) "new-group",
      Ui.flatButton "Join" (.ask .join) "join-group"] (px 6),
    Ui.selectListOf names m.selected .select row (fun n => (Display.name n).text) ("group:" ++ ·)
      (rows := 14) (framed := false) (key := "groups")] (px 12)

/-- With no group yet: what to do, centered. -/
def empty : Node Msg :=
  Ui.col [Ui.filler, Ui.row [Ui.spacer, Ui.width (px 380) (Ui.col [
    Ui.label "No groups yet" "empty" (bold := true) (size := .title),
    Ui.label ("Start a group of your own, or join someone else's: a voucher code appears, which " ++
      "you give to one of its members, who adds you with Invite.") (maxLines := 4) (tone := .muted),
    Ui.row [Ui.mainButton "New group" (.ask .newGroup) "empty-new",
      Ui.button "Join a group" (.ask .join) "empty-join"] (px 6)] (px 12)), Ui.spacer], Ui.filler] 0

def sendCaption (c : Chat) (draft : String) : String :=
  let n := (draft.splitOn "\n").length
  let to := (Display.name c.name).text
  if n > 1 then s!"Send {n} lines to {to}" else s!"Send to {to}"

/-- The voice note being recorded in the group, or recorded and not yet sent. -/
def voiceBar (m : Model) (c : Chat) : Option (Node Msg) :=
  let bar (parts : List (Node Msg)) := some (Ui.pad (px 12) (Ui.row parts (px 6)))
  match m.voice with
  | .recording chat since =>
    if chat != c.name then none else
    bar [Ui.caption (SafeText.trusted s!"Recording a voice note, {Voice.seconds (m.clock - since)}: let go to stop") "voice-status"]
  | .starting chat _ | .stopping chat =>
    if chat != c.name then none else bar [Ui.caption (SafeText.trusted "Recording a voice note…") "voice-status"]
  | .draft chat clip =>
    if chat != c.name then none else
    let playing := m.playing == some clip.path
    bar [Ui.text (SafeText.trusted s!"Voice note, {Voice.seconds clip.durationMs}") (key := "voice-status"),
      if playing then Ui.flatButton "Stop" .stopPlay "draft-stop" else Ui.flatButton "Play" .playDraft "draft-play",
      Ui.spacer, Ui.button "Discard" .discardDraft "draft-discard",
      Ui.mainButton "Send voice note" .sendDraft "draft-send"]
  | .idle => none

def conversationPane (m : Model) (c : Chat) : Node Msg :=
  let info := match c.group with
    | some g => s!"{g.readers.size + 1} members · epoch {g.epoch}"
    | none => if c.joining.isSome then "waiting to be added" else "starting"
  let joined := c.group.isSome
  let header := Ui.pad (px 12) <| Ui.row [
    Ui.col [Ui.text (Display.name c.name).toText (key := "title") (overflow := .ellipsis) (bold := true)
        (size := .heading), Ui.caption (SafeText.trusted info) "info"] (px 2),
    Ui.spacer,
    Ui.enabled joined (Ui.flatButton "Invite" (.ask .invite) "invite"),
    Ui.enabled joined (Ui.flatButton "Remove" (.ask .remove) "remove"),
    Ui.enabled joined (Ui.flatButton "Scan" .scan "scan"),
    Ui.width (px 12) Ui.spacer,
    Ui.flatButton "Rename" (.ask .rename) "rename",
    Ui.flatButton "Clear" (.ask .clear) "clear",
    Ui.destructiveButton "Leave" (.ask .leave) "leave"] (px 6)
  let voucher := (Model.voucher? c).toList.map fun code =>
    Ui.pad (px 12) <| Ui.panel (Ui.col [
      Ui.heading "Your voucher code",
      Ui.label "Give it to a member of the group, who adds you with Invite. It is also in the state directory."
        (maxLines := 3) (tone := .muted),
      Ui.row [Ui.text (Display.text code) (maxLines := 6) (key := "voucher-code"), Ui.spacer,
        Ui.mainButton "Copy" .copyVoucher "copy-voucher"] (px 12)] (px 6))
  let talk := Ui.enabled (joined && m.soundOff.isNone && (m.voice == .idle || m.voice.chat? == some c.name))
    (Node.leaf (Voice.holdButton (SafeText.trusted "Hold to talk") .holdStart .holdEnd
      (match m.voice with | .recording .. | .starting .. => true | _ => false)) "talk")
  let talk := match m.soundOff with
    | some why => Ui.tooltip why talk
    | none => talk
  let composer := Ui.pad (px 12) <| Ui.height (px 72) <| Ui.row [
    Ui.keystroke [({ key := .enter, ctrl := true }, .send)]
      (Ui.textArea m.draft .draft { rows := 3, placeholder := SafeText.trusted "a message" } "draft"),
    Node.container (box { alignV := .bottom })
      [Ui.row [talk, Ui.enabled joined (Ui.button "Attach…" (.ask .attach) "attach"),
        Ui.enabled joined (Ui.mainButton (sendCaption c m.draft) .send "send")] (px 6)]] (px 12)
  Ui.col ([header, rule] ++ voucher ++ [conversation m c, rule, Ui.col (voiceBar m c).toList 0 (key := "voice-bar"), composer]) 0

def membersPane (m : Model) (c : Chat) : Node Msg :=
  let ms := Display.members m.state.me c
  let row (mb : Display.Member) : Node Msg :=
    Ui.row ([Ui.text mb.label (overflow := .ellipsis)] ++
      (if mb.doubtful then [Ui.tooltip ("This name could be taken for another's, or for yours, or it mixes " ++
          "scripts: tell them apart by the start of their key.") (Ui.label "(!)" (tone := .error))] else []) ++
      [Ui.spacer, Ui.caption (SafeText.trusted (Display.fingerprint mb.key))]) (px 6)
  Ui.surface <| Ui.pad (px 12) <| Ui.col [
    Ui.row [Ui.heading "Members", Ui.caption (SafeText.trusted (toString ms.length))] (px 6),
    Ui.list ms (fun mb => s!"member:{Display.hex mb.key}") row (px 6)] (px 12)

def logPane (m : Model) : Node Msg :=
  Ui.height (px 120) <| Ui.pad (px 6) <| Ui.scroll (Ui.col (spacing := 0)
    (m.logs.toList.map fun l => Ui.caption (Display.text l) (overflow := .clip))) "log" (follow := true)

def status (m : Model) : String :=
  let pending := m.state.chats.foldl (fun n c => n + c.jobs.length) 0
  let epoch := match m.current.bind (·.group) with
    | some g => s!" · epoch {g.epoch}"
    | none => ""
  s!"{m.network}{epoch} · {pending} to write"

def statusBar (m : Model) : Node Msg :=
  Ui.pad (px 6) <| Ui.row [Ui.caption (Display.text (status m)) "status", Ui.spacer,
    Ui.caption (Display.text m.note) "note"] (px 12)

def accept (caption : String) (kind : Widgets.ButtonKind) : Node Msg :=
  Node.leaf (Widgets.button (SafeText.trusted caption) .confirm (designated := true) (kind := kind)) "accept"

/-- A folder's entries to choose from, and the folder above. -/
def browser (d : Dialog) : List (Node Msg) :=
  let caption (e : Disk.Entry) := if e.dir then e.name ++ "/" else s!"{e.name}  ({Core.sizeText e.size})"
  let picked := d.pick.bind fun p => d.entries.find? (·.name == p)
  [Ui.row [Ui.caption (Display.text d.dir) "dir", Ui.spacer, Ui.flatButton "Up" .up "up"] (px 6),
   Ui.selectList d.entries picked .entry caption (fun e => "entry:" ++ e.name) (rows := 10) (key := "entries")]

def dialogView (m : Model) (d : Dialog) : Node Msg :=
  let group := (Display.name (d.chat.getD "")).text
  let field (placeholder : String) :=
    Ui.textField d.field .field { placeholder := SafeText.trusted placeholder } "dialog-field"
  let buttons (caption : String) (kind : Widgets.ButtonKind) :=
    Ui.row [Ui.spacer, Ui.button "Cancel" .dismiss "cancel", accept caption kind] (px 6)
  let note := if d.note.isEmpty then [] else
    [Ui.text (Display.text d.note) (maxLines := 3) (key := "dialog-note") (tone := .error)]
  let body (title : String) (parts : List (Node Msg)) (caption : String) (kind : Widgets.ButtonKind) :=
    Ui.dialog d.modal (SafeName.filter title)
      (Ui.width (px 420) (Ui.col ([Node.leaf (Widgets.label (SafeText.trusted title) (bold := true) (size := .heading))] ++
        parts ++ note ++ [buttons caption kind]) (px 12))) .dismiss
  match d.kind with
  | .newGroup => body "New group"
      [Ui.paragraph "A group of your own; you add members with Invite.", field "its name"] "Create" .main
  | .join => body "Join a group"
      [Ui.paragraph ("Name it as you will know it here. A voucher code will appear: give it to a " ++
        "member of the group, who adds you with Invite."), field "its name here"] "Join" .main
  | .invite => body s!"Invite to {group}"
      [Ui.paragraph s!"Whoever holds this code will read everything said in {group} from now on.",
        field "voucher code"] "Invite" .main
  | .remove =>
    let others := ((m.state.chat? (d.chat.getD "")).map (Display.members m.state.me ·)).getD [] |>.drop 1
    let hexes := others.map (Display.hex ·.key)
    let label (h : String) := ((others.find? (Display.hex ·.key == h)).map fun mb =>
      mb.label.text ++ s!" {Display.fingerprint mb.key}").getD h
    let chosen := (d.pick.map label).getD "The member you choose"
    body s!"Remove a member of {group}"
      [Ui.selectList hexes d.pick .pick label ("pick:" ++ ·) (rows := 6) (key := "members"),
        Ui.paragraph s!"{chosen} will no longer be read here; what they sent is deleted here. They can still read {group}."]
      "Remove" .destructive
  | .leave => body s!"Leave {group}"
      [Ui.paragraph s!"Leave {group} and delete it here? This cannot be undone. Type its name to confirm.",
        field "the group's name"] "Leave" .destructive
  | .rename => body s!"Rename {group}"
      [Ui.paragraph "Its name here. The other members each know it by a name of their own.",
        field "its new name"] "Rename" .main
  | .clear => body s!"Clear {group}"
      [Ui.paragraph s!"Delete this conversation's lines here? The other members keep theirs."] "Clear" .destructive
  | .attach => body s!"Send a file to {group}"
      (browser d ++ [field "the file's path",
        Ui.paragraph s!"Everyone in {group} will be able to read it. At most {Files.maxFile / (1024 * 1024)} MB."])
      "Send" .main
  | .save =>
    let name := ((d.line.bind m.line?).bind (·.attachment)).map (·.name) |>.getD "the file"
    body s!"Save {name}" (browser d ++ [field "where to save it"]) "Save" .main
  | .view =>
    let a := (d.line.bind m.line?).bind (·.attachment)
    let name := (a.map (·.name)).getD ""
    let picture := match a.bind m.pictureOf with
      | some (.shown img) =>
        let (w, h) := Disk.fit img.w img.h largeW largeH
        [Ui.row [Ui.spacer, pictureView img w h (Display.text name) "picture-large", Ui.spacer]]
      | _ => [Ui.paragraph "The picture cannot be shown."]
    Ui.dialog d.modal (SafeName.filter name)
      (Ui.width (px largeW) (Ui.col (picture ++ [Ui.row [Ui.text (Display.text name) (overflow := .ellipsis),
        Ui.spacer, Ui.button "Save…" (.saveAs (d.line.getD 0)) "view-save", accept "Close" .main] (px 6)]) (px 12)))
      .dismiss

def bindings : List (Widgets.KeyCombo × Msg) :=
  [({ key := .char 'q', ctrl := true }, .quit), ({ key := .f 10 }, .toggleBlank),
   ({ key := .f 2 }, .toggleLog), ({ key := .pageDown, ctrl := true }, .next true),
   ({ key := .pageUp, ctrl := true }, .next false)]

def view (m : Model) : Node Msg :=
  Voice.keys bindings .holdStart .holdEnd <| Ui.themed (if m.dark then Theme.dark else Theme.light) <|
  if m.blank then Ui.pad (px 24) (Ui.label "echo-chat · F10 to return" "blank") else
  let (middle, right) := match m.current with
    | some c => (conversationPane m c, membersPane m c)
    | none => (empty, Ui.surface Ui.spacer)
  let panes := Ui.split (groupsPane m) (Ui.split middle right m.inner (.ratio false) (key := "inner"))
    m.outer (.ratio true) (key := "outer")
  Ui.col ([panes] ++ (if m.showLog then [rule, logPane m] else []) ++
    [rule, statusBar m] ++ (m.dialog.toList.map (dialogView m))) 0

def app (post : GroupChatKatzenqt1.Msg → IO Unit) (audio : Voice.Audio) (init : Model)
    (start : List (Cmd Msg caps .other) := []) : App caps :=
  { Model := Model, Msg := Msg, init := { init with soundOff := audio.off }, update := update post audio, view, start }

end EchoChat.App
