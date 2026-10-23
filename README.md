# echo-chat

*echo-chat was called glint until v0.2.0. On its first run it moves a state kept in
`$XDG_DATA_HOME/glint` to `$XDG_DATA_HOME/echo-chat`; `ECHO_CHAT_STATE` and `ECHO_CHAT_LOG`
replace `GLINT_STATE` and `GLINT_LOG`.*

A desktop group chat over the [Katzenpost](https://katzenpost.network) mixnet, written in Lean,
that speaks [katzenqt](https://github.com/katzenpost/katzenqt)'s group chat: an echo-chat member, a
[jam](https://github.com/katzenpost/jam) member and a katzenqt member can be in one group.

- The group chat protocol is Cryptlib's member state machine
  (`Cryptlib/Protocols/GroupComm/GroupChatKatzenqt1/Member`), with its proofs. echo-chat drives the member as katzenqt's
  adapter does and does the IO.
- Boxes are read and written through the client daemon, `kpclientd`, with the Lean
  [thin client](https://github.com/katzenpost/thin_client).
- The window is drawn with [Paw](https://github.com/katzenpost/paw), on X11 or Wayland, and echo-chat
  logs with [Logger](https://github.com/katzenpost/Logger).

![echo-chat: groups on the left, a conversation with delivery marks in the middle, members with the start of their keys on the right](docs/screenshot.png)

## Building

echo-chat is Lean, with small Rust libraries underneath it: Paw's, for the window, one for the
daemon's unix socket, and [rustic_audio_lean](https://github.com/katzenpost/rustic_audio_lean),
for voice notes. You need:

- **Lean**, through [elan](https://github.com/leanprover/elan), which installs the toolchain
  named in `lean-toolchain` by itself.
- **Rust**, through [rustup](https://rustup.rs). Lake runs `cargo` itself while building, so
  `cargo` only has to be on the `PATH`.
- On Debian or Ubuntu, `libxkbcommon-x11-0` to open a window on X11, and `libasound2-dev` and
  `pkg-config` for sound.
- **git**, and about 8 GB of disk.

Then:

    git clone https://github.com/katzenpost/echo-chat
    cd echo-chat
    make build

`make build` runs `lake exe cache get`, which fetches the dependencies and Mathlib's compiled
files (several GB, which Cryptlib needs), then `lake build echo-chat`. The program is
`.lake/build/bin/echo-chat`.

### Verifying a release

The binaries on the [releases](https://github.com/katzenpost/echo-chat/releases) page are
reproducible: the same tag built anywhere with the toolchains it pins gives the same bytes. Each
release is built twice, on two runner images, and published only if both agree. To check one
yourself, with what Building lists and Rust 1.99.0 (`rustup toolchain install 1.99.0`):

    git clone https://github.com/katzenpost/echo-chat
    cd echo-chat
    git checkout v0.2.0
    FROM_SOURCE=1 make release
    curl -fsSL https://github.com/katzenpost/echo-chat/releases/download/v0.2.0/SHA256SUMS | diff - dist/SHA256SUMS

No output from `diff` means your build and the release match. `FROM_SOURCE=1` skips
`lake exe cache get` and builds Mathlib too, so nothing you run was compiled by someone else; it
takes a few hours. Without it, `make release` is quicker and trusts
Mathlib's downloaded files. Either way, `gh attestation verify echo-chat-v0.2.0-x86_64-linux --repo
katzenpost/echo-chat` checks that a downloaded binary was built by this repository's release workflow.

## Running

echo-chat does not reach the mixnet itself. It talks to the Katzenpost client daemon, `kpclientd`,
which does the networking and the cryptography, so start the daemon first, with a client
configuration that says which mixnet to join.

Build `kpclientd` from [katzenpost](https://github.com/katzenpost/katzenpost) with Go, of at least
the version its `go.mod` names:

    git clone https://github.com/katzenpost/katzenpost
    cd katzenpost/cmd/kpclientd && go build

This repository carries the configuration of the namenlos mixnet, in `config/client.toml`. Run the
daemon with it and leave it running:

    ./kpclientd -c /path/to/echo-chat/config/client.toml

It logs to the terminal. Once it has fetched the mixnet's PKI document from the voting authorities
and connected to one of the gateways the file pins, echo-chat can use it. namenlos's gateways change
from time to time; if the daemon cannot connect to any of them, pull this repository for the
latest `config/client.toml`.

The file's `[Listen]` section says where echo-chat finds the daemon: `@katzenpost`, echo-chat's default.
Several echo-chat instances, jam and katzenqt can share one daemon. Then start echo-chat:

    .lake/build/bin/echo-chat --name alice

| Option | |
|---|---|
| `--daemon ADDR` | the daemon's socket: `@katzenpost` (the default), a path, or `HOST:PORT` |
| `--state DIR` | where echo-chat keeps its state and log; by default `$XDG_DATA_HOME/echo-chat/${ECHO_CHAT_STATE:-default}` |
| `--name NAME` | your display name, which others see; remembered after the first run |
| `--log FILE` | the log file, by default `echo-chat.log` in the state directory |
| `--offline` | show the saved state, without a daemon |

`ECHO_CHAT_LOG` sets the log level: `critical`, `error`, `warning`, `notice`, `info` (the default) or
`debug`. echo-chat is dark by default; `PAW_THEME=light` gives the light theme, and
`PAW_REDUCE_MOTION=1` turns animations off.

### Starting a group and adding someone

A group is its members: each writes a stream of their own on the mixnet and reads everyone
else's. There are no accounts and no servers.

1. Alice clicks **New group** and names it.
2. Sam clicks **Join a group** and names it as it will be known on his screen. echo-chat mints a
   voucher, and its code appears at the top of the conversation, with a **Copy** button. It is
   also written to `voucher-NAME.txt` in Sam's state directory. Sam gives Alice the code out of
   band.
3. Alice selects the group, clicks **Invite**, and pastes the code. Whoever holds a code reads
   everything said in the group from then on, so she takes it only from the person she means to
   add.
4. A few minutes later Alice sees `— added ~sam`, and Sam `— joined the group`.

Any member can add more people the same way, and everyone hears of them.

## Using it

The groups are on the left, the selected conversation in the middle, and on the right everyone
who reads what is written there, with the start of each member's key. Messages are grouped: one
sender's messages a few minutes apart sit under one header with their name and the time they were
said or read here. The log is hidden until F2 shows it.

| Button | |
|---|---|
| New group | start a group of your own |
| Join a group | join someone else's group: echo-chat shows a voucher code to give one of its members |
| Invite | let the person whose voucher code you were given into the selected group |
| Remove member | stop reading a member and delete what they sent; they can still read the group |
| Rename | call the selected group something else here; the other members keep their own names for it |
| Clear | delete the selected conversation's lines here |
| Scan | look again for messages a member's stream skipped |
| Leave | stop reading and writing the group and delete it here, once you type its name |
| Attach… | choose a file and send it to the selected group |
| View, Save… | beside a file received: see a picture large, or copy the file out |
| Hold to talk | record a voice note while you hold it, to play, discard or send |
| Play, Stop | beside a voice note: play it, or stop |

The **Send** button names the group the message goes to, and how many lines it is.

### Files

Files travel as katzenqt's do, so echo-chat, jam and katzenqt members can send each other files. A file,
or any message too long for one box, is written to a stream of its own, a box at a time, and the
group's stream then names that stream; members read it before what comes after it. A file can be
up to 16 MB, but each box takes a trip across the mixnet, so a large file takes a long time: its
line says how far it has gone. PNG and JPEG pictures are shown in the conversation, at most
320 × 240, and large with View; other files show their name and size. Received files are kept in
`attachments/` in the state directory, and Save… copies one out.

### Voice notes

Hold **Hold to talk**, or Ctrl+Space, while you speak, and let go. The voice note waits above the
message box, to Play, Discard, or Send to the group; nothing is sent until you click Send. A
voice note is Ogg Opus, 48 kHz mono at 12 kb/s, about 1.5 kB a second, recorded and played by
Rustic Audio through ALSA's default devices. It is sent as katzenqt sends one: a file of type
`audio/opus` named by its SHA-256, so that its name tells nothing of when it was recorded.
Voice notes received show Play and Stop. If echo-chat cannot reach the sound system, Hold to talk is
greyed out and says why.

| Key | |
|---|---|
| Ctrl+Enter | send |
| Ctrl+Space, held | record a voice note |
| Ctrl+PageUp, Ctrl+PageDown | the previous or next group |
| F2 | show or hide the log |
| F10 | blank the window at once, and bring it back |
| Ctrl+Q | quit |

Your own messages are marked `…` until written, `✓` once written, and `✓✓` once a member
acknowledges reading them.

## Security

echo-chat follows Paw's [GUI security guidelines](https://github.com/katzenpost/paw/blob/main/docs/GUI_SECURITY_GUIDELINES.md):
everything another member sends is untrusted.

- **One filter.** Text from elsewhere reaches a widget only as Paw's `SafeText` or `SafeName`,
  through `EchoChat.Display`. Control characters, invisible characters, private-use glyphs and line
  separators show as `�`; combining marks are capped at four a letter; a message shows at most 20
  lines and says how many more there were. Nothing is parsed as markup.
- **echo-chat decides who said what.** A member's chosen name is shown after `~`, ours as `me`. A
  name cannot hold bidi controls, joiners, badges, or echo-chat's own marks (`…`, `✓`), and is cut at
  30 characters. Names that look alike, names like ours and names mixing scripts show the start of
  the member's key, and are marked `(!)` among the members.
- **A message cannot pass for another.** A run of messages begins with a header echo-chat draws: the
  sender's name in bold, flush left, and the time. Every row of a message is indented under it,
  in regular weight, with our delivery mark in a column of its own, so no row of a message can
  look like a header. echo-chat's own notices are small, muted and centered, which no message is.
- **Authority follows the user's click.** The message box only sends text; everything else is a
  button. A dialog opens only from the user's click, never from the network, and its accept
  button takes no click in the half second after it appears. A member to remove is chosen from
  the list, by key. Copy writes the clipboard only for a click on it. A file is read only once
  you choose it and click Send, and one received is written outside the state directory only where
  you save it, never over a file already there. The microphone records only while you hold Hold
  to talk or Ctrl+Space, and what it recorded leaves only when you click Send. echo-chat asks for the
  clipboard and for running tasks, and for nothing else: no links, no notifications. The window's
  title is always "echo-chat".
- **Pictures.** A picture received is decoded by Paw, which takes only PNG and JPEG and refuses one
  larger than 8192 pixels a side or 64 MiB of pixels before decoding it. A file's name is cut to
  ASCII letters, digits and `._-+()[]` and spaces before it is shown or kept.
- **On disk.** The state directory is created 0700, `state.cbor`, `echo-chat.log` and received files
  0600. The log is
  filtered like the screen and holds no message text. `state.cbor` and `attachments/` are not encrypted:
  they hold your write caps and every message and file. Clear deletes a conversation's lines and
  files, Leave the group.
- **Leaving.** F10 blanks the window at once. SIGTERM, SIGHUP and SIGQUIT exit.

## Testing

    make test          # in one process: what reaches the screen, each action, the window
                       # driven by clicks and keys, and two members each with a shell and a window
    make e2e           # a saved state in a real window on Xvfb, driven with xdotool
    make shots         # pictures of the window, drawn offscreen, in shots/
    make screenshot    # docs/screenshot.png, from a conversation over the simulated Pigeonhole
    N=5 DAEMON=@katzenpost sh tests/e2e/mixnet.sh   # N windows (2 to 8) in one group, against a running kpclientd
    ./test-integration.sh                       # the same over the docker mixnet

The client core, its saved state and its scenarios are tested in
[group_chat_client](https://github.com/katzenpost/group_chat_client), which echo-chat shares with jam.
