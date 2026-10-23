/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import GroupChatClient.GroupChatKatzenqt1.Core

/-! # What each action asks of the core

One function per thing the user can do: the checks it needs, the message for the core, the group
to select once it appears, and echo-chat's note on it. -/

namespace EchoChat.Command

open Cryptlib.Protocols.GroupComm.Common
open Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member
open GroupChatClient GroupChatClient.GroupChatKatzenqt1

structure Asked where
  msg : Option Msg := none
  /-- A group to select once it appears. -/
  want : Option String := none
  note : String := ""

def taken (s : State) (name : String) : Bool := s.chats.any (·.name == name)

def clean (name : String) : String := name.trimAscii.toString

def newGroup (s : State) (name : String) : Asked :=
  let name := clean name
  if name.isEmpty then { note := "a new group needs a name" }
  else if taken s name then { want := some name, note := s!"you already have a group called {name}" }
  else { msg := some (.create name), want := some name }

def joinGroup (s : State) (name : String) : Asked :=
  let name := clean name
  if name.isEmpty then { note := "give the group a name to know it by here" }
  else if taken s name then
    { want := some name,
      note := s!"you already have a group called {name}: to join someone else's group, give it a name of its own" }
  else { msg := some (.join name), want := some name,
         note := "a voucher code will appear: give it to a member of the group, who adds you with Invite" }

def invite (chat : Option String) (code : String) : Asked :=
  match chat with
  | none => { note := "select a group first" }
  | some c =>
    let code := code.trimAscii.toString
    if code.isEmpty then { note := "paste the voucher code the new member gave you" }
    else { msg := some (.induct c code),
           note := s!"whoever holds that code will read everything said in {c} from now on" }

def send (chat : Option String) (text : String) : Asked :=
  match chat with
  | none => { note := "create or join a group first" }
  | some c => if text.trimAscii.isEmpty then {} else { msg := some (.send c text) }

def scan (chat : Option String) : Asked :=
  match chat with
  | none => { note := "select a group first" }
  | some c => { msg := some (.scan c) }

def clear (chat : Option String) : Asked :=
  match chat with
  | none => { note := "select a group first" }
  | some c => { msg := some (.clear c) }

/-- Call `chat` `to` here, and select it by its new name. -/
def rename (s : State) (chat : Option String) (to : String) : Asked :=
  match chat with
  | none => { note := "select a group first" }
  | some c =>
    let to := clean to
    if to.isEmpty || to == c then { note := s!"type a new name for {c}" }
    else if taken s to then { note := s!"you already have a group called {to}" }
    else { msg := some (.rename c to), want := some to, note := s!"renamed {c} to {to}" }

/-- Leave `chat` only when `typed` is its name. -/
def leave (chat : Option String) (typed : String) : Asked :=
  match chat with
  | none => { note := "select a group first" }
  | some c =>
    if clean typed == c then { msg := some (.leave c), note := s!"left {c}" }
    else { note := s!"to leave {c} and delete it here, type its name" }

def remove (s : State) (chat : Option String) (who : Key) : Asked :=
  match chat.bind s.chat? with
  | none => { note := "select a group first" }
  | some c =>
    if c.group.any (·.me == who) then { note := "to stop reading yourself, leave the group" }
    else if c.group.any (·.readers.contains who) then { msg := some (.remove c.name who) }
    else { note := "that member is no longer in this group" }

end EchoChat.Command
