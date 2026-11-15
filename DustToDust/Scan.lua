-- The scan: three browse searches (uncommon, rare, epic weapons and armor), 500 results a
-- page. The search we sent says the quality, the item key says the item level, and the
-- class comes from GetItemInfoInstant, so pricing a result never waits for the server:
-- it's a lookup of its bucket's value (Logic.price).
local _, ns = ...
local Data, Logic, AH = ns.Data, ns.Logic, ns.AH
local Scan = {}
ns.Scan = Scan

local TAG = "scan"
local F = Enum.AuctionHouseFilter
local QUALITIES = {
    { Data.UNCOMMON_QUALITY, F.UncommonQuality },
    { Data.RARE_QUALITY, F.RareQuality },
    { Data.EPIC_QUALITY, F.EpicQuality },
}

Scan.results = {} -- the panel's rows: one per item key (item, item level, suffix)
Scan.running = false
local byKey = {}
local values = {} -- bucket -> value at the current prices (Logic.price)
local step -- index into QUALITIES
local skipped = 0 -- results without an item level

local function add(list, quality)
    local prices = ns.netPrices()
    local results = Scan.results
    for _, b in ipairs(list) do
        local key = b.itemKey
        local id = key.itemID .. ":" .. key.itemLevel .. ":" .. key.itemSuffix
        if not byKey[id] then
            local _, _, _, _, icon, classID = C_Item.GetItemInfoInstant(key.itemID)
            local ilvl = key.itemLevel
            local bucket, outcomes = Logic.bucket(classID, quality, ilvl, key.itemID)
            if ilvl == 0 then
                skipped = skipped + 1
            elseif bucket then
                local r = {
                    id = id,
                    browse = b,
                    itemKey = key,
                    itemID = key.itemID,
                    ilvl = ilvl,
                    band = Logic.band(ilvl),
                    skill = Logic.skillNeeded(ilvl),
                    quality = quality,
                    icon = icon,
                    bucket = bucket,
                    outcomes = outcomes,
                    buyout = b.minPrice > 0 and b.minPrice or nil,
                    qty = b.totalQuantity,
                }
                Logic.price(r, outcomes, prices, values)
                byKey[id] = r
                results[#results + 1] = r
            end
        end
    end
    if ns.Panel then
        ns.Panel.dirty()
    end
end

local function finish(text)
    Scan.running = false
    AH.cancel(TAG)
    if ns.Panel then
        ns.Panel.status(text)
        ns.Panel.refresh()
    end
end

local query

-- After each page: ask for the next one, or the next quality, or stop.
local function nextPage()
    if C_AuctionHouse.HasFullBrowseResults() then
        step = step + 1
        if step > #QUALITIES then
            finish(
                ("Scan done: %d items%s."):format(
                    #Scan.results,
                    skipped > 0 and (", %d without an item level skipped"):format(skipped) or ""
                )
            )
            return true
        end
        query()
        return true
    end
    AH.add({
        tag = TAG,
        timeout = 15,
        send = C_AuctionHouse.RequestMoreBrowseResults,
        handles = Scan.handles,
        onTimeout = function()
            finish("The auction house stopped answering; the list may be incomplete.")
        end,
    }, true) -- next page first: keep the scan together
    return true
end

Scan.handles = {
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function()
        add(C_AuctionHouse.GetBrowseResults(), QUALITIES[step][1])
        return nextPage()
    end,
    AUCTION_HOUSE_BROWSE_RESULTS_ADDED = function(list)
        add(list, QUALITIES[step][1])
        return nextPage()
    end,
    AUCTION_HOUSE_BROWSE_FAILURE = function()
        finish("The auction house search failed. Try again.")
        return true
    end,
}

query = function()
    local filter = QUALITIES[step][2]
    AH.add({
        tag = TAG,
        timeout = 15,
        send = function()
            C_AuctionHouse.SendBrowseQuery({
                searchString = "",
                sorts = {},
                filters = { filter },
                itemClassFilters = { { classID = Data.WEAPON }, { classID = Data.ARMOR } },
            })
        end,
        handles = Scan.handles,
        onTimeout = function()
            finish("The auction house didn't answer the search. Try again.")
        end,
    }, true) -- before any price checks still queued
    if ns.Panel then
        ns.Panel.status(("Scanning... %d items so far"):format(#Scan.results))
    end
end

function Scan.start()
    wipe(Scan.results)
    wipe(byKey)
    wipe(values)
    skipped, step, Scan.running = 0, 1, true
    query()
    if ns.Panel then
        ns.Panel.refresh()
    end
end

function Scan.stop(text)
    if Scan.running then
        finish(text or "Scan stopped.")
    end
end

-- Values the results again (prices or settings changed). One pass, bucket values cached.
function Scan.reprice()
    wipe(values)
    local prices = ns.netPrices()
    for _, r in ipairs(Scan.results) do
        Logic.price(r, r.outcomes, prices, values)
    end
end

-- One result again, e.g. after its cheapest auction changed.
function Scan.repriceOne(r)
    Logic.price(r, r.outcomes, ns.netPrices(), values)
end

function Scan.remove(r)
    for i, x in ipairs(Scan.results) do
        if x == r then
            table.remove(Scan.results, i)
            break
        end
    end
    byKey[r.id] = nil
end
