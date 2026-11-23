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
Logic.MIN_PROFIT = 100

-- What buying the auction and selling it to a vendor earns; <= 0 when it doesn't pay.
-- No buyout (bid only) never pays: we only buy outright.
function Logic.profit(sellPrice, count, buyout)
    if not sellPrice or sellPrice <= 0 or not buyout or buyout <= 0 then
        return 0
    end
    return sellPrice * (count or 1) - buyout
end

-- Adds one auction from the dump to `deals` (itemID -> deal) if it pays: any profit for
-- a pooled item, MIN_PROFIT for one bought auction by auction. Logic.sorted drops
-- pooled items whose total stays under MIN_PROFIT.
-- A deal: { itemID, auctions, units, cost, value, profit }.
function Logic.add(deals, itemID, count, buyout, sellPrice, pooled)
    local profit = Logic.profit(sellPrice, count, buyout)
    if profit < (pooled and 1 or Logic.MIN_PROFIT) then
        return
    end
    local deal = deals[itemID]
    if not deal then
        deal = { itemID = itemID, auctions = 0, units = 0, cost = 0, value = 0, profit = 0 }
        deals[itemID] = deal
    end
    deal.auctions = deal.auctions + 1
    deal.units = deal.units + count
    deal.cost = deal.cost + buyout
    deal.value = deal.value + sellPrice * count
    deal.profit = deal.profit + profit
end

-- Adds one browse search result (one item key: its cheapest price per unit and how
-- many are listed) to `deals` as an estimate, if its cheapest unit is under vendor
-- price. The search doesn't say how many are that cheap, so `profit` is a guess until
-- a lookup (Logic.fromOffers, Logic.fromCommodity) replaces it: for an item bought
-- auction by auction, what the cheapest one earns; for a pooled one, the most it could
-- earn (every listed unit at the cheapest price). Item keys of the same item (suffixes,
-- item levels) share its vendor price; the cheapest one is kept. `key` is kept as is
-- for the lookup.
function Logic.browse(deals, itemID, minPrice, listed, sellPrice, pooled, key)
    if not minPrice or minPrice <= 0 or not sellPrice or minPrice >= sellPrice then
        return
    end
    local gap = sellPrice - minPrice
    local profit = pooled and gap * (listed or 1) or gap
    if profit < Logic.MIN_PROFIT then
        return
    end
    local old = deals[itemID]
    if old and old.minPrice and old.minPrice <= minPrice then
        return
    end
    deals[itemID] = {
        itemID = itemID,
        itemKey = key,
        estimate = true,
        pooled = pooled or false,
        minPrice = minPrice,
        sellPrice = sellPrice,
        auctions = pooled and 0 or 1,
        units = pooled and listed or 1,
        cost = pooled and minPrice * listed or minPrice,
        value = pooled and sellPrice * listed or sellPrice,
        profit = profit,
    }
end

-- The deals worth showing, best profit first (ties: item ID, so the order is stable).
function Logic.sorted(deals)
    local list = {}
    for _, deal in pairs(deals) do
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
-- containsOwnerItem }), the auctions earning MIN_PROFIT, best profit first. Skips your
-- own and those in `skip` (auctionID -> true: already bought this visit).
function Logic.offers(results, sellPrice, skip)
    local out = {}
    for _, r in ipairs(results) do
        local profit = Logic.profit(sellPrice, r.quantity, r.buyoutAmount)
        if
            profit >= Logic.MIN_PROFIT
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
-- pays, what they cost, and in how many listings. A commodity purchase always takes
-- the cheapest units, so this stops at the first listing that doesn't pay (or is your
-- own).
function Logic.commodityUnits(results, sellPrice)
    local units, cost, listings = 0, 0, 0
    for _, r in ipairs(results) do
        if r.containsOwnerItem or not r.unitPrice or r.unitPrice >= (sellPrice or 0) then
            break
        end
        units = units + r.quantity
        cost = cost + r.unitPrice * r.quantity
        listings = listings + 1
    end
    return units, cost, listings
end

-- A deal's numbers from a lookup's offers (Logic.offers), replacing the estimate or
-- the dump's figures with what is listed now.
function Logic.fromOffers(deal, offers)
    deal.estimate = nil
    deal.auctions, deal.units, deal.cost, deal.profit = #offers, 0, 0, 0
    for _, offer in ipairs(offers) do
        deal.units = deal.units + offer.quantity
        deal.cost = deal.cost + offer.buyout
        deal.profit = deal.profit + offer.profit
    end
    deal.value = deal.cost + deal.profit
end

-- The same from a commodity lookup (Logic.commodityUnits).
function Logic.fromCommodity(deal, units, cost, listings, sellPrice)
    deal.estimate = nil
    deal.auctions, deal.units, deal.cost = listings, units, cost
    deal.value = units * sellPrice
    deal.profit = deal.value - cost
end
