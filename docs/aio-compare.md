# All-in-one addons for Forever: a comparison

A small review of three all-in-one addons and a leveling guide addon. They were checked for
quality, safety and performance, then compared by feature. The copies reviewed are in
`~/src/github.com/tinnet/AIOAddons/`. This was a skim on 2026-11-11: pattern searches over
all the code, plus a closer read wherever something stood out. It is not a line-by-line
review.

## Context (CurseForge, 2026-11-11)

| Addon | Version reviewed | Downloads | Created | Last updated |
|---|---|---|---|---|
| [Leatrix Plus](https://www.curseforge.com/wow/addons/leatrix-plus) (Leatrix) | 1.60.30-forever | 76.7M (all game versions) | about 10 years ago | 1 hour ago |
| [OneForAll](https://www.curseforge.com/wow/addons/oneforall-forever) (Smoergi) | 6.2.5 | 1.19M | about 1 month ago | 10 hours ago |
| [Polestar](https://www.curseforge.com/wow/addons/polestar) (0xFitz) | 0.3.6 (0.3.7 is out) | 190k | 28 days ago | 6 hours ago |
| [Forever++](https://www.curseforge.com/wow/addons/foreverplusplus) (xIGBClutchIx) | 1.5.0 | 19k | about 1 month ago | 18 minutes ago |

CurseForge only shows relative dates. Leatrix is a decade-old addon ported to Forever. The
other three are a month old and are updated several times a day: OneForAll got to version
6.x in that month. Their code comments read like logs of AI-assisted work ("user 09.11.",
"Discord 05.11."). That isn't bad in itself, but expect things to break from day to day.

## Leatrix Plus

About 41k lines, 22k of them in one file.

- **Quality:** old-school but proven. One big file, few globals, settings in `LeaPlusDB`. The
  files start with a byte order mark (BOM), which the game accepts but plain `luac` refuses.
- **Safety:**
  - Loads no code from strings and sends no hidden addon messages.
  - Writes in chat only when you ask: the "announce target" key binding and a boss-tactics
    button.
  - `/ltp al` sets `autoLootDefault`. That is the setting that got SnapLoot blocked from an
    action (see `docs/forever-notes.md`), but it only runs when you type the command.
- **Performance:** a few short timers (0.1–0.3 s). As far as the skim showed, they and its
  OnUpdate scripts run only while a window is open or a feature is on.
- **Defaults:** many automations are on, e.g. auto accept and turn in quests, and auto repair
  from guild funds.

## Forever++

About 64k lines in 150 files, split cleanly into modules.

- **Quality:**
  - The best-built of the three new ones: one documented file per module, and careful
    handling of the game's secret values.
  - Pasted profile imports are checked, and only known settings are kept.
  - Its debug tools (profiler, self-test, gear probe) ship in the release.
- **Safety:**
  - Sends no addon messages and loads no code from strings.
  - Replaces the game's Lua error handler (ErrorCatcher), but passes every error on to the
    handler that was there before, and can put it back.
  - Its fast loot only reads `autoLootDefault`, it never sets it.
- **Performance:** almost no repeating timers or always-on OnUpdate scripts.
- **Defaults:** 66 modules are on, among them AutoGossip, FastLoot, AutoRepair,
  BestQuestReward and a quest tracker. AutoQuest and AutoSellJunk are off.

## OneForAll

About 92k lines of Lua, plus 40 MB of textures.

- **Quality:** the weakest of the three new ones.
  - Over 300 `pcall` wrappers, even around `RegisterEvent`. They quietly hide its own bugs.
  - About 5 MB of data loads at every login. Nothing is load-on-demand.
  - Comments are a running changelog. Version 6.1.2 kept joining channels `OFAShare3` to
    `OFAShare12` until it hit the game's limit of 20 channels.
- **Safety and privacy:**
  - **`guildMap` is on by default.** It sends your zone and exact map position to your guild
    every 5–60 seconds. Other OneForAll users in the guild see you as a dot on their map.
  - Also sends your known recipes to the guild, a version check, dungeon quest sharing with
    your party, and profiles by whisper.
  - The hidden recipe channel `OFAShare3` is off in this build (`CHANNEL_OFF`, since 6.1.4).
  - Its auto loot switch sets `autoLootDefault` when you flip it: the same blocked-action
    risk as Leatrix's `/ltp al`.
- **Performance:** fine on its own, but the heaviest at login.

### Its hidden chat channel

Version 6.2.5 never joins `OFAShare3`. At every login it leaves that channel and its older
ones (`OFAShare`, `OFAShare2`, `OFAShare4` to `OFAShare12`). Our OneForAll save data is
small and was only just created, which fits with having run only 6.2.5.

If an older version did join, disabling OneForAll won't take you out. The server remembers
channel membership per character; it isn't in the `chat-cache.txt` files. You would stay in
the channel, but nothing would send there with OneForAll off. OneForAll's own comments say
`/leave` doesn't work on those channels because the server has blocked them. To check, type
`/chatlist` on each character, then `/leave OFAShare3` (or whichever number shows up).

Disabling OneForAll does stop the guild sharing: map position and known recipes are only
sent while it runs.

## Polestar (leveling guide)

About 102 MB on disk, in 30 addon folders.

- **Quality:** seriously engineered: tests, format specs, checks on everything it reads.
  Language packs, guide packs and walking maps are load-on-demand.
- **Safety:**
  - Guide steps are stored as Lua text and run with `loadstring`, but in an empty
    environment, and only for data from its own addon folders.
  - Pasted import strings are read as JSON, field by field, and never run.
  - Its addon messages (party quest progress, shared travel info) are opt-in.
- **Performance:** a 1-second timer in 4 places and about 40 OnUpdate scripts. The real cost
  is size: an 11.7k-line engine plus guide data, which is why its memory use is high.
- **Defaults:** auto accept and turn in quests are on.

## Feature matrix

✔ = has it, ★ = on by default, "conflict" = clashes with one of our addons.

| Feature | Leatrix | Forever++ | OneForAll | Polestar |
|---|---|---|---|---|
| Auto sell junk / auto repair | ✔★ | ✔ / ✔★ | – | ✔ |
| Fast loot | ✔ | ✔★ (conflict: SnapLoot) | – | ✔ |
| Skip NPC chat window | ✔ | ✔★ (conflict: NoSmallTalk) | – | ✔ |
| Auto accept / turn in quests | ✔★ | ✔ | – | ✔★ |
| Best quest reward | – | ✔★ | ✔ (sell price) | ✔ |
| Quest icons on map / nameplates | – | ✔★ | ✔★ | ✔ |
| Leveling guide with arrow and route | – | – | – | ✔ |
| Dungeon bosses, loot, quests | – | – | ✔ | ✔ |
| Talent planner | – | ✔ | ✔ | ✔ |
| Gear upgrade value | – | ✔ | ✔ | ✔ (Pawn-style) |
| AH / disenchant prices in tooltip | – | ✔ (with Auctionator) | – | – |
| Profession helpers (costs, skill-ups, recipe sources) | – | ✔ | ✔ | – |
| Gathering-node map | – | ✔ | – | – |
| Library Books tracker | – | – | ✔ | – |
| Hunter pets | – | – | ✔ | – |
| Flight timer | ✔ | ✔ | ✔ | ✔ |
| Reveal unexplored map / coordinates | ✔ | ✔ | ✔ | ✔ |
| Minimap tweaks / button collector | ✔ | ✔ (square) | ✔ | – |
| Chat tweaks (history, copy, whisper window) | ✔ | ✔ | ✔ | – |
| Mute sounds / CVar editor | ✔ | ✔ | – | – |
| Profile export / import | – | ✔ | ✔ | guide imports |
| Talks to other players (addon messages) | – | – | ✔★ (guild position) | opt-in |
| Lua error catcher | – | ✔★ | ✔ | – |

## For our setup

- **Forever++** is the best fit if we want an all-in-one. Turn off its AutoGossip and
  FastLoot, or they fight NoSmallTalk and SnapLoot.
- **OneForAll** is worth it for dungeon, Library Books and profession data. Turn off
  `guildMap` unless the guild should see where you are.
- **Polestar** is fine, just big. Update it to 0.3.7.
- **Don't stack them:** they overlap a lot. Running several gives three flight timers, three
  talent planners, and two or three addons auto-accepting quests.
