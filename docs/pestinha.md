# Pestinha

Pestinha is a desktop pet with a spiking neural network of its own
([Andersonk01/pestinha](https://github.com/Andersonk01/pestinha), branch
`hyprland`). It falls, walks on top of your windows, plays with a ball, works
at a notebook while you code, pulls pranks with memes and sticky notes and
learns from your petting. This fork runs it from three places:

| Piece | What it does |
|---|---|
| Hub > Desktop > Pestinha (`ryoku/hub/quickshell/PestinhaControl.qml`) | On/off, character, style, sound, permissions. Saves at once, outside the Hub's Save. |
| `ryoku-pestinha` (`ryoku/shell/scripts/ryoku-pestinha`) | The command the Hub, the panic key and the login call. |
| `ryoku/hyprland/modules/pestinha.lua` | Window rule, panic key and the login hook. |

## Install

The pet lives in a checkout with its own venv:

```bash
git clone -b hyprland https://github.com/Andersonk01/pestinha.git ~/Projects/pestinha
cd ~/Projects/pestinha && python -m venv .venv && .venv/bin/pip install -r requirements.txt
```

A checkout somewhere else is named in `~/.config/ryoku/pestinha.json` as
`{"dir": "/path/to/pestinha"}`. Turn it on in the Hub; the first start shows
the pet's own welcome and permission window.

## The characters

Every character runs the same neural network. The seed and the temperament
(gains on some of the network's connections) make each one an individual,
and each keeps its own memory, so what one learns never reaches another.

| Character | Who it is |
|---|---|
| **Bryan** | The original: a small green-framed screen with two eyes. Curious and playful, the one who likes the ball most and gets truly sad when it is taken away. Being dragged barely bothers him; a hard hit or his things being dismissed makes him angry, and then he protests against the cursor, Alt+F4 and the Task Manager, goes on strike and ends up in a revolution, throwing paper balls. |
| **Cypher** | A cybersecurity hacker in a hood and headset, with a cyan screen, code rain and glitch (the look of the login intro). The most focused one: when you type or code he sits at his own notebook and works along. New things and the web make him curious, so does a poke, and loneliness weighs less on him. Dragging him or dismissing his things annoys him; petting calms him down. When bored he would rather stick security notes ("2FA. ATIVE. AGORA.") than play ball. It is a joke: he never probes or breaks into anything. |
| **Jorge** | A satirical finance and AI "coach", smooth and overconfident, with a gold frame and a red tie. Ignored, he insists: boredom turns into curiosity and play. Attention thrills him, since pokes and petting turn into joy. He is almost never sad, but despairs when you refuse or dismiss his things, sticks notes and throws mentoring flyers. Jorge is not a reference to any real coach, company or person, and he sells, charges or asks for nothing. |

The Hub lists every character under THE CHARACTERS with the description from
its `pets/<id>.json`. The `descricao` field holds one text per language, keyed
by the same codes as the desktop (`{"en": "...", "pt": "..."}`), and the Hub
shows the one for the desktop's language: the exact code (`pt_BR`), then its
base (`pt`), then English. A plain string counts as Portuguese. The pet's own
Settings window shows the Portuguese one under the character picker, because
the pet's own windows, menus, notes and signs are in Portuguese for now. A new
character is a new `pets/<id>.json` plus a `pets/<id>/` folder (see the pet's
`pets/README.md`); it shows up in both places on its own.

Changing the character restarts a running pet. With the pet closed, it is
saved for its next start.

## Style and sound

- **Style** (Original, Pink, Cyber, Matrix, Amber) recolours any character at
  once, without a restart. Cyber is cyan with code rain, scanlines and
  glitch. The character keeps its accessories.
- **Sounds** are beeps and reactions to pokes, petting, impacts, fireworks,
  waking up and emotions, plus a typing sound while he works at the notebook.
  Each has its own switch, and the volume is Low, Medium or High. A hidden,
  paused or panicked pet is silent.

## The command

| Command | What it does |
|---|---|
| `ryoku-pestinha status` | State as JSON, read by the Hub every few seconds (characters with name and description included). |
| `ryoku-pestinha on` / `off` | Turns it on (now and at every login) or off. |
| `ryoku-pestinha start` / `stop` / `restart` | Opens or closes it without touching on/off. |
| `ryoku-pestinha autostart` | At login: opens it only when it is on. |
| `ryoku-pestinha pet <id>` | Picks the character. |
| `ryoku-pestinha set key=on\|off ...` | Permissions (`bolinha`, `fogos`, `sons`, `digitacao`, ...). |
| `ryoku-pestinha set estilo=<name> volume=<level>` | Style and volume. The pet rejects an unknown option. |
| `ryoku-pestinha panic` / `religar` | Panic, and turning back on after it. |
| `ryoku-pestinha settings` / `pause` / `hide` | Opens its Settings window, pauses, hides. |

With the pet open, the command talks to its local control socket
(`$XDG_RUNTIME_DIR/pestinha.sock`, reachable only by your user). With the pet
closed, it edits the saved permissions in `<checkout>/memory/permissions.json`.
Starts are serialised by a lock in `$XDG_RUNTIME_DIR/ryoku-pestinha.lock`, so
two login hooks or a double click never open two pets.

## Hyprland

The pet runs under XWayland. Its windows have the class `pestinha` and titles
starting with `pestinha:janela`; the `pestinha-overlay` rule keeps them
floating on every workspace, without borders, shadow, blur or animation, and
never focused.

- `Ctrl + Alt + Shift + B` is the panic key: the pet and everything it put on
  screen vanish at once. TURN BACK ON in the Hub (or `ryoku-pestinha religar`)
  brings it back.
- The `hyprland.start` hook runs `ryoku-pestinha autostart`, which opens the
  pet only when it is on in the Hub.

## Files

| Path | Holds |
|---|---|
| `~/.config/ryoku/pestinha.json` | `enabled` and the checkout `dir`. |
| `<checkout>/memory/` | Permissions, each character's memory, logs and the sound cache. |
| `~/.local/state/ryoku/pestinha.log` | The pet's terminal output, trimmed past 1 MiB. |
