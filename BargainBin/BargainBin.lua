-- BargainBin: finds auctions you can buy for less than a vendor pays for them.
--
-- A window next to the auction house, opened with the Bargains tab under it (like
-- DustToDust's; opening one closes the other, since both sit in the same place).
--
-- Full scan (the Full button, /rpbm scan, or Auctionator's slower scan mode): reads
-- every full auction house dump (C_AuctionHouse.ReplicateItems), compares each
-- auction's buyout with the item's vendor price times the stack size, and lists the
-- items that pay, best profit first. The server sends one only every 15 minutes per
-- account and ignores earlier requests, so the Full button counts down from the last
-- request this client saw (any addon's).
--
-- Quick scan (the Quick button): the auction house's own search with no filters, which
-- gives every item's cheapest price per unit, not every auction. It isn't limited to
-- once per 15 minutes, so it can be repeated to catch new listings before someone else
-- buys them. An item whose cheapest unit is under vendor price is listed as an
-- estimate (see Logic.browse) until a click looks it up. A quick scan replaces only the
-- last quick scan's estimates; what the full dump found stays until the next dump.
--
-- "At least 1s each" (saved): only auctions where every single unit earns 1s count.
-- Deals keep their auctions, so switching it re-filters at once without a new scan.
--
-- Buying: the dump has no auction IDs, and the game only buys from a click. So the
-- first click on an item looks up its current auctions; every further click buys one
-- auction that still pays (best first). Each lookup is trusted for a minute. Stackable
-- items that the auction house sells as commodities (pooled units, not stacks) take a
-- click to start the purchase and one to confirm once the game names the total.
--
-- Vendor prices are the client's (C_Item.GetItemInfo); an item the client hasn't loaded
-- yet is asked for and counted once it arrives.
local addonName, ns = ...
local Logic = ns.Logic

local PER_FRAME = 2000 -- dump rows read per frame
-- The dump arrives in batches (another addon saw one stop at exactly 1024 auctions after
-- 2 quiet seconds), and on full realms it can take well over a minute to start.
local QUIET = 4 -- read once no update event has come for this many seconds...
local MAX_WAIT = 120 -- ...or this long after the first one
local NO_ANSWER = 120 -- seconds after a request with no update event: the server refused
local SERVER_LIMIT = 15 * 60 -- seconds between full scans the server allows (per account)
local OFFER_TTL = 60 -- seconds a lookup is trusted for buying
local LOOKUP_TIMEOUT = 5 -- seconds before an unanswered search is sent again (once)
local QUICK_TIMEOUT = 15 -- seconds the quick scan waits for a page before giving up
-- Quality filters are opt-in: a browse search without any matches nothing. Blizzard's
-- search bar sends all of them by default (AUCTION_HOUSE_DEFAULT_FILTERS).
local F = Enum.AuctionHouseFilter
local ALL_QUALITIES = {
    F.PoorQuality,
    F.CommonQuality,
    F.UncommonQuality,
    F.RareQuality,
    F.EpicQuality,
    F.LegendaryQuality,
}

local WIDTH = 720 -- DustToDust's
local ROW_HEIGHT = 20
local GREEN, GREY = { 0.1, 1, 0.1 }, { 0.6, 0.6, 0.6 }
local COLUMNS = {
    { label = "Item", width = 0 }, -- takes what the others leave
    { label = "Qty", width = 50 },
    { label = "Cost", width = 110 },
    { label = "Vendor pays", width = 110 },
    { label = "Profit", width = 110 },
    { label = "Each", width = 90 },
}

local db -- BargainBinDB: { each = bool, lastFullScan = time() of the last request }
local deals = {} -- itemID -> deal (Logic.add, Logic.browse)
local prices = {} -- itemID -> vendor price per unit (0: none)
local pooled = {} -- itemID -> true when it stacks (Logic.MIN_PROFIT says why that matters)
local waiting = {} -- itemID -> { fn(price, pooled), ... } results waiting for the price
local waitingCount = 0
local bought = {} -- auctionID -> true: bought this session, never offered again
local earned = { spent = 0, value = 0 } -- what was bought this session

local requested, timer, firstEvent, reading
local quick -- the running quick scan: { keys = seen item keys, items, pages, waiting }
local pendingSend -- a quick scan request waiting for the auction house's throttle
local selected -- the deal the next click acts on: { lookup state on it }
local panel, tab, scrollBox, statusText, totalText, boughtText
local scanButton, quickButton, eachBox, ticker
local statusMsg = "Quick or full scan, or let another addon's full scan arrive."

local function chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BargainBin|r: " .. msg)
end

local function money(copper)
    return GetMoneyString(math.floor(copper + 0.5), true)
end

-- The item's link (in its quality color), or a stand-in while it loads.
local function itemName(itemID)
    local _, link = C_Item.GetItemInfo(itemID)
    return link or ("item " .. itemID)
end

local function rules()
    return { each = db and db.each }
end

local function setColor(fs, c)
    if c then
        fs:SetTextColor(c[1], c[2], c[3])
    else
        fs:SetTextColor(1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- Window: status and redrawing
---------------------------------------------------------------------------
local function setStatus(text)
    statusMsg = text or ""
    if statusText then
        statusText:SetText(statusMsg)
    end
end

-- Seconds until the server takes another full scan request (0: now).
local function fullScanWait()
    local last = db and db.lastFullScan
    return last and math.max(0, SERVER_LIMIT - (time() - last)) or 0
end

local function updateButtons()
    if not panel then
        return
    end
    -- one scan at a time
    quickButton:SetEnabled(not (quick or reading))
    local wait = fullScanWait()
    if reading or requested then
        scanButton:SetText("Full ...")
        scanButton:Disable()
    elseif wait > 0 then
        scanButton:SetText(("%d:%02d"):format(math.floor(wait / 60), wait % 60))
        scanButton:Disable()
    else
        scanButton:SetText("Full")
        scanButton:SetEnabled(not quick)
    end
end

local tabCount = 0 -- deals shown, for the tab's label
local function updateTab(count)
    if not tab then
        return
    end
    count = count or tabCount
    tabCount = count
    tab:SetText(count and count > 0 and ("Bargains (%d)"):format(count) or "Bargains")
    PanelTemplates_TabResize(tab, 0)
    if panel:IsShown() then
        PanelTemplates_SelectTab(tab)
        tab:Enable() -- SelectTab disables it; a click must still hide the window
    else
        PanelTemplates_DeselectTab(tab)
    end
end

local function refresh()
    if not panel then
        return
    end
    local list = Logic.sorted(deals, rules())
    updateTab(#list)
    updateButtons()
    if not panel:IsShown() then
        return
    end
    scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
    local profit, estimates = 0, false
    for _, deal in ipairs(list) do
        profit = profit + deal.profit
        estimates = estimates or deal.estimate
    end
    totalText:SetText(
        (
            #list > 0
                and ("%d item(s), %s%s profit"):format(
                    #list,
                    estimates and "up to " or "",
                    money(profit)
                )
            or "No deals."
        ) .. (waitingCount > 0 and (" (%d prices loading)"):format(waitingCount) or "")
    )
    boughtText:SetText(
        earned.spent > 0
                and ("Bought for %s, sells for %s"):format(money(earned.spent), money(earned.value))
            or ""
    )
    statusText:SetText(statusMsg)
end

-- Many items arrive in a burst: redraw once for all of them.
local redrawPending = false
local function scheduleRefresh()
    if redrawPending then
        return
    end
    redrawPending = true
    C_Timer.After(0.5, function()
        redrawPending = false
        refresh()
    end)
end

---------------------------------------------------------------------------
-- Reading the dump
---------------------------------------------------------------------------
-- The item's vendor price per unit and whether it stacks, or nil while the client
-- loads the item.
local function priceOf(itemID)
    local price = prices[itemID]
    if price == nil then
        local _, _, _, _, _, _, _, stack, _, _, sell = C_Item.GetItemInfo(itemID)
        if sell then
            price = sell
            prices[itemID] = sell
            pooled[itemID] = (stack or 1) > 1
        end
    end
    return price, pooled[itemID]
end

-- Calls fn(price, pooled) now, or once the client has loaded the item.
local function whenPriced(itemID, fn)
    local price, stacks = priceOf(itemID)
    if price then
        fn(price, stacks)
        return
    end
    local queue = waiting[itemID]
    if not queue then
        queue = {}
        waiting[itemID] = queue
        waitingCount = waitingCount + 1
        C_Item.RequestLoadItemDataByID(itemID)
    end
    queue[#queue + 1] = fn
end

local function addAuction(itemID, count, buyout)
    whenPriced(itemID, function(price, stacks)
        Logic.add(deals, itemID, count, buyout, price, stacks)
    end)
end

local function priceArrived(itemID)
    local queue = waiting[itemID]
    if not queue then
        return
    end
    local price, stacks = priceOf(itemID)
    if not price then
        return
    end
    waiting[itemID] = nil
    waitingCount = waitingCount - 1
    for _, fn in ipairs(queue) do
        fn(price, stacks)
    end
    scheduleRefresh()
end

local function readBatch(scan)
    if reading ~= scan then
        return
    end
    local now = C_AuctionHouse.GetNumReplicateItems()
    if now < scan.count then
        reading = nil
        setStatus("The auction list changed while reading; scan again later.")
        refresh()
        return
    end
    scan.count = now -- a late batch arrived: read it too
    local last = math.min(scan.read + PER_FRAME, scan.count) - 1
    for i = scan.read, last do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
            C_AuctionHouse.GetReplicateItemInfo(i)
        if itemID and buyout and buyout > 0 then
            addAuction(itemID, count or 1, buyout)
        end
    end
    scan.read = last + 1
    if scan.read < scan.count then
        setStatus(("Reading the full scan: %d of %d"):format(scan.read, scan.count))
        C_Timer.After(0, function()
            readBatch(scan)
        end)
        return
    end
    reading = nil
    setStatus(("Read %d auctions."):format(scan.count))
    refresh()
end

local function startReading()
    timer, firstEvent, requested = nil, nil, false
    local count = C_AuctionHouse.GetNumReplicateItems()
    if count == 0 then
        setStatus("The full scan came back empty.")
        refresh()
        return
    end
    -- a new dump replaces what the last one found, and a quick scan
    quick, pendingSend = nil, nil
    wipe(deals)
    wipe(waiting)
    waitingCount = 0
    selected = nil
    reading = { count = count, read = 0 }
    refresh()
    readBatch(reading)
end

local function onReplicateUpdate()
    if not requested or reading then
        return -- not asked for, or the repeats of a dump already read
    end
    local now = GetTime()
    firstEvent = firstEvent or now
    if timer then
        timer:Cancel()
    end
    timer =
        C_Timer.NewTimer(math.max(0, math.min(QUIET, firstEvent + MAX_WAIT - now)), startReading)
end

-- After every ReplicateItems call, whoever makes it (RichPeopleBoatMoney does the
-- same). A call the server refuses (within 15 minutes) never sends update events.
hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
    if db then
        db.lastFullScan = time()
    end
    if reading or timer then
        updateButtons()
        return
    end
    local asked = GetTime()
    requested = asked
    setStatus("Waiting for the full scan (up to two minutes)...")
    updateButtons()
    C_Timer.After(NO_ANSWER, function()
        if requested == asked and not firstEvent then
            requested = false
            setStatus(
                "No full scan came. The server sends one every 15 minutes per account, "
                    .. "and ignores earlier requests."
            )
            updateButtons()
        end
    end)
end)

---------------------------------------------------------------------------
-- Quick scan (the browse search)
---------------------------------------------------------------------------
-- Sends fn's request once the auction house's throttle allows it.
local function send(fn)
    if C_AuctionHouse.IsThrottledMessageSystemReady() then
        pendingSend = nil
        fn()
    else
        pendingSend = fn -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY sends it
    end
end

local function quickDone(text)
    quick, pendingSend = nil, nil
    setStatus(text)
    refresh()
end

-- Gives up when the page asked for at `sentAt` never arrives.
local function watchPage(scan)
    local sentAt = GetTime()
    scan.sentAt = sentAt
    C_Timer.After(QUICK_TIMEOUT, function()
        if quick == scan and scan.waiting and scan.sentAt == sentAt then
            quickDone("The auction house stopped answering; the list may be incomplete.")
        end
    end)
end

-- A page of results. UPDATED (with everything so far) and ADDED (with the new page)
-- may both come for one page, so results are counted once per item key and the next
-- page is asked for once.
local function quickResults(results)
    local scan = quick
    if not scan then
        return
    end
    for _, r in ipairs(results) do
        local key = r.itemKey
        local id = ("%d:%d:%d:%d"):format(
            key.itemID,
            key.itemLevel or 0,
            key.itemSuffix or 0,
            key.battlePetSpeciesID or 0
        )
        if not scan.keys[id] and (key.battlePetSpeciesID or 0) == 0 then
            scan.keys[id] = true
            scan.items = scan.items + 1
            local itemID, minPrice, listed = key.itemID, r.minPrice, r.totalQuantity
            whenPriced(itemID, function(price, stacks)
                Logic.browse(deals, itemID, minPrice, listed, price, stacks, key)
            end)
        end
    end
    if not scan.waiting then
        return
    end
    scan.waiting = false
    if C_AuctionHouse.HasFullBrowseResults() then
        if scan.items == 0 then
            quickDone("The quick scan came back empty.")
            return
        end
        quickDone(
            ("Quick scan done: %d items checked, %d pages in %ds."):format(
                scan.items,
                scan.pages,
                GetTime() - scan.started
            )
        )
        return
    end
    setStatus(("Quick scan: %d items so far..."):format(scan.items))
    scheduleRefresh()
    send(function()
        if quick == scan then
            scan.waiting = true
            scan.pages = scan.pages + 1
            watchPage(scan)
            C_AuctionHouse.RequestMoreBrowseResults()
        end
    end)
end

local function quickScan()
    if reading or quick then
        return
    end
    Logic.dropEstimates(deals)
    if selected and selected.estimate then
        selected = nil
    end
    local scan = { keys = {}, items = 0, pages = 0, started = GetTime(), waiting = false }
    quick = scan
    setStatus("Quick scan: searching...")
    refresh()
    send(function()
        if quick == scan then
            scan.waiting = true
            scan.pages = scan.pages + 1
            watchPage(scan)
            C_AuctionHouse.SendBrowseQuery({
                searchString = "",
                sorts = {},
                filters = ALL_QUALITIES,
            })
        end
    end)
end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------
local function remove(deal)
    deals[deal.itemID] = nil
    if selected == deal then
        selected = nil
    end
    refresh()
end

local function sendLookup(deal)
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        deal.lookupDue = true -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY sends it
        return
    end
    deal.lookupDue, deal.lookupSent = false, GetTime()
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    local key = deal.itemKey or C_AuctionHouse.MakeItemKey(deal.itemID)
    C_AuctionHouse.SendSearchQuery(key, sorts, true)
    local sent = deal.lookupSent
    C_Timer.After(LOOKUP_TIMEOUT, function()
        if selected == deal and deal.lookupSent == sent then
            if deal.retried then
                deal.lookupSent = nil
                setStatus("No answer from the auction house; click to try again.")
            else
                deal.retried = true
                sendLookup(deal)
            end
        end
    end)
end

local function lookUp(deal)
    selected = deal
    deal.offers, deal.commodity, deal.confirm, deal.retried = nil, nil, nil, false
    setStatus("Checking the current auctions of " .. itemName(deal.itemID) .. "...")
    sendLookup(deal)
    refresh()
end

-- The lookup's answer for an ordinary item: the auctions that still pay.
local function itemResults(itemKey)
    local deal = selected
    if not (deal and deal.lookupSent and itemKey.itemID == deal.itemID) then
        return
    end
    local results = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if info then
            results[#results + 1] = info
        end
    end
    if #results == 0 and not C_AuctionHouse.HasFullItemSearchResults(itemKey) then
        return -- more is coming
    end
    deal.lookupSent = nil
    deal.offers = Logic.offers(results, prices[deal.itemID], bought, rules())
    deal.offerAt = GetTime()
    if #deal.offers == 0 then
        setStatus(itemName(deal.itemID) .. ": no auction worth a click any more.")
        remove(deal)
        return
    end
    Logic.fromOffers(deal, deal.offers)
    Logic.total(deal, rules())
    setStatus(
        ("%d auction(s), %s profit. Click to buy them one by one, best first."):format(
            #deal.offers,
            money(deal.profit)
        )
    )
    refresh()
end

-- The lookup's answer for a commodity: how many units cost less than a vendor pays.
local function commodityResults(itemID)
    local deal = selected
    if not (deal and deal.lookupSent and itemID == deal.itemID) then
        return
    end
    local results = {}
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if info then
            results[#results + 1] = info
        end
    end
    deal.lookupSent = nil
    local units, cost = Logic.commodityUnits(results, prices[itemID], rules())
    if units == 0 then
        setStatus(itemName(itemID) .. " isn't listed under vendor price any more.")
        remove(deal)
        return
    end
    Logic.fromCommodity(deal, units, cost)
    Logic.total(deal, rules())
    if deal.profit < Logic.MIN_PROFIT then
        setStatus(
            ("%s: only %d under vendor price now, %s profit."):format(
                itemName(itemID),
                units,
                money(deal.profit)
            )
        )
        remove(deal)
        return
    end
    deal.commodity, deal.offerAt = { units = units, cost = cost }, GetTime()
    setStatus(
        ("%d for %s (sells for %s). Click to start the purchase."):format(
            units,
            money(cost),
            money(units * prices[itemID])
        )
    )
    refresh()
end

local function recordBuy(cost, value)
    earned.spent, earned.value = earned.spent + cost, earned.value + value
end

local function buyItem(deal)
    local offer = deal.offers[1]
    if GetMoney() < offer.buyout then
        setStatus("Not enough gold for the next one (" .. money(offer.buyout) .. ").")
        return
    end
    table.remove(deal.offers, 1) -- also the deal's lot (Logic.fromOffers)
    C_AuctionHouse.PlaceBid(offer.auctionID, offer.buyout)
    bought[offer.auctionID] = true
    recordBuy(offer.buyout, offer.buyout + offer.profit)
    if #deal.offers == 0 then
        setStatus(("Bought the last one for %s."):format(money(offer.buyout)))
        remove(deal)
        return
    end
    setStatus(
        ("Bought %d for %s; %d more, click again."):format(
            offer.quantity,
            money(offer.buyout),
            #deal.offers
        )
    )
    refresh()
end

-- First click: ask the game for the price of that many units; second: confirm it.
local function buyCommodity(deal)
    local c = deal.commodity
    if deal.confirm then
        C_AuctionHouse.ConfirmCommoditiesPurchase(deal.itemID, c.units)
        recordBuy(deal.confirm, c.units * prices[deal.itemID])
        setStatus(("Bought %d for %s."):format(c.units, money(deal.confirm)))
        remove(deal)
        return
    end
    if GetMoney() < c.cost then
        setStatus("Not enough gold (" .. money(c.cost) .. ").")
        return
    end
    deal.starting = true
    C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, c.units)
    setStatus("Asking for the final price...")
end

local function commodityPrice(_, total)
    local deal = selected
    if not (deal and deal.starting) then
        return
    end
    deal.starting = false
    local value = deal.commodity.units * prices[deal.itemID]
    if total >= value then
        C_AuctionHouse.CancelCommoditiesPurchase()
        setStatus("The price went up to " .. money(total) .. "; not worth it any more.")
        remove(deal)
        return
    end
    deal.confirm = total
    setStatus(
        ("Total %s, sells for %s. Click again to confirm."):format(money(total), money(value))
    )
end

local function onRowClick(row)
    local deal = row.deal
    if not deal or reading or quick then
        return
    end
    if IsModifiedClick() then
        local _, link = C_Item.GetItemInfo(deal.itemID)
        if link and HandleModifiedItemClick(link) then
            return
        end
    end
    local fresh = selected == deal and deal.offerAt and GetTime() - deal.offerAt < OFFER_TTL
    if fresh and deal.offers and #deal.offers > 0 then
        buyItem(deal)
    elseif fresh and deal.commodity then
        buyCommodity(deal)
    elseif not (selected == deal and deal.lookupSent) then
        lookUp(deal)
    end
end

---------------------------------------------------------------------------
-- Window: rows
---------------------------------------------------------------------------
local function showTooltip(row)
    local deal = row.deal
    if not deal then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(deal.itemID)
    GameTooltip:AddLine(" ")
    if deal.estimate then
        GameTooltip:AddDoubleLine("Cheapest", money(deal.minPrice), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Vendor pays", money(deal.sellPrice), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine(
            deal.pooled
                    and "From the quick scan: as if every listed unit cost the cheapest price, so the most it could earn."
                or "From the quick scan: what the cheapest one earns.",
            0.7,
            0.7,
            0.7,
            true
        )
        GameTooltip:AddLine("Click: check how many pay, then click again to buy.", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddDoubleLine("Auctions", deal.auctions, 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine("Click: look up, then click again to buy.", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

local function createCells(row)
    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.15)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 4, 0)
    row.cells = {}
    local x = 0
    for i, c in ipairs(COLUMNS) do
        local fs = row:CreateFontString(
            nil,
            "ARTWORK",
            i == 1 and "GameFontHighlight" or "GameFontHighlightSmall"
        )
        fs:SetWordWrap(false)
        if i == 1 then
            fs:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            fs:SetWidth(c.width - 28)
            fs:SetJustifyH("LEFT")
        else
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(c.width - 6)
            fs:SetJustifyH("RIGHT")
        end
        row.cells[i] = fs
        x = x + c.width
    end
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", onRowClick)
    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

local function initRow(row, deal)
    if not row.cells then
        createCells(row)
    end
    row.deal = deal
    local c = row.cells
    row.icon:SetTexture(C_Item.GetItemIconByID(deal.itemID))
    row.selected:SetShown(selected == deal)
    c[1]:SetText(itemName(deal.itemID))
    c[2]:SetText(deal.units)
    c[3]:SetText(money(deal.cost))
    c[4]:SetText(money(deal.value))
    -- estimates: "~" and grey until a click checks them
    c[5]:SetText((deal.estimate and "~" or "") .. money(deal.profit))
    setColor(c[5], deal.estimate and GREY or GREEN)
    c[6]:SetText(money(deal.units > 0 and deal.profit / deal.units or 0))
    setColor(c[6], deal.estimate and GREY or nil)
end

---------------------------------------------------------------------------
-- Window: building it
---------------------------------------------------------------------------
local function createHeaders(parent)
    local x = 0
    for _, c in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, parent, "ColumnDisplayButtonShortTemplate")
        h:SetSize(c.width, 19)
        h:SetPoint("TOPLEFT", x, 0)
        h:SetText(c.label)
        h:EnableMouse(false) -- always sorted by profit
        x = x + c.width
    end
end

local function tooltipFor(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function createPanel()
    panel = CreateFrame("Frame", "BargainBinPanel", AuctionHouseFrame, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(panel)
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 0, 0)
    panel:EnableMouse(true)
    ---@diagnostic disable-next-line: param-type-mismatch
    panel:SetTitle("BargainBin: under vendor price")
    panel.Inset:Hide()
    panel.CloseButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    -- the item column takes what the others leave
    local used = 0
    for i = 2, #COLUMNS do
        used = used + COLUMNS[i].width
    end
    COLUMNS[1].width = WIDTH - 16 - 26 - used

    quickButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    quickButton:SetSize(90, 22)
    quickButton:SetPoint("TOPLEFT", 12, -30)
    quickButton:SetText("Quick")
    quickButton:SetScript("OnClick", quickScan)
    tooltipFor(
        quickButton,
        "Quick scan",
        "Every item's cheapest price, not every auction. Repeat it any time to catch new listings."
    )

    scanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanButton:SetSize(90, 22)
    scanButton:SetPoint("LEFT", quickButton, "RIGHT", 6, 0)
    scanButton:SetScript("OnClick", function()
        C_AuctionHouse.ReplicateItems()
    end)
    scanButton:SetMotionScriptsWhileDisabled(true) -- the tooltip explains the countdown
    tooltipFor(
        scanButton,
        "Full scan",
        "Every auction. The server sends one every 15 minutes per account and ignores "
            .. "earlier requests, so this counts down from the last one (any addon's)."
    )

    eachBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    eachBox:SetSize(24, 24)
    eachBox:SetPoint("LEFT", scanButton, "RIGHT", 10, 0)
    eachBox.text = eachBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    eachBox.text:SetPoint("LEFT", eachBox, "RIGHT", 0, 0)
    eachBox.text:SetText("At least 1s each")
    eachBox:SetScript("OnClick", function(self)
        db.each = self:GetChecked() and true or false
        if selected then
            selected.offerAt = nil -- its lookup was under the other rule: look up again
        end
        refresh()
    end)
    tooltipFor(
        eachBox,
        "At least 1s each",
        "Only auctions where every single item earns at least 1s over what it costs "
            .. "(per item, not per stack)."
    )

    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", 8, -62)
    list:SetPoint("BOTTOMRIGHT", -8, 52)
    local bg = list:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("auctionhouse-background-index")
    bg:SetPoint("TOPLEFT", 3, -22)
    bg:SetPoint("BOTTOMRIGHT", -22, 3)
    local border = CreateFrame("Frame", nil, list, "NineSlicePanelTemplate")
    border:SetPoint("TOPLEFT", 0, -19)
    border:SetPoint("BOTTOMRIGHT")
    NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")

    local headerRow = CreateFrame("Frame", nil, list)
    headerRow:SetPoint("TOPLEFT", 4, -1)
    headerRow:SetPoint("TOPRIGHT", -26, -1)
    headerRow:SetHeight(19)
    createHeaders(headerRow)

    scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -6)
    scrollBox:SetPoint("RIGHT", headerRow, "RIGHT")
    scrollBox:SetPoint("BOTTOM", 0, 3)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 9, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 9, 4)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 14, 30)
    statusText:SetPoint("BOTTOMRIGHT", -14, 30)
    statusText:SetJustifyH("LEFT")
    totalText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    totalText:SetPoint("BOTTOMLEFT", 14, 10)
    totalText:SetJustifyH("LEFT")
    boughtText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    boughtText:SetPoint("BOTTOMRIGHT", -14, 10)
    boughtText:SetJustifyH("RIGHT")

    panel:SetScript("OnShow", function()
        -- DustToDust's window sits in the same place
        local other = _G["DustToDustPanel"]
        if other and other:IsShown() then
            other:Hide()
        end
        ticker = C_Timer.NewTicker(1, updateButtons) -- the Full button's countdown
        refresh()
    end)
    panel:SetScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        updateTab()
    end)

    -- PanelTabButtonTemplate adds the button to its parent's Tabs; a holder keeps it out
    -- of the auction house's own tabs (DustToDust does the same).
    local holder = CreateFrame("Frame", nil, AuctionHouseFrame)
    holder:SetAllPoints()
    tab = CreateFrame("Button", "BargainBinTab", holder, "PanelTabButtonTemplate")
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        panel:SetShown(not panel:IsShown())
    end)
end

-- Bottom right under the auction house, left of DustToDust's tab (or DisenchantValue's)
-- when there is one; those place theirs when the auction house opens, so this runs again
-- a moment later.
local function placeTab()
    local other = _G["DustToDustTab"] or _G["DisenchantValueAuctionTab"]
    tab:ClearAllPoints()
    if other then
        tab:SetPoint("RIGHT", other, "LEFT", -2, 0)
    else
        tab:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, 2)
    end
end

-- The auction house UI loads on demand, when AUCTION_HOUSE_SHOW first arrives; if
-- this addon hears the event before it's loaded, try again on the next frame.
local function onAuctionHouseShow(retried)
    if not panel and AuctionHouseFrame then
        createPanel()
    end
    if not panel then
        if not retried then
            C_Timer.After(0, function()
                onAuctionHouseShow(true)
            end)
        end
        return
    end
    eachBox:SetChecked(db.each)
    panel:Hide() -- starts closed every visit; the Bargains tab opens it
    refresh()
    placeTab()
    C_Timer.After(0.3, placeTab)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
f:RegisterEvent("COMMODITY_PRICE_UPDATED")
f:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")
f:SetScript("OnEvent", function(_, event, a, b)
    if event == "ADDON_LOADED" then
        if a == addonName then
            BargainBinDB = BargainBinDB or {}
            db = BargainBinDB
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        onAuctionHouseShow()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if timer then
            timer:Cancel()
        end
        timer, firstEvent, requested, reading = nil, nil, false, nil
        quick, pendingSend = nil, nil
        if selected then
            selected.lookupSent, selected.offerAt, selected.starting = nil, nil, false
            selected = nil
        end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        onReplicateUpdate()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if waiting[a] then
            priceArrived(a)
        elseif deals[a] then
            scheduleRefresh() -- its name and link arrived: "item 4247" becomes a link
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        itemResults(a)
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        commodityResults(a)
    elseif event == "COMMODITY_PRICE_UPDATED" then
        commodityPrice(a, b)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if pendingSend then
            send(pendingSend)
        elseif selected and selected.lookupDue then
            sendLookup(selected)
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        if quick then
            quickResults(C_AuctionHouse.GetBrowseResults())
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        quickResults(a)
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        if quick then
            quickDone("The auction house search failed. Try again.")
        end
    end
end)

SLASH_BARGAINBIN1 = "/bargainbin"
SlashCmdList.BARGAINBIN = function()
    if panel and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        panel:SetShown(not panel:IsShown())
    else
        chat(
            ("%d item(s) under vendor price from the last scan. Open the auction house to see them."):format(
                #Logic.sorted(deals, rules())
            )
        )
    end
end
