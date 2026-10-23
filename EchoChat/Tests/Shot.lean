/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Linux
import EchoChat.Tests.App
import EchoChat.Tests.Files
import EchoChat.Tests.Voice

/-! # Pictures of the window

The window drawn offscreen with the bundled fonts, for a person to look at. -/

namespace EchoChat.Tests.Shot

open EchoChat EchoChat.Tests Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1
open GroupChatClient.GroupChatKatzenqt1.Tests

def write {caps : List Cap} {app : Paw.App caps} (rt : Runtime app) (path : System.FilePath) : IO Unit := do
  let scene := match rt.present with | .request (.present s) => s | _ => Scene.empty
  IO.FS.writeBinFile path (Linux.renderPng scene 1000 700)

def shots (dir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll dir
  let sent ← IO.mkRef #[]
  let some c ← DisplayTests.threeMembers | throw (IO.userError "no group")
  let bob := (c.names.pairs.find? (·.2 == "bob")).map (·.1) |>.getD .empty
  let me := (c.group.map (·.me)).getD .empty
  let c := { c with log := [AppTests.line 0 "~alice added ~bob", AppTests.line 1 "hello alice" bob,
    AppTests.line 2 "a message\nof two lines" bob, AppTests.line 3 "hi bob" me .pending, AppTests.line 4 "sent" me] }
  let start := (Paw.Runtime.start (AppTests.mkApp sent) (Rect.ofXYWH 0 0 (px 1000) (px 700)) 0 Linux.measure (motion := false)).1
  write start (dir / "empty.png")
  let (rt, _) := start.results [App.Msg.state { me := "alice", chats := [c, { name := "other" }] }] 100
  write rt (dir / "chat.png")
  let joining : Chat := { name := "theirs", joining := some (.awaiting "SGVsbG8gdm91Y2hlciBjb2RlIHRoYXQgaXMgcXVpdGUgbG9uZyBpbmRlZWQ=" .empty .empty .empty) }
  let (rt, _) := start.results [App.Msg.state { me := "alice", chats := [joining] }] 100
  write rt (dir / "joining.png")
  let r ← AppTests.state (AppTests.begin sent) { me := "alice", chats := [AppTests.chatWith "g" [AppTests.line 0 "a notice"]] }
  let r ← AppTests.click r "leave"
  write r.rt (dir / "dialog.png")
  FilesTests.setup
  let me := (c.group.map (·.me)).getD .empty
  let files := { c with
    log := [AppTests.line 0 "look at this" bob, { FilesTests.picture 1 "pic.png" "attachments/g/0-1-pic.png" with sender := bob },
      { FilesTests.picture 2 "report.txt" "attachments/g/0-2-report.txt" "arbitrary" with sender := bob },
      { FilesTests.picture 3 "cat.png" "attachments/g/0-3-cat.png" with sender := me, status := .pending }],
    jobs := [{ id := 0, box := .empty, line := some 3, upload := some { file := "", boxSize := 1530, total := 40, sent := 13 } }] }
  IO.FS.writeBinFile (FilesTests.stateDir / "attachments" / "g" / "0-3-cat.png") (FilesTests.png 200 120)
  let measured : AppTests.Run sent :=
    { rt := (Paw.Runtime.start (AppTests.mkApp sent) (Rect.ofXYWH 0 0 (px 1000) (px 700)) 0 Linux.measure (motion := false)).1 }
  let r ← AppTests.state measured { me := "alice", chats := [files] }
  let r ← AppTests.state r { me := "alice", chats := [files] }
  write r.rt (dir / "files.png")
  let r ← AppTests.click r "attach"
  write r.rt (dir / "attach.png")
  let r ← AppTests.click r "cancel"
  let r ← AppTests.click r "view:1"
  write r.rt (dir / "view.png")
  -- The pictures live as long as the model holding them, which must outlive the drawing.
  discard <| AppTests.click r "accept"
  VoiceTests.setup
  let voice := { c with log := [AppTests.line 0 "listen to this" bob,
    { VoiceTests.voiceLine 5 "attachments/g/0-5-ab.opus" with sender := bob }] }
  let r ← AppTests.state measured { me := "alice", chats := [voice] }
  let r ← AppTests.click r "play:5"
  let r ← VoiceTests.press r "talk"
  let r ← AppTests.other r .poll
  write r.rt (dir / "recording.png")
  let r ← VoiceTests.release r "talk"
  write r.rt (dir / "voice.png")

/-- Alice, Bob and Carol in a group over the simulated Pigeonhole, after a short conversation:
Alice's state, with her last message still on its way. -/
def conversation : IO (Option Chat) := do
  let world ← IO.mkRef ({} : Sim.World)
  let net : Net := { cores := #["alice", "bob", "carol"].map fun me => { present := presentation, state := { me } } }
  let say (who : Nat) (text : String) : NetM Bool := do
    feed who (.send "friends" text)
    runUntil world fun n => [0, 1, 2].all (says n · "friends" text)
  let (ok, net) ← (do
    feed 0 (.create "friends")
    for who in [1, 2] do
      feed who (.join "friends")
      unless ← runUntil world fun n => (code? n who "friends").isSome do return false
      let some code := code? (← get) who "friends" | return false
      feed 0 (.induct "friends" code)
      unless ← runUntil world fun n => joined n who "friends" &&
          !(chatOf n 0 "friends").any (fun (c : Chat) => c.inducting.isSome) do
        return false
    let mut ok := true
    for (who, text) in [(1, "Did everyone get the notes from Thursday?"), (1, "I put them in the shared folder."),
        (2, "Yes. The second half was a lot to take in.\nI'll write up a summary tonight."),
        (0, "Got them, thanks. Coffee on Saturday to go through it?"),
        (1, "Saturday works for me."), (2, "Same. 10 at the usual place?")] do
      ok := ok && (← say who text)
    feed 0 (.send "friends" "10 it is, see you there")
    return ok).run net
  if !ok then return none
  return chatOf net 0 "friends"

/-- The picture in the README: Alice's window, in the dark theme, with three groups, one of them a conversation. -/
def readme (path : System.FilePath) : IO Unit := do
  let some friends ← conversation | throw (IO.userError "the conversation did not finish")
  let friends := { friends with log := friends.log.filter fun l =>
    !(l.text.startsWith "a new group" || l.text.startsWith "reading the voucher") }
  -- Times as a morning's conversation would have them: 09:12 on, a minute or two apart.
  let base := 1792055520000
  let friends := { friends with log := friends.log.zipIdx.map fun (l, k) =>
    { l with time := some (base + k * 95000) } }
  let work := AppTests.chatWith "work" [AppTests.line 0 "a new group: Invite, with a member's voucher code, adds them",
    AppTests.line 1 "added ~dana: they now read everything said in this group",
    AppTests.line 2 "added ~eli: they now read everything said in this group"]
  let book : Chat := { name := "book club", joining := some (.awaiting "" .empty .empty .empty) }
  let app := App.app (fun _ => pure ()) AppTests.fakeAudio { state := { me := "alice" }, network := "daemon @katzenpost" }
  let rt := (Paw.Runtime.start app (Rect.ofXYWH 0 0 (px 1000) (px 640)) 0 Linux.measure (motion := false) (theme := Theme.dark)).1
  let logs := #["18:20:29.973 NOTI echo-chat: started as alice", "18:21:02.114 INFO echo-chat/net: friends: read box 41: 212 bytes",
    "18:21:15.611 INFO echo-chat/driver: replica epoch 488", "18:21:40.020 INFO echo-chat/net: friends: wrote job 7 at box 12"]
  let (rt, _) := rt.results [App.Msg.state { me := "alice", chats := [friends, work, book] }, .logs logs] 100
  let scene := match rt.present with | .request (.present s) => s | _ => Scene.empty
  IO.FS.writeBinFile path (Linux.renderPng scene 2000 1280 2000)

/-- A saved state for the end-to-end tests: Alice in a group of three, and a second group. -/
def fixture (dir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll dir
  let some c ← DisplayTests.threeMembers | throw (IO.userError "no group")
  let bob := (c.names.pairs.find? (·.2 == "bob")).map (·.1) |>.getD .empty
  let c := { c with log := [AppTests.line 0 "~alice added ~bob", AppTests.line 1 "hello alice" bob] }
  let s : State := { me := "alice", chats := [c, AppTests.chatWith "second" [AppTests.line 0 "a notice"]] }
  IO.FS.writeBinFile (dir / "state.cbor") (GroupChatClient.GroupChatKatzenqt1.Persist.save s)

end EchoChat.Tests.Shot
