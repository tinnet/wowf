-- LayerCake: which layer you're on. Every NPC's GUID carries the ID of the zone copy (layer)
-- it lives on; we read it from the NPCs the game hands us anyway (target, mouseover,
-- nameplates) and number the IDs seen per zone, lowest first. Nothing is sent or asked of
-- anyone: no chat, no addon messages, no other addons.
local ADDON, ns = ...
local Logic = ns.Logic

local db
local cur = {} -- mapID, mapName, zone, npc, at, prevZone, changedAt, stale, hidden
local window, layerText, detailText, minimapButton, buttonText, ticker

-- issecretvalue only exists on clients with secret values; treat those as unknown.
local function plain(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

-- The zone-level map the player is on (a city or cave sub-map counts as its zone).
local function zoneMap()
    local mapID = C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    while
        info
        and info.mapType > Enum.UIMapType.Zone
        and info.parentMapID
        and info.parentMapID ~= 0
    do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return info
end

local function seenHere()
    if not cur.mapID then
        return nil
    end
    local realm = GetRealmName()
    db.seen[realm] = db.seen[realm] or {}
    local seen = db.seen[realm][cur.mapID] or {}
    db.seen[realm][cur.mapID] = seen
    Logic.prune(seen, GetServerTime())
    return seen
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function grey(text)
    return "|cff999999" .. text .. "|r"
end

local function refresh()
    local seen = seenHere()
    local layer, count
    if seen and cur.zone then
        layer, count = Logic.rank(seen, cur.zone)
    end

    if buttonText then
        buttonText:SetText(layer and not cur.stale and tostring(layer) or "")
    end
    if not (window and window:IsShown()) then
        return
    end

    local now = GetServerTime()
    local lines = {}
    if IsInInstance() then
        layerText:SetText("No layer")
        lines[#lines + 1] = "You're in an instance. Instances have no layers."
    elseif not cur.mapID then
        layerText:SetText("Layer ?")
        lines[#lines + 1] = "The game doesn't say which zone you're in."
    else
        layerText:SetText(layer and ("Layer " .. layer) or "Layer ?")
        lines[#lines + 1] = ("%s: %d layer%s seen in the last %dh"):format(
            cur.mapName or "?",
            count or 0,
            count == 1 and "" or "s",
            Logic.MAX_AGE / 3600
        )
        if cur.zone then
            lines[#lines + 1] = ("Zone ID %d, from %s %s ago"):format(
                cur.zone,
                cur.npc or "an NPC",
                Logic.ago(now - cur.at)
            )
        end
        if cur.prevZone then
            lines[#lines + 1] = ("Changed from zone ID %d %s ago"):format(
                cur.prevZone,
                Logic.ago(now - cur.changedAt)
            )
        end
        if seen and count and count > 1 then
            local parts = {}
            for i, zone in ipairs(Logic.sorted(seen)) do
                parts[#parts + 1] = ("%d: %d (%s ago)"):format(i, zone, Logic.ago(now - seen[zone]))
            end
            lines[#lines + 1] = grey("Seen here: " .. table.concat(parts, ", "))
        end
        if cur.stale then
            lines[#lines + 1] = "|cffffd100Your group changed, and the game may move you to the "
                .. "leader's layer. Look at an NPC to check.|r"
        elseif not cur.zone then
            lines[#lines + 1] = "|cffffd100Target, mouse over or show the nameplate of any NPC.|r"
        end
        if cur.hidden then
            lines[#lines + 1] = grey("The game hid an NPC's ID here, so it was skipped.")
        end
    end
    detailText:SetText(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- Reading NPCs
---------------------------------------------------------------------------
local function onZoneChanged()
    local info = zoneMap()
    local mapID = info and info.mapID
    if mapID ~= cur.mapID then
        cur = { mapID = mapID, mapName = info and info.name }
    end
    refresh()
end

local function observe(unit)
    if IsInInstance() or not cur.mapID then
        return
    end
    local guid = UnitGUID(unit)
    if guid == nil then
        return
    end
    if plain(guid) == nil then
        if not cur.hidden then
            cur.hidden = true
            refresh()
        end
        return
    end
    local zone = Logic.parseGUID(guid)
    if not zone then
        return
    end

    local now = GetServerTime()
    seenHere()[zone] = now
    if cur.zone and cur.zone ~= zone then
        cur.prevZone, cur.changedAt = cur.zone, now
    end
    cur.zone, cur.at, cur.stale = zone, now, nil
    cur.npc = plain(UnitName(unit))
    refresh()
end

local function groupChanged()
    if cur.zone then
        cur.stale = true
        refresh()
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function createWindow()
    window = CreateFrame("Frame", "LayerCakeWindow", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(300, 190)
    window:SetPoint(
        db.point or "CENTER",
        UIParent,
        db.relativePoint or db.point or "CENTER",
        db.x or 0,
        db.y or 0
    )
    window:SetFrameStrata("MEDIUM")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
    end)
    window:Hide()

    local title = window.TitleText or window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not window.TitleText then
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("LayerCake")

    layerText = window:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    layerText:SetPoint("TOPLEFT", 14, -34)

    detailText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailText:SetPoint("TOPLEFT", layerText, "BOTTOMLEFT", 0, -8)
    detailText:SetWidth(272)
    detailText:SetJustifyH("LEFT")
    detailText:SetSpacing(3)

    local forget = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    forget:SetSize(120, 22)
    forget:SetPoint("BOTTOMLEFT", 12, 10)
    forget:SetText("Forget this zone")
    forget:SetScript("OnClick", function()
        local realm = db.seen[GetRealmName()]
        if cur.mapID and realm then
            realm[cur.mapID] = nil
            cur = { mapID = cur.mapID, mapName = cur.mapName }
            refresh()
        end
    end)
    forget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Forget the zone IDs seen here", 1, 1, 1)
        GameTooltip:AddLine(
            "Numbers start over from the next NPC you look at. Useful after a server restart, "
                .. "or if an NPC across a zone border added a layer that isn't one.",
            nil,
            nil,
            nil,
            true
        )
        GameTooltip:Show()
    end)
    forget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local note = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMRIGHT", -14, 14)
    note:SetPoint("LEFT", forget, "RIGHT", 8, 0)
    note:SetJustifyH("RIGHT")
    note:SetText("Numbers are only this addon's")

    window:SetScript("OnShow", function()
        refresh()
        ticker = C_Timer.NewTicker(1, refresh)
    end)
    window:SetScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)

    -- Escape closes the window
    tinsert(UISpecialFrames, "LayerCakeWindow")
end

local function toggle()
    window:SetShown(not window:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local function placeMinimapButton()
    local a = math.rad(db.minimapAngle or 160)
    local r = Minimap:GetWidth() / 2 + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- Angles (degrees) of other small frames sitting around the minimap's rim:
-- other addons' minimap buttons and Blizzard's (mail, tracking, ...).
local function occupiedAngles()
    local mx, my = Minimap:GetCenter()
    local ms = Minimap:GetEffectiveScale()
    local r = Minimap:GetWidth() / 2 * ms
    local angles = {}
    local function scan(parent)
        if not parent then
            return
        end
        for _, child in ipairs({ parent:GetChildren() }) do
            local cx, cy = child:GetCenter()
            if child ~= minimapButton and child:IsShown() and cx then
                local cs = child:GetEffectiveScale()
                local dx, dy = cx * cs - mx * ms, cy * cs - my * ms
                local dist = math.sqrt(dx * dx + dy * dy)
                local size = math.max(child:GetSize()) * cs
                if size < r and dist > r * 0.75 and dist < r * 1.6 then
                    angles[#angles + 1] = math.deg(math.atan2(dy, dx))
                end
            end
        end
    end
    scan(Minimap)
    scan(MinimapCluster)
    return angles
end

-- Put the button in the biggest free gap on the rim (ties go to the default spot).
local function autoPlaceMinimapButton()
    local taken = occupiedAngles()
    local bestAngle, bestGap = 160, -1
    for step = 0, 71 do
        local a = (160 + step * 5) % 360
        local gap = 180
        for _, t in ipairs(taken) do
            local d = math.abs((a - t + 180) % 360 - 180)
            gap = math.min(gap, d)
        end
        if gap > bestGap then
            bestAngle, bestGap = a, gap
        end
    end
    db.minimapAngle = bestAngle
    placeMinimapButton()
end

local function createMinimapButton()
    local b = CreateFrame("Button", "LayerCakeMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    -- the layer number, over the icon
    buttonText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    buttonText:SetPoint("CENTER", icon, "CENTER", 1, 0)

    local function onDragUpdate()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
        placeMinimapButton()
    end

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnClick", toggle)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("LayerCake")
        local text = buttonText:GetText()
        if text and text ~= "" then
            GameTooltip:AddLine("Layer " .. text, 1, 1, 1)
        end
        GameTooltip:AddLine("Click to toggle the layer window.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapButton = b
    placeMinimapButton()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            return
        end
        LayerCakeDB = LayerCakeDB or {}
        db = LayerCakeDB
        db.seen = db.seen or {} -- realm -> zone mapID -> zone ID -> last seen
        createWindow()
        createMinimapButton()
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if not db.minimapAngle then
            -- first run: wait for other addons to place their buttons, then avoid them
            C_Timer.After(2, autoPlaceMinimapButton)
        end
    elseif
        event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS"
    then
        onZoneChanged()
    elseif event == "PLAYER_TARGET_CHANGED" then
        observe("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        observe("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        observe(arg1)
    elseif event == "GROUP_JOINED" or event == "GROUP_LEFT" or event == "PARTY_LEADER_CHANGED" then
        groupChanged()
    end
end)

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("GROUP_JOINED")
events:RegisterEvent("GROUP_LEFT")
events:RegisterEvent("PARTY_LEADER_CHANGED")

-- also listed in the minimap's addon menu (AddonCompartmentFunc in the .toc)
function LayerCake_Toggle()
    toggle()
end

SLASH_LAYERCAKE1 = "/layercake"
SlashCmdList.LAYERCAKE = function(msg)
    if msg:lower():match("^%s*minimap") then
        autoPlaceMinimapButton() -- re-pick a free spot on the rim
    else
        toggle()
    end
end
