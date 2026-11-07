# wowf

Small personal addons for WoW Forever (client 1.60.x, `## Interface: 16001`).

| Addon | What it does |
|-------|--------------|
| [RankUp](RankUp/) | Replaces lower spell ranks on your action bars with the highest rank you know. Runs on login, when you learn a spell, and when talent points change. `/rankup` for options (ignore list for deliberate downranks). |
| [SpaceFish](SpaceFish/) | Minimap button (or `/spacefish`) opens a small window. While it's open, Space casts Fishing and the next press reels in; Shift+Space jumps. Shows lure time left. Also listed in the minimap's addon menu. Closing it (X, Escape, button) gives Space back. Combat always gives Space back to jump. |

## Setup

Tools are managed with [mise](https://mise.jdx.dev/) (`mise.toml`): `just`, Lua 5.1,
lua-language-server, StyLua, and lefthook.

```sh
mise install     # install the tools
just setup       # fetch WoW API annotations, install git hooks
just link        # symlink the addons into the game
```

Every recipe runs its tools through `mise exec`, so you don't need mise activated in
your shell. If it isn't, run just itself with `mise exec -- just <recipe>`.

## Recipes

| Recipe | What it does |
|--------|--------------|
| `just` | Lists all recipes. |
| `just link` | Symlinks each addon into `…/_forever_/Interface/AddOns`. An addon is any folder `Name/` that contains `Name/Name.toc`. Links that already exist are left alone, and a real folder with the same name is skipped, never overwritten. Run it again after adding a new addon. |
| `just unlink` | Removes the symlinks in the AddOns folder that point back into this repo. Other addons aren't touched. |
| `just status` | Shows which addons are linked from this repo. |
| `just setup` | Clones or updates into `.cache/` (gitignored): Blizzard's UI source and generated API docs for the Forever client ([Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), `forever` branch, `Interface/AddOns` only, ~60 MB), plus annotations for lua-language-server: [Ketho/vscode-wow-api](https://github.com/Ketho/vscode-wow-api) for the game API, events, and widgets, and the `forever` branch of [NumyAddon/FramexmlAnnotations](https://github.com/NumyAddon/FramexmlAnnotations) for Blizzard's UI code. Both are MIT licensed. Also installs the lefthook git hooks. Rerun it after a game patch. |
| `just check` | Syntax-checks every addon `.lua` with the real Lua 5.1 `luac` (the game's Lua version, which rejects 5.2+ syntax such as `goto` and `//`). Then checks every registered event and `C_*` function against Forever's own API docs (`scripts/check-api.lua`). Then runs `lua-language-server --check` for undefined globals, typos, and wrong argument types. Runs `setup` first if the annotations are missing. Exits non-zero if it finds problems. |
| `just fmt` | Formats addon Lua with StyLua (`.stylua.toml`: 4 spaces, 100 columns). |
| `just fmt-check` | Fails if anything isn't formatted. Changes nothing. |

## Git hooks

[lefthook](https://lefthook.dev/) (`lefthook.yml`) runs on every commit that touches `.lua` files:

1. **fmt**: StyLua formats the staged files, and the changes are re-staged into the commit. This never fails the commit.
2. **check**: runs `just check`. The commit is blocked if it reports problems.

Skip the hooks once with `LEFTHOOK=0 git commit …`.

## The Forever API

Forever uses the modern, retail-style API (`C_Spell`, `C_SpellBook`, …), not the Classic
one. See [CLAUDE.md](CLAUDE.md#forever-api-where-the-truth-is) for where to look things up.
[`types/forever.lua`](types/forever.lua) only declares a few UI globals the annotations miss.

## In-game testing

`/console scriptErrors 1` shows Lua errors, and `/reload` loads code changes.
Changes to a `.toc` file only take effect after a full client restart.
