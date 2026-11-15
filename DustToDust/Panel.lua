-- The panel next to the auction house: Scan, filters, the sortable list, and quick buy.
--
-- Quick buy: a click buys the cheapest auction of the row's item at once, with no prompt,
-- but only at the price the row shows. The game only buys inside a click, so the cheapest
-- auction is looked up beforehand: when the mouse rests on a row, and after each buy (to
-- show the next one). A click with no fresh lookup only starts one. When a lookup finds a
-- higher price than the row had, the row turns orange and the next click only accepts the
-- new price.
local _, ns = ...
local Data, Logic, AH, Scan, Prices = ns.Data, ns.Logic, ns.AH, ns.Scan, ns.Prices
local Panel = {}
ns.Panel = Panel

local WIDTH = 720
local ROW_HEIGHT = 20
local OFFER_TTL = 60 -- seconds a looked-up auction is trusted for a buy
local LOOKUP = "lookup" -- AH request tag
local GREEN, RED, ORANGE, GREY = { 0.1, 1, 0.1 }, { 1, 0.3, 0.3 }, { 1, 0.5, 0 }, { 0.6, 0.6, 0.6 }

local COLUMNS = {
    { key = "name", label = "Item", width = 0 }, -- takes what the others leave
    { key = "ilvl", label = "iLvl", width = 40 },
    { key = "qty", label = "Qty", width = 40 },
    { key = "buyout", label = "Price", width = 110 },
    { key = "value", label = "DE value", width = 110 },
    { key = "profit", label = "Profit", width = 110 },
    { key = "loss", label = "Loss", width = 50 },
    { key = "skill", label = "Skill", width = 44 },
}

local panel, tab, scrollBox, statusText, pricesText, totalsText, scanButton
local bracketButtons = {}
---@type table
local onlyDeals
---@type table
local onlySkill
local sortKey, sortDesc = "profit", true
local statusMsg = "Press Scan to search for weapons and armor to disenchant."
local skill -- your Enchanting, read when the auction house opens
local hovered -- the row frame under the mouse
local bought = {} -- auctionID -> true
local session = { count = 0, spent = 0, value = 0 }

local function itemName(r)
    return r.name or ("item " .. r.itemID)
end

---------------------------------------------------------------------------
-- Status and redrawing
---------------------------------------------------------------------------
function Panel.status(text)
    if text then
        statusMsg = text
    end
    if not panel then
        return
    end
    statusText:SetText(statusMsg)
    pricesText:SetText(Prices.summary())
    totalsText:SetText(
        session.count > 0
                and ("Bought %d for %s, worth %s disenchanted"):format(
                    session.count,
                    ns.money(session.spent),
                    ns.money(session.value)
                )
            or ""
    )
    scanButton:SetText(Scan.running and "Stop" or "Scan")
end

function Panel.refresh()
    if not (panel and panel:IsShown()) then
        return
    end
    local db = ns.db
    local view = Logic.view(Scan.results, {
        onlyDeals = db.onlyDeals,
        opts = ns.opts(),
        skill = db.onlySkill and skill or nil,
        brackets = db.brackets,
    }, sortKey, sortDesc)
    scrollBox:SetDataProvider(CreateDataProvider(view), ScrollBoxConstants.RetainScrollPosition)
    for _, c in ipairs(COLUMNS) do
        local arrow = c.header.Arrow
        arrow:SetShown(c.key == sortKey)
        -- the atlas points down; flipped for ascending
        arrow:SetTexCoord(0, 1, sortDesc and 0 or 1, sortDesc and 1 or 0)
    end
    Panel.status()
end

local dirtyPending = false
-- Many changes in a row (scan pages): redraw at most once a second.
function Panel.dirty()
    if dirtyPending then
        return
    end
    dirtyPending = true
    C_Timer.After(1, function()
        dirtyPending = false
        Panel.refresh()
        if Scan.running then
            Panel.status(("Scanning... %d items so far"):format(#Scan.results))
        end
    end)
end

---------------------------------------------------------------------------
-- Quick buy
---------------------------------------------------------------------------
local function sameKey(a, b)
    return a.itemID == b.itemID and a.itemLevel == b.itemLevel and a.itemSuffix == b.itemSuffix
end

local function fresh(r)
    local o = r.offer
    return o and GetTime() - o.at < OFFER_TTL and o.price == r.buyout
end

local showTooltip -- defined with the rows

local function refreshTooltip(r)
    if hovered and hovered.r == r and hovered:IsMouseOver() then
        showTooltip(hovered)
    end
end

-- The search answer: the cheapest auction we haven't bought and isn't ours becomes the offer.
local function offerFrom(r)
    local key = r.itemKey
    local n = C_AuctionHouse.GetNumItemSearchResults(key)
    if n == 0 and not C_AuctionHouse.HasFullItemSearchResults(key) then
        return false -- more is coming
    end
    r.checking = false
    local best
    for i = 1, n do
        local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
        if
            info
            and info.buyoutAmount
            and info.buyoutAmount > 0
            and not info.containsOwnerItem
            and not bought[info.auctionID]
            and (not best or info.buyoutAmount < best.buyoutAmount)
        then
            best = info
        end
    end
    if not best then
        Scan.remove(r)
        Panel.status(itemName(r) .. " isn't listed any more.")
        Panel.refresh()
        return true
    end
    local old = r.buyout
    r.offer = { auctionID = best.auctionID, price = best.buyoutAmount, at = GetTime() }
    r.buyout = best.buyoutAmount
    Scan.repriceOne(r)
    if old and r.buyout > old then
        r.priceUp = old
        Panel.status(
            ("|cffff8000Price went up:|r %s now costs %s (was %s). Click it to accept the new price."):format(
                itemName(r),
                ns.money(r.buyout),
                ns.money(old)
            )
        )
    else
        Panel.status(("%s: click to buy for %s."):format(itemName(r), ns.money(r.buyout)))
    end
    Panel.refresh()
    refreshTooltip(r)
    return true
end

local function lookUp(r)
    AH.cancel(LOOKUP) -- one lookup at a time: the latest wins
    r.checking = true
    AH.add({
        tag = LOOKUP,
        timeout = 5,
        ready = function()
            return C_AuctionHouse.GetItemKeyInfo(r.itemKey) ~= nil -- searches for unknown keys are ignored
        end,
        send = function()
            C_AuctionHouse.SendSearchQuery(
                r.itemKey,
                { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } },
                true
            )
        end,
        handles = {
            ITEM_SEARCH_RESULTS_UPDATED = function(key)
                return sameKey(key, r.itemKey) and offerFrom(r)
            end,
        },
        onTimeout = function()
            r.checking = false
            Panel.status("No answer about " .. itemName(r) .. "; click it to try again.")
        end,
    }, true)
end

local function quickBuy(r)
    if r.priceUp then
        r.priceUp = nil
        Panel.status(
            ("Price accepted: click %s again to buy for %s."):format(
                itemName(r),
                ns.money(r.buyout)
            )
        )
        Panel.refresh()
        return
    end
    if not fresh(r) then
        Panel.status("Checking the current price of " .. itemName(r) .. "...")
        lookUp(r)
        return
    end
    local offer = r.offer
    if GetMoney() < offer.price then
        Panel.status("Not enough gold for " .. itemName(r) .. ".")
        return
    end
    C_AuctionHouse.PlaceBid(offer.auctionID, offer.price)
    bought[offer.auctionID] = true
    r.offer = nil
    session.count = session.count + 1
    session.spent = session.spent + offer.price
    session.value = session.value + (r.value or 0)
    Panel.status(("Bought %s for %s."):format(itemName(r), ns.money(offer.price)))
    lookUp(r) -- the next cheapest, so the next click never buys at a price the list didn't show
end

-- Right-click: the auction house's own buy view for the item.
local function openInAuctionHouse(r)
    Scan.stop()
    Prices.stop()
    AH.cancel(LOOKUP)
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        Panel.status("The auction house is busy; right-click again in a moment.")
        return
    end
    local f = AuctionHouseFrame
    local alreadyOpen = f.ItemBuyFrame and f.ItemBuyFrame:IsShown()
    f:SelectBrowseResult(r.browse)
    -- already open, the view would keep the previous item's auctions
    if alreadyOpen then
        f:RefreshSearchResults(AuctionHouseSearchContext.BuyItems, r.itemKey)
    end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function setColor(fs, c)
    if c then
        fs:SetTextColor(c[1], c[2], c[3])
    else
        fs:SetTextColor(1, 1, 1)
    end
end

-- The outcomes grouped per material: { mat, chance, min, max }.
local function groups(outcomes)
    local out, byMat = {}, {}
    for _, o in ipairs(outcomes) do
        local g = byMat[o.mat]
        if not g then
            g = { mat = o.mat, chance = 0, min = o.qty, max = o.qty }
            byMat[o.mat] = g
            out[#out + 1] = g
        end
        g.chance = g.chance + o.p
        g.min, g.max = math.min(g.min, o.qty), math.max(g.max, o.qty)
    end
    return out
end

showTooltip = function(row)
    local r = row.r
    if not r then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local k = r.itemKey
    GameTooltip:SetItemKey(k.itemID, k.itemLevel, k.itemSuffix)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Disenchants into (worth to you each):")
    local nets = ns.netPrices()
    for _, g in ipairs(groups(r.outcomes)) do
        local p = ns.matPrice(g.mat)
        local qty = g.min == g.max and tostring(g.min) or (g.min .. "-" .. g.max)
        local right = ns.money(nets[g.mat])
        if p then
            right = right .. (" (%s%s)"):format(p.source, p.age and (", " .. ns.age(p.age)) or "")
        end
        local c = (not p or p.stale) and GREY or { 1, 1, 1 }
        GameTooltip:AddDoubleLine(
            ("%s%% %s %s"):format(math.floor(g.chance * 1000 + 0.5) / 10, qty, ns.matName(g.mat)),
            right,
            1,
            1,
            1,
            c[1],
            c[2],
            c[3]
        )
    end
    if r.loss then
        GameTooltip:AddLine(
            ("Chance of getting less than you pay: %d%%"):format(math.floor(r.loss * 100 + 0.5)),
            1,
            1,
            1
        )
    end
    if skill and r.skill > skill then
        GameTooltip:AddLine(
            ("Needs Enchanting %d (you have %d)."):format(r.skill, skill),
            RED[1],
            RED[2],
            RED[3]
        )
    elseif not skill then
        GameTooltip:AddLine(("Needs Enchanting %d."):format(r.skill), GREY[1], GREY[2], GREY[3])
    end
    GameTooltip:AddLine(" ")
    if r.priceUp then
        GameTooltip:AddLine("Click to accept the new price.", ORANGE[1], ORANGE[2], ORANGE[3])
    elseif fresh(r) then
        GameTooltip:AddLine(
            "Click to buy the cheapest for " .. ns.money(r.buyout) .. ".",
            GREEN[1],
            GREEN[2],
            GREEN[3]
        )
    else
        GameTooltip:AddLine("Checking the current price...", GREY[1], GREY[2], GREY[3])
    end
    GameTooltip:AddLine(
        "Right-click: open it in the auction house. Shift-click: link it.",
        GREY[1],
        GREY[2],
        GREY[3]
    )
    GameTooltip:Show()
end

local function createCells(row)
    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")
    row.warn = row:CreateTexture(nil, "BACKGROUND")
    row.warn:SetAllPoints()
    row.warn:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.18)
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
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self)
        hovered = self
        showTooltip(self)
        local r = self.r
        if r and not fresh(r) and not r.checking and not r.priceUp then
            C_Timer.After(0.2, function()
                if hovered == self and self.r == r and self:IsMouseOver() then
                    lookUp(r)
                end
            end)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if hovered == self then
            hovered = nil
        end
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        local r = self.r
        if not r then
            return
        end
        if IsModifiedClick() then
            local _, link = C_Item.GetItemInfo(r.itemID)
            if link and HandleModifiedItemClick(link) then
                return
            end
        end
        if button == "RightButton" then
            openInAuctionHouse(r)
        else
            quickBuy(r)
        end
    end)
end

local function initRow(row, r)
    if not row.cells then
        createCells(row)
    end
    row.r = r
    local c = row.cells
    row.icon:SetTexture(r.icon)
    local info = C_AuctionHouse.GetItemKeyInfo(r.itemKey) -- nil until loaded: ns.onItemKeyInfo redraws
    if info then
        r.name = info.itemName
        c[1]:SetText(AuctionHouseUtil.GetItemDisplayTextFromItemKey(r.itemKey, info, true))
    else
        c[1]:SetText("...")
    end
    c[2]:SetText(r.ilvl)
    c[3]:SetText(r.qty)
    c[4]:SetText(ns.money(r.buyout))
    setColor(c[4], r.priceUp and ORANGE)
    row.warn:SetShown(r.priceUp ~= nil)
    c[5]:SetText(r.value and ns.money(r.value) or "?")
    c[6]:SetText(r.profit and ns.money(r.profit) or "")
    setColor(c[6], r.profit and (r.profit > 0 and GREEN or RED))
    c[7]:SetText(r.loss and ("%d%%"):format(math.floor(r.loss * 100 + 0.5)) or "")
    setColor(c[7], r.loss and r.loss > ns.db.maxLoss / 100 and RED)
    if not skill then
        c[8]:SetText(r.skill)
        setColor(c[8], GREY)
    elseif r.skill > skill then
        c[8]:SetText(r.skill)
        setColor(c[8], RED)
    else
        c[8]:SetText("")
    end
end

-- An item key's name arrived: redraw the rows on screen that show it.
function ns.onItemKeyInfo(itemID)
    if scrollBox and panel:IsShown() then
        scrollBox:ForEachFrame(function(row)
            if row.r and row.r.itemID == itemID then
                initRow(row, row.r)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Building the panel
---------------------------------------------------------------------------
local function checkbox(label, key, anchor)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
    cb.text = cb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    cb.text:SetText(label)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        Panel.refresh()
    end)
    return cb
end

local function paintBrackets()
    local any = next(ns.db.brackets) ~= nil
    for _, b in ipairs(bracketButtons) do
        if (b.band and ns.db.brackets[b.band]) or (not b.band and not any) then
            b:LockHighlight()
        else
            b:UnlockHighlight()
        end
    end
end

local function createBrackets(anchor)
    local n = #Data.UNCOMMON + 1
    local width = math.floor((WIDTH - 24 - 2 * (n - 1)) / n)
    local prev
    local min = 1
    for i = 0, #Data.UNCOMMON do
        local row = Data.UNCOMMON[i]
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(width, 20)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else
            b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        end
        if row then
            b.band = row.max
            b:SetText(row.max >= 999 and (min .. "+") or (min .. "-" .. row.max))
            min = row.max + 1
        else
            b:SetText("All")
        end
        b:SetScript("OnClick", function(self)
            if self.band then
                ns.db.brackets[self.band] = not ns.db.brackets[self.band] or nil
            else
                wipe(ns.db.brackets)
            end
            paintBrackets()
            Panel.refresh()
        end)
        bracketButtons[#bracketButtons + 1] = b
        prev = b
    end
end

local function createHeaders(parent)
    local x = 0
    for _, c in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, parent, "ColumnDisplayButtonShortTemplate")
        h:SetSize(c.width, 19)
        h:SetPoint("TOPLEFT", x, 0)
        h:SetText(c.label)
        h.Arrow = h:CreateTexture(nil, "OVERLAY")
        h.Arrow:SetAtlas("auctionhouse-ui-sortarrow", true)
        h.Arrow:SetPoint("LEFT", h:GetFontString(), "RIGHT", 3, 0)
        h:SetScript("OnClick", function()
            if sortKey == c.key then
                sortDesc = not sortDesc
            else
                sortKey = c.key
                sortDesc = c.key ~= "name"
                    and c.key ~= "loss"
                    and c.key ~= "skill"
                    and c.key ~= "buyout"
            end
            Panel.refresh()
        end)
        c.header = h
        x = x + c.width
    end
end

local function updateTab()
    if not tab then
        return
    end
    if panel:IsShown() then
        PanelTemplates_SelectTab(tab)
        tab:Enable() -- SelectTab disables it; a click must still hide the panel
    else
        PanelTemplates_DeselectTab(tab)
    end
end

local function createPanel()
    panel = CreateFrame("Frame", "DustToDustPanel", AuctionHouseFrame, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(panel)
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 0, 0)
    panel:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 0, 0)
    panel:EnableMouse(true)
    ---@diagnostic disable-next-line: param-type-mismatch
    panel:SetTitle("DustToDust")
    panel.Inset:Hide()
    panel.CloseButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    -- the name column takes what the others leave
    local inner = WIDTH - 16 - 26
    local used = 0
    for i = 2, #COLUMNS do
        used = used + COLUMNS[i].width
    end
    COLUMNS[1].width = inner - used

    scanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanButton:SetSize(90, 22)
    scanButton:SetPoint("TOPLEFT", 12, -30)
    scanButton:SetScript("OnClick", function()
        if Scan.running then
            Scan.stop()
        else
            Scan.start()
        end
    end)

    local pricesButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    pricesButton:SetSize(110, 22)
    pricesButton:SetPoint("LEFT", scanButton, "RIGHT", 6, 0)
    pricesButton:SetText("Check prices")
    pricesButton:SetScript("OnClick", function()
        Prices.check(true)
    end)
    pricesButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Check material prices now")
        GameTooltip:AddLine(
            "Happens by itself when the panel opens, at most every 5 minutes.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    pricesButton:SetScript("OnLeave", GameTooltip_Hide)

    onlyDeals = checkbox("Only deals", "onlyDeals", pricesButton)
    onlySkill = checkbox("Only what I can disenchant", "onlySkill", onlyDeals.text)
    onlyDeals:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Only deals")
        GameTooltip:AddLine(
            "Profit of at least the minimum and the margin, with a chance of a loss under the limit (Options > AddOns > DustToDust).",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    onlyDeals:SetScript("OnLeave", GameTooltip_Hide)

    createBrackets(scanButton)

    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", 8, -88)
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
    pricesText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    pricesText:SetPoint("BOTTOMLEFT", 14, 10)
    pricesText:SetJustifyH("LEFT")
    totalsText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    totalsText:SetPoint("BOTTOMRIGHT", -14, 10)
    totalsText:SetJustifyH("RIGHT")

    panel:SetScript("OnShow", function()
        Panel.refresh()
        updateTab()
        Prices.check() -- at most every 5 minutes
    end)
    panel:SetScript("OnHide", function()
        Scan.stop()
        updateTab()
    end)

    -- PanelTabButtonTemplate adds the button to its parent's Tabs. On AuctionHouseFrame that
    -- makes it the auction house's last tab, and Auctionator puts its tabs after that one.
    local holder = CreateFrame("Frame", nil, AuctionHouseFrame)
    holder:SetAllPoints()
    tab = CreateFrame("Button", "DustToDustTab", holder, "PanelTabButtonTemplate")
    tab:SetText("Dust")
    PanelTemplates_TabResize(tab, 0)
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        panel:SetShown(not panel:IsShown())
    end)
end

-- Bottom right under the auction house; left of DisenchantValue's tab while that's
-- installed (it makes its tab a frame after the auction house opens).
local function placeTab()
    local other = _G["DisenchantValueAuctionTab"]
    tab:ClearAllPoints()
    if other then
        tab:SetPoint("RIGHT", other, "LEFT", -2, 0)
    else
        tab:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, 2)
    end
end

-- The auction house UI loads on demand: AuctionHouseFrame may only exist a frame later.
function ns.onAuctionHouseShow(retried)
    if not panel and AuctionHouseFrame then
        createPanel()
    end
    if not panel then
        if not retried then
            C_Timer.After(0, function()
                ns.onAuctionHouseShow(true)
            end)
        end
        return
    end
    skill = ns.enchanting()
    onlyDeals:SetChecked(ns.db.onlyDeals)
    onlySkill:SetChecked(ns.db.onlySkill)
    onlySkill:SetShown(skill ~= nil)
    onlySkill.text:SetShown(skill ~= nil)
    paintBrackets()
    panel:Hide() -- starts closed every visit; the Dust tab opens it
    updateTab()
    placeTab()
    C_Timer.After(0.2, placeTab)
    Panel.refresh()
    Panel.status()
end

function ns.onAuctionHouseClosed()
    Scan.stop()
    Prices.stop()
    for _, r in ipairs(Scan.results) do
        r.offer, r.checking = nil, false
    end
end

ns.onChange(function()
    Scan.reprice()
    Panel.refresh()
end)
