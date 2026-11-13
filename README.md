# wowf

Small personal addons for WoW Forever (client 1.60.x, `## Interface: 16001`).

| Addon | What it does |
|-------|--------------|
| [RankUp](RankUp/) | Replaces lower spell ranks on your action bars with the highest rank you know. Runs on login, when you learn a spell, and when talent points change. `/rankup` for options (ignore list for deliberate downranks). |
| [SpaceFish](SpaceFish/) | Minimap button (or `/spacefish`) opens a small window. While it's open, Space casts Fishing and the next press reels in; Shift+Space jumps. Shows lure time left. Also listed in the minimap's addon menu. On first run the button picks the biggest free gap around the minimap; `/spacefish minimap` re-picks. Closing it (X, Escape, button) gives Space back. Combat always gives Space back to jump. |
| [QuestSparkle](QuestSparkle/) | Keeps the game's own loot sparkle on quest items switched on (`outlineModeShowLootEffectWhenDisabled`): sets it at login and again after a graphics preset change resets it. Nothing else, no options. |
| [SnapLoot](SnapLoot/) | Fast loot: when auto loot applies, takes every slot at once on `LOOT_READY`. Leaves locked (roll) slots, bind-on-pickup confirmations and full bags to the normal loot window. Options > AddOns > SnapLoot has an on/off toggle and shows (read-only) the game's own Auto Loot setting. |
| [KindHands](KindHands/) | One button for buffs, all classes: each press casts the next buff someone is missing from you, at a rank they can take, on your friendly target, then you, then your party (in range). Decided on the press, nothing runs in the background, nothing in combat. `/kindhands macro` makes an account-wide macro and puts it on your cursor; or bind it under Options > Keybindings > AddOns. `/kindhands` says what the next press casts; when it casts nothing it says why (who's out of range, or that everyone in reach has your buffs). A minimap button (also in the minimap's addon menu, or `/kindhands window`) opens a small window: while it's open, and only out of combat (it closes when a fight starts and comes back after), it notices other players buffing you (buffs of a minute or more) and offers **Buff back** (casts what suits them from your buffs; if the game has no unit for them any more, and you have no target, one press targets them by name, casts what they lacked when they buffed you, and clears the target again; with a target of your own, the first press targets them and the second buffs, so a miss can't cast on or lose your target; either way it says when they couldn't be targeted) and **/thanks** (the emote at them, once per person). The game only says who cast a buff when it has a unit for them (target, party, mouseover, a nameplate), so turn on friendly player nameplates to catch strangers; others show as "someone the game didn't name". Options > AddOns > KindHands: "Only buffs that suit them" (turn off to hand out anything you have to passers-by) and "Also buff myself" (turn off to only ever buff others). |
| [NoSmallTalk](NoSmallTalk/) | When an NPC's chat window has exactly one option and no quests (vendor, trainer, flight master, banker), picks it so you go straight to the shop. Leaves alone quest-marked options and ones you can't pick or that cost or give something. Options that ask for gold still ask. Hold Shift while talking to see the window. `/nosmalltalk` says why the last window wasn't skipped. No options. |
| [RichPeopleBoatMoney](RichPeopleBoatMoney/) | Saves every full auction house dump (every single listing; Forever leaves the seller empty) to SavedVariables: from `/rpbm scan` at the auction house, or any addon that asks for one, e.g. Auctionator with "Use alternate slower scan mode by default" on (Auctionator options > Advanced; its default "summary" scan only gets one lowest price per item and isn't saved). Buyouts are per stack. Keeps the last 4 scans (a full scan is ~200k auctions, ~6 MB). They reach the disk on logout or `/reload`. `just rpbm-export` writes each scan to its own JSON Lines file, one auction per line, named by scan time, realm and faction, in the folder you run it from (or `just rpbm-export some/dir`); scans already exported are skipped, so run it after every session and nothing is lost or overwritten (`scripts/rpbm-jsonl.lua`, which prints to stdout without `-d`). `/rpbm` lists saved scans, `/rpbm clear` deletes them. |
| [BargainBin](BargainBin/) | Finds auctions that cost less than a vendor pays for them. Reads every full auction house dump (its Scan button, `/rpbm scan`, or Auctionator's slower scan mode; once per 15 minutes, the game's limit) and lists the items that pay in a panel next to the auction house, best profit first, with the session's total bought and what it sells for. Click an item to look up its current auctions, then each further click buys one that still pays (stackables sold as pooled units: one click to get the final price, one to confirm). Only auctions earning at least 1s count (a full scan is full of crafted greens listed a few copper under vendor price). Vendor prices are the client's. `/bargainbin` toggles the panel. No options. |

## Setup

Tools are managed with [mise](https://mise.jdx.dev/) (`mise.toml`): `just`, Lua 5.1,
lua-language-server, StyLua, and lefthook.

```sh
mise install     # install the tools
just setup       # fetch WoW API annotations, install git hooks
just link        # symlink the addons into the game
```

The AddOns folder is derived from `WOW_DIR`, the folder that contains `_forever_`.
The defaults are `C:/Program Files (x86)/World of Warcraft` on Windows,
`/Applications/World of Warcraft` on macOS, and a Wine prefix at
`~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft` on Linux. To use a
different location, set `WOW_DIR` in your environment or in a `.env` file (gitignored).
`just status` prints the path in use.

Every recipe runs its tools through `mise exec`, so you don't need mise activated in
your shell. If it isn't, run just itself with `mise exec -- just <recipe>`.

## Recipes

| Recipe | What it does |
|--------|--------------|
| `just` | Lists all recipes. |
| `just link` | Puts each addon into `…/_forever_/Interface/AddOns`. An addon is any folder `Name/` that contains `Name/Name.toc`. On Linux and macOS it creates symlinks, so edits show up after a `/reload`. On Windows it makes full copies instead, because symlinks there need Developer Mode. Each copy is replaced fresh on every run, so files you delete in the repo disappear too, and it's marked with a `.wowf-copy` file. Rerun it after every change. A folder with the same name that this repo didn't create is skipped, never overwritten. Set `LINK_MODE=copy` or `LINK_MODE=symlink` to override the mode. |
| `just unlink` | Removes what `link` created: symlinks into this repo and marked copies. Other addons aren't touched. |
| `just status` | Shows the AddOns path and mode in use, and which addons came from this repo. |
| `just setup` | Clones or updates into `.cache/` (gitignored): Blizzard's UI source and generated API docs for the Forever client ([Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), `forever` branch, `Interface/AddOns` only, ~60 MB), plus annotations for lua-language-server: [Ketho/vscode-wow-api](https://github.com/Ketho/vscode-wow-api) for the game API, events, and widgets, and the `forever` branch of [NumyAddon/FramexmlAnnotations](https://github.com/NumyAddon/FramexmlAnnotations) for Blizzard's UI code. Both are MIT licensed. Installs [busted](https://lunarmodules.github.io/busted/) 2.2.0 into `.cache/rocks` with LuaRocks. Also installs the lefthook git hooks. Rerun it after a game patch. |
| `just check` | Syntax-checks every addon `.lua` with the real Lua 5.1 `luac` (the game's Lua version, which rejects 5.2+ syntax such as `goto` and `//`). Then checks every registered event and `C_*` function against Forever's own API docs (`scripts/check-api.lua`). Then runs `lua-language-server --check` for undefined globals, typos, and wrong argument types. Runs `setup` first if the annotations are missing. Exits non-zero if it finds problems. |
| `just test` | Runs the busted unit tests in `tests/` (`*_spec.lua`). They cover plain logic that doesn't call the game, such as KindHands' buff choice in `KindHands/Logic.lua`; nothing in the game API is faked. |
| `just fmt` | Formats addon Lua with StyLua (`.stylua.toml`: 4 spaces, 100 columns). |
| `just fmt-check` | Fails if anything isn't formatted. Changes nothing. |

## Git hooks

[lefthook](https://lefthook.dev/) (`lefthook.yml`) runs on every commit that touches `.lua` files:

1. **fmt**: StyLua formats the staged files, and the changes are re-staged into the commit. This never fails the commit.
2. **check**: runs `just check`. The commit is blocked if it reports problems.
3. **test**: runs `just test`. The commit is blocked if a test fails.

Skip the hooks once with `LEFTHOOK=0 git commit …`.

## The Forever API

Forever uses the modern, retail-style API (`C_Spell`, `C_SpellBook`, …), not the Classic
one. See [CLAUDE.md](CLAUDE.md#forever-api-where-the-truth-is) for where to look things up.
[`types/forever.lua`](types/forever.lua) only declares a few UI globals the annotations miss.

## In-game testing

`/console scriptErrors 1` shows Lua errors. `/reload` loads code changes, `.toc` edits
and newly linked addons.
