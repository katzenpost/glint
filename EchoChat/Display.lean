/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Text
import GroupChatClient.GroupChatKatzenqt1.State

/-! # What may reach the screen

Text from the network reaches a widget only as Paw's `SafeText` or `SafeName`. This module adds
echo-chat's own rules on top of Paw's: what a member's name may hold and how long it may be, and how a
member is named, since a display name is only what its owner chose. -/

namespace EchoChat.Display

open Paw Paw.Text
open GroupChatClient GroupChatClient.GroupChatKatzenqt1
open Cryptlib.Protocols.GroupComm.Common
open Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member

/-- Characters of a name shown. -/
def maxName : Nat := 30

/-- Characters a name may not hold, even where a message may: echo-chat's marks of a message's state
(`…`, `✓`, `✓✓`), crosses and locks, and the substitute Paw shows for a character refused. -/
def mark (n : Nat) : Bool :=
  inRanges n [(0x2713, 0x2718), (0x2026, 0x2026), (0x1F512, 0x1F513), (0x1F6E1, 0x1F6E1),
    (0x2400, 0x2426), (0xFFFD, 0xFFFD)]

/-- One line of text from elsewhere. -/
def text (s : String) : SafeText := SafeText.filter s

/-- A message's text as lines, at most 20, the last saying how many more there were. -/
def body (s : String) : List SafeText := SafeText.lines s 20

/-- A member's name: one line, none of echo-chat's marks, at most `maxName` characters, the rest cut
with an ellipsis echo-chat draws. -/
def name (s : String) : SafeName :=
  let kept := (SafeName.filter s).text.toList.map fun c => if mark c.toNat then '?' else c
  let kept := if kept.isEmpty then ['?'] else kept
  SafeName.filter (if kept.length > maxName then String.ofList (kept.take (maxName - 1)) ++ "…"
    else String.ofList kept)

/-- Text the user typed or pasted, as it is sent: without control characters other than newlines
and tabs, and without bidi controls, which another client might obey. -/
def outgoing (s : String) : String :=
  String.ofList (s.toList.filter fun c =>
    c == '\n' || c == '\t' || !(control c.toNat || bidiControl c.toNat))

/-- A log line: one line, filtered, so that reading the log in a terminal is safe. -/
def logLine (s : String) : String := (SafeText.filter s).text

def hexByte (b : UInt8) : String :=
  let s := String.ofList (Nat.toDigits 16 b.toNat)
  if s.length < 2 then "0" ++ s else s

def hex (b : ByteArray) : String := String.join (b.data.toList.map hexByte)

/-- The start of a member's key. -/
def fingerprint (key : ByteArray) : String := hex (key.extract 0 2)

/-- The members whose names could be taken for another's, ours included, or that mix scripts. -/
def doubtful (me : String) (c : Chat) : List ByteArray :=
  match c.group with
  | none => []
  | some g =>
    let named := g.readers.keys.map fun k => (k, skeleton ((c.names.get? k).getD "?"))
    let mine := skeleton me
    named.filterMap fun (k, sk) =>
      let n := (c.names.get? k).getD "?"
      if sk == mine || (named.filter (·.2 == sk)).length > 1 || mixedScript n then some k
      else none

/-- How a member is named: `me`, or the name they chose after `~`, with the start of their key
when it could be mistaken. No name a member chooses can be `me`, since theirs begins with `~`. -/
def who (me : String) (c : Chat) (key : ByteArray) : SafeText :=
  if c.group.any (·.me == key) then SafeText.trusted "me"
  else
    let n := SafeText.trusted "~" ++ (name ((c.names.get? key).getD "?")).toText
    if (doubtful me c).contains key then n ++ SafeText.trusted s!" ({fingerprint key})" else n

/-- A member of a group as listed: how they are named, their key, the start of it, and whether
their name could be mistaken. -/
structure Member where
  label : SafeText
  key : ByteArray
  doubtful : Bool

/-- Everyone who reads the group: ourselves, then the others by name. -/
def members (me : String) (c : Chat) : List Member :=
  match c.group with
  | none => []
  | some g =>
    let doubt := doubtful me c
    let others := g.readers.keys.map fun k => ((c.names.get? k).getD "?", k)
    { label := SafeText.trusted "me", key := g.me, doubtful := false } ::
      (others.mergeSort (fun a b => a.1 ≤ b.1)).map fun (n, k) =>
        { label := SafeText.trusted "~" ++ (name n).toText, key := k, doubtful := doubt.contains k }

/-- A time of day, `HH:MM`, at `offset` seconds from UTC. -/
def clock (offset : Int) (ms : Nat) : String :=
  let secs := ((ms / 1000 : Nat) : Int) + offset
  let day := secs % 86400
  let two (n : Int) := let s := toString n; if s.length < 2 then "0" ++ s else s
  s!"{two (day / 3600)}:{two (day % 3600 / 60)}"

/-- Which day a time falls on, at `offset` seconds from UTC: days since the Unix epoch. -/
def dayOf (offset : Int) (ms : Nat) : Int := (((ms / 1000 : Nat) : Int) + offset) / 86400

def monthNames : List String :=
  ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

/-- A day as `Mon D`, from days since the Unix epoch, by the proleptic Gregorian calendar. -/
def date (day : Int) : String :=
  -- Howard Hinnant's days_from_civil, inverted.
  let z := day + 719468
  let era := (if z ≥ 0 then z else z - 146096) / 146097
  let doe := z - era * 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let d := doy - (153 * mp + 2) / 5 + 1
  let m := if mp < 10 then mp + 3 else mp - 9
  s!"{monthNames.getD (m - 1).toNat "?"} {d}"

/-- Lines a conversation shows together: a run of messages from one sender, each within five
minutes of the one before (as Element groups them), or a notice alone. -/
inductive Run
  | messages (sender : Key) (lines : List Line)
  | notice (line : Line)

def Run.first : Run → Option Line
  | .messages _ ls => ls.head?
  | .notice l => some l

/-- How long apart two messages of one sender may be and still be one run. -/
def runGap : Nat := 5 * 60 * 1000

/-- A conversation's lines in runs. -/
def runs (log : List Line) : List Run :=
  let close (a b : Line) : Bool := match a.time, b.time with
    | some x, some y => y ≤ x + runGap && x ≤ y + runGap
    | _, _ => true
  (log.foldl (fun (acc : List Run) l =>
    if l.sender.size == 0 then .notice l :: acc
    else match acc with
      | .messages s ls :: rest =>
        if s == l.sender && (ls.getLast?.all (close · l)) then .messages s (ls ++ [l]) :: rest
        else .messages l.sender [l] :: acc
      | _ => .messages l.sender [l] :: acc) []).reverse

/-- Lines of a conversation not yet seen, by how many of each were. -/
def unread (seen : List (String × Nat)) (c : Chat) : Nat :=
  c.log.length - ((seen.lookup c.name).getD 0)

/-- A group's row in the list: its name, how many lines are unread, and what is under way. -/
def groupRow (seen : List (String × Nat)) (c : Chat) : String :=
  let n := unread seen c
  let state := if c.joining.isSome then " joining…" else if c.inducting.isSome then " adding…"
    else if c.group.isNone then " …" else ""
  (name c.name).text ++ (if n > 0 then s!" ({n})" else "") ++ state

end EchoChat.Display
