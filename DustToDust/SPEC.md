# DustToDust: spec

Finds weapons and armor on the auction house that are worth more disenchanted than they
cost. It is meant to do the job of DisenchantValue (Siz, 1.1.1), but with three
differences:

- It doesn't freeze the game while it scans.
- Its profit figure is what you actually keep after selling the materials: after the
  auction house cut and the deposit, at a price someone will actually pay.
- It tells you how likely an item is to lose money, and whether you can disenchant it at
  all.

Status: version 1 built (2026-11-15), not yet tried in game.

## What's wrong with DisenchantValue (why not just patch it)

Read on 2026-11-15, from the copy installed in the game:

- **The lag.**
  - Each scan result asks the server for the item's data and its auction house name, so a
    scan sends thousands of requests.
  - Each answer then loops over every result to find its own item
    (`AuctionScan.lua:462-472`). That's N² work on the main thread.
  - The list is also re-sorted and rebuilt every 0.2 s while answers keep arriving.
  - Its disenchant button rescans your bags on every item data answer.
- **Profit is too high.** Materials are priced at Auctionator's lowest listing, with no
  5% cut, no deposit and no undercut. A material Auctionator no longer prices keeps its
  last saved price for good.
- **Its tables are slightly off.**
  - Weapons from item level 51 up have their own chances in the wiki (dust 22%, essence
    75%, shard 3%). DisenchantValue uses the item level 50 numbers (20/75/5) for them too.
  - It records your own disenchant results, but the value shown never uses them.
- **No skill check.** It lists items your Enchanting is too low for.

## Scope

**Version 1:**

1. An auction house panel with a tab, like DisenchantValue's: Scan, a sortable list,
   item level bracket filters, and "only profitable".
2. Material prices: its own price check of the ~24 disenchanting materials while the
   panel is open, with Auctionator's prices as the fallback.
3. Profit after the cut, deposit and undercut. Also: chance of a loss, and a "can't
   disenchant yet" mark.
4. Quick buy: click to buy the cheapest one, only at the price shown. A higher price
   needs one more click to confirm. This works the same way as BargainBin and
   DisenchantValue.
5. A tooltip line on disenchantable items: what disenchanting it is worth after costs.
6. Recording your own disenchants, with `/dtd data` comparing what you got to the table.

**Later, or never:**

- Feeding a shopping list into Auctionator.
- Using your own results in the value.

## Data

### Disenchant table

The table lives in `DustToDust/Data.lua`. Its source is warcraft.wiki.gg "Disenchanting
tables" (fetched 2026-11-15, page dated 2021). The wiki marks that page as outdated, and it
isn't Classic-specific. Its item level 65 and lower rows agree with Auctionator's Classic
table (`Source_Classic/Enchant/DisenchantingProbabilities.lua`), so it is the best source
we have, but nobody has checked it against Forever. The recording in version 1, item 6,
is how we check it.

The table goes by item class, quality and item level band. Each row lists every possible
result with its chance (e.g. "4-6 Strange Dust, 75%" becomes 4, 5 and 6 at 25% each). The
outcomes are kept, not just their average, because the chance of a loss needs them.

- **Uncommon armor** (5–15 … 61–65): dust 75–80%, essence 15–20%, shard 0–10%.
- **Uncommon weapons**: the dust and essence chances are swapped. From item level 51 up
  the chances are dust 22%, essence 75%, shard 3%. The first band starts at item level 6.
- **Rare**: one shard, 100% of the time. From item level 56 up it is a Large Brilliant
  Shard 99.5% of the time and a Nexus Crystal 0.5% of the time.
- **Epic**:

  | Item level | Result |
  |---|---|
  | 40–45 | 2–4 Small Radiant Shards |
  | 46–50 | 2–4 Large Radiant Shards |
  | 51–55 | 2–4 Small Brilliant Shards |
  | 56–60 | 1 Nexus Crystal |
  | 61+ | 1–2 Nexus Crystals |

  Below item level 40 the wiki says "fall within the ranges for Uncommon/Rare", so we use
  the rare row. There are very few such items.
- **Never listed:** the enchanter-made wands (11287–11290) and anything that isn't weapon
  or armor.

### Enchanting skill needed

| Item level | Skill needed |
|---|---|
| 1–20 | 1 |
| 21–25 | 25 |
| 26–30 | 50 |
| 31–35 | 75 |
| 36–40 | 100 |
| 41–45 | 125 |
| 46–50 | 150 |
| 51–55 | 175 |
| 56–60 | 200 |
| 61+ | 225 |

- The same table applies to every quality. Rares start at item level 10, which needs 25.
- The wiki's 275 for rares of item level 61 and up is a later expansion's number. For
  Classic we use 225, which needs checking in game.
- Your skill comes from `GetProfessions()` / `GetProfessionInfo()` (Blizzard's own Forever
  profession book uses them), Enchanting's skill line is 333. Characters without
  Enchanting see everything, and a column says the skill needed.

### Material prices (the main improvement)

**Our own price check.** When the panel opens, DustToDust searches each material, at most
about once every 5 minutes. That is about 24 searches, queued behind the auction house's
throttle.

- Each search gives every listing, cheapest first: unit price and quantity.
- Each material then has:
  - `lowest`: the cheapest unit price.
  - `depth`: how many units are listed within 10% of the lowest price.
  - `checkedAt`.
- Whether a material is a commodity (pooled units) or an item comes from
  `C_AuctionHouse.GetItemKeyInfo(itemKey).isCommodity`, which decides between
  `SendSearchQuery`'s commodity and item results. This isn't verified on Forever yet.

**Fallback.** Without our own check, the price is Auctionator's
(`Auctionator.API.v1.GetAuctionPriceByItemID`). `GetAuctionAgeByItemID` gives its age, and
prices older than 2 days are shown as stale (grey, with the age in the tooltip). We don't
keep a copy of our own: an old price shows as old instead of quietly standing in for a
current one.

**What a material is worth to you:**

```
net = (lowest − 1c undercut) × (1 − cut) − deposit per unit
```

- **Cut:** 5% by default, as a setting. It still needs checking against the sale mail of
  one real sale.
- **Deposit:**
  - Comes from `C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, 1)` when the
    material is a commodity.
  - Otherwise from the vendor price, using the deposit formula. Which formula Forever
    uses still needs checking.
  - Duration is a setting, 24 h by default. Forever's durations are 2, 8 and 24 h, per
    Auctionator's `Source_Forever`.
- **Setting "I use the materials myself":** no cut, no deposit, no undercut, so `net`
  becomes the market price. Use it when you level Enchanting rather than sell.

If a material has no price at all, every item that can give it shows "?" in the value
column. It isn't silently valued at 0 the way DisenchantValue does.

## Value, profit, risk

All of this is pure math in `Logic.lua`, tested in `tests/dusttodust_spec.lua`.

- **Bucket value:** the value depends only on item class, quality and item level band. That
  is at most about 70 buckets, not one per auction. DustToDust works out each bucket's
  outcomes and their worth whenever material prices change. Pricing an auction is then a
  table lookup.
- **Expected value:** the sum of chance × quantity × `net` over the bucket's outcomes.
- **Profit:** expected value − buyout.
- **Loss chance:** the chance that what you actually get is worth less than the buyout.
  A bucket has at most about 10 outcomes, so this is an exact sum, not a guess.
  - Example: a green at item level 23 costs 30s. A shard (10%) or a 5- or 6-dust result
    may cover that, while 1–2 essence doesn't.
  - Shown as a column. "Only profitable" also hides items whose loss chance is over 50%
    (a setting).
- **Margin floor:** a deal must earn at least 1s and at least 10% of its buyout to count as
  profitable. Both are settings; BargainBin's first scan showed that tiny margins are just
  noise.

## Scanning (the efficient part)

**Three browse searches,** one each for uncommon, rare and epic weapons and armor
(`SendBrowseQuery` with a single quality filter). The search we sent tells us the quality,
so no item data is needed for it.

Everything else a result needs is available without asking the server:

| What | From |
|---|---|
| item level | `itemKey.itemLevel` |
| class | `C_Item.GetItemInfoInstant(itemID)`, which works without the item being loaded |
| buyout | `minPrice` |
| quantity | `totalQuantity` |

So pricing a result is a bucket lookup that needs no server request.

- Results are kept in a table keyed by item ID, item level and suffix. They are added one
  batch at a time, as the 500-result batches arrive.
- A batch's work is a single loop, without sorting or redrawing during the batch.

**Names and icons only for rows on screen.**

- The list is a ScrollBox. Its row initializer asks for an item's name with
  `Item:CreateFromItemID(id):ContinueOnItemLoad` only when that row is drawn.
- When the name arrives, that one row is redrawn, if it's still showing.
- There's no event handler that loops over the results.

**Redrawing.**

- During a scan, the list is sorted and redrawn at most once a second, and once at the
  end.
- Clicking a sort header sorts once.
- Filters run over the results once, not per row.

**Budget.** If a batch is ever slow, the work is spread over frames, with at most 4 ms per
frame measured with `debugprofilestop`. We expect a whole batch to take about 1 ms, since
it's a loop with table lookups.

**Outside the auction house:**

- No events are registered except `AUCTION_HOUSE_SHOW`, the loot and spellcast events
  used for recording, and the tooltip hook.
- The tooltip line is a bucket lookup plus `GetItemInfo`, which the tooltip has already
  loaded.

**What we won't do:**

- We won't use the full dump (`ReplicateItems`). It's limited to once per 15 minutes,
  it's 200k rows, and it gets in the way of BargainBin and RichPeopleBoatMoney.
- We won't keep track of other addons' browse searches. Auctionator does record our
  results as prices; that's harmless.

## The panel

It looks like DisenchantValue's: a ButtonFrame to the right of the auction house, a
"Disenchant" tab under the auction house, and Blizzard's list art.

**Top row:**

- Scan / Stop.
- "Only profitable".
- "Only what I can disenchant", shown when the character has Enchanting.
- Item level bracket buttons.

**Columns:**

| Column | Notes |
|---|---|
| Item | The name includes its suffix; the icon only loads once the row is on screen. |
| iLvl | |
| Qty | |
| Price | |
| DE value | Expected value after costs. |
| Profit | |
| Loss % | |
| Skill | Shown only when you can't disenchant the item yet. |

**Row tooltip:**

- The item.
- Each outcome with its chance and its value after costs.
- Each material's price source and age ("checked 3 min ago" / "Auctionator, 2 days old").

**Footer:**

- Status.
- Material check status ("prices: 24/24 checked 2 min ago").
- This visit's totals: number bought, spent, expected value.

**Clicks:**

- Click: quick buy.
- Right-click: open the item in the auction house's buy view.
- Shift-click: link it in chat.

DisenchantValue's careful handling here is worth keeping as an idea: wait for the
throttle before opening the buy view, never buy at a price the row doesn't show, and
require one confirmation click after a price rise. We write our own code for it.

## Recording your disenchants

- **How a disenchant is caught:**
  - `UNIT_SPELLCAST_SENT` for Disenchant (13262); its payload has the target item's name.
  - A hook on `C_Container.UseContainerItem` gives the item link.
  - The next `LOOT_OPENED` within 15 s gives the results.
- **What's stored,** per bucket in `DustToDustDB.observed`: the number of disenchants and
  the count of each outcome.
- **`/dtd data`** lists the buckets with at least 10 disenchants, next to the table. It
  flags any outcome whose share is more than 2 standard errors away from the table's
  chance, which is a sign that Forever's chances differ.
- **Later:** a setting to blend your results into the value, with the table counting as
  20 disenchants of its own.

## Files

```
DustToDust/
  DustToDust.toc        Interface 16001, SavedVariables DustToDustDB, OptionalDeps Auctionator
  Data.lua              tables: outcomes, skill needed, materials (pure data)
  Logic.lua             buckets, outcome values, net price, loss chance, filters (pure, tested)
  Core.lua              saved settings, material prices (own check or Auctionator), /dtd
  AH.lua                one auction house request at a time, behind the throttle
  Prices.lua            material price check queue + Auctionator fallback
  Scan.lua              the three browse searches, result table
  Panel.lua             panel, tab, rows, quick buy
  Tooltip.lua           tooltip line
  Record.lua            recording disenchants, /dtd data
  Options.lua           Settings panel: cut, duration, use-myself, margin floor, loss filter
tests/dusttodust_spec.lua
```

Plus a README row and notes in `docs/forever-notes.md` for whatever we verify: the cut,
commodity status, deposit formula, skill numbers.

## Things to verify in game (first session)

1. The cut: sell one dust and read the mail.
2. Whether dusts and shards are commodities (the search result type).
3. Whether `itemKey.itemLevel` is filled in for browse results of gear, and not 0.
4. Whether `GetProfessionInfo` returns Enchanting with skill line 333.
5. The skill needed for rares of item level 61 and up: 225, or something else.
6. Whether Auctionator shows any disenchant value on Forever at all. Its Mainline module
   only covers retail expansions (Warlords of Draenor and later). If it shows nothing, our
   tooltip line is the only one.

## Decisions (2026-11-15)

1. No one-button disenchanter.
2. Quick buy without a prompt, as in DisenchantValue (a price rise still takes one click
   to accept).
3. Defaults as proposed: 5% cut, 24 h deposit, 1s and 10% margin, at most 50% loss chance.
4. The tooltip line always shows; DisenchantValue is going to be uninstalled.
