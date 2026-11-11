-- RichPeopleBoatMoney: whenever a full auction house dump arrives
-- (C_AuctionHouse.ReplicateItems, from any addon or /rpbm scan), copy every auction into
-- SavedVariables so a script outside the game can export it (just rpbm-export,
-- scripts/rpbm-jsonl.lua). Auctionator only makes this dump with "Use alternate slower
-- scan mode by default" on (its Advanced options); its default "summary" scan is a
-- browse search with one lowest price per item, which this addon doesn't see.
-- CraftProfit dumps too.
-- The game writes SavedVariables only on logout, /reload or exit, so a scan reaches
-- the disk then. The last MAX_SCANS scans are kept, so a few scans in one session
-- survive until the next export: a full scan is ~200k auctions (~6 MB), and the whole
-- file is rewritten at logout and read back at every login. `just rpbm-export` copies
-- each scan to its own file outside the game, so nothing older than that is needed here.
--
-- One dump = one ReplicateItems call (hooked, so other addons' calls count too).
-- REPLICATE_ITEM_LIST_UPDATE then fires hundreds of times (seen 2026-11-11), probably
-- as item details load, so the read waits until it has been quiet for a moment.
--
-- Each auction is one row, fields in this order (ROW_FIELDS in the export script):
--   itemID,count,quality,level,minBid,minIncrement,buyout,bid,timeLeft,saleStatus,owner,itemString
-- Rows are joined with ";" into one string per PER_FRAME auctions: Lua 5.1 refuses to
-- load a file with more than 262,143 distinct strings in one table, and the dump is
-- already past 200k.
-- Money is in copper; buyout and bids are for the whole stack, not per item. itemString
-- is the link's "item:..." part when it says more than the item ID (suffix like "of the
-- Bear", enchant, bonus IDs), else empty; also empty when the client hadn't loaded the
-- item yet (then quality is -1). Forever leaves owner empty.

local ADDON = ...
local PER_FRAME = 1000 -- rows read per frame (and per saved string)
local QUIET = 3 -- read once no update event has come for this many seconds...
local MAX_WAIT = 30 -- ...or this long after the first one, whichever is first
local MAX_SCANS = 4 -- oldest saved scan is dropped beyond this

local db
local requested = false -- a dump was asked for and not read yet
local requestedAt -- GetTime() of that request
local readAt -- GetTime() of the request whose dump was read last
local timer -- pending read
local firstEvent -- GetTime() of the first update event of this dump
local reading -- the scan being read right now, or nil
local events, ignored = 0, 0 -- update events since login: all, and ones not acted on

local function chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RichPeopleBoatMoney|r: " .. msg)
end

-- The link's "item:..." part minus what describes you, not the item: the game puts the
-- viewer's level and spec in fields 9 and 10 of every link. "" when only the item ID is
-- left (84% of auctions on 2026-11-11), which halves the scan's size.
local VIEWER_FIELDS = "^(item" .. (":[^:]*"):rep(8) .. "):[^:]*:[^:]*(.*)$"
local function itemDetails(link, itemID)
    local itemString = link and link:match("|H(item:[^|]+)|h")
    if not itemString then
        return ""
    end
    local head, tail = itemString:match(VIEWER_FIELDS)
    if head then
        itemString = (head .. "::" .. tail):gsub(":+$", "")
    end
    return itemString == "item:" .. itemID and "" or itemString
end

-- One auction as a row, and whether it had a link. Replicate indexes start at 0.
-- %.0f for money: %d would wrap above 2^31 copper.
local function readRow(i)
    local _, _, count, quality, _, level, _, minBid, minIncrement, buyout, bid, _, _, owner, _, saleStatus, itemID =
        C_AuctionHouse.GetReplicateItemInfo(i)
    local link = C_AuctionHouse.GetReplicateItemLink(i)
    return ("%d,%d,%d,%d,%.0f,%.0f,%.0f,%.0f,%d,%d,%s,%s"):format(
        itemID or 0,
        count or 0,
        quality or 0,
        level or 0,
        minBid or 0,
        minIncrement or 0,
        buyout or 0,
        bid or 0,
        C_AuctionHouse.GetReplicateItemTimeLeft(i) or 0,
        saleStatus or 0,
        owner or "",
        itemDetails(link, itemID)
    ),
        link ~= nil
end

local function stopReading(why)
    if reading then
        reading = nil
        chat("stopped reading the scan: " .. why .. "; nothing saved")
    end
end

local function readBatch(scan)
    if reading ~= scan then
        return -- stopped
    end
    if C_AuctionHouse.GetNumReplicateItems() ~= scan.count then
        stopReading("the auction list changed while reading")
        return
    end
    local first = scan.read
    local last = math.min(first + PER_FRAME, scan.count) - 1
    local rows = {}
    for i = first, last do
        local row, hasLink = readRow(i)
        if not hasLink then
            scan.missingLinks = scan.missingLinks + 1
        end
        rows[#rows + 1] = row
    end
    scan.chunks[#scan.chunks + 1] = table.concat(rows, ";")
    scan.read = last + 1
    if scan.read < scan.count then
        C_Timer.After(0, function()
            -- an error must not leave `reading` set, or every later dump is ignored
            local ok, err = pcall(readBatch, scan)
            if not ok then
                stopReading("error " .. tostring(err))
            end
        end)
        return
    end
    reading = nil
    scan.read = nil
    table.insert(db.scans, scan)
    while #db.scans > MAX_SCANS do
        table.remove(db.scans, 1)
    end
    chat(
        ("saved %d auctions (%d without item details), %d scan(s) kept; on disk after logout or /reload."):format(
            scan.count,
            scan.missingLinks,
            #db.scans
        )
    )
end

local function startReading()
    timer, firstEvent, requested = nil, nil, false
    readAt = requestedAt
    local count = C_AuctionHouse.GetNumReplicateItems()
    if count == 0 then
        chat("the scan came back empty")
        return
    end
    reading = {
        time = GetServerTime(),
        realm = GetRealmName(),
        faction = UnitFactionGroup("player"), -- "Alliance"/"Horde" in every client language
        character = UnitName("player"),
        count = count,
        missingLinks = 0,
        read = 0,
        chunks = {},
    }
    local ok, err = pcall(readBatch, reading)
    if not ok then
        stopReading("error " .. tostring(err))
    end
end

local function onUpdate()
    events = events + 1
    if not requested or reading then
        ignored = ignored + 1
        return
    end
    local now = GetTime()
    firstEvent = firstEvent or now
    if timer then
        timer:Cancel()
    end
    timer =
        C_Timer.NewTimer(math.max(0, math.min(QUIET, firstEvent + MAX_WAIT - now)), startReading)
end

local function forget()
    if timer then
        timer:Cancel()
    end
    timer, firstEvent, requested = nil, nil, false
    stopReading("the auction house was closed")
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg)
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        onUpdate()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        forget()
    elseif arg == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        RichPeopleBoatMoneyDB = RichPeopleBoatMoneyDB or {}
        db = RichPeopleBoatMoneyDB
        db.scans = db.scans or {}
        self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    end
end)

-- Runs after every ReplicateItems call, whoever makes it. Calls within 15 minutes of
-- the dump we read last are ignored: the server refuses them, and the update events
-- still trickling in for that dump must not start a second read of the same data.
hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
    local now = GetTime()
    if reading or timer or (readAt and now - readAt < 15 * 60) then
        return
    end
    requested, requestedAt = true, now
end)

local function status()
    if reading then
        chat(("reading a scan right now (%d of %d)"):format(reading.read, reading.count))
    elseif requested then
        chat("a scan was asked for; waiting for it")
    end
    chat(
        ("scan update events since login: %d (%d ignored: no scan asked for, or already read)"):format(
            events,
            ignored
        )
    )
    if #db.scans == 0 then
        chat(
            "no scan saved yet: open the auction house and /rpbm scan, or see the notes on Auctionator in README"
        )
        return
    end
    for _, scan in ipairs(db.scans) do
        chat(
            ("saved: %s, %d auctions, %s %s"):format(
                date("%Y-%m-%d %H:%M", scan.time),
                scan.count or 0,
                scan.realm or "?",
                scan.faction or "?"
            )
        )
    end
end

SLASH_RPBM1 = "/rpbm"
SlashCmdList.RPBM = function(msg)
    msg = msg:lower():match("^%s*(.-)%s*$")
    if msg == "scan" then
        if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
            chat("open the auction house first")
            return
        end
        C_AuctionHouse.ReplicateItems()
        chat(
            "asked for a full scan; it arrives within a minute unless one ran in the last 15 minutes (then nothing comes)"
        )
    elseif msg == "clear" then
        db.scans = {}
        chat("saved scans deleted")
    else
        status()
        chat("/rpbm scan asks for a full scan, /rpbm clear deletes the saved ones")
    end
end
