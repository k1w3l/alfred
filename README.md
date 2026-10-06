# Alfred

Spotlight-style composer for [Hermes Agent](https://hermes-agent.nousresearch.com/) inside the [Omarchy](https://omarchy.org/) shell. Quick prompts stay in the bar; Hermes Desktop remains one shortcut away.

This plugin runs unsandboxed inside `omarchy-shell`. It talks to your Hermes gateway (local systemd unit or a remote gateway registered in Hermes Desktop) and does not start a second gateway or a second Quickshell process.

## Requirements

- [Omarchy](https://omarchy.org/) with `omarchy-shell` / Quattro plugins
- [Hermes Agent](https://hermes-agent.nousresearch.com/) CLI on `PATH` (`hermes`)
- For voice dictation: PipeWire (`pw-record`) and a working Hermes STT setup
- For clipboard paste of images: `wl-copy` / `wl-paste`
- Optional: Hermes Desktop, if you want its registered gateways listed in the pill

## Install

```fish
omarchy plugin add https://github.com/k1w3l/alfred.git --enable
omarchy plugin enable kiwel.alfred --section right
```

From a local clone of this repository:

```fish
omarchy plugin validate .
omarchy plugin add . --yes
omarchy plugin enable kiwel.alfred --section right
```

Place the bar widget where you like:

```fish
omarchy bar move kiwel.alfred --section right
```

## Usage

- Left-click the bar icon to open the pill and type.
- Type `/` in the composer to list Hermes commands and skills (same catalog as Hermes Desktop). Arrow keys move, Tab or Enter inserts, Escape closes the list.
- Right-click the bar icon opens Hermes Desktop (when installed).
- Middle-click hides the overlay.
- While the pill has focus, the Hermes profiles sit on the lower row, at the size of the send button (local gateway and every remote Desktop gateway). The prompt and the attach button fill the row above. Click a face to select it. In the Profile menu, the pencil on a row edits that agent's shape, color, and expression (`profileEmoji` in `alfred.json`). The face is the ball when the pill shrinks, and it replaces the bar icon. Each agent has its own shape, colour, expression and idle film, offset so the row does not move in lockstep. A hairline rim is drawn on top of the fill, thinner on the 26px chips, including the side dots of the working animation, so a dark body stays visible. A short drop shadow sits just outside that rim. While a task runs, a segment travels that rim: cream while working, green on success, amber on attention, red on error. Voice uses an attentive face and a slightly thicker red rim. The bar icon follows the selected agent. A replacement bar cannot see the plugin service, so the service writes `~/.config/Hermes/alfred-face.json` and the tray paints from that snapshot. While a task runs the tray keeps that silhouette and lets the rim travel; the pill plays the three-dot working pose, and every dot keeps the dark fill plus the rim. The ball and the current face follow a flow instead of a loop: a new task goes straight to `working` (`start` and `start-work` are not in the flow), which then loops (the ball grows a little while it works). The result plays `success`, `error` or `attention` three times, then `notification` loops until you open the pill, which plays `end` once and returns to idle.
- Click outside to shrink the pill to that face; hover or click it to open the pill again.
- `+` attaches files, folders, or images through an in-overlay browser (Wayland layer-shell cannot host the native Desktop dialog above the HUD). The `+` button shows a badge with the attachment count, and each attachment appears as a chip under the pill with its type icon and an X to remove it; **Clear all** drops every one.
- The composer grows as you type (up to about eight lines, then scrolls). Enter sends, Shift+Enter adds a line.
- The gear dropdown (labelled with the current model and effort) groups every setting:
  - **Model** switches `model.default` for the current Hermes provider.
  - **Reasoning** sets `agent.reasoning_effort` (`none` … `ultra`).
  - **Profile** lists the same faces as the pill: local profiles and the profiles of each remote gateway. Choosing one selects that gateway and that profile. A local choice also runs `hermes profile use`; a remote choice does not change the local sticky profile.
  - **Keyboard shortcuts** rebinds the global Hyprland keys and the keys inside the pill. Click a shortcut, press the new combination (Escape cancels, Backspace turns it off); the reset icon restores the default.
  - **Gateway** lists connections from Hermes Desktop (`~/.config/Hermes/connections.json`). Choose **This device** for the local CLI, or a remote entry to send through that dashboard.
- Under the pill, **New chat** and **Previous sessions** sit side by side. Previous sessions lists recent sessions from the active profile's `state.db` (cron runs hidden); picking one opens it as a chat and resumes it with `hermes chat --resume`.
- Several chats can run at once, each in its own Hermes session. With more than one chat, chips next to those buttons switch or close them; a pulsing dot marks a chat that is still working.
- While a chat is working, the eye button opens a live preview: each tool call with its target and duration, plus the reply as it streams (`hermes chat --format stream-json`). Remote gateways only report the final reply.
- Long conversations scroll inside the thread (mouse wheel, scrollbar, or PageUp/PageDown from the composer). When you are not at the bottom, **Jump to latest** appears under the thread.
- The microphone records a clip with `pw-record` and transcribes it into the composer.
- Escape hides the pill when idle. While a reply is in flight, Escape shrinks to the ball so the travelling arc stays visible. Inside a submenu, Escape goes back one level.

Default shortcuts (change them in the gear dropdown under **Keyboard shortcuts**):

| Keys | Where | Action |
| --- | --- | --- |
| Super+H | Global | Show / hide Alfred |
| Super+Alt+H | Global | Start / stop voice capture |
| Ctrl+M | Pill | Start / stop voice capture |
| Ctrl+N | Pill | New chat |
| Ctrl+W | Pill | Close the current chat |
| Ctrl+Tab / Ctrl+Shift+Tab | Pill | Next / previous chat |
| Ctrl+H | Pill | Previous sessions |
| Ctrl+P | Pill | Toggle the live preview (while working) |
| Ctrl+1 … Ctrl+9 | Pill | Switch to a profile (order shown in the pill) |
| Super+Alt+1 … Super+Alt+9 | Global | Switch to the same profile from anywhere |

Global keys are written to `~/.config/hypr/alfred.lua` and applied with `hyprctl reload`. Load that file once from your Hyprland bindings:

```lua
pcall(require, "hypr.alfred")
```

Remove any older hardcoded Alfred bind for the same keys. Pill shortcuts are stored in `~/.config/Hermes/alfred.json`. Without the hook, the dropdown shows a warning and only the pill shortcuts apply.

```fish
omarchy-shell kiwel.alfred toggle
omarchy-shell kiwel.alfred focus
omarchy-shell kiwel.alfred hide
omarchy-shell kiwel.alfred send "status"
omarchy-shell kiwel.alfred newchat
omarchy-shell kiwel.alfred voice
omarchy-shell kiwel.alfred attach ~/notes.md
omarchy-shell kiwel.alfred resume 20260923_025333_31e917
omarchy-shell kiwel.alfred menu shortcuts
omarchy-shell shell summon kiwel.alfred '{}'
omarchy-shell shell hide kiwel.alfred
```

`menu` accepts `settings`, `sessions`, `attach`, `model`, `effort`, `profile`, `gateway`, or `shortcuts`. On other compositors, bind keys to these commands yourself.

## Configure

The first chat uses the named Hermes session `alfred` (`-c`). Change `sessionName` on the bar widget entry in `~/.config/omarchy/shell.json`. New chats start fresh sessions and keep resuming them by id.

Hermes allows one writer per session: resuming a session that is still open in Hermes Desktop or another terminal fails with `SESSION_NOT_OWNED`. Close it there, or start a new chat.

### Remote gateways

Alfred reads the same registry Hermes Desktop uses:

`~/.config/Hermes/connections.json`

Selected gateway and profile are remembered in `~/.config/Hermes/alfred.json`.

Remote sends authenticate with an optional credentials file (never commit this):

`~/.config/Hermes/alfred-auth.json`

```json
{
  "your-connection-id": {
    "username": "you",
    "password": "secret"
  }
}
```

For token-mode gateways, use `"token": "..."` instead of username/password. You can also set `ALFRED_GATEWAY_TOKEN`, or `ALFRED_GATEWAY_USER` + `ALFRED_GATEWAY_PASSWORD`, for a one-off override.

Without credentials, remote status still probes `/api/status`, but sending a prompt will fail with a clear error until auth is configured.

## Remove

```fish
omarchy plugin remove kiwel.alfred
```

## License

MIT
