# WoW Forever notes

Things we learned about the Forever client (1.60.x) that differ from Classic or
aren't obvious from the API docs. Add to this when something surprises us, with
where it came from and when. How to look up the API itself is in CLAUDE.md.

## Client and UI

- The main action bar is Blizzard's gamepad-style bar (`Blizzard_GamepadActionBars`,
  loaded for game type `camelot`), even with mouse and keyboard. It caches the
  `autoLootDefault` CVar through `CVarCallbackRegistry`, so setting that CVar from addon
  code taints it (SnapLoot got blamed for a blocked interact action, 2026-11-09).
- Some API returns are secret values (`issecretvalue`), e.g. `UnitInRange` always,
  auras in combat. Use `C_Spell.IsSpellInRange(spell, unit)` for range checks.
- Vendors have a Sell Junk button; addons can call `C_MerchantFrame.SellAllJunkItems()`
  (check `C_MerchantFrame.IsSellAllJunkEnabled()`).
- Settings panel (`Settings.RegisterVerticalLayoutCategory`, `RegisterAddOnSetting`,
  `RegisterProxySetting`, `CreateCheckbox`) works for addons; proxy defaults can be
  functions.
- `/reload` re-reads the addon folder: newly linked addons load and `.toc` edits apply
  (new `## IconTexture` lines showed up) without restarting the game (2026-11-09).
- Full auction house dump (`C_AuctionHouse.ReplicateItems`): `REPLICATE_ITEM_LIST_UPDATE`
  fires hundreds of times for one dump, always with the same `GetNumReplicateItems()`
  (214,178 auctions on 2026-11-11, Alliance), so read once and ignore the repeats. Replicate
  indexes start at 0, and the buyout from `GetReplicateItemInfo` is for the whole stack.
  Auctionator's default full scan is the "summary" browse search, not this dump; its
  "alternate slower scan mode" option switches to the dump. Sources: our own
  RichPeopleBoatMoney, and CraftProfit's comments (`AHAdapter.lua`, measured by its author).
  In the dump (2026-11-11): the seller (`owner`) is always empty, almost every auction is
  buyout-only (min bid and increment 0), and items the client hasn't loaded come back
  with quality -1 and no link (~14%), though item ID and prices are there.
- The combat log is closed to addons the way it is on retail Midnight:
  `COMBAT_LOG_EVENT_UNFILTERED` is marked `HasRestrictions` and `GetCurrentEventInfo` only
  exists in the secure/internal combat log docs. So "who buffed me" comes from `UNIT_AURA`,
  whose `AuraData` has `sourceUnit` (a unit token, nil when the caster has none) but no
  source GUID or name (API docs, 2026-11-11; KindHands' window).
- Almost every item button (bags, bank, loot, mail, trade, guild bank, auction house
  rows, quest rewards) shows its item through the global `SetItemButtonQuality(button,
  quality, itemIDOrLink)`, also with no item to clear it, so one `hooksecurefunc` on it
  reaches them all. The merchant calls the button's own method instead; hook
  `MerchantFrameItem_UpdateQuality(item, link)` for it. Forever loads the `Mainline`
  versions of these frames (Blizzard_UIPanels_Game toc; CrateExpectations, 2026-11-16).
- Secure action buttons honor the `useOnKeyDown` attribute; with it `false` and
  `RegisterForClicks("AnyUp")`, key bindings and `/click Button` both fire once.

## Settings players change

- Options > Controls > "Loot Key" (called "Auto Loot Key" while Auto Loot is off) can be
  set to None, which removes the Shift bypass for auto loot entirely. Not a bug in an
  addon if Shift does nothing (2026-11-09).

## Game data

- `C_GossipInfo.ForceGossip()` is true for plain vendors with greeting text (Gorbold
  Steelhand, Auberdine: one option "I would like to buy from you.", 2026-11-09), so it
  isn't a useful "don't auto-pick" signal.
- Waylaid Crates (Merchant's Favor): a revealed crate's tooltip lists the bundles it
  takes after its "Use:" line, one per line (`- 6 Bolt of Woolen Cloth`), sometimes inside
  the Use line's own text with `\r\n` breaks (Forever++'s WaylaidCrates module). 30
  shipments in 7 kinds (ore, ingots, herbs, parts, textiles, fabrics, curiosities), one
  bundle fills a crate: https://www.method.gg/wow-forever/how-to-get-waylaid-crates-and-merchants-favor-in-wow-forever
  (3 Nov 2026, beta data; read 2026-11-16). Not yet checked against a crate in game.
  Crates can be traded and mailed until they're filled (seen in game by the player,
  2026-11-16), so alts can mail theirs to one character who fills and turns them in.
- Blessing of Kings is baseline: every Paladin trains it at level 20 (Classic: a
  Protection talent), and it lasts 1 hour. Source: Forever spell DB and guides, e.g.
  https://wow-forever.gg/db/spells/20217-blessing-of-kings/ (checked 2026-11-09).
- Forever realms have layering. Layers are separate per world, and Forever's starter
  islands are instance maps of their own directly under Azeroth (947): Zephras Isle
  (UiMap 2521, plus a second, parentless row 2665) and Darkspear Islands (2524). Players
  there can't share a layer with the continents, so a layer number on an island means
  nothing on the mainland. Source: AutoLayer 1.9.15's `AutoLayer_Camelot.toc`
  (`## Interface: 16001`) and `layerSegmentOverrides` in `AutoLayer.lua`, which cites
  Questie's `docs/forever-development.md` for the map IDs
  (https://github.com/iraizo/AutoLayer, read 2026-11-22). Not checked in game.
  Layering seems to be per zone: a group invite only moves you to the leader's layer
  when the leader is in your zone (AutoLayer issue #143 and its 1.9.16 fix, from player
  reports and its contributor's testing; Blizzard hasn't documented it).
- NPC GUIDs don't show the layer, unlike Classic Era. Of `Creature-0-A-B-C-npcID-spawn`,
  only B (the map: 36 Deadmines, 2999 Ruins of Lordaeron, 3065 Hall of Thanes) is shared. A (up to ~60000)
  and C (up to ~16.7 million) differ for every creature, even within one Deadmines run
  (ForeverDungeonJournal's saved GUIDs) and among NPCs in Stormwind's Trade District while
  standing on one layer (LayerCake saw 19 different C values within a minute, 2026-11-22).
  So the Classic trick (Nova World Buffs: C is the layer's zone ID) can't work here.
- Classic spell IDs (rank 1) still name the same spells, e.g. 20217 Kings; names should
  still come from `C_Spell.GetSpellName` so other client languages work.
