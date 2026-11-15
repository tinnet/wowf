-- One request to the auction house at a time, sent when its throttle allows.
--
-- A request: { send = fn, handles = { EVENT = fn(...) -> true when it's answered },
-- timeout = seconds, onTimeout = fn, ready = fn (optional: false holds the queue until an
-- event pumps again), tag = anything (for cancel) }. Answers that come after a timeout
-- find another request (or none) waiting and are ignored by its handlers.
local _, ns = ...
local AH = {}
ns.AH = AH

local queue = {}
local current, sentAt
local open = false

-- Blizzard's own buy views show whatever item search comes back; don't search under them.
local function blizzardBuying()
    local f = AuctionHouseFrame
    return f
        and (
            (f.ItemBuyFrame and f.ItemBuyFrame:IsShown())
            or (f.CommoditiesBuyFrame and f.CommoditiesBuyFrame:IsShown())
        )
end

local retryTimer
local function retrySoon()
    if not retryTimer then
        retryTimer = C_Timer.NewTimer(1, function()
            retryTimer = nil
            AH.pump()
        end)
    end
end

function AH.pump()
    if current or not open or #queue == 0 then
        return
    end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        return -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY pumps again
    end
    if blizzardBuying() then
        retrySoon()
        return
    end
    local req = queue[1]
    if req.ready and not req.ready() then
        retrySoon()
        return
    end
    table.remove(queue, 1)
    current, sentAt = req, GetTime()
    local mine = sentAt
    req.send()
    C_Timer.After(req.timeout or 5, function()
        if current == req and sentAt == mine then
            current = nil
            if req.onTimeout then
                req.onTimeout()
            end
            AH.pump()
        end
    end)
end

function AH.add(req, front)
    if front then
        table.insert(queue, 1, req)
    else
        queue[#queue + 1] = req
    end
    AH.pump()
end

-- Drops queued requests (and the one waiting for its answer) whose tag matches.
function AH.cancel(tag)
    for i = #queue, 1, -1 do
        if queue[i].tag == tag then
            table.remove(queue, i)
        end
    end
    if current and current.tag == tag then
        current = nil
        AH.pump()
    end
end

function AH.busy(tag)
    if current and current.tag == tag then
        return true
    end
    for _, req in ipairs(queue) do
        if req.tag == tag then
            return true
        end
    end
    return false
end

function AH.isOpen()
    return open
end

local EVENTS = {
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
}

local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        open = true
        for _, e in ipairs(EVENTS) do
            self:RegisterEvent(e)
        end
        self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        self:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
        if ns.onAuctionHouseShow then
            ns.onAuctionHouseShow()
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        open = false
        wipe(queue)
        current = nil
        for _, e in ipairs(EVENTS) do
            self:UnregisterEvent(e)
        end
        self:UnregisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        self:UnregisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
        if ns.onAuctionHouseClosed then
            ns.onAuctionHouseClosed()
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        AH.pump()
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        if ns.onItemKeyInfo then
            ns.onItemKeyInfo(...)
        end
        AH.pump()
    else
        local req = current
        local handle = req and req.handles[event]
        if handle and handle(...) and current == req then
            current = nil
            AH.pump()
        end
    end
end)
