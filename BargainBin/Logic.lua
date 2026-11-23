-- BargainBin's arithmetic: plain data in, plain data out, no game API calls, so
-- tests/ can run it under busted. BargainBin.lua reads the game and calls in here.
-- All money is in copper. An auction's buyout is for the whole stack (true for the
-- full dump and for item searches alike; see docs/forever-notes.md).
local _, ns = ...
local Logic = {}
ns.Logic = Logic

-- Copper a deal must earn to be worth a click. The first real scan (2026-11-12)
-- had 91 items "under vendor price", nearly all crafted greens listed a few copper
-- under it by the hundred (Rough Bronze Leggings: 510 auctions, 1.8c each).
--
-- Items that don't stack are bought one auction per click, so each auction must earn
-- it. Stackable ones (cloth, herbs, ore, ...) are pooled: one purchase takes all the
-- cheap units at once, so only the item's total must earn it. "Stackable" stands in
-- for "commodity", which the game only tells for an item in your bags.
--
-- The rules (`rules`, optional everywhere): `each` = every single unit must earn
-- MIN_PROFIT over what it costs (per item, not per stack).
Logic.MIN_PROFIT = 100

-- What buying the auction and selling it to a vendor earns; <= 0 when it doesn't pay.
-- No buyout (bid only) never pays: we only buy outright.
function Logic.profit(sellPrice, count, buyout)
    if not sellPrice or sellPrice <= 0 or not buyout or buyout <= 0 then
        return 0
    end
    return sellPrice * (count or 1) - buyout
end

-- Whether an auction earning `profit` for `quantity` units passes the rules.
local function passes(profit, quantity, pooled, rules)
    if profit <= 0 then
        return false
    end
    if rules and rules.each and profit < Logic.MIN_PROFIT * (quantity or 1) then
        return false
    end
    return pooled or profit >= Logic.MIN_PROFIT
end

-- A deal: { itemID, sellPrice, pooled, lots = { {quantity, buyout}, ... } }, or an
-- estimate from the browse search (Logic.browse). Logic.total fills in its totals.
local function newDeal(itemID, sellPrice, pooled)
    return { itemID = itemID, sellPrice = sellPrice, pooled = pooled or false, lots = {} }
end

-- Adds one auction from the dump to `deals` (itemID -> deal) if it costs less than a
-- vendor pays. Which auctions count is decided later (Logic.total), so the rules can
-- change without a new scan.
function Logic.add(deals, itemID, count, buyout, sellPrice, pooled)
    if Logic.profit(sellPrice, count, buyout) <= 0 then
        return
    end
    local deal = deals[itemID]
    if not deal then
        deal = newDeal(itemID, sellPrice, pooled)
        deals[itemID] = deal
    end
    deal.lots[#deal.lots + 1] = { quantity = count, buyout = buyout }
end

-- Adds one browse search result (one item key: its cheapest price per unit and how
-- many are listed) to `deals` as an estimate, if its cheapest unit is under vendor
-- price. The search doesn't say how many are that cheap, so the estimate's profit is a
-- guess until a lookup (Logic.fromOffers, Logic.fromCommodity) replaces it: for an item
-- bought auction by auction, what the cheapest one earns; for a pooled one, the most it
-- could earn (every listed unit at the cheapest price). Item keys of the same item
-- (suffixes, item levels) share its vendor price; the cheapest one is kept. An item
-- already listed with exact numbers (from the full dump or a lookup) is left as it is.
-- `key` is kept as is for the lookup.
function Logic.browse(deals, itemID, minPrice, listed, sellPrice, pooled, key)
    if not minPrice or minPrice <= 0 or not sellPrice or minPrice >= sellPrice then
        return
    end
    local old = deals[itemID]
    if old and (not old.estimate or old.minPrice <= minPrice) then
        return
    end
    local deal = newDeal(itemID, sellPrice, pooled)
    deal.lots = nil
    deal.itemKey, deal.estimate, deal.minPrice, deal.listed = key, true, minPrice, listed or 1
    deals[itemID] = deal
end

-- Fills in a deal's totals under the rules: auctions, units, cost, value (what a
-- vendor pays for those units), profit.
function Logic.total(deal, rules)
    local auctions, units, cost = 0, 0, 0
    if deal.estimate then
        local n = deal.pooled and deal.listed or 1
        local gap = deal.sellPrice - deal.minPrice
        if passes(gap * n, n, deal.pooled, rules) then
            auctions, units, cost = deal.pooled and 0 or 1, n, deal.minPrice * n
        end
    else
        for _, lot in ipairs(deal.lots) do
            local profit = Logic.profit(deal.sellPrice, lot.quantity, lot.buyout)
            if passes(profit, lot.quantity, deal.pooled, rules) then
                auctions = auctions + 1
                units = units + lot.quantity
                cost = cost + lot.buyout
            end
        end
    end
    deal.auctions, deal.units, deal.cost = auctions, units, cost
    deal.value = units * deal.sellPrice
    deal.profit = deal.value - cost
end

-- Drops the estimates (Logic.browse) and keeps exact deals: a new quick scan replaces
-- only what the last one found.
function Logic.dropEstimates(deals)
    for itemID, deal in pairs(deals) do
        if deal.estimate then
            deals[itemID] = nil
        end
    end
end

-- The deals worth showing under the rules, best profit first (ties: item ID, so the
-- order is stable). Totals are filled in on every deal.
function Logic.sorted(deals, rules)
    local list = {}
    for _, deal in pairs(deals) do
        Logic.total(deal, rules)
        if deal.profit >= Logic.MIN_PROFIT then
            list[#list + 1] = deal
        end
    end
    table.sort(list, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.itemID < b.itemID
    end)
    return list
end

-- From an item search's results ({ auctionID, quantity, buyoutAmount,
-- containsOwnerItem }), the auctions earning MIN_PROFIT (each one is a click) under
-- the rules, best profit first. Skips your own and those in `skip` (auctionID -> true:
-- already bought this visit).
function Logic.offers(results, sellPrice, skip, rules)
    local out = {}
    for _, r in ipairs(results) do
        local profit = Logic.profit(sellPrice, r.quantity, r.buyoutAmount)
        if
            passes(profit, r.quantity, false, rules)
            and not r.containsOwnerItem
            and not (skip and skip[r.auctionID])
        then
            out[#out + 1] = {
                auctionID = r.auctionID,
                quantity = r.quantity,
                buyout = r.buyoutAmount,
                profit = profit,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then
            return a.profit > b.profit
        end
        return a.auctionID < b.auctionID
    end)
    return out
end

-- From a commodity search's results ({ quantity, unitPrice, containsOwnerItem },
-- cheapest first as the game sends them), how many units cost less than a vendor
-- pays (by MIN_PROFIT each under the `each` rule), and what they cost. A commodity
-- purchase always takes the cheapest units, so this stops at the first listing that
-- doesn't pay (or is your own).
function Logic.commodityUnits(results, sellPrice, rules)
    local margin = rules and rules.each and Logic.MIN_PROFIT or 1
    local units, cost = 0, 0
    for _, r in ipairs(results) do
        if r.containsOwnerItem or not r.unitPrice or (sellPrice or 0) - r.unitPrice < margin then
            break
        end
        units = units + r.quantity
        cost = cost + r.unitPrice * r.quantity
    end
    return units, cost
end

-- A lookup replaces the estimate or the dump's auctions with what is listed now:
-- the offers (Logic.offers; the same table, so buying one removes its lot)...
function Logic.fromOffers(deal, offers)
    deal.estimate, deal.lots = nil, offers
end

-- ...or the commodity units that pay (Logic.commodityUnits), bought as one.
function Logic.fromCommodity(deal, units, cost)
    deal.estimate, deal.lots = nil, { { quantity = units, buyout = cost } }
end
