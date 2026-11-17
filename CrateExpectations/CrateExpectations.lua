-- CrateExpectations: a small crate in the corner of every item a Waylaid Crate takes, on
-- any of Blizzard's item buttons (bags, bank, merchant, loot, mail, trade, guild bank,
-- auction house), and a tooltip line saying which shipments take it.
local addonName, ns = ...
local Logic = ns.Logic

local ICON = "Interface\\Icons\\INV_Crate_01"
-- GlobalStrings' "Use:" in the client's language (not in the UI source or the annotations)
local USE = rawget(_G, "ITEM_SPELL_TRIGGER_ONUSE") or "Use:"

local DEFAULTS = {
    marks = true,
    corner = "BOTTOMLEFT",
    size = 40, -- percent of the button's width
    tooltip = true,
    learned = {}, -- shipment -> bundles, read from crate tooltips seen in game
}

local index = {} -- item name -> { { shipment, count } }
local wanted = {} -- itemID -> that list, or false; nil while the name isn't loaded
local marks = setmetatable({}, { __mode = "k" }) -- button -> our mark frame
local shown = setmetatable({}, { __mode = "k" }) -- button -> itemID it last showed

function ns.chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CrateExpectations|r: " .. msg)
end

-- What the crates take of this item, false if nothing, nil until its name has loaded.
local function lookup(itemID)
    local known = wanted[itemID]
    if known ~= nil then
        return known
    end
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        return nil
    end
    known = index[name] or false
    wanted[itemID] = known
    return known
end

local function newMark(button)
    local mark = CreateFrame("Frame", nil, button)
    mark:SetFrameLevel(button:GetFrameLevel() + 5)
    local edge = mark:CreateTexture(nil, "OVERLAY", nil, 6)
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 0.9)
    local icon = mark:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    marks[button] = mark
    return mark
end

local function place(mark, button)
    local db = ns.db
    local host = button.icon or button.Icon or button
    local size = math.max(8, math.floor((host:GetWidth() or 0) * db.size / 100 + 0.5))
    local corner = db.corner
    mark:SetSize(size, size)
    mark:ClearAllPoints()
    mark:SetPoint(
        corner,
        host,
        corner,
        corner:find("LEFT") and 1 or -1,
        corner:find("TOP") and -1 or 1
    )
end

local function mark(button, itemIDOrLink)
    if not ns.db or type(button) ~= "table" or not button.GetObjectType then
        return
    end
    if button.IsForbidden and button:IsForbidden() then
        return
    end
    local itemID
    local kind = type(itemIDOrLink)
    if kind == "number" or kind == "string" then
        itemID = C_Item.GetItemInfoInstant(itemIDOrLink)
    end
    shown[button] = itemID
    local want = itemID and ns.db.marks and lookup(itemID)
    local m = marks[button]
    if not want then
        if m then
            m:Hide()
        end
        return
    end
    m = m or newMark(button)
    place(m, button)
    m:Show()
end

-- Rebuilds the index and redraws every button we've marked or looked at.
function ns.refresh()
    index = Logic.index(Logic.SHIPMENTS, ns.db.learned)
    wipe(wanted)
    for button, itemID in pairs(shown) do
        mark(button, itemID)
    end
end

-- A crate's tooltip lists its bundles: save any we didn't know.
local function learn(data)
    local lines = {}
    for i, line in ipairs(data.lines or {}) do
        local text = line.leftText
        if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            lines[i] = Logic.plain(text)
        else
            lines[i] = ""
        end
    end
    local bundles = Logic.parseBundles(lines, USE)
    if #bundles == 0 or lines[1] == "" then
        return
    end
    local shipment = Logic.shipmentName(lines[1])
    local merged, changed = Logic.merge(ns.db.learned[shipment], bundles)
    if changed then
        ns.db.learned[shipment] = merged
        ns.refresh()
    end
end

local function onTooltip(tooltip, data)
    if not ns.db or not data or (tooltip.IsForbidden and tooltip:IsForbidden()) then
        return
    end
    learn(data)
    if not ns.db.tooltip or type(data.id) ~= "number" then
        return
    end
    local list = lookup(data.id)
    if list then
        tooltip:AddLine("Waylaid Crate: " .. Logic.describe(list), 0.9, 0.7, 0.3, true)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then
            return
        end
        frame:UnregisterEvent("ADDON_LOADED")
        CrateExpectationsDB = CrateExpectationsDB or {}
        ns.db = CrateExpectationsDB
        for key, value in pairs(DEFAULTS) do
            if ns.db[key] == nil then
                ns.db[key] = type(value) == "table" and {} or value
            end
        end
        ns.refresh()
        ns.registerSettings()
    elseif event == "ITEM_DATA_LOAD_RESULT" and ns.db then
        for button, itemID in pairs(shown) do
            if itemID == arg1 then
                mark(button, itemID)
            end
        end
    end
end)

-- Nearly every item button goes through SetItemButtonQuality when it shows an item (or
-- nothing); the merchant calls the button's own method instead.
hooksecurefunc("SetItemButtonQuality", function(button, _, itemIDOrLink)
    mark(button, itemIDOrLink)
end)
hooksecurefunc("MerchantFrameItem_UpdateQuality", function(item, link)
    if item then
        mark(item.ItemButton, link)
    end
end)

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)

SLASH_CRATEEXPECTATIONS1 = "/crates"
SlashCmdList.CRATEEXPECTATIONS = function()
    Settings.OpenToCategory(ns.settingsCategory:GetID())
end
