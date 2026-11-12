-- KindHands: one button that casts the next buff someone is missing.
-- Nothing runs in the background: the choice is made when you press it (PreClick
-- on a secure button), out of combat only. Order: your friendly target, you,
-- then your party. A buff counts as there whenever it's there at all.
-- This file reads the game; the choosing itself is in Logic.lua (tested in tests/).
local ADDON, ns = ...
local Logic = ns.Logic
local BUFFS = Logic.BUFFS
local BANK = Enum.SpellBookSpellBank.Player
local BUTTON = "KindHandsButton"
local PARTY = { "party1", "party2", "party3", "party4" }

local playerClass
local db
local ranks -- buff's rank 1 ID -> the ranks you know, lowest level first; nil = rebuild

local function say(msg)
    UIErrorsFrame:AddExternalErrorMessage("KindHands: " .. msg)
end

-- issecretvalue only exists on clients with secret values; treat those as unknown.
local function plain(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

local function buildRanks()
    local wanted = {} -- spell name -> its buff's rank 1 ID
    for _, entry in ipairs(BUFFS[playerClass] or {}) do
        local name = C_Spell.GetSpellName(entry.id)
        if name then
            wanted[name] = entry.id
        end
    end
    local found = {}
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
            local key = item
                and item.itemType == Enum.SpellBookItemType.Spell
                and item.spellID
                and wanted[item.name]
            if key then
                local list = found[key] or {}
                found[key] = list
                list[#list + 1] = {
                    id = item.spellID,
                    level = C_SpellBook.GetSpellBookItemLevelLearned(slot, BANK) or 0,
                }
            end
        end
    end
    for _, list in pairs(found) do
        table.sort(list, function(a, b)
            return a.level < b.level
        end)
    end
    return found
end

-- Spell name -> the watched ID it stands for (buffs and their `also`); with ranks.
local watchedNames

local function buildWatchedNames()
    local names = {}
    for _, id in ipairs(Logic.watchedIDs(playerClass)) do
        local name = C_Spell.GetSpellName(id)
        if name then
            names[name] = id
        end
    end
    return names
end

-- The unit as plain data for Logic (see the field list there). Walks all buffs
-- instead of looking up by name: a name lookup returns only one of two same-named
-- auras (two Paladins' Wisdom), which could hide yours.
local function readUnit(unit, isMe)
    local data = {
        class = plain(select(2, UnitClass(unit))),
        power = plain(select(2, UnitPowerType(unit))),
        level = plain(UnitLevel(unit)) or 0,
        isMe = isMe,
        has = {},
        mine = {},
    }
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then
            break
        end
        local id = watchedNames[plain(aura.name) or ""]
        if id then
            data.has[id] = true
            local source = plain(aura.sourceUnit)
            if source and UnitIsUnit(source, "player") then
                data.mine[id] = true
            end
        end
    end
    return data
end

-- Whether the unit is close enough for the spell. Units out of sight (UnitIsVisible
-- false) are far away; for those the range check may not answer at all.
local function inRange(id, unit)
    return UnitIsVisible(unit) and plain(C_Spell.IsSpellInRange(id, unit)) ~= false
end

-- The rank to cast on the unit, or nil. Second return: true when it lacks something
-- of yours but is out of range for all of it.
local function pickFor(unit, isMe)
    local options = Logic.candidates(playerClass, readUnit(unit, isMe), ranks, db.onlySuitable)
    for _, rank in ipairs(options) do
        if isMe or inRange(rank.id, unit) then
            return rank
        end
    end
    return nil, #options > 0
end

-- Alive, online, friendly. Range is pickFor's business, so it can say who's too far.
local function canBuff(unit)
    return UnitExists(unit)
        and UnitIsConnected(unit)
        and not UnitIsDeadOrGhost(unit)
        and UnitCanAssist("player", unit)
end

local function prepare()
    ranks = ranks or buildRanks()
    watchedNames = watchedNames or buildWatchedNames()
end

-- Friendly target, then you, then your party. Returns rank, unit; or nil and the
-- names of those who lack something of yours but are out of range.
local function pick()
    prepare()
    local far = {}
    local function try(unit, isMe)
        local rank, tooFar = pickFor(unit, isMe)
        if tooFar then
            far[#far + 1] = UnitName(unit) or unit
        end
        return rank
    end
    if canBuff("target") and not UnitIsUnit("target", "player") then
        local rank = try("target", false)
        if rank then
            return rank, "target"
        end
    end
    local rank = db.buffSelf and try("player", true)
    if rank then
        return rank, "player"
    end
    for _, unit in ipairs(PARTY) do
        if canBuff(unit) and not UnitIsUnit(unit, "target") then
            rank = try(unit, false)
            if rank then
                return rank, unit
            end
        end
    end
    return nil, nil, far
end

-- Whether you know any buff the button could cast, given the "Also buff myself" option.
local function canGiveAnything()
    for _, entry in ipairs(BUFFS[playerClass] or {}) do
        if ranks[entry.id] and (db.buffSelf or entry.who ~= "self") then
            return true
        end
    end
    return false
end

-- Why a press casts nothing.
local function nothingToCast(far)
    if not BUFFS[playerClass] then
        return "no buffs for your class"
    elseif not canGiveAnything() then
        return "you don't know any buff to give yet"
    elseif #far > 0 then
        return "out of range: " .. table.concat(far, ", ")
    end
    return "everyone in reach has your buffs"
end

-- For Window.lua (buff back): the rank to cast on one unit, or nil and why not:
-- out of range (true/false), and whether it can take buffs at all.
function ns.pickFor(unit)
    prepare()
    if not canBuff(unit) then
        return nil, false, false
    end
    local rank, far = pickFor(unit, false)
    return rank, far, true
end
-- For Window.lua: a unit as Logic sees it, kept for when there's no unit for them later.
function ns.readUnit(unit)
    prepare()
    return readUnit(unit, false)
end

-- For Window.lua: the best rank for a unit read earlier, without a range check.
function ns.pickForData(data)
    prepare()
    return Logic.candidates(playerClass, data, ranks, db.onlySuitable)[1]
end
-- For Window.lua: the rank 1 ID KindHands watches for under this spell's name, or nil.
function ns.watchedID(spellID)
    prepare()
    return watchedNames[C_Spell.GetSpellName(spellID) or ""]
end
ns.say, ns.plain = say, plain

local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyUp")
button:SetAttribute("useOnKeyDown", false) -- act on release, same for keys and /click

button:SetScript("PreClick", function(self)
    if InCombatLockdown() then
        say("can't pick buffs in combat")
        return
    end
    local rank, unit, far = pick()
    if rank then
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", rank.id)
        self:SetAttribute("unit", unit)
    else
        self:SetAttribute("type", nil)
        say(nothingToCast(far))
    end
end)

-- Clear after each cast so nothing stale is cast if the next press is in combat.
button:SetScript("PostClick", function(self)
    if not InCombatLockdown() then
        self:SetAttribute("type", nil)
    end
end)

BINDING_HEADER_KINDHANDS = "KindHands"
_G["BINDING_NAME_CLICK " .. BUTTON .. ":LeftButton"] = "Buff next missing"

local function chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99KindHands|r: " .. msg)
end

local MACRO_NAME = "KindHands"
local MACRO_ICON = "Spell_Holy_SealOfSacrifice"
local MACRO_BODY = "/click " .. BUTTON

-- Account-wide macro (each character still casts its own class's buffs), put on
-- the cursor to drop on a bar. Reuses an existing one, fixing its text if needed.
local function makeMacro()
    local index = GetMacroIndexByName(MACRO_NAME)
    if index == 0 then
        local account = GetNumMacros()
        if account >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
            chat("your account macros are full; delete one or use /click " .. BUTTON)
            return
        end
        index = CreateMacro(MACRO_NAME, MACRO_ICON, MACRO_BODY, false)
    elseif GetMacroBody(index) ~= MACRO_BODY then
        EditMacro(index, MACRO_NAME, MACRO_ICON, MACRO_BODY)
    end
    PickupMacro(index)
    chat("macro on your cursor: click an action bar slot to place it")
end

local function status()
    local rank, unit, far = pick()
    local next_ = rank
            and unit
            and ("%s (%s) on %s"):format(
                C_Spell.GetSpellName(rank.id) or "?",
                C_Spell.GetSpellSubtext(rank.id) or "",
                UnitName(unit) or unit
            )
        or ("nothing (" .. nothingToCast(far) .. ")")
    chat("next press casts " .. next_ .. ".")
    chat(
        "use it: /kindhands macro, or bind a key in Options > Keybindings > AddOns, "
            .. "or /click "
            .. BUTTON
            .. " in your own macro"
    )
end

SLASH_KINDHANDS1 = "/kindhands"
SlashCmdList.KINDHANDS = function(msg)
    if InCombatLockdown() then
        chat("not in combat")
    elseif msg:lower():match("^%s*macro%s*$") then
        makeMacro()
    elseif msg:lower():match("^%s*window%s*$") then
        ns.toggleWindow()
    else
        status()
    end
end

-- Whether the button can be used at all: a key bound to it, or any macro on your
-- bars that clicks it (ours or your own). Action slots 1-180 cover every bar page.
local function reachable()
    if GetBindingKey("CLICK " .. BUTTON .. ":LeftButton") then
        return true
    end
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if kind == "macro" and id then
            local body = GetMacroBody(id)
            if body and body:find(BUTTON, 1, true) then
                return true
            end
        end
    end
    return false
end

local function registerSettings()
    local category = Settings.RegisterVerticalLayoutCategory("KindHands")
    local onlySuitable = Settings.RegisterAddOnSetting(
        category,
        "KINDHANDS_ONLY_SUITABLE",
        "onlySuitable",
        db,
        Settings.VarType.Boolean,
        "Only buffs that suit them",
        Settings.Default.True
    )
    Settings.CreateCheckbox(
        category,
        onlySuitable,
        "On: only buffs that suit them: mana buffs for mana users, Might for melee, "
            .. "Wisdom for casters (Might for casters too until you learn Wisdom). "
            .. "Off: once they have what suits them, give them anything else of yours they "
            .. "lack, e.g. Arcane Intellect on a Warrior passing by."
    )

    local buffSelf = Settings.RegisterAddOnSetting(
        category,
        "KINDHANDS_BUFF_SELF",
        "buffSelf",
        db,
        Settings.VarType.Boolean,
        "Also buff myself",
        Settings.Default.True
    )
    Settings.CreateCheckbox(
        category,
        buffSelf,
        "On: when your target has everything (or you have no friendly target), buff "
            .. "yourself before your party, including self-only buffs like Inner Fire. "
            .. "Off: only ever buff others."
    )
    Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg)
    if event == "SPELLS_CHANGED" then
        ranks = nil -- rebuilt on the next press
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- once per login, after the bars and bindings have settled
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(5, function()
            ranks = ranks or buildRanks()
            -- only nag when you know at least one buff (not Rogues, not a Hunter without
            -- Trueshot Aura, ...) and nothing reaches the button
            if canGiveAnything() and not reachable() then
                chat(
                    "loaded, but there's no way to press it yet: bind a key "
                        .. "(Options > Keybindings > AddOns) or type /kindhands macro "
                        .. "and put the macro on a bar."
                )
            end
        end)
    elseif arg == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        KindHandsDB = KindHandsDB or {}
        db = KindHandsDB
        registerSettings()
        local _, class = UnitClass("player")
        playerClass = class
        self:RegisterEvent("SPELLS_CHANGED")
        if BUFFS[class] then -- no reminder for classes without buffs (Rogues, Warriors)
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
        end
    end
end)
