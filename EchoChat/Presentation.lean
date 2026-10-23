/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import EchoChat.Display
import GroupChatClient.GroupChatKatzenqt1.Presentation

/-! # How echo-chat words and filters what the core says -/

namespace EchoChat

open GroupChatClient.GroupChatKatzenqt1

def presentation : Presentation where
  name s := (Display.name s).text
  outgoing := Display.outgoing
  newGroup := "a new group: Invite, with a member's voucher code, adds them"
  voucherMinted _ _ file :=
    s!"give the voucher code shown above to a member of the group, who adds you with Invite (it is also in {file} in the state directory)"

end EchoChat
