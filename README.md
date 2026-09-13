# Hermes HUD for Omarchy

Native Omarchy shell plugin: a Spotlight-style HUD for [Hermes Agent](https://hermes-agent.nousresearch.com/), always ready for a command. The full Hermes Desktop app stays one shortcut away.

## What it does

- Keeps a chrome-free composer pill on the focused monitor (idle HUD).
- Shows the recent thread while you type, while Hermes is busy, or for a moment after a reply.
- Sends prompts with `hermes chat -Q --oneshot -c hud --create-if-missing --source omarchy-hud`.
- Watches `hermes-gateway.service` instead of starting a second gateway.
- Bar icon: left-click focuses the HUD, right-click opens Hermes Desktop, middle-click hides the pill.

## Install

The plugin is a git repo. From a clone of this directory:

```fish
omarchy plugin add /home/kiwel/git/alfred --yes
omarchy plugin enable kiwel.hermes-hud --section right --after omarchy.agents
```

`omarchy plugin validate .` should exit 0 before enable.

## Shortcuts

| Binding | Action |
| --- | --- |
| `SUPER+H` | Focus or unfocus the HUD |
| `SUPER+SHIFT+H` | Open Hermes Desktop |
| Escape | Clear the draft, then unfocus |

IPC:

```fish
omarchy-shell kiwel.hermes-hud toggle
omarchy-shell kiwel.hermes-hud focus
omarchy-shell kiwel.hermes-hud hide
omarchy-shell kiwel.hermes-hud send "status"
```

## Out of scope (v1)

Slash commands, attachments, voice, and the Desktop composer. Use `SUPER+SHIFT+H` for those.
