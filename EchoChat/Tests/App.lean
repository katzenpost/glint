/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import EchoChat.App
import GroupChatClient.GroupChatKatzenqt1.Shell
import EchoChat.Tests.Display

/-! # The window

The app driven through `Paw.Runtime` as the platform drives it: clicks and keys at points, states
from the shell as messages of origin `other`, and the tasks it starts run here, posting to a fake
inbox. -/

namespace EchoChat.Tests.AppTests

open EchoChat EchoChat.Tests Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1
open Cryptlib.Protocols.GroupComm.Common
open Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member

abbrev Sent := IO.Ref (Array GroupChatKatzenqt1.Msg)

/-- Where the tests keep files: the state directory, and a home with files to send. -/
def testDir : System.FilePath := ".lake/echo-chat-test"

/-- The fake sound system: what it was asked, and what it does. -/
structure Sound where
  log : Array String := #[]
  recording : Bool := false
  playing : Option String := none
  /-- How long the next clip is, in milliseconds. -/
  clipMs : Nat := 2000
  clips : Nat := 0
  /-- Recording fails, and why. -/
  fail : Option String := none
  deriving Inhabited

initialize sound : IO.Ref Sound ← IO.mkRef {}

def drafts : System.FilePath := testDir / "state" / "audio" / "drafts"

def fakeAudio : Voice.Audio where
  start := do
    if let some e := (← sound.get).fail then throw (IO.userError e)
    sound.modify fun s => { s with recording := true, log := s.log.push "start" }
  stop := do
    let s ← sound.get
    sound.set { s with recording := false, clips := s.clips + 1, log := s.log.push "stop" }
    IO.FS.createDirAll drafts
    let path := drafts / s!"voice-note-{s.clips}.opus"
    let bytes := s!"OggS clip {s.clips}".toUTF8
    IO.FS.writeBinFile path bytes
    return { path := path.toString, durationMs := s.clipMs, size := bytes.size }
  cancel := sound.modify fun s => { s with recording := false, log := s.log.push "cancel" }
  play p := do
    unless ← System.FilePath.pathExists p do throw (IO.userError s!"{p} does not exist")
    sound.modify fun s => { s with playing := some p, log := s.log.push s!"play {p}" }
  stopPlay := sound.modify fun s => { s with playing := none }
  playing := return (← sound.get).playing.isSome
  error := pure none

def mkApp (sent : Sent) (me : String := "alice") : Paw.App App.caps :=
  let home := (testDir / "home").toString
  App.app (fun m => sent.modify (·.push m)) fakeAudio
    { state := { me }, network := "test", stateDir := testDir / "state", home, downloads := home }

/-- A runtime, the outputs of its last step, and the time. -/
structure Run (sent : Sent) where
  rt : Runtime (mkApp sent)
  outs : List (Output (mkApp sent).Msg) := []
  now : Nat := 0

variable {sent : Sent}

/-- Run the tasks among the outputs, as the platform would, and hand their results back. -/
partial def settle (r : Run sent) : IO (Run sent) := do
  let tasks := r.outs.filterMap fun | .task io => some io | _ => none
  if tasks.isEmpty then return r
  let mut r := r
  let mut outs := r.outs.filter fun | .task _ => false | _ => true
  for io in tasks do
    let m ← io
    let (rt, o) := r.rt.taskResult m r.now
    r := { r with rt }
    outs := outs ++ o
  settle { r with outs }

def begin (sent : Sent) : Run sent :=
  { rt := (Paw.Runtime.start (mkApp sent) (Rect.ofXYWH 0 0 (px 1000) (px 700)) 0 Env.mock.measure).1 }

def input (r : Run sent) (k : InputKind) (dt : Nat := 50) : IO (Run sent) :=
  let now := r.now + dt
  let (rt, outs) := r.rt.step (.input { kind := k, time := now }) now
  settle { rt, outs, now }

def at_ (r : Run sent) (k : String) : Point :=
  match r.rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

/-- A click on the widget keyed `k`, after waiting long enough for it to be designated. -/
def click (r : Run sent) (k : String) : IO (Run sent) := do
  let p := at_ r k
  let r ← input r (.press p .primary) 600
  let r' ← input r (.release p .primary)
  return { r' with outs := r.outs ++ r'.outs }

def key (r : Run sent) (k : Paw.Key) (m : Mods := {}) : IO (Run sent) := input r (.key k m true) 600

def typeText (r : Run sent) (s : String) : IO (Run sent) := input r (.text s) 600

def state (r : Run sent) (s : State) : IO (Run sent) :=
  let now := r.now + 50
  let (rt, outs) := r.rt.results [App.Msg.state s] now
  settle { rt, outs, now }

def other (r : Run sent) (m : App.Msg) : IO (Run sent) :=
  let now := r.now + 50
  let (rt, outs) := r.rt.results [m] now
  settle { rt, outs, now }

def last (sent : Sent) : IO (Option String) := return (← sent.get).back?.map (·.describe)

def clipboard {M : Type} (outs : List (Output M)) : List String :=
  outs.filterMap fun | .request (.setClipboard t) => some t.text | _ => none

/-- The texts drawn by the widget keyed `k` and everything in it. -/
def textsOf (r : Run sent) (k : String) : List String :=
  match r.rt.tree.findKey? k with
  | some n => (n.render r.rt.env).items.filterMap fun
      | (_, .text _ t _) => some t.text
      | _ => none
  | none => []

partial def kinds {Msg : Type} (n : Node Msg) : List String := n.kind :: n.children.flatMap kinds

/-- The texts the widget keyed `k` draws, with their styles, in echo-chat's dark theme. -/
def stylesOf (r : Run sent) (k : String) : List (String × TextStyle) :=
  match r.rt.tree.findKey? k with
  | some n => (n.render { r.rt.env with theme := Theme.dark }).items.filterMap fun
      | (_, .text _ t st) => some (t.text, st)
      | _ => none
  | none => []

/-- Whether what the widget keyed `k` draws is centered in the conversation, within a few
pixels. -/
def centered (r : Run sent) (k : String) : Bool :=
  let pane := ((r.rt.tree.findKey? "conversation").map (·.viewport)).getD default
  let mid := (pane.x0 + pane.x1 - Widgets.gutter) / 2
  match r.rt.tree.findKey? k with
  | some n => (n.render r.rt.env).items.any fun
      | (_, .text p t st) =>
        let w := (r.rt.env.measure st t).1
        let c := p.x + w / 2
        c ≤ mid + px 8 && mid ≤ c + px 8 && w > 0
      | _ => false
  | none => false

def line (id : Nat) (text : String) (sender : ByteArray := .empty) (status : Status := .sent) : Line :=
  { id, sender, text, status }

/-- A group of our own, founded with a made-up read cap. -/
def chatWith (name : String) (log : List Line) : Chat :=
  let readCap := ByteArray.mk ((List.replicate 136 (name.length.toUInt8)).toArray)
  { name, log, group := some (Group.found readCap [readCap]) }

def selection : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r := begin sent
  check "with no groups, the empty state explains what to do" ((textsOf r "empty") == ["No groups yet"])
  check "and offers to start or join one" ((r.rt.tree.findKey? "empty-new").isSome && (r.rt.tree.findKey? "empty-join").isSome)
  let s : State := { me := "alice", chats := [chatWith "g" [line 0 "one"], chatWith "h" [line 0 "a", line 1 "b"]] }
  let r ← state r s
  check "the first group is selected" (r.rt.model.selected == some "g")
  check "the other's lines are unread, its badge says how many" ((textsOf r "group:h") == ["h", "2"])
    fun _ => toString (textsOf r "group:h")
  check "the selected one's are not" ((textsOf r "group:g") == ["g"]) fun _ => toString (textsOf r "group:g")
  let only (k : String) (texts : List String) := (textsOf r k).filter (· != "—") == texts
  check "the conversation shows the selected group's lines" (only "conversation" ["one"])
  let r ← click r "group:h"
  check "a click selects a group, by name" (r.rt.model.selected == some "h")
  let only (k : String) (texts : List String) := (textsOf r k).filter (· != "—") == texts
  check "and the conversation shows its lines alone" (only "conversation" ["a", "b"])
  check "and reads it" ((textsOf r "group:h") == ["h"]) fun _ => toString (textsOf r "group:h")
  let r ← click r "new-group"
  check "New group opens a dialog" (r.rt.model.dialog.any (·.kind == .newGroup))
  let r ← click r "dialog-field"
  let r ← typeText r "fresh"
  let r ← click r "accept"
  check "which creates the group" ((← last sent) == some "fresh: create")
  check "and closes" r.rt.model.dialog.isNone
  let r ← state r { s with chats := s.chats ++ [chatWith "fresh" []] }
  check "the new group is selected once it appears" (r.rt.model.selected == some "fresh")
  let r ← key r .pageUp { ctrl := true }
  check "Ctrl+PageUp selects the group before" (r.rt.model.selected == some "h")
  let r ← key r (.f 10)
  check "F10 blanks the window" ((textsOf r "blank") == ["echo-chat · F10 to return"] && (r.rt.tree.findKey? "groups").isNone)
  let r ← key r (.f 10)
  check "and F10 brings it back" (r.rt.tree.findKey? "groups").isSome
  check "the log is hidden at first" ((r.rt.tree.findKey? "log").isNone)
  let r ← key r (.f 2)
  check "F2 shows it" ((r.rt.tree.findKey? "log").isSome)
  let r ← key r (.f 2)
  check "and hides it again" ((r.rt.tree.findKey? "log").isNone)

def origin : TestM Unit := do
  let sent ← IO.mkRef #[]
  let s : State := { me := "alice", chats := [{ name := "g", joining := some (.awaiting "CODE" .empty .empty .empty) }] }
  let r ← state (begin sent) s
  check "a state from the shell starts nothing" (r.outs.all fun | .request (.present _) | .request (.access ..) => true | _ => false)
  for (what, m) in [("New group", App.Msg.ask .newGroup), ("Invite", .ask .invite), ("Leave", .ask .leave)] do
    let r ← other r m
    check s!"{what} of origin other opens no dialog" r.rt.model.dialog.isNone
  let r ← other r .copyVoucher
  check "Copy of origin other copies nothing" (clipboard r.outs).isEmpty
  check "nothing was posted" (← sent.get).isEmpty

def sending : TestM Unit := do
  let sent ← IO.mkRef #[]
  let s : State := { me := "alice", chats := [chatWith "g" [], chatWith "h" []] }
  let r ← state (begin sent) s
  check "the Send button names the group" ((textsOf r "send") == ["Send to g"])
  let r ← click r "draft"
  let r ← typeText r "hello"
  let r ← click r "send"
  check "Send posts the draft to the selected group" ((← last sent) == some "g: send 5 characters")
  check "and empties it" (r.rt.model.draft.isEmpty)
  let r ← click r "group:h"
  let r ← click r "draft"
  let r ← typeText r "one"
  let r ← key r .enter
  let r ← typeText r "two"
  check "a draft of more lines says how many, and where to"
    ((textsOf r "send") == ["Send 2 lines to h"])
  let r ← key r .enter { ctrl := true }
  check "Ctrl+Enter sends" (match (← sent.get).back? with | some (.send "h" "one\ntwo") => true | _ => false)
  let r ← click r "draft"
  let r ← typeText r "/leave h"
  let _ ← click r "send"
  check "the message box only sends text" (match (← sent.get).back? with | some (.send "h" "/leave h") => true | _ => false)

def dialogs : TestM Unit := do
  let sent ← IO.mkRef #[]
  let some c ← DisplayTests.threeMembers | check "three members join a group" false
  let s : State := { me := "alice", chats := [c] }
  let r ← state (begin sent) s
  let count := fun () => do return (← sent.get).size
  -- Escape posts nothing, whatever was typed.
  for (button, kind) in [("invite", App.DialogKind.invite), ("leave", .leave), ("join-group", .join),
      ("new-group", .newGroup), ("clear", .clear), ("remove", .remove), ("rename", .rename)] do
    let r ← click r button
    check s!"{button} opens its dialog" (r.rt.model.dialog.any (·.kind == kind)) fun _ => s!"{repr (r.rt.model.dialog.map (·.kind))} at {repr (at_ r button)} note={r.rt.model.note}"
    let r ← if (r.rt.tree.findKey? "dialog-field").isSome then do
        let r ← click r "dialog-field"
        typeText r "g"
      else pure r
    let r ← key r .escape
    check s!"Escape closes {button}'s dialog" r.rt.model.dialog.isNone
  check "and posts nothing" ((← count ()) == 0)
  -- Each posts on confirm.
  let r ← click r "invite"
  check "Invite says what it means" (((String.intercalate "" (textsOf r "dialog")).splitOn "Whoever holds this code will read everything said in g from now on.").length > 1) fun _ => toString (textsOf r "dialog")
  let r ← click r "dialog-field"
  let r ← typeText r "QUJD"
  let r ← click r "accept"
  check "Invite posts on confirm" ((← last sent) == some "g: add a member")
  let r ← click r "leave"
  let r ← click r "dialog-field"
  let r ← typeText r "not g"
  let r ← click r "accept"
  check "Leave with the wrong name posts nothing" ((← count ()) == 1 && r.rt.model.dialog.isSome)
  check "and says what to type" (String.intercalate "" (textsOf r "dialog-note") == "to leave g and delete it here, type its name")
  let r ← key r .escape
  let r ← click r "leave"
  let r ← click r "dialog-field"
  let r ← typeText r "g"
  let r ← click r "accept"
  check "Leave with the group's name leaves" ((← last sent) == some "g: leave")
  let r ← click r "clear"
  let r ← click r "accept"
  check "Clear clears on confirm" ((← last sent) == some "g: clear")
  let carol := (c.names.pairs.find? (·.2 == "carol")).map (·.1) |>.getD .empty
  let r ← click r "remove"
  let r ← click r "accept"
  check "Remove with no one chosen posts nothing" ((← count ()) == 3)
  let r ← click r s!"pick:{Display.hex carol}"
  check "Remove names whom it removes" ((textsOf r "dialog").any (·.startsWith "~carol"))
  let r ← click r "accept"
  check "Remove posts the member chosen, by key"
    (match (← sent.get).back? with | some (.remove "g" k) => k == carol | _ => false)
  check "and closes" r.rt.model.dialog.isNone
  let r ← click r "clear"
  let r ← input r (.press (at_ r "accept") .primary) 10
  let r ← input r (.release (at_ r "accept") .primary) 10
  check "a click on a button that has just appeared is not the user's choice"
    ((← count ()) == 4 && r.rt.model.dialog.isSome)

def renames : TestM Unit := do
  let sent ← IO.mkRef #[]
  let s : State := { me := "alice", chats := [chatWith "g" [line 0 "one"], chatWith "h" []] }
  let r ← state (begin sent) s
  let r ← click r "rename"
  check "Rename opens with the group's name" (r.rt.model.dialog.any fun d => d.kind == .rename && d.field == "g")
  let r ← other r (.field "h")
  let r ← click r "accept"
  check "Rename to a name taken posts nothing, and says why" ((← sent.get).isEmpty &&
    String.intercalate "" (textsOf r "dialog-note") == "you already have a group called h")
  let r ← other r (.field "friends")
  let r ← click r "accept"
  check "Rename posts the new name" ((← last sent) == some "g: rename to friends")
  let r ← state r { s with chats := [{ chatWith "g" [line 0 "one"] with name := "friends" }, chatWith "h" []] }
  check "the group stays selected by its new name" (r.rt.model.selected == some "friends")
  check "and its lines stay read" ((textsOf r "group:friends") == ["friends"]) fun _ => toString (textsOf r "group:friends")

def copy : TestM Unit := do
  let sent ← IO.mkRef #[]
  let s : State := { me := "bob", chats := [{ name := "g", joining := some (.awaiting "Q09ERQ==" .empty .empty .empty) }] }
  let r ← state (begin sent) s
  check "the voucher code is shown" ((textsOf r "voucher-code") == ["Q09ERQ=="])
  let r ← click r "copy-voucher"
  check "Copy writes the code to the clipboard" (clipboard r.outs == ["Q09ERQ=="])
  let r ← click r "voucher-code"
  check "a click elsewhere copies nothing" (clipboard r.outs).isEmpty

def rendering : TestM Unit := do
  let sent ← IO.mkRef #[]
  let some c ← DisplayTests.threeMembers | check "three members join a group" false
  let bob := (c.names.pairs.find? (·.2 == "bob")).map (·.1) |>.getD .empty
  let me := (c.group.map (·.me)).getD .empty
  let long := String.intercalate "\n" ((List.range 30).map (s!"row {·}"))
  let hostile := "‮evil " ++ String.ofList (List.replicate 400 'W')
  let c := { c with log := [line 0 "carol joined", line 1 "hi" bob, line 2 long bob, line 3 hostile bob,
    line 4 "mine" me .pending, line 5 "sent" me] }
  let r ← state (begin sent) { me := "alice", chats := [c] }
  let t := Theme.dark
  let styled (k : String) := stylesOf r k
  check "a notice is small and muted" ((styled "line:0").all fun (_, st) => st.color == t.muted && st.size == t.captionSize)
  check "and centered" (centered r "line:0")
  check "a message is never muted, small or centered"
    ([1, 2, 4, 5].all fun i => (styled s!"line:{i}").any (fun (x, st) => x != "" && st.color == t.text && st.size == t.fontSize)
      && !centered r s!"line:{i}")
  check "a message's rows are never bold" ([1, 2, 3, 4, 5].all fun i => (styled s!"line:{i}").all (!·.2.bold))
  let head := styled "run:1"
  check "a run of messages begins with who sent it, in bold" (head.head?.any fun (x, st) => x == "~bob" && st.bold)
  check "bob's messages are one run" ((r.rt.tree.findKey? "run:1").isSome &&
    (r.rt.tree.findKey? "run:2").isNone && (r.rt.tree.findKey? "run:3").isNone)
  let rows := textsOf r "line:2"
  check "a long message is cut at 20 lines, with its mark" (rows.length == 20 + 1)
  check "and a marker" (rows.dropLast.getLast? == some "[11 more lines not shown]")
  check "our pending message is marked …" ((textsOf r "line:4") == ["mine", "…"])
  check "a written one ✓" ((textsOf r "line:5") == ["sent", "✓"])
  check "another's has no mark" ((textsOf r "line:1") == ["hi", ""])
  check "our run is headed me" ((textsOf r "run:4").head? == some "me")
  -- Every text of the conversation is drawn within the conversation's box.
  let box := ((r.rt.tree.findKey? "conversation").map (·.viewport)).getD default
  let scene := match r.rt.present with | .request (.present s) => s | _ => Scene.empty
  let remote := ["hi", "carol joined", "mine", "sent"] ++ ((List.range 19).map (s!"row {·}"))
  let inside := scene.items.all fun
    | (clip, .text _ t _) => !(remote.contains t.text || t.text.startsWith "�evil") || decide (clip.Within box)
    | _ => true
  check "every remote string sits within the conversation" inside
  check "the window's title is never set" (r.outs.all fun | .request (.setTitle _) => false | _ => true)

/-- The background of the last fill covering the whole window: what the window is seen on. -/
def background {caps : List Cap} {app : Paw.App caps} (rt : Runtime app) : Option Color :=
  match rt.present with
  | .request (.present s) => (s.items.filterMap fun
    | (_, .fill r c _) => if r == rt.window then some c else none
    | _ => none).getLast?
  | _ => none

def theme : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r := begin sent
  check "echo-chat is dark by default" (background r.rt == some Theme.dark.background)
  let light := App.app (fun m => sent.modify (·.push m)) fakeAudio { state := { me := "alice" }, dark := false }
  let rt := (Paw.Runtime.start light (Rect.ofXYWH 0 0 (px 1000) (px 700)) 0 Env.mock.measure).1
  check "and light when asked" (background rt == some Theme.light.background)

def grouping : TestM Unit := do
  let sent ← IO.mkRef #[]
  let some c ← DisplayTests.threeMembers | check "three members join a group" false
  let bob := (c.names.pairs.find? (·.2 == "bob")).map (·.1) |>.getD .empty
  let at_ (id : Nat) (text : String) (min : Nat) : Line := { line id text bob with time := some (1792055520000 + min * 60000) }
  let c := { c with log := [at_ 0 "one" 0, at_ 1 "two" 4, at_ 2 "three" 12] }
  let r ← state (begin sent) { me := "alice", chats := [c] }
  check "messages a few minutes apart are one run" (((textsOf r "run:0").filter (· == "~bob")).length == 1)
  check "one more than five minutes later starts another" (r.rt.tree.findKey? "run:2").isSome
  check "each run's header has its time" ((textsOf r "run:0").take 2 == ["~bob", "09:12"] &&
    (textsOf r "run:2").take 2 == ["~bob", "09:24"])
  let c := { c with log := [at_ 0 "today" 0, { at_ 1 "tomorrow" 0 with time := some (1792055520000 + 86400000) }] }
  let r ← state (begin sent) { me := "alice", chats := [c] }
  check "a new day is marked with its date" (r.rt.tree.findKey? s!"day:{Display.dayOf 0 (1792055520000 + 86400000)}").isSome

def buttonKinds : TestM Unit := do
  let sent ← IO.mkRef #[]
  let s : State := { me := "alice", chats := [chatWith "g" []] }
  let r ← state (begin sent) s
  let t := Theme.dark
  let colorOf (r : Run sent) (k : String) := (stylesOf r k).head?.map (·.2.color)
  check "Send is the main button" (colorOf r "send" == some t.mainButton.basic.fg)
  check "Leave is destructive" (colorOf r "leave" == some t.destructiveButton.basic.fg)
  let r ← click r "new-group"
  check "a new group's Create is the main kind" (colorOf r "accept" == some t.mainButton.basic.fg)
  let r ← key r .escape
  let r ← click r "clear"
  check "Clear's accept is destructive" (colorOf r "accept" == some t.destructiveButton.basic.fg)

def tests : TestM Unit := do
  grouping
  buttonKinds
  theme
  selection
  origin
  sending
  dialogs
  renames
  copy
  rendering

end EchoChat.Tests.AppTests
