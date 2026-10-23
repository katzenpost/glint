/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Linux
import EchoChat.Tests.App

/-! # Files

Choosing a file to send, pictures shown in the conversation and large, and saving a file
received, with files on disk under `AppTests.testDir`. -/

namespace EchoChat.Tests.FilesTests

open EchoChat EchoChat.Tests EchoChat.Tests.AppTests Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1

def home : System.FilePath := testDir / "home"
def stateDir : System.FilePath := testDir / "state"

/-- A picture `w` × `h` pixels: a sky in bands, and a sun. -/
def png (w h : Nat) : ByteArray :=
  let (W, H) : Int × Int := (px w, px h)
  let all := Rect.ofXYWH 0 0 W H
  let band (i : Nat) : Rect × Draw :=
    (all, .fill (Rect.ofXYWH 0 (H * i / 6) W (H / 6 + px 1))
      (Color.rgb (40 + 30 * i).toUInt8 (90 + 20 * i).toUInt8 (220 - 25 * i).toUInt8) 0)
  let sun : Rect × Draw := (all, .fill (Rect.ofXYWH (W * 3 / 5) (H / 6) (H / 3) (H / 3)) (Color.rgb 250 210 60) (H / 6))
  Linux.renderPng { items := (List.range 6).map band ++ [sun] } w h

def setup : IO Unit := do
  if ← testDir.pathExists then IO.FS.removeDirAll testDir
  IO.FS.createDirAll (home / "docs")
  IO.FS.createDirAll (stateDir / "attachments" / "g")
  IO.FS.writeBinFile (home / "cat.png") (png 40 30)
  IO.FS.writeFile (home / "docs" / "notes.txt") "hello"
  IO.FS.writeBinFile (stateDir / "attachments" / "g" / "0-1-pic.png") (png 640 480)
  IO.FS.writeFile (stateDir / "attachments" / "g" / "0-2-report.txt") "the report"

def fitting : TestM Unit := do
  checkEq "a small picture keeps its size" (100, 50) (Disk.fit 100 50 320 240)
  checkEq "a large one shrinks to the box" (320, 240) (Disk.fit 640 480 320 240)
  checkEq "a wide one to its width" (320, 32) (Disk.fit 1000 100 320 240)
  checkEq "a tall one to its height" (24, 240) (Disk.fit 100 1000 320 240)

def attaching : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r ← state (begin sent) { me := "alice", chats := [chatWith "g" []] }
  let r ← click r "attach"
  let names (r : Run sent) := ((r.rt.model.dialog.map (·.entries)).getD []).map (·.name)
  check "Attach opens a dialog listing the home folder, folders first"
    (r.rt.model.dialog.any (·.kind == .attach) && names r == ["docs", "cat.png"]) fun _ => toString (names r)
  let r ← click r "entry:docs"
  check "a folder clicked is opened" (names r == ["notes.txt"])
  let r ← click r "up"
  check "and Up goes back" (names r == ["docs", "cat.png"])
  let r ← click r "accept"
  check "with nothing chosen, nothing is sent" ((← sent.get).isEmpty && r.rt.model.dialog.any (!·.note.isEmpty))
  let r ← click r "entry:cat.png"
  check "a file clicked fills in its path"
    (r.rt.model.dialog.any (·.field == (home / "cat.png").toString))
  let r ← click r "accept"
  let posted ← last sent
  check "Send reads it and sends it to the group"
    (posted == some s!"g: send a file of {(png 40 30).size} bytes") fun _ => toString posted
  check "and closes" r.rt.model.dialog.isNone
  check "the folder is remembered" (r.rt.model.lastDir == some home.toString)
  let r ← click r "attach"
  let r ← click r "dialog-field"
  let r ← typeText r "~/nothing-here"
  let r ← click r "accept"
  check "a file that is not there is refused, in the dialog"
    (r.rt.model.dialog.any fun d => d.kind == .attach && !d.note.isEmpty)
  let r ← other r (.view 1)
  check "View of origin other opens nothing" (r.rt.model.dialog.any (·.kind == .attach))

def picture (id : Nat) (name file : String) (filetype := "image/png") : Line :=
  { id, sender := ByteArray.mk #[9], text := s!"[file {name}]",
    attachment := some { name, filetype, size := 10, file } }

def pictures : TestM Unit := do
  let sent ← IO.mkRef #[]
  let log := [picture 1 "pic.png" "attachments/g/0-1-pic.png",
    picture 2 "report.txt" "attachments/g/0-2-report.txt" "arbitrary",
    picture 3 "late.png" "attachments/g/0-3-late.png"]
  let s : State := { me := "alice", chats := [chatWith "g" log] }
  let r ← state (begin sent) s
  let shown := r.rt.tree.findKey? "picture:1"
  check "a picture received is shown in the conversation" shown.isSome
  check "no larger than the box for it" (shown.any fun n => n.viewport.width == px 320 && n.viewport.height == px 240)
    fun _ => toString (shown.map fun n => (n.viewport.width / px 1, n.viewport.height / px 1))
  check "a file that is not a picture shows its name and a Save button"
    ((r.rt.tree.findKey? "picture:2").isNone && (r.rt.tree.findKey? "save:2").isSome && (textsOf r "line:2").contains "report.txt")
  check "a picture whose file is not there yet says so"
    ((r.rt.tree.findKey? "picture:3").isNone && (textsOf r "line:3").any (·.endsWith "not received yet"))
  IO.FS.writeBinFile (stateDir / "attachments" / "g" / "0-3-late.png") (png 50 50)
  let r ← state r s
  check "and is shown once it is" (r.rt.tree.findKey? "picture:3").isSome
  let r ← click r "view:1"
  check "View shows the picture large" ((r.rt.tree.findKey? "picture-large").any fun n => n.viewport.width == px 640)
  let r ← click r "accept"
  check "and Close closes it" r.rt.model.dialog.isNone
  let r ← click r "save:2"
  check "Save offers the file's name in the downloads folder"
    (r.rt.model.dialog.any fun d => d.kind == .save && d.field == (home / "report.txt").toString)
  let r ← click r "accept"
  check "and writes it there" ((← IO.FS.readFile (home / "report.txt")) == "the report" && r.rt.model.dialog.isNone)
  let r ← click r "save:2"
  let r ← click r "accept"
  check "a file already there is not overwritten" (r.rt.model.dialog.any fun d => d.note.endsWith "choose another name")
    fun _ => (r.rt.model.dialog.map (·.note)).getD ""
  let r ← other r (.saveAs 1)
  check "Save of origin other changes nothing" (r.rt.model.dialog.any (·.line == some 2))

def tests : TestM Unit := do
  setup
  fitting
  attaching
  pictures

end EchoChat.Tests.FilesTests
