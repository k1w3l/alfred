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
- While the pill has focus, click outside to shrink it to a ball; hover or click the ball to open it again.
- `+` attaches files, folders, or images through an in-overlay browser (Wayland layer-shell cannot host the native Desktop dialog above the HUD).
- The **model** control switches `model.default` for the current Hermes provider.
- The **effort** control (next to model) sets `agent.reasoning_effort` (`none` … `ultra`).
- The **profile** control lists Hermes profiles (`hermes profile list`) and runs `hermes profile use` sticky; local sends use `hermes -p <name>`.
- The **gateway** control lists connections from Hermes Desktop (`~/.config/Hermes/connections.json`). Choose **This device** for the local CLI, or a remote entry to send through that dashboard.
- The microphone records a clip with `pw-record` and transcribes it into the composer.
- Escape hides the pill when idle. While a reply is in flight, Escape shrinks to the ball so the travelling arc stays visible.

```fish
omarchy-shell kiwel.alfred toggle
omarchy-shell kiwel.alfred focus
omarchy-shell kiwel.alfred hide
omarchy-shell kiwel.alfred send "status"
omarchy-shell shell summon kiwel.alfred '{}'
omarchy-shell shell hide kiwel.alfred
```

Bind a key in Hyprland (or your compositor) to `omarchy-shell kiwel.alfred toggle` if you want a global shortcut.

## Configure

The named Hermes session defaults to `alfred` (`-c`). Change `sessionName` on the bar widget entry in `~/.config/omarchy/shell.json`.

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
