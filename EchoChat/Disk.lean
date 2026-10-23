/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Image
import GroupChatClient.GroupChatKatzenqt1.Files

/-! # Files on this machine

What echo-chat reads and writes besides its state, each on a task the user's click starts: a folder
listed to choose a file, a file read to send, a file received copied out, and a picture decoded to
show. -/

namespace EchoChat.Disk

open GroupChatClient.GroupChatKatzenqt1

structure Entry where
  name : String
  dir : Bool
  size : Nat
  deriving BEq, Inhabited, Repr

/-- `~` and `~/…` as the home directory. -/
def expand (home path : String) : System.FilePath :=
  if path == "~" then home
  else if path.startsWith "~/" then System.FilePath.mk home / (path.drop 2).toString
  else path

/-- A folder's entries, folders first, each part by name; hidden ones left out. -/
def list (dir : System.FilePath) : IO (Except String (List Entry)) := do
  try
    let mut out : Array Entry := #[]
    for e in ← dir.readDir do
      if e.fileName.startsWith "." then continue
      try
        let m ← e.path.metadata
        out := out.push { name := e.fileName, dir := m.type == .dir, size := m.byteSize.toNat }
      catch _ => continue
    let sorted := out.qsort fun a b => if a.dir != b.dir then a.dir else a.name.toLower < b.name.toLower
    return .ok sorted.toList
  catch e => return .error (toString e)

/-- A file to send: its name and bytes, if it is a file no larger than one can be. -/
def readUpload (path : System.FilePath) : IO (Except String (String × ByteArray)) := do
  try
    let m ← path.metadata
    if m.type == .dir then return .error "that is a folder: choose a file"
    if m.byteSize.toNat > Files.maxFile then
      return .error s!"that file is too large to send: at most {Files.maxFile / (1024 * 1024)} MB"
    return .ok ((path.fileName.getD "unnamed"), ← IO.FS.readBinFile path)
  catch e => return .error (toString e)

/-- Copy `src` to `dst`, which must not exist yet. -/
def copyOut (src dst : System.FilePath) : IO (Except String Unit) := do
  try
    if ← dst.pathExists then return .error s!"{dst} already exists: choose another name"
    let bytes ← IO.FS.readBinFile src
    let h ← IO.FS.Handle.mk dst .writeNew
    h.write bytes
    h.flush
    return .ok ()
  catch e => return .error (toString e)

/-- Why a picture is not shown. -/
inductive Unshown
  /-- Its file is not there, or not yet. -/
  | missing
  | refused (why : String)
  deriving Repr, BEq

/-- A picture from its file. -/
def picture (path : System.FilePath) : IO (Except Unshown Paw.Image) := do
  try
    let bytes ← IO.FS.readBinFile path
    match ← Paw.Image.decode bytes with
    | .ok img => return .ok img
    | .error .format => return .error (.refused "not a PNG or JPEG")
    | .error .tooLarge => return .error (.refused "too large to show")
    | .error .corrupt => return .error (.refused "damaged")
  catch _ => return .error .missing

/-- The size to show a picture of `w` × `h` pixels at, within `maxW` × `maxH`, never larger than
it is. -/
def fit (w h maxW maxH : Nat) : Nat × Nat :=
  let (w, h) := (max w 1, max h 1)
  if w ≤ maxW && h ≤ maxH then (w, h)
  else if w * maxH ≤ h * maxW then (max 1 (w * maxH / h), maxH)
  else (maxW, max 1 (h * maxW / w))

end EchoChat.Disk
