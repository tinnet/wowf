local ADDON = ...
local FISHING = C_Spell.GetSpellName(7620) or "Fishing"

-- Soft-target settings so "Interact with Target" picks up the bobber.
-- Previous values are stored in SavedVariables and restored on close.
local CVARS = {
    SoftTargetInteract = "3", -- always soft-target interactables
    SoftTargetInteractArc = "2", -- any direction
    SoftTargetInteractRange = "30", -- bobbers land up to ~20yd away
}

local db
local fishing = false -- currently channeling Fishing
local ticker

local events = CreateFrame("Frame")
local window, statusText, lureText

local function isFishing(spellID)
    return spellID and C_Spell.GetSpellName(spellID) == FISHING
end

local function msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SpaceFish|r: " .. text)
end

---------------------------------------------------------------------------
-- Secure cast button (only a secure button may cast spells for us)
---------------------------------------------------------------------------
local castButton =
    CreateFrame("Button", "SpaceFishCastButton", UIParent, "SecureActionButtonTemplate")
castButton:SetAttribute("type", "spell")
castButton:SetAttribute("spell", FISHING)
-- SecureActionButton_OnClick only acts on the phase that matches the "cast on key down"
-- setting, so registering both casts once per press and follows that setting live.
castButton:RegisterForClicks("AnyUp", "AnyDown")
-- left shown (but sizeless, so invisible) so binding clicks always reach it

---------------------------------------------------------------------------
-- CVars
---------------------------------------------------------------------------
local function applyCVars()
    if db.savedCVars then
        return -- already applied (and originals already saved)
    end
    db.savedCVars = {}
    for name, value in pairs(CVARS) do
        db.savedCVars[name] = C_CVar.GetCVar(name)
        C_CVar.SetCVar(name, value)
    end
end

local function restoreCVars()
    if not db.savedCVars then
        return
    end
    for name, value in pairs(db.savedCVars) do
        C_CVar.SetCVar(name, value)
    end
    db.savedCVars = nil
end

---------------------------------------------------------------------------
-- Bindings (override bindings only; your saved keybinds are never changed)
---------------------------------------------------------------------------
local function setStatus()
    if not statusText then
        return
    end
    if InCombatLockdown() then
        statusText:SetText("|cffff5555In combat: Space is jump|r")
    elseif fishing then
        statusText:SetText("|cff55ff55Fishing: Space to reel in|r")
    else
        statusText:SetText("Ready: Space to cast")
    end
end

local function applyBindings()
    if InCombatLockdown() then
        setStatus()
        return -- PLAYER_REGEN_ENABLED will call us again
    end
    ClearOverrideBindings(events)
    if window and window:IsShown() then
        if fishing then
            SetOverrideBinding(events, true, "SPACE", "INTERACTTARGET")
        else
            SetOverrideBindingClick(events, true, "SPACE", "SpaceFishCastButton")
        end
        SetOverrideBinding(events, true, "SHIFT-SPACE", "JUMP")
    end
    setStatus()
end

---------------------------------------------------------------------------
-- Lure status
---------------------------------------------------------------------------
local function updateLure()
    local enchant = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND)
    if enchant then
        local s = math.floor(enchant.remainingTimeMs / 1000)
        lureText:SetFormattedText("Lure: |cff55ff55%d:%02d|r", math.floor(s / 60), s % 60)
    else
        lureText:SetText("Lure: |cffff5555none|r")
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function createWindow()
    window = CreateFrame("Frame", "SpaceFishWindow", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(200, 96)
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
    title:SetText("SpaceFish")

    statusText = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", 14, -32)

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -6)
    hint:SetText("Shift+Space: jump")

    lureText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lureText:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)

    window:SetScript("OnShow", function()
        -- already channeling (cast from an action bar): Space should reel in, not recast
        fishing = isFishing(select(8, UnitChannelInfo("player"))) or false
        applyCVars()
        applyBindings()
        updateLure()
        ticker = C_Timer.NewTicker(1, updateLure)
    end)
    window:SetScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        applyBindings() -- clears them (window is hidden)
        restoreCVars()
    end)

    -- Escape closes the window
    tinsert(UISpecialFrames, "SpaceFishWindow")
end

local function toggle()
    window:SetShown(not window:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local minimapButton

local function placeMinimapButton()
    local a = math.rad(db.minimapAngle or 200)
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
    local bestAngle, bestGap = 200, -1
    for step = 0, 71 do
        local a = (200 + step * 5) % 360
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
    local b = CreateFrame("Button", "SpaceFishMinimapButton", Minimap)
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
    icon:SetTexture("Interface\\Icons\\Trade_Fishing")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

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
        GameTooltip:AddLine("SpaceFish")
        GameTooltip:AddLine("Click to toggle the fishing window.", 1, 1, 1)
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
events:SetScript("OnEvent", function(_, event, arg1, _, spellID)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            return
        end
        SpaceFishDB = SpaceFishDB or {}
        db = SpaceFishDB
        restoreCVars() -- left over from a /reload or crash with the window open
        createWindow()
        createMinimapButton()
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if not db.minimapAngle then
            -- first run: wait for other addons to place their buttons, then avoid them
            C_Timer.After(2, autoPlaceMinimapButton)
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if isFishing(spellID) then
            fishing = true
            applyBindings()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if fishing then
            fishing = false
            applyBindings()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- last moment before combat lockdown: give Space back to jump
        ClearOverrideBindings(events)
        setStatus()
    elseif event == "PLAYER_REGEN_ENABLED" then
        applyBindings()
    elseif event == "PLAYER_LOGOUT" then
        restoreCVars() -- don't leave our soft-target settings behind
    end
end)

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGOUT")

-- also listed in the minimap's addon menu (AddonCompartmentFunc in the .toc)
function SpaceFish_Toggle()
    toggle()
end

SLASH_SPACEFISH1 = "/spacefish"
SlashCmdList.SPACEFISH = function(msg)
    if msg:lower():match("^%s*minimap") then
        autoPlaceMinimapButton() -- re-pick a free spot on the rim
    else
        toggle()
    end
end
