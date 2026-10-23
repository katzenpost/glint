/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import EchoChat.Display
import EchoChat.Display
import EchoChat.Tests.Util

/-! # Times and runs

Times and dates shown, and a conversation cut into runs. -/

namespace EchoChat.Tests.StateTests

open EchoChat EchoChat.Tests
open GroupChatClient GroupChatClient.GroupChatKatzenqt1
open Cryptlib.Protocols.GroupComm.Common
open Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member

def bob : Key := ByteArray.mk #[2]
def carol : Key := ByteArray.mk #[3]

def msg (id : Nat) (sender : Key) (min : Nat) : Line :=
  { id, sender, text := s!"m{id}", time := some (min * 60000) }

def tests : TestM Unit := do
  -- Showing times.
  checkEq "the time of day" "09:12" (Display.clock 0 1792055520000)
  checkEq "at an offset from UTC" "11:12" (Display.clock 7200 1792055520000)
  checkEq "midnight" "00:00" (Display.clock 0 0)
  checkEq "the epoch's date" "Jan 1" (Display.date 0)
  checkEq "a date this year" "Oct 15" (Display.date (Display.dayOf 0 1792055520000))
  checkEq "a leap day" "Feb 29" (Display.date (Display.dayOf 0 1709208000000))
  -- Runs.
  let notice : Line := { id := 9, text := "a notice", time := some 60000 }
  let runs := Display.runs [msg 0 bob 0, msg 1 bob 3, msg 2 carol 4, msg 3 carol 5, notice, msg 4 carol 6, msg 5 carol 20]
  let shape := runs.map fun
    | .messages s ls => s!"{if s == bob then "bob" else "carol"}{ls.map (fun (l : Line) => l.id)}"
    | .notice l => s!"notice{l.id}"
  checkEq "messages are cut into runs by sender, notices and five-minute gaps"
    ["bob[0, 1]", "carol[2, 3]", "notice9", "carol[4]", "carol[5]"] shape
  checkEq "a run's first line" (some 0) ((runs.head?.bind Display.Run.first).map (fun (l : Line) => l.id))

end EchoChat.Tests.StateTests
