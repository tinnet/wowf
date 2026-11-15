-- Checks what each disenchanting material sells for right now: one search per material
-- while the panel is open, at most every CHECK_EVERY seconds. Each check keeps the
-- cheapest unit price, how much is listed near it, and the deposit for each duration.
local _, ns = ...
local Data, Logic, AH = ns.Data, ns.Logic, ns.AH
local Prices = {}
ns.Prices = Prices

local CHECK_EVERY = 300
local TAG = "prices"

local lastStart -- GetTime() of the last check
local left = 0 -- materials still to answer in the running check
local answered = 0

local function sorts()
    return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

-- Deposit per unit for each duration. Commodities: the game's own number. Items: only
-- when you carry one (the game wants a bag slot); nil otherwise.
local function deposits(mat, commodity)
    local out = {}
    for d = 1, 3 do
        local cost
        if commodity then
            cost = C_AuctionHouse.CalculateCommodityDeposit(mat, d, 100)
            cost = cost and cost / 100
        else
            for bag = 0, NUM_BAG_SLOTS do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    if not cost and C_Container.GetContainerItemID(bag, slot) == mat then
                        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                        cost = C_AuctionHouse.CalculateItemDeposit(loc, d, 1)
                    end
                end
            end
        end
        out[d] = cost
    end
    return out
end

local function store(mat, listings, commodity)
    local lowest, depth, total = Logic.summarize(listings)
    if not lowest then
        ns.db.prices[mat] = nil -- none listed: no price is better than an old one
        return
    end
    local old = ns.db.prices[mat]
    local dep = deposits(mat, commodity)
    if old and old.deposits then
        for d = 1, 3 do
            dep[d] = dep[d] or old.deposits[d]
        end
    end
    ns.db.prices[mat] =
        { lowest = lowest, depth = depth, total = total, deposits = dep, at = time() }
end

local function finished()
    left = left - 1
    if left == 0 then
        ns.changed()
    elseif ns.Panel then
        ns.Panel.status()
    end
end

local function request(mat)
    local key = C_AuctionHouse.MakeItemKey(mat)
    return {
        tag = TAG,
        timeout = 5,
        send = function()
            C_AuctionHouse.SendSearchQuery(key, sorts(), false)
        end,
        handles = {
            COMMODITY_SEARCH_RESULTS_UPDATED = function(itemID)
                if itemID ~= mat then
                    return false
                end
                local listings = {}
                for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(mat) do
                    local info = C_AuctionHouse.GetCommoditySearchResultInfo(mat, i)
                    if info then
                        listings[#listings + 1] = info
                    end
                end
                store(mat, listings, true)
                answered = answered + 1
                finished()
                return true
            end,
            ITEM_SEARCH_RESULTS_UPDATED = function(itemKey)
                if itemKey.itemID ~= mat then
                    return false
                end
                local n = C_AuctionHouse.GetNumItemSearchResults(itemKey)
                if n == 0 and not C_AuctionHouse.HasFullItemSearchResults(itemKey) then
                    return false -- more is coming
                end
                local listings = {}
                for i = 1, n do
                    local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
                    if info and info.buyoutAmount and info.quantity and info.quantity > 0 then
                        listings[#listings + 1] = {
                            unitPrice = math.floor(info.buyoutAmount / info.quantity),
                            quantity = info.quantity,
                        }
                    end
                end
                store(mat, listings, false)
                answered = answered + 1
                finished()
                return true
            end,
        },
        onTimeout = finished,
    }
end

-- Starts a check unless one ran in the last CHECK_EVERY seconds (or force).
function Prices.check(force)
    if left > 0 or (not force and lastStart and GetTime() - lastStart < CHECK_EVERY) then
        return
    end
    lastStart, left, answered = GetTime(), #Data.MATERIALS, 0
    for _, m in ipairs(Data.MATERIALS) do
        AH.add(request(m[1]))
    end
    if ns.Panel then
        ns.Panel.status()
    end
end

function Prices.stop()
    AH.cancel(TAG)
    left = 0
end

-- One line for the panel's footer.
function Prices.summary()
    if left > 0 then
        return ("Checking material prices: %d of %d"):format(
            #Data.MATERIALS - left,
            #Data.MATERIALS
        )
    end
    local oldest, missing = 0, 0
    for _, m in ipairs(Data.MATERIALS) do
        local p = ns.matPrice(m[1])
        if not p then
            missing = missing + 1
        elseif p.age and p.age > oldest then
            oldest = p.age
        end
    end
    local text = ("Material prices: %d of %d"):format(#Data.MATERIALS - missing, #Data.MATERIALS)
    if oldest > 0 then
        text = text .. (", oldest %s"):format(ns.age(oldest))
    end
    return text
end
