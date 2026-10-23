/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import GroupChatClient.GroupChatKatzenqt1.Tests.Net
import EchoChat.Tests.Util
import EchoChat.Presentation

/-! # What reaches the screen

A hostile corpus through `name` and `body`, and names that could be taken for another's. -/

namespace EchoChat.Tests.DisplayTests

open EchoChat EchoChat.Tests Paw Paw.Text
open GroupChatClient GroupChatClient.GroupChatKatzenqt1
open GroupChatClient.GroupChatKatzenqt1.Tests
open Cryptlib.Protocols.GroupComm.Common
open Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member

def corpus : List String :=
  ["‮evil‬", "a​b⁠c﻿", "e" ++ String.ofList (List.replicate 40 '́'),
   "alice ✓", "bob ✓✓", "carol…", "🔒 verified", "🛡", "✔ ok", "☑ ✅", " next ",
   "<b>bold</b> &amp; <script>", "\u001b[31mred\u001b[0m", "⁦iso⁩", "tag" ++ (Char.ofNat 0xE0041).toString,
   "‍join‌", "x️", "\u0007bell\u007F", "\u0085nel", "private", "﷐",
   "line\nbreak", "tab\there", "�stand-in", "␛ escape picture", String.ofList (List.replicate 80 'w')]

def nameOk (n : SafeName) : Bool :=
  n.text.toList.all fun c => allowedInName c && (!Display.mark c.toNat || c == '…') &&
    !(c == '\n' || c == '\t')

def textOk (t : SafeText) : Bool := t.text.toList.all allowed

def corpusTests : TestM Unit := do
  for s in corpus do
    let n := Display.name s
    check s!"name {repr s} keeps only allowed characters" (nameOk n) fun _ => repr n.text |>.pretty
    check s!"name {repr s} is at most {Display.maxName} characters" (n.text.length ≤ Display.maxName)
    check s!"name {repr s} holds no ellipsis but echo-chat's" (!(n.text.dropEnd 1).toString.contains '…')
    check s!"body {repr s} keeps only allowed characters" ((Display.body s).all textOk)
  check "a long name ends with echo-chat's ellipsis" ((Display.name (String.ofList (List.replicate 80 'w'))).text.endsWith "…")
  check "a name of marks only is not empty" (!(Display.name "✓✓").text.isEmpty)
  check "markup is shown as text" ((Display.body "<b>bold</b> &amp;").map (·.text) == ["<b>bold</b> &amp;"])
  let long := String.intercalate "\n" ((List.range 30).map toString)
  let lines := Display.body long
  check "a long message is cut at 20 lines" (lines.length == 20)
  check "with a marker saying how many more" ((lines.getLast?.map (·.text)) == some "[11 more lines not shown]")
  check "outgoing text loses bidi and control characters"
    (Display.outgoing "a‮b\u0007c\nd\te" == "abc\nd\te")

def threeMembers : IO (Option Chat) := do
  let world ← IO.mkRef ({} : Sim.World)
  let net : Net := { cores := #["alice", "bob", "carol"].map fun me => { present := presentation, state := { me } } }
  let (ok, net) ← (do
    feed 0 (.create "g")
    for who in [1, 2] do
      feed who (.join "g")
      unless ← runUntil world fun n => (code? n who "g").isSome do return false
      let some code := code? (← get) who "g" | return false
      feed 0 (.induct "g" code)
      unless ← runUntil world fun n => joined n who "g" && !(chatOf n 0 "g").any (fun (c : Chat) => c.inducting.isSome) do
        return false
    return true).run net
  if !ok then return none
  return chatOf net 0 "g"

def keyNamed (c : Chat) (n : String) : Option ByteArray := (c.names.pairs.find? (·.2 == n)).map (·.1)

def doubtfulTests : TestM Unit := do
  let some c ← threeMembers | check "three members join a group" false
  check "three members join a group" true
  let some bob := keyNamed c "bob" | check "alice knows bob" false
  let some carol := keyNamed c "carol" | check "alice knows carol" false
  check "plain names are not doubtful" (Display.doubtful "alice" c).isEmpty
  check "and show no fingerprint" ((Display.who "alice" c bob).text == "~bob")
  -- Carol takes a name that looks like Bob's, with a Cyrillic о.
  let c2 := { c with names := c.names.set carol "bоb" }
  let d := Display.doubtful "alice" c2
  check "names that look alike are both doubtful" (d.contains bob && d.contains carol)
  check "and show the start of their keys"
    ((Display.who "alice" c2 bob).text == s!"~bob ({Display.fingerprint bob})" &&
     (Display.who "alice" c2 carol).text == s!"~bоb ({Display.fingerprint carol})")
  check "the members list marks them" ((Display.members "alice" c2).all fun m =>
    m.doubtful == (m.key == bob || m.key == carol))
  -- Bob takes our own name.
  let c3 := { c with names := c.names.set bob "Alice" }
  check "a member named like us is doubtful" ((Display.doubtful "alice" c3) == [bob])
  check "we are always me" ((Display.who "alice" c (c.group.map (·.me) |>.getD .empty)).text == "me")
  check "a member cannot be me" ((Display.who "alice" { c with names := c.names.set bob "me" } bob).text.startsWith "~")

def tests : TestM Unit := do
  corpusTests
  doubtfulTests

end EchoChat.Tests.DisplayTests
