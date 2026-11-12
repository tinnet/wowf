-- KindHands window: while it's open (and only then), it notices other players buffing
-- you and offers two buttons for the last one: buff them back, and /thank them.
-- Opened from the minimap button, the minimap's addon menu or /kindhands window.
-- Out of combat only: it closes when combat starts and comes back after. The buff back
-- button casts, so it's a secure button, which makes the window locked in combat anyway.
--
-- Who buffed you comes from the aura's sourceUnit: the game only names a caster that
-- has a unit token right then (target, party, mouseover, a nameplate). A stranger you
-- neither target nor see a nameplate for comes back as nobody; then the window can
-- only say what you got. Friendly player nameplates make strangers visible.
local ADDON, ns = ...
local plain = ns.plain
local MIN_DURATION = 60 -- seconds; shorter auras (Renew, shields, procs) aren't buffs
local ICON = "Interface\\Icons\\Spell_Holy_SealOfSacrifice"

local db
local window, whoText, spellText, unknownText, thanksButton
local reopen = false -- closed by combat, to come back after
local resuming = false -- reopening after combat: keep who buffed you
local expires = {} -- auraInstanceID -> expirationTime, to notice rebuffs (refreshes)
local last -- { name, fullName, guid, spells = { names }, thanked } who buffed you last
local unknown -- spell names from casters the game didn't name, since `last`

local function refresh()
    if not window then
        return
    end
    if last then
        whoText:SetText(("|cffffffff%s|r buffed you"):format(last.name))
        spellText:SetText(table.concat(last.spells, ", "))
        thanksButton:SetEnabled(not last.thanked)
        thanksButton:SetText(last.thanked and "Thanked" or "/thanks")
    else
        whoText:SetText("Nobody has buffed you yet.")
        spellText:SetText("")
        thanksButton:SetEnabled(false)
        thanksButton:SetText("/thanks")
    end
    unknownText:SetText(
        unknown
                and ("Also got %s from someone the game didn't name."):format(
                    table.concat(unknown, ", ")
                )
            or ""
    )
end

local function addTo(list, name)
    for _, have in ipairs(list) do
        if have == name then
            return
        end
    end
    list[#list + 1] = name
end

-- One new or refreshed aura on you.
local function noticed(aura)
    local name = plain(aura.name)
    local duration = plain(aura.duration)
    if not (name and plain(aura.isHelpful) and duration and duration >= MIN_DURATION) then
        return
    end
    local source = plain(aura.sourceUnit)
    if not source then
        unknown = unknown or {}
        addTo(unknown, name)
    elseif UnitIsPlayer(source) and not UnitIsUnit(source, "player") then
        local guid = plain(UnitGUID(source))
        local who, realm = UnitName(source)
        who, realm = plain(who), plain(realm)
        if not (guid and who) then
            return
        end
        if not last or last.guid ~= guid then
            last = {
                name = who,
                fullName = (realm and realm ~= "") and (who .. "-" .. realm) or who,
                guid = guid,
                spells = {},
            }
            unknown = nil
        end
        addTo(last.spells, name)
        last.thanked = false
    else
        return -- your own, or from an NPC
    end
    refresh()
end

-- Remembers every aura's expiration, so a rebuff (same aura, later expiration) is seen.
local function seed()
    wipe(expires)
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then
            break
        end
        local id = plain(aura.auraInstanceID)
        if id then
            expires[id] = plain(aura.expirationTime)
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, _, info)
    if event ~= "UNIT_AURA" or InCombatLockdown() then
        return
    end
    if info.isFullUpdate then
        seed() -- don't know what changed; everything already there counts as old
        return
    end
    for _, aura in ipairs(info.addedAuras or {}) do
        local id = plain(aura.auraInstanceID)
        if id then
            expires[id] = plain(aura.expirationTime)
        end
        noticed(aura)
    end
    for _, id in ipairs(info.updatedAuraInstanceIDs or {}) do
        local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", id)
        local ends = aura and plain(aura.expirationTime)
        if ends then
            local before = expires[id]
            expires[id] = ends
            if before and ends > before + 1 then
                noticed(aura)
            end
        end
    end
    for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
        expires[id] = nil
    end
end)

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function createBuffBack()
    local b = CreateFrame(
        "Button",
        "KindHandsBuffBackButton",
        window,
        "SecureActionButtonTemplate, UIPanelButtonTemplate"
    )
    b:SetSize(100, 22)
    b:SetText("Buff back")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetScript("PreClick", function(self)
        self:SetAttribute("type", nil)
        if InCombatLockdown() or not last then
            return
        end
        -- a token now (target, party, nameplate) or, failing that, target them by name
        -- so the next press finds them as your target
        local unit = plain(UnitTokenFromGUID(last.guid))
        if not unit then
            self:SetAttribute("type", "macro")
            self:SetAttribute("macrotext", "/targetexact " .. last.fullName)
            ns.say(("targeting %s: press again to buff"):format(last.name))
            return
        end
        local rank, far, buffable = ns.pickFor(unit)
        if rank then
            self:SetAttribute("type", "spell")
            self:SetAttribute("spell", rank.id)
            self:SetAttribute("unit", unit)
        elseif not buffable then
            ns.say(last.name .. " can't take buffs right now")
        elseif far then
            ns.say(last.name .. " is out of range")
        else
            ns.say(last.name .. " already has your buffs")
        end
    end)
    b:SetScript("PostClick", function(self)
        if not InCombatLockdown() then
            self:SetAttribute("type", nil)
        end
    end)
    return b
end

local function createThanks()
    local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    b:SetSize(100, 22)
    b:SetScript("OnClick", function()
        if last then
            C_ChatInfo.PerformEmote("THANK", last.fullName)
            last.thanked = true
            refresh()
        end
    end)
    return b
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function show(on)
    if InCombatLockdown() then
        ns.say("the window is for out of combat")
        return
    end
    window:SetShown(on)
end

local function createWindow()
    window = CreateFrame("Frame", "KindHandsWindow", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(240, 120)
    window:SetPoint(
        db.point or "CENTER",
        UIParent,
        db.relativePoint or "CENTER",
        db.x or 0,
        db.y or 0
    )
    window:SetFrameStrata("MEDIUM")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
    end)
    window:Hide()
    window.TitleText:SetText("KindHands")
    -- the template's X hides the window directly; go through the combat check
    window.CloseButton:SetScript("OnClick", function()
        show(false)
    end)
    -- Escape closes it too; safe since it's never open in combat
    tinsert(UISpecialFrames, "KindHandsWindow")

    whoText = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whoText:SetPoint("TOPLEFT", 14, -32)
    whoText:SetPoint("RIGHT", -14, 0)
    whoText:SetJustifyH("LEFT")
    spellText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellText:SetPoint("TOPLEFT", whoText, "BOTTOMLEFT", 0, -4)
    spellText:SetPoint("RIGHT", -14, 0)
    spellText:SetJustifyH("LEFT")
    unknownText = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    unknownText:SetPoint("TOPLEFT", spellText, "BOTTOMLEFT", 0, -4)
    unknownText:SetPoint("RIGHT", -14, 0)
    unknownText:SetJustifyH("LEFT")

    local buffBack = createBuffBack()
    buffBack:SetPoint("BOTTOMLEFT", 12, 10)
    thanksButton = createThanks()
    thanksButton:SetPoint("BOTTOMRIGHT", -12, 10)

    window:SetScript("OnShow", function()
        if not resuming then
            last, unknown = nil, nil -- only buffs from while it's open
        end
        resuming = false
        seed()
        events:RegisterUnitEvent("UNIT_AURA", "player")
        refresh()
    end)
    window:SetScript("OnHide", function()
        events:UnregisterEvent("UNIT_AURA")
    end)
end

function ns.toggleWindow()
    show(not window:IsShown())
end

-- also listed in the minimap's addon menu (AddonCompartmentFunc in the .toc)
function KindHands_ToggleWindow()
    ns.toggleWindow()
end

---------------------------------------------------------------------------
-- Minimap button (same as SpaceFish's: drag around the rim, first run picks a gap)
---------------------------------------------------------------------------
local minimapButton

local function placeMinimapButton()
    local a = math.rad(db.minimapAngle or 220)
    local r = Minimap:GetWidth() / 2 + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- Angles (degrees) of other small frames on the minimap's rim.
local function occupiedAngles()
    local mx, my = Minimap:GetCenter()
    local ms = Minimap:GetEffectiveScale()
    local r = Minimap:GetWidth() / 2 * ms
    local angles = {}
    for _, parent in ipairs({ Minimap, MinimapCluster }) do
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
    return angles
end

local function autoPlaceMinimapButton()
    local taken = occupiedAngles()
    local bestAngle, bestGap = 220, -1
    for step = 0, 71 do
        local a = (220 + step * 5) % 360
        local gap = 180
        for _, t in ipairs(taken) do
            gap = math.min(gap, math.abs((a - t + 180) % 360 - 180))
        end
        if gap > bestGap then
            bestAngle, bestGap = a, gap
        end
    end
    db.minimapAngle = bestAngle
    placeMinimapButton()
end

local function createMinimapButton()
    local b = CreateFrame("Button", "KindHandsMinimapButton", Minimap)
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
    icon:SetTexture(ICON)
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
    b:SetScript("OnClick", ns.toggleWindow)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("KindHands")
        GameTooltip:AddLine("Click: window to buff back and thank whoever buffs you.", 1, 1, 1)
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
-- Load, combat
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg)
    if event == "PLAYER_REGEN_DISABLED" then
        -- the last moment before the lockdown: close now, open again after
        if window:IsShown() then
            reopen = true
            window:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if reopen then
            reopen, resuming = false, true
            window:Show()
        end
    elseif event == "PLAYER_LOGIN" then
        if not db.minimapAngle then
            -- first run: wait for other addons to place their buttons, then avoid them
            C_Timer.After(2, autoPlaceMinimapButton)
        end
    elseif arg == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        KindHandsDB = KindHandsDB or {}
        KindHandsDB.window = KindHandsDB.window or {}
        db = KindHandsDB.window
        createWindow()
        createMinimapButton()
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end)
