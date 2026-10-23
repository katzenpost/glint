/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import EchoChat.Command
import GroupChatClient.GroupChatKatzenqt1.Shell
import EchoChat.Tests.Util

/-! # What each action asks of the core -/

namespace EchoChat.Tests.CommandTests

open EchoChat EchoChat.Tests EchoChat.Command
open GroupChatClient GroupChatClient.GroupChatKatzenqt1
open Cryptlib.Protocols.GroupComm.Common
open Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member

def asks (a : Asked) (expected : String) : Bool := (a.msg.map (·.describe)) == some expected

def silent (a : Asked) : Bool := a.msg.isNone

def tests : TestM Unit := do
  let me : Key := ByteArray.mk #[1, 2, 3]
  let bob : Key := ByteArray.mk #[4, 5, 6]
  let g : Chat := { name := "g", group := some (Group.found (me ++ ByteArray.mk (List.replicate 133 0).toArray) []) }
  let s : State := { me := "alice", chats := [g] }
  check "new group creates it" (asks (newGroup s " h ") "h: create")
  check "and selects it once it appears" ((newGroup s "h").want == some "h")
  check "a new group needs a name" (silent (newGroup s "  ") && !(newGroup s "").note.isEmpty)
  check "a name already taken is refused, and says why"
    (silent (newGroup s "g") && (newGroup s "g").note == "you already have a group called g")
  check "join joins under a name of its own" (asks (joinGroup s "h") "h: join")
  check "and says a voucher code will appear" ((joinGroup s "h").note.startsWith "a voucher code will appear")
  check "join under a name taken is refused"
    (silent (joinGroup s "g") && (joinGroup s "g").note.startsWith "you already have a group called g: to join")
  check "invite needs a group" (silent (invite none "code") && (invite none "code").note == "select a group first")
  check "invite needs a code" (silent (invite (some "g") " "))
  check "invite inducts with the code" (asks (invite (some "g") " QUJD ") "g: add a member" &&
    (match (invite (some "g") " QUJD ").msg with | some (.induct "g" "QUJD") => true | _ => false))
  check "and says what that means"
    ((invite (some "g") "x").note == "whoever holds that code will read everything said in g from now on")
  check "send sends to the group given" (match (send (some "g") "hi\nthere").msg with
    | some (.send "g" "hi\nthere") => true | _ => false)
  check "send with nothing typed does nothing" (silent (send (some "g") " \n ") && (send (some "g") "").note.isEmpty)
  check "send with no group says so" (silent (send none "hi") && !(send none "hi").note.isEmpty)
  check "scan scans the group" (asks (scan (some "g")) "g: scan")
  check "clear clears the group" (asks (clear (some "g")) "g: clear")
  check "leave needs the group's name typed" (silent (leave (some "g") "h") &&
    (leave (some "g") "h").note == "to leave g and delete it here, type its name")
  check "leave with its name leaves" (asks (leave (some "g") " g ") "g: leave")
  check "rename renames the group" (asks (rename s (some "g") " friends ") "g: rename to friends")
  check "and selects it by its new name" ((rename s (some "g") "friends").want == some "friends")
  check "rename needs a new name" (silent (rename s (some "g") " ") && silent (rename s (some "g") "g") &&
    (rename s (some "g") "g").note == "type a new name for g")
  check "rename to a name taken is refused"
    (silent (rename { s with chats := s.chats ++ [{ name := "h" }] } (some "g") "h"))
  check "rename needs a group" (silent (rename s none "h"))
  check "remove needs a member of the group" (silent (remove s (some "g") bob) &&
    (remove s (some "g") bob).note == "that member is no longer in this group")
  check "remove needs a group" (silent (remove s none bob))

end EchoChat.Tests.CommandTests
