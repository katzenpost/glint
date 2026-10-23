/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import EchoChat.Tests.App

/-! # Voice notes

Recording while Hold to talk or Ctrl+Space is held, the draft played, discarded or sent, and
voice notes received played, with `AppTests.fakeAudio` for the sound system. -/

namespace EchoChat.Tests.VoiceTests

open EchoChat EchoChat.Tests EchoChat.Tests.AppTests Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1

variable {sent : Sent}

def stateDir : System.FilePath := testDir / "state"

def press (r : Run sent) (k : String) : IO (Run sent) := input r (.press (at_ r k) .primary) 600
def release (r : Run sent) (k : String) : IO (Run sent) := input r (.release (at_ r k) .primary) 100

def ctrlSpace (r : Run sent) (pressed : Bool) : IO (Run sent) :=
  input r (.key (.char ' ') { ctrl := pressed } pressed) 100

def isRecording (r : Run sent) : Bool := match r.rt.model.voice with
  | .recording .. => true
  | _ => false

def draft? (r : Run sent) : Option RusticAudio.Clip := match r.rt.model.voice with
  | .draft _ clip => some clip
  | _ => none

def has (r : Run sent) (k : String) : Bool := (r.rt.tree.findKey? k).isSome

def starts : IO Nat := return ((← sound.get).log.filter (· == "start")).size

def voiceLine (id : Nat) (file : String) : Line :=
  { id, sender := ByteArray.mk #[9], text := "[file voice]",
    attachment := some { name := "ab.opus", filetype := "audio/opus", size := 11, file } }

def setup : IO Unit := do
  if ← testDir.pathExists then IO.FS.removeDirAll testDir
  IO.FS.createDirAll (stateDir / "attachments" / "g")
  IO.FS.writeFile (stateDir / "attachments" / "g" / "0-5-ab.opus") "OggS voice"
  sound.set {}

def recording : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r ← state (begin sent) { me := "alice", chats := [chatWith "g" [], chatWith "h" []] }
  check "a Hold to talk button beside Attach" (has r "talk")
  let r ← press r "talk"
  check "holding it records" (isRecording r && (← sound.get).recording)
  check "and says so" ((textsOf r "voice-status").any (·.startsWith "Recording a voice note"))
  let r ← other r .poll
  check "with how long so far" ((textsOf r "voice-status").any (·.endsWith "s: let go to stop"))
  let r ← release r "talk"
  let some clip := draft? r | check "letting go keeps a draft" false
  check "letting go keeps a draft" (clip.durationMs == 2000 && !(← sound.get).recording)
  check "shown with its length, to play, discard or send"
    ((textsOf r "voice-status") == ["Voice note, 2.0 s"] && has r "draft-play" && has r "draft-discard" && has r "draft-send")
  check "nothing is sent yet" (← sent.get).isEmpty
  let r ← click r "draft-play"
  check "Play plays it" ((← sound.get).playing == some clip.path && has r "draft-stop")
  sound.modify fun s => { s with playing := none }
  let r ← other r .poll
  check "and once it has played, Play again" (r.rt.model.playing.isNone && has r "draft-play")
  let r ← press r "talk"
  check "while a draft waits, holding records nothing" (!isRecording r && (draft? r).isSome)
  let r ← release r "talk"
  let r ← click r "draft-send"
  let some (.sendFile chat name bytes) := (← sent.get).back? | check "Send sends it to the group" false
  check "Send sends it to the group" (chat == "g" && bytes == s!"OggS clip 0".toUTF8)
  check "named by its hash, as katzenqt names voice notes"
    (name == Voice.nameOf bytes && name.length == 64 + 5 && Files.filetypeOf name == "audio/opus") fun _ => name
  check "and the draft is gone" (r.rt.model.voice == .idle && !(← System.FilePath.pathExists clip.path))

def slips : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r ← state (begin sent) { me := "alice", chats := [chatWith "g" [], chatWith "h" []] }
  sound.modify fun s => { s with clipMs := 100 }
  let r ← press r "talk"
  let r ← release r "talk"
  check "a tap records nothing" (r.rt.model.voice == .idle && r.rt.model.note == "hold to record a voice note")
  check "and leaves no file" ((← drafts.readDir).all fun e => !e.fileName.endsWith "-1.opus")
  sound.modify fun s => { s with clipMs := 1500 }
  let r ← press r "talk"
  let r ← release r "talk"
  let some clip := draft? r | check "a draft" false
  let r ← click r "draft-discard"
  check "Discard throws a draft away" (r.rt.model.voice == .idle && !(← System.FilePath.pathExists clip.path))
  check "and sends nothing" (← sent.get).isEmpty
  let r ← press r "talk"
  let r ← click r "group:h"
  check "selecting another group stops recording, keeping nothing"
    (r.rt.model.voice == .idle && (← sound.get).log.back? == some "cancel")
  let r ← click r "group:g"
  sound.modify fun s => { s with fail := some "no audio input device" }
  let r ← press r "talk"
  check "a microphone that fails says why" (r.rt.model.voice == .idle && r.rt.model.note == "no audio input device")
  sound.modify fun s => { s with fail := none }
  let r ← other r .sendDraft
  check "Send of origin other sends nothing" (← sent.get).isEmpty

def keys : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r ← state (begin sent) { me := "alice", chats := [chatWith "g" []] }
  let r ← click r "draft"
  let n ← starts
  let r ← ctrlSpace r true
  check "Ctrl+Space, in the message box, records" (isRecording r)
  let r ← ctrlSpace r true
  let r ← ctrlSpace r true
  check "held, it repeats, and records once" (isRecording r && (← starts) == n + 1)
  let r ← input r (.key (.char ' ') {} false) 100
  check "letting go of Space keeps a draft" (draft? r).isSome
  check "and types nothing" (r.rt.model.draft == "")
  let r ← click r "draft-discard"
  let r ← input r (.key (.char ' ') {} false) 100
  check "Space let go, not recording, is nothing" (r.rt.model.voice == .idle)

def received : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r ← state (begin sent) { me := "alice", chats := [chatWith "g" [voiceLine 5 "attachments/g/0-5-ab.opus",
    voiceLine 6 "attachments/g/0-6-late.opus"]] }
  check "a voice note received shows as one, with Play and Save"
    ((textsOf r "line:5").contains "Voice note" && has r "play:5" && has r "save:5" && !(textsOf r "line:5").contains "ab.opus")
  let r ← click r "play:5"
  check "Play plays echo-chat's copy" ((← sound.get).playing == some (stateDir / "attachments/g/0-5-ab.opus").toString && has r "stop:5")
  let r ← click r "stop:5"
  check "and Stop stops it" ((← sound.get).playing.isNone && has r "play:5")
  let r ← click r "play:5"
  let r ← press r "talk"
  check "recording stops what was playing" (r.rt.model.playing.isNone && has r "play:5")
  let r ← release r "talk"
  let r ← click r "draft-discard"
  let r ← click r "play:6"
  check "one not received yet cannot be played, and says why" (r.rt.model.playing.isNone && r.rt.model.note.endsWith "does not exist")
  let r ← other r (.playLine 5)
  check "Play of origin other plays nothing" (r.rt.model.playing.isNone)

def tests : TestM Unit := do
  setup
  recording
  slips
  keys
  received

end EchoChat.Tests.VoiceTests
