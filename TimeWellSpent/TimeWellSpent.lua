-- TimeWellSpent: /played for every character on the account, by class.
--
-- Each login asks the server for /played (the reply's chat lines are hidden, since we
-- asked, not the player). The current character's time then counts up from that reply,
-- and the estimate is saved on logout, so totals are never a session behind. The next
-- login's server reply replaces the estimate.
local _, ns = ...
local Logic = ns.Logic

local db -- TimeWellSpentDB
local playerKey
local baseline, baselineAt -- server's /played for this character, and GetTime() of the reply
local window, listBox, totalText, ticker

local ROW_HEIGHT = 18

local function classColor(class)
    return RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
end

-- The saved characters, with the current one's time counted up to now.
local function currentChars()
    if baseline and db.chars[playerKey] then
        db.chars[playerKey].played = baseline + (GetTime() - baselineAt)
    end
    return db.chars
end

---------------------------------------------------------------------------
-- Asking for /played without the chat lines
---------------------------------------------------------------------------
-- Chat frames print TIME_PLAYED_MSG (it's in the SYSTEM message group). While our own
-- request is out, the chat frames that listen for it stop listening; they listen again
-- right after the reply, or after a few seconds if none comes. A /played typed by the
-- player still prints as usual.
local muted

local function unmute()
    if not muted then
        return
    end
    for _, frame in ipairs(muted) do
        frame:RegisterEvent("TIME_PLAYED_MSG")
    end
    muted = nil
end

local function requestPlayed()
    if not muted then
        muted = {}
        for _, name in ipairs(CHAT_FRAMES) do
            local frame = _G[name]
            if frame and frame:IsEventRegistered("TIME_PLAYED_MSG") then
                frame:UnregisterEvent("TIME_PLAYED_MSG")
                muted[#muted + 1] = frame
            end
        end
        C_Timer.After(5, unmute)
    end
    RequestTimePlayed()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local refresh

StaticPopupDialogs["TIMEWELLSPENT_FORGET"] = {
    text = "Forget %s's played time?",
    button1 = "Forget",
    button2 = "Cancel",
    OnAccept = function(_, key)
        db.chars[key] = nil
        refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function initRow(row, data)
    if not row.label then
        row:SetHeight(ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetAllPoints()
        row.bar:SetFrameLevel(row:GetFrameLevel())
        row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row.bar:SetMinMaxValues(0, 1)
        row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", -4, 0)
        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.label:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function(self, button)
            local d = self.data
            if d.group and button == "LeftButton" then
                db.collapsed[d.group.class] = not db.collapsed[d.group.class] or nil
                refresh()
            elseif d.key and button == "RightButton" and d.key ~= playerKey then
                StaticPopup_Show("TIMEWELLSPENT_FORGET", d.key, nil, d.key)
            end
        end)
        row:SetScript("OnEnter", function(self)
            local d = self.data
            if not d.key then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(d.key, 1, 1, 1)
            GameTooltip:AddLine(
                ("Level %s %s"):format(d.char.level or "?", d.char.className or ""),
                0.8,
                0.8,
                0.8
            )
            if d.key == playerKey then
                GameTooltip:AddLine("Playing now", 0.5, 1, 0.5)
            elseif d.char.updated then
                GameTooltip:AddLine(
                    "Last played " .. date("%Y-%m-%d", d.char.updated),
                    0.8,
                    0.8,
                    0.8
                )
                GameTooltip:AddLine("Right-click to forget", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end
    row.data = data
    if data.group then
        local g = data.group
        local color = classColor(g.class)
        row.label:SetPoint("LEFT", 4, 0)
        row.label:SetFontObject("GameFontNormal")
        row.label:SetText(
            ("%s %s"):format(
                db.collapsed[g.class] and "+" or "-",
                color:WrapTextInColorCode(g.className)
            )
        )
        row.value:SetFontObject("GameFontNormal")
        row.value:SetText(
            ("%s  |cff999999%4.1f%%|r"):format(Logic.duration(g.played), data.share * 100)
        )
        local r, g, b = color:GetRGB()
        row.bar:SetStatusBarColor(r, g, b, 0.35)
        row.bar:SetValue(data.bar)
        row.bar:Show()
    else
        local c = data.char
        local name = c.name or data.key
        if c.realm and c.realm ~= GetRealmName() then
            name = name .. "-" .. c.realm
        end
        if data.key == playerKey then
            name = name .. " |cff80ff80*|r"
        end
        row.label:SetPoint("LEFT", 20, 0)
        row.label:SetFontObject("GameFontHighlightSmall")
        row.label:SetText(("%s |cff999999%s|r"):format(name, c.level or ""))
        row.value:SetFontObject("GameFontHighlightSmall")
        row.value:SetText(Logic.duration(c.played))
        row.bar:Hide()
    end
end

function refresh()
    if not (window and window:IsShown()) then
        return
    end
    local total, classes = Logic.breakdown(currentChars())
    local top = classes[1] and classes[1].played or 0
    local rows, count = {}, 0
    for _, group in ipairs(classes) do
        rows[#rows + 1] = {
            group = group,
            share = total > 0 and group.played / total or 0,
            bar = top > 0 and group.played / top or 0,
        }
        if not db.collapsed[group.class] then
            for _, entry in ipairs(group.chars) do
                rows[#rows + 1] = { key = entry.key, char = entry.char }
            end
        end
        count = count + #group.chars
    end
    listBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    totalText:SetText(
        ("Total: |cffffffff%s|r  (%d characters)"):format(Logic.duration(total), count)
    )
end

local function createWindow()
    window = CreateFrame("Frame", "TimeWellSpentWindow", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(340, 400)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, "TimeWellSpentWindow") -- Escape closes it

    local title = window.TitleText or window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not window.TitleText then
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("TimeWellSpent: /played")

    listBox = CreateFrame("Frame", nil, window, "WowScrollBoxList")
    listBox:SetPoint("TOPLEFT", 12, -30)
    listBox:SetPoint("BOTTOMRIGHT", -28, 32)
    local bar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(listBox, bar, view)

    totalText = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalText:SetPoint("BOTTOMLEFT", 16, 12)

    window:SetScript("OnShow", function()
        refresh()
        ticker = C_Timer.NewTicker(30, refresh) -- the current character's time counts up
    end)
    window:SetScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
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
local function saveCharacter()
    local char = db.chars[playerKey] or {}
    db.chars[playerKey] = char
    char.name = UnitName("player")
    char.realm = GetRealmName()
    char.className, char.class = UnitClass("player")
    char.level = UnitLevel("player")
    char.updated = time()
    return char
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        TimeWellSpentDB = TimeWellSpentDB or {}
        db = TimeWellSpentDB
        db.chars = db.chars or {}
        db.collapsed = db.collapsed or {}
        playerKey = UnitName("player") .. "-" .. GetRealmName()
        requestPlayed()
    elseif event == "TIME_PLAYED_MSG" then
        local total = ...
        baseline, baselineAt = total, GetTime()
        saveCharacter().played = total
        C_Timer.After(0, unmute) -- after every frame has seen this reply
        refresh()
    elseif event == "PLAYER_LEVEL_UP" then
        if db.chars[playerKey] then
            db.chars[playerKey].level = ...
        end
    elseif event == "PLAYER_LOGOUT" then
        if baseline then
            saveCharacter()
            currentChars()
        end
    end
end)
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TIME_PLAYED_MSG")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_LOGOUT")

-- also listed in the minimap's addon menu (AddonCompartmentFunc in the .toc)
function TimeWellSpent_Toggle()
    toggle()
end

SLASH_TIMEWELLSPENT1 = "/aplayed"
SLASH_TIMEWELLSPENT2 = "/tws"
SlashCmdList.TIMEWELLSPENT = toggle
