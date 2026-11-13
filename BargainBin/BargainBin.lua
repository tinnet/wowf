-- BargainBin: finds auctions you can buy for less than a vendor pays for them.
--
-- Reads every full auction house dump (C_AuctionHouse.ReplicateItems: the Scan button
-- here, /rpbm scan, or Auctionator's slower scan mode), compares each auction's buyout
-- with the item's vendor price times the stack size, and lists the items that pay in a
-- panel next to the auction house, best profit first.
--
-- Buying: the dump has no auction IDs, and the game only buys from a click. So the
-- first click on an item looks up its current auctions; every further click buys one
-- auction that still pays (best first). Each lookup is trusted for a minute. Stackable
-- items that the auction house sells as commodities (pooled units, not stacks) take a
-- click to start the purchase and one to confirm once the game names the total.
--
-- The dump can only be asked for once every 15 minutes (the game's limit, account-wide).
-- Vendor prices are the client's (C_Item.GetItemInfo); an item the client hasn't loaded
-- yet is asked for and counted once it arrives.
local _, ns = ...
local Logic = ns.Logic

local PER_FRAME = 2000 -- dump rows read per frame
local QUIET = 3 -- read once no update event has come for this many seconds...
local MAX_WAIT = 30 -- ...or this long after the first one
local OFFER_TTL = 60 -- seconds a lookup is trusted for buying
local LOOKUP_TIMEOUT = 5 -- seconds before an unanswered search is sent again (once)
local ROWS = 14

local deals = {} -- itemID -> deal (Logic.add)
local list = {} -- Logic.sorted(deals), what the panel shows
local prices = {} -- itemID -> vendor price per unit (0: none)
local waiting = {} -- itemID -> { {count, buyout}, ... } auctions waiting for the price
local waitingCount = 0
local bought = {} -- auctionID -> true: bought this session, never offered again
local earned = { spent = 0, value = 0 } -- what was bought this session

local requested, timer, firstEvent, reading
local selected -- the deal the next click acts on: { lookup state on it }
local panel, statusText, totalText, scanButton
local rows = {}
local offset = 0

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

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function setStatus(text)
    if statusText then
        statusText:SetText(text or "")
    end
end

local function refresh()
    if not panel then
        return
    end
    list = Logic.sorted(deals)
    offset = math.max(0, math.min(offset, #list - ROWS))
    local profit = 0
    for _, deal in ipairs(list) do
        profit = profit + deal.profit
    end
    totalText:SetText(
        (#list > 0 and ("%d item(s), %s profit"):format(#list, money(profit)) or "No deals.")
            .. (waitingCount > 0 and (" (%d prices loading)"):format(waitingCount) or "")
            .. (
                earned.spent > 0
                    and ("\nBought for %s, sells for %s."):format(
                        money(earned.spent),
                        money(earned.value)
                    )
                or ""
            )
    )
    for i, row in ipairs(rows) do
        local deal = list[i + offset]
        row.deal = deal
        if deal then
            row.icon:SetTexture(C_Item.GetItemIconByID(deal.itemID))
            row.name:SetText(itemName(deal.itemID))
            row.count:SetText(
                ("%d in %d, %s each"):format(
                    deal.units,
                    deal.auctions,
                    money(deal.profit / deal.auctions)
                )
            )
            row.profit:SetText(money(deal.profit))
            row.selected:SetShown(selected == deal)
            row:Show()
        else
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Reading the dump
---------------------------------------------------------------------------
-- The item's vendor price per unit, or nil while the client loads the item.
local function priceOf(itemID)
    local price = prices[itemID]
    if price == nil then
        local sell = select(11, C_Item.GetItemInfo(itemID))
        if sell then
            price = sell
            prices[itemID] = sell
        end
    end
    return price
end

local function addAuction(itemID, count, buyout)
    local price = priceOf(itemID)
    if price then
        Logic.add(deals, itemID, count, buyout, price)
        return
    end
    local queue = waiting[itemID]
    if not queue then
        queue = {}
        waiting[itemID] = queue
        waitingCount = waitingCount + 1
        C_Item.RequestLoadItemDataByID(itemID)
    end
    queue[#queue + 1] = { count, buyout }
end

-- Many items arrive in a burst: redraw once for all of them.
local function scheduleRefresh()
    if not panel or panel.redrawPending then
        return
    end
    panel.redrawPending = true
    C_Timer.After(0.5, function()
        panel.redrawPending = false
        refresh()
    end)
end

local function priceArrived(itemID)
    local queue = waiting[itemID]
    local price = queue and priceOf(itemID)
    if not price then
        return
    end
    waiting[itemID] = nil
    waitingCount = waitingCount - 1
    for _, auction in ipairs(queue) do
        Logic.add(deals, itemID, auction[1], auction[2], price)
    end
    scheduleRefresh()
end

local function readBatch(scan)
    if reading ~= scan then
        return
    end
    if C_AuctionHouse.GetNumReplicateItems() ~= scan.count then
        reading = nil
        setStatus("The auction list changed while reading; scan again later.")
        return
    end
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
        setStatus(("Reading the scan: %d of %d"):format(scan.read, scan.count))
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
        setStatus("The scan came back empty.")
        return
    end
    -- a new dump replaces what the last one found
    wipe(deals)
    wipe(waiting)
    waitingCount = 0
    selected = nil
    reading = { count = count, read = 0 }
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
    if not reading and not timer then
        requested = true
        setStatus("Waiting for the scan (up to a minute)...")
    end
end)

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
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(deal.itemID), sorts, true)
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
    deal.offers = Logic.offers(results, prices[deal.itemID], bought)
    deal.offerAt = GetTime()
    if #deal.offers == 0 then
        setStatus(itemName(deal.itemID) .. " isn't listed under vendor price any more.")
        remove(deal)
        return
    end
    local profit = 0
    for _, offer in ipairs(deal.offers) do
        profit = profit + offer.profit
    end
    setStatus(
        ("%d auction(s), %s profit. Click to buy them one by one, best first."):format(
            #deal.offers,
            money(profit)
        )
    )
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
    local units, cost = Logic.commodityUnits(results, prices[itemID])
    if units == 0 then
        setStatus(itemName(itemID) .. " isn't listed under vendor price any more.")
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
end

local function recordBuy(cost, value)
    earned.spent, earned.value = earned.spent + cost, earned.value + value
end

local function buyItem(deal)
    local offer = table.remove(deal.offers, 1)
    if GetMoney() < offer.buyout then
        table.insert(deal.offers, 1, offer)
        setStatus("Not enough gold for the next one (" .. money(offer.buyout) .. ").")
        return
    end
    C_AuctionHouse.PlaceBid(offer.auctionID, offer.buyout)
    bought[offer.auctionID] = true
    recordBuy(offer.buyout, offer.buyout + offer.profit)
    deal.auctions, deal.units = deal.auctions - 1, deal.units - offer.quantity
    deal.cost, deal.profit = deal.cost - offer.buyout, deal.profit - offer.profit
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
    if not deal or reading then
        return
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
-- Panel layout
---------------------------------------------------------------------------
local function createRow(i)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(280, 24)
    row:SetPoint("TOPLEFT", 10, -78 - (i - 1) * 26)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.15)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0)
    row.name:SetPoint("RIGHT", -80, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 4, 0)
    row.profit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.profit:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnClick", onRowClick)
    row:SetScript("OnEnter", function(self)
        if self.deal then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.deal.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Buyout total", money(self.deal.cost), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Vendor pays", money(self.deal.value), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddLine("Click: look up, then click again to buy.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return row
end

local function createPanel()
    panel =
        CreateFrame("Frame", "BargainBinPanel", AuctionHouseFrame, "BasicFrameTemplateWithInset")
    panel:SetSize(300, 78 + ROWS * 26 + 10)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
    panel.TitleText:SetText("BargainBin: under vendor price")

    scanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanButton:SetSize(70, 22)
    scanButton:SetPoint("TOPRIGHT", -10, -28)
    scanButton:SetText("Scan")
    scanButton:SetScript("OnClick", function()
        C_AuctionHouse.ReplicateItems()
    end)
    scanButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Full scan of the auction house")
        GameTooltip:AddLine(
            "Once per 15 minutes (the game's limit). Other addons' full scans count too.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    scanButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    totalText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalText:SetPoint("TOPLEFT", 12, -28)
    totalText:SetPoint("RIGHT", scanButton, "LEFT", -6, 0)
    totalText:SetJustifyH("LEFT")
    statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", 12, -54)
    statusText:SetPoint("RIGHT", -12, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Scan, or let another addon's full scan arrive.")

    for i = 1, ROWS do
        rows[i] = createRow(i)
    end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        refresh()
    end)
    refresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- The auction house UI loads on demand, when AUCTION_HOUSE_SHOW first arrives; if
-- this addon hears the event before it's loaded, try again on the next frame.
local function showPanel(retried)
    if not panel and AuctionHouseFrame then
        createPanel()
    end
    if panel then
        panel:Show()
        refresh()
    elseif not retried then
        C_Timer.After(0, function()
            showPanel(true)
        end)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
f:RegisterEvent("COMMODITY_PRICE_UPDATED")
f:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
f:SetScript("OnEvent", function(_, event, a, b)
    if event == "AUCTION_HOUSE_SHOW" then
        showPanel()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if timer then
            timer:Cancel()
        end
        timer, firstEvent, requested, reading = nil, nil, false, nil
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
        if selected and selected.lookupDue then
            sendLookup(selected)
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
                #Logic.sorted(deals)
            )
        )
    end
end
