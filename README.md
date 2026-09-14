# Alfred

Spotlight-style composer for [Hermes Agent](https://hermes-agent.nousresearch.com/) inside the Omarchy shell. The full Hermes Desktop app stays one shortcut away.

This plugin runs unsandboxed inside `omarchy-shell`. It talks to the already-running `hermes-gateway.service` and does not start a second gateway or a second Quickshell process.

## Install

```sh
omarchy plugin add https://github.com/k1w3l/alfred.git --enable
omarchy plugin enable kiwel.alfred --section right --after omarchy.agents
```

From a local clone:

```sh
omarchy plugin validate .
omarchy plugin add /home/kiwel/git/alfred --yes
omarchy plugin enable kiwel.alfred --section right --after omarchy.agents
```

## Usage

- Left-click the bar icon (suited butler glyph) to open the pill and type.
- Type `/` in the composer to list Hermes commands and skills (same catalog as Hermes Desktop). Arrow keys move, Tab or Enter inserts, Escape closes the list.
- Right-click opens Hermes Desktop.
- Middle-click hides the overlay.
- `SUPER+H` shows or hides the overlay. While the pill has focus, click outside to shrink it to a ball; hover or click the ball to open it again. The travelling arc stays if Alfred is still working.
- `+` attaches files through the desktop file picker (`zenity`, `kdialog`, or `yad`).
- The model pill switches `model.default` for the current Hermes provider.
- The microphone records a clip with `pw-record` and attaches it to the next send.
- The circular send button submits. The window button opens Hermes Desktop and hides the pill.
- Escape hides the pill when Alfred is idle. While a reply is in flight, Escape shrinks to the ball so the travelling arc stays visible.

```sh
omarchy-shell kiwel.alfred toggle
omarchy-shell kiwel.alfred focus
omarchy-shell kiwel.alfred hide
omarchy-shell kiwel.alfred send "status"
omarchy-shell shell summon kiwel.alfred '{}'
omarchy-shell shell hide kiwel.alfred
```

## Configure

```sh
omarchy bar move kiwel.alfred --section right
```

The named Hermes session defaults to `alfred` (`-c`). Change `sessionName` on the bar widget entry in `~/.config/omarchy/shell.json`.

## Remove

```sh
omarchy plugin remove kiwel.alfred
```
