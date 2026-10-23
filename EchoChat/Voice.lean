/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw
import RusticAudio
import Cryptlib.Primitives.Hash.Sha2
import EchoChat.Display

/-! # Voice notes

Recording a voice note while a button or Ctrl+Space is held, and playing voice notes, through
Rustic Audio. A voice note goes to the group as a file `<sha256>.opus` of type `audio/opus`, as
katzenqt names them, so that its name tells nothing of when or by whom it was recorded. -/

namespace EchoChat.Voice

open Paw Paw.Widgets
open RusticAudio (Clip)

/-- What echo-chat asks of the sound system. -/
structure Audio where
  start : IO Unit
  stop : IO Clip
  cancel : IO Unit
  play : String → IO Unit
  stopPlay : IO Unit
  playing : IO Bool
  error : IO (Option String)
  /-- Why there is no sound, when there is none. -/
  off : Option String := none

def Audio.silent (why : String) : Audio where
  start := throw (IO.userError why)
  stop := throw (IO.userError why)
  cancel := pure ()
  play _ := throw (IO.userError why)
  stopPlay := pure ()
  playing := pure false
  error := pure none
  off := some why

def Audio.engine (e : RusticAudio.Engine) : Audio where
  start := discard <| e.startCapture (some "voice-note")
  stop := e.stopCapture
  cancel := discard e.cancelCapture
  play := e.play
  stopPlay := e.stopPlayback
  playing := e.isPlaying
  error := e.takePlaybackError

/-- The sound system, with drafts kept in `dir`; or none, and why. -/
def Audio.open (dir : System.FilePath) : IO Audio := do
  if !RusticAudio.abiMatches then return .silent "the sound library does not match echo-chat"
  try
    -- A draft not sent before echo-chat stopped is not kept.
    if ← dir.pathExists then IO.FS.removeDirAll dir
    IO.FS.createDirAll dir
    return .engine (← RusticAudio.Engine.new dir.toString)
  catch e => return .silent s!"no sound: {e}"

/-- A recording shorter than this is taken for a slip, and thrown away. -/
def shortest : Nat := 300

/-- The longest recording; one held longer stops there, in case a release went astray. -/
def longest : Nat := 10 * 60 * 1000

/-- The name a voice note is sent under. -/
def nameOf (bytes : ByteArray) : String :=
  Display.hex (Cryptlib.Primitives.Hash.Sha2.Sha256.hash bytes).val ++ ".opus"

def isVoice (filetype : String) : Bool := filetype == "audio/opus"

/-- Seconds, to a tenth. -/
def seconds (ms : Nat) : String := s!"{ms / 1000}.{ms % 1000 / 100} s"

/-- A button that emits `onPress` when pressed and `onRelease` when let go, wherever the pointer
is by then. -/
def holdButton {Msg : Type} (caption : SafeText) (onPress onRelease : Msg) (held : Bool) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "hold-button"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      let (padX, padY) := env.theme.button.padding
      (SizeReq.fixedSize (w + 2 * padX).toNat, SizeReq.fixedSize (h + 2 * padY).toNat)
    render := fun env _ v =>
      let s := env.look (if held then env.theme.mainButton else env.theme.button)
      let style := { textStyle env with color := s.fg }
      let (w, _) := env.measure style caption
      Scene.inBox v (frame v s ++ [centeredText env v (v.x0 + (v.width - w) / 2) caption style])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .press .. => some (st, [.emit onPress])
      | .release .. => some (st, [.emit onRelease])
      | .enter _ | .leave _ | .click .. | .focus | .blur => some (st, [])
      | _ => none
    cursor := fun env _ => (env.look env.theme.button).cursor
    access := fun _ _ => some { role := .button, name := caption } }

/-- Emits a binding's message when its keys are pressed in the child, `onPress` when Ctrl+Space
is, and `onRelease` when Space is let go, with whatever keys are held; each only where the child
does not handle them. -/
def keysWidget {Msg : Type} (bindings : List (KeyCombo × Msg)) (onPress onRelease : Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "keystroke"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun _ _ _ => Scene.empty
    render_within := fun _ _ v => Scene.empty_within v
    handle := fun _ st _ e => match e with
      | .key (.char ' ') m true => if m.ctrl then some (st, [.emit onPress]) else none
      | .key (.char ' ') _ false => some (st, [.emit onRelease])
      | .key k m true => (bindings.find? (·.1.matches k m)).map fun (_, msg) => (st, [.emit msg])
      | _ => none }

/-- `Ui.keystroke`, and Ctrl+Space held. -/
def keys {Msg : Type} (bindings : List (KeyCombo × Msg)) (onPress onRelease : Msg) (child : Node Msg) : Node Msg :=
  Node.containerWith (keysWidget bindings onPress onRelease) (box { expand := true }) [child]

end EchoChat.Voice
