# CLAUDE.md

Personal WoW addons for one player, not for public release.

- Target only WoW Forever (1.60.x, `## Interface: 16001`). Don't add retail/Classic
  compatibility shims or multi-version `.toc` lines.
- If supporting every class would be a lot of extra work, focus on the classes I play:
  druid, warrior, rogue, paladin. Others can be best-effort or skipped.
- See README.md for tooling; run `just check` and `just fmt` before committing.

## Forever API: where the truth is

Forever plays like Classic but runs the **modern (retail-style) client API**: `C_Spell`,
`C_SpellBook`, `C_AddOns`, `Enum.*`, the retail minimap with an addon compartment.
Classic-era globals (`GetSpellInfo`, `GetNumSpellTabs`, `GetSpellBookItemInfo`, `PickupSpell`)
and events (`LEARNED_SPELL_IN_TAB`) **do not exist**, and registering an unknown event throws
and aborts the rest of the file. Don't write from Classic memory; look it up:

1. `just setup` puts Blizzard's own UI source for the Forever build in
   `.cache/wow-ui-source-forever/Interface/AddOns/` (Gethe/wow-ui-source, `forever` branch,
   synced per client build; its commit message names the build, e.g. `1.60.1 (70862)`).
2. API functions, events (with payloads), structs, and enums:
   `Blizzard_APIDocumentationGenerated/*Documentation.lua`, e.g.
   `grep -rn 'Name = "GetSpellBookItemInfo"' .cache/wow-ui-source-forever/Interface/AddOns/Blizzard_APIDocumentationGenerated`.
3. Undocumented globals (`GetActionInfo`, `PlaceAction`, `SetOverrideBinding`, ...),
   templates, binding names (`INTERACTTARGET`), CVars, `.toc` metadata: grep Blizzard's
   code in the same tree. If Blizzard calls it, it exists. Forever-specific UI code lives in
   `Camelot/` subfolders (`[Game]` / `AllowLoadGameType camelot` in Blizzard tocs); check
   the toc to see which `Mainline/`/`Shared/` files load alongside.
4. `just check` runs `scripts/check-api.lua`, which fails on events or `C_*` functions
   that aren't in the Forever docs. LuaLS uses Ketho's annotations, which follow **retail**,
   so they're a good proxy but not exact.
5. `types/forever.lua` is only for FrameXML globals the annotations miss. Never stub
   game API functions there; that hid real load errors before.
6. `/console scriptErrors 1` in-game. Lua errors are not written to any log file.
   A load error usually leaves `WTF/Account/*/SavedVariables/<Addon>.lua` as `<DB> = nil`.
7. Taint: before `C_CVar.SetCVar` on a CVar, grep the tree for `"<cvar>"`. If Blizzard UI
   caches it via `CVarCallbackRegistry` (e.g. `autoLootDefault` in Forever's
   `Blizzard_GamepadActionBars`), setting it from addon code taints that frame and
   blocks protected actions ("<Addon> has been blocked from an action only available
   to the Blizzard UI"). `/console taintLog 1` writes `Logs/taint.log` to confirm.

Facts about the Forever client and game data that we've verified (UI quirks, taint traps,
spell changes from Classic) live in `docs/forever-notes.md`. Read it before building
something new, and add to it with a source and date when something surprises us.

Reading other addons on GitHub for ideas is fine; don't copy their code verbatim.
