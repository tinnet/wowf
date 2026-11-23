-- PriceIsRight: search Auctionator's price database by item name. A search box and the
-- matching items on the left; click one for everything Auctionator keeps on it (last price,
-- price history, your own posts) and its item tooltip, with whatever other addons add.
--
-- Auctionator's public API (Auctionator.API.v1) only answers "what does item X cost", so
-- the list of items comes from its internal database table (Auctionator.Database.db).
-- That isn't a promised interface: if a new Auctionator changes it, the window says so.
local _, ns = ...
local Logic = ns.Logic

local items, byKey = {}, {} -- one record per database key: key, itemID, extra, kind, name, ...
local waiting, waitingCount = {}, 0 -- itemID -> records waiting for the item's data
local window, searchBox, listBox, historyBox, statusText, headerText, tooltip
local selected
local refreshPending = false

local ROW_HEIGHT = 18

local function database()
    local atr = _G["Auctionator"]
    local db = atr and atr.Database and atr.Database.db
    if type(db) == "table" then
        return db
    end
end

local function money(copper)
    return copper and GetMoneyString(copper, true) or "-"
end

-- Auctionator counts days since 2020-01-01 (local time).
local function dayZero()
    local atr = _G["Auctionator"]
    return atr and atr.Constants and atr.Constants.SCAN_DAY_0
        or time({ year = 2020, month = 1, day = 1, hour = 0 })
end

local function today()
    return math.floor((time() - dayZero()) / 86400)
end

local function dayText(day)
    return date("%b %d", dayZero() + day * 86400)
end

---------------------------------------------------------------------------
-- The index of Auctionator's items
---------------------------------------------------------------------------
-- Name, quality and icon from the item's data; false while the client hasn't loaded it.
local function fill(record)
    local name, _, quality = C_Item.GetItemInfo(record.itemID)
    if not name then
        return false
    end
    if record.kind == "gr" then
        name = name .. " " .. record.extra
    elseif record.kind == "g" then
        name = ("%s (item level %s)"):format(name, record.extra)
    end
    record.name, record.quality = name, quality
    return true
end

local function index()
    local db = database()
    if not db then
        return false
    end
    for key in pairs(db) do
        if not byKey[key] then
            local itemID, extra, kind = Logic.parseKey(key)
            if itemID then
                local record = { key = key, itemID = itemID, extra = extra, kind = kind }
                record.icon = select(5, C_Item.GetItemInfoInstant(itemID))
                byKey[key] = record
                items[#items + 1] = record
                if not fill(record) then
                    if not waiting[itemID] then
                        waiting[itemID] = {}
                        waitingCount = waitingCount + 1
                        C_Item.RequestLoadItemDataByID(itemID)
                    end
                    table.insert(waiting[itemID], record)
                end
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Details: Auctionator's data on the selected item, and its tooltip
---------------------------------------------------------------------------
local function showDetails()
    local db = database()
    local entry = selected and db and db[selected.key]
    if not entry then
        headerText:SetText(selected and "Auctionator has no data on this item any more." or "")
        historyBox:SetDataProvider(CreateDataProvider({}))
        tooltip:Hide()
        return
    end

    local lines = {}
    local r, g, b = C_Item.GetItemQualityColor(selected.quality or 1)
    lines[#lines + 1] = CreateColor(r, g, b):WrapTextInColorCode(selected.name or selected.key)
    lines[#lines + 1] = ("|cff999999Item ID %d, Auctionator key %s|r"):format(
        selected.itemID,
        selected.key
    )
    local last = Logic.lastDay(entry)
    local ago = last and today() - last
    lines[#lines + 1] = ("Last seen: %s%s"):format(
        money(entry.m),
        ago == nil and ""
            or ago <= 0 and ", today"
            or ago == 1 and ", yesterday"
            or (", %d days ago"):format(ago)
    )
    local sellPrice = select(11, C_Item.GetItemInfo(selected.itemID))
    if sellPrice and sellPrice > 0 then
        lines[#lines + 1] = "Vendor pays: " .. money(sellPrice)
    end
    headerText:SetText(table.concat(lines, "\n"))

    local rows = {}
    rows[#rows + 1] = { heading = true, "Day", "Lowest", "Highest lowest", "Up" }
    for _, h in ipairs(Logic.history(entry)) do
        local day = dayText(h.day)
        rows[#rows + 1] =
            { day, money(h.low), money(h.high), h.available and tostring(h.available) or "" }
    end
    local postingHistory = _G["AUCTIONATOR_POSTING_HISTORY"] -- Auctionator's saved variable
    local posts = type(postingHistory) == "table" and postingHistory[selected.key]
    if type(posts) == "table" and #posts > 0 then
        rows[#rows + 1] = { heading = true, "You posted", "Each", "", "Count" }
        for i = #posts, 1, -1 do
            local post = posts[i]
            rows[#rows + 1] = {
                post.time and date("%b %d", post.time) or "?",
                money(post.price),
                "",
                tostring(post.quantity or ""),
            }
        end
    end
    historyBox:SetDataProvider(CreateDataProvider(rows))

    -- Named "NotGameTooltip..." so Auctionator adds its lines (its convention for addon
    -- tooltips). Addons that only touch GameTooltip show up when hovering the list instead.
    tooltip:SetOwner(window, "ANCHOR_NONE")
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", window, "TOPRIGHT", 2, 0)
    tooltip:SetItemByID(selected.itemID)
    tooltip:Show()
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function refresh()
    if not (window and window:IsShown()) then
        return
    end
    if not index() then
        statusText:SetText(
            _G["Auctionator"]
                    and "|cffff5555Can't read Auctionator's database (a new Auctionator version?)|r"
                or "|cffff5555Auctionator isn't loaded.|r"
        )
        listBox:SetDataProvider(CreateDataProvider({}))
        return
    end
    local found = Logic.search(items, searchBox:GetText())
    listBox:SetDataProvider(CreateDataProvider(found), ScrollBoxConstants.RetainScrollPosition)
    local status = ("%d of %d items"):format(#found, #items)
    if waitingCount > 0 then
        status = status .. (", loading %d names"):format(waitingCount)
    end
    statusText:SetText(status)
end

-- Item data arrives in bursts: redraw at most a few times a second.
local function refreshSoon()
    if refreshPending then
        return
    end
    refreshPending = true
    C_Timer.After(0.3, function()
        refreshPending = false
        refresh()
    end)
end

local function initRow(row, item)
    if not row.label then
        row:SetHeight(ROW_HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.mark = row:CreateTexture(nil, "BACKGROUND")
        row.mark:SetAllPoints()
        row.mark:SetColorTexture(1, 0.82, 0, 0.15)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
        row.icon:SetPoint("LEFT", 2, 0)
        row.price = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.price:SetPoint("RIGHT", -4, 0)
        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row.price, "LEFT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local link = select(2, C_Item.GetItemInfo(self.item.itemID))
            if IsModifiedClick() and link and HandleModifiedItemClick(link) then
                return -- shift-click links it in chat, ctrl-click tries it on
            end
            selected = self.item
            listBox:ForEachFrame(function(other)
                other.mark:SetShown(other.item == selected)
            end)
            showDetails()
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(window, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPRIGHT", window, "TOPLEFT", -2, 0)
            GameTooltip:SetItemByID(self.item.itemID)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    row.item = item
    row.icon:SetTexture(item.icon)
    local r, g, b = C_Item.GetItemQualityColor(item.quality or 1)
    row.label:SetText(item.name)
    row.label:SetTextColor(r, g, b)
    local db = database()
    local entry = db and db[item.key]
    row.price:SetText(entry and money(entry.m) or "")
    row.mark:SetShown(item == selected)
end

local function initHistoryRow(row, data)
    if not row.cols then
        row:SetHeight(ROW_HEIGHT - 2)
        row.cols = {}
        local x = { 0, 60, 150, 250 }
        for i = 1, 4 do
            local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", x[i], 0)
            row.cols[i] = fs
        end
    end
    for i = 1, 4 do
        row.cols[i]:SetText(data[i])
        row.cols[i]:SetFontObject(
            data.heading and "GameFontNormalSmall" or "GameFontHighlightSmall"
        )
    end
end

local function scrollList(parent, extent, initializer, rowType)
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(extent)
    view:SetElementInitializer(rowType, initializer)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    return box
end

local function createWindow()
    window = CreateFrame("Frame", "PriceIsRightWindow", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(720, 440)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, "PriceIsRightWindow") -- Escape closes it

    local title = window.TitleText or window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not window.TitleText then
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("PriceIsRight: Auctionator's prices")

    searchBox = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    searchBox:SetSize(300, 20)
    searchBox:SetPoint("TOPLEFT", 20, -32)
    searchBox:HookScript("OnTextChanged", refreshSoon)

    listBox = scrollList(window, ROW_HEIGHT, initRow, "Button")
    listBox:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -6, -8)
    listBox:SetPoint("BOTTOMLEFT", 14, 30)
    listBox:SetWidth(310)

    statusText = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", 16, 12)

    headerText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerText:SetPoint("TOPLEFT", 356, -34)
    headerText:SetPoint("RIGHT", -16, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetSpacing(4)

    historyBox = scrollList(window, ROW_HEIGHT - 2, initHistoryRow, "Frame")
    historyBox:SetPoint("TOPLEFT", 356, -120)
    historyBox:SetPoint("BOTTOMRIGHT", -30, 12)

    tooltip =
        CreateFrame("GameTooltip", "NotGameTooltipPriceIsRight", window, "GameTooltipTemplate")

    window:SetScript("OnShow", function()
        refresh()
        searchBox:SetFocus()
    end)
    window:SetScript("OnHide", function()
        tooltip:Hide()
    end)
end

local function toggle()
    if not window then
        createWindow()
    end
    window:SetShown(not window:IsShown())
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, itemID, success)
    if event == "ITEM_DATA_LOAD_RESULT" then
        local records = waiting[itemID]
        if not records then
            return
        end
        waiting[itemID] = nil
        waitingCount = waitingCount - 1
        for _, record in ipairs(records) do
            if not (success and fill(record)) then
                record.name = ("item %d"):format(itemID) -- the game doesn't know it
            end
        end
        refreshSoon()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        refreshSoon() -- a scan may have added items
    end
end)
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")

-- also listed in the minimap's addon menu (AddonCompartmentFunc in the .toc)
function PriceIsRight_Toggle()
    toggle()
end

SLASH_PRICEISRIGHT1 = "/pir"
SLASH_PRICEISRIGHT2 = "/priceisright"
SlashCmdList.PRICEISRIGHT = function(msg)
    msg = msg:match("^%s*(.-)%s*$")
    if msg == "" then
        toggle()
        return
    end
    if not (window and window:IsShown()) then
        toggle()
    end
    searchBox:SetText(msg) -- "/pir copper ore" searches right away
end
