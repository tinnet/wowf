-- BargainBin's arithmetic: plain data in, plain data out, no game API calls, so
-- tests/ can run it under busted. BargainBin.lua reads the game and calls in here.
-- All money is in copper. An auction's buyout is for the whole stack (true for the
-- full dump and for item searches alike; see docs/forever-notes.md).
local _, ns = ...
local Logic = {}
ns.Logic = Logic

-- Copper an auction must earn to be worth a click. The first real scan (2026-11-12)
-- had 91 items "under vendor price", nearly all crafted greens listed a few copper
-- under it by the hundred (Rough Bronze Leggings: 510 auctions, 1.8c each).
Logic.MIN_PROFIT = 100

-- What buying the auction and selling it to a vendor earns; <= 0 when it doesn't pay.
-- No buyout (bid only) never pays: we only buy outright.
function Logic.profit(sellPrice, count, buyout)
    if not sellPrice or sellPrice <= 0 or not buyout or buyout <= 0 then
        return 0
    end
    return sellPrice * (count or 1) - buyout
end

-- Adds one auction from the dump to `deals` (itemID -> deal) if it earns MIN_PROFIT.
-- A deal: { itemID, auctions, units, cost, value, profit }.
function Logic.add(deals, itemID, count, buyout, sellPrice)
    local profit = Logic.profit(sellPrice, count, buyout)
    if profit < Logic.MIN_PROFIT then
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

-- The deals as a list, best profit first (ties: item ID, so the order is stable).
function Logic.sorted(deals)
    local list = {}
    for _, deal in pairs(deals) do
        list[#list + 1] = deal
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
-- pays, and what they cost. A commodity purchase always takes the cheapest units,
-- so this stops at the first listing that doesn't pay (or is your own).
function Logic.commodityUnits(results, sellPrice)
    local units, cost = 0, 0
    for _, r in ipairs(results) do
        if r.containsOwnerItem or not r.unitPrice or r.unitPrice >= (sellPrice or 0) then
            break
        end
        units = units + r.quantity
        cost = cost + r.unitPrice * r.quantity
    end
    return units, cost
end
