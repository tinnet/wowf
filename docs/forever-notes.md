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
- Secure action buttons honor the `useOnKeyDown` attribute; with it `false` and
  `RegisterForClicks("AnyUp")`, key bindings and `/click Button` both fire once.

## Settings players change

- Options > Controls > "Loot Key" (called "Auto Loot Key" while Auto Loot is off) can be
  set to None, which removes the Shift bypass for auto loot entirely. Not a bug in an
  addon if Shift does nothing (2026-11-09).

## Game data

- Blessing of Kings is baseline: every Paladin trains it at level 20 (Classic: a
  Protection talent), and it lasts 1 hour. Source: Forever spell DB and guides, e.g.
  https://wow-forever.gg/db/spells/20217-blessing-of-kings/ (checked 2026-11-09).
- Classic spell IDs (rank 1) still name the same spells, e.g. 20217 Kings; names should
  still come from `C_Spell.GetSpellName` so other client languages work.
