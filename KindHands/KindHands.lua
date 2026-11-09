-- KindHands: one button that casts the next buff someone is missing.
-- Nothing runs in the background: the choice is made when you press it (PreClick
-- on a secure button), out of combat only. Order: your friendly target, you,
-- then your party. A buff counts as there whenever it's there at all.
local ADDON = ...
local BANK = Enum.SpellBookSpellBank.Player
local BUTTON = "KindHandsButton"

-- Rank 1 spell IDs (Classic numbering); names come from the client, ranks from
-- your spellbook. `who`: "any", "mana", "melee", "caster", "self", or a set of
-- classes; it's what suits them (see the "only buffs that suit them" option).
-- `me` overrides `who` for yourself. `also`: auras that count as having it
-- (group versions, other armors). `blessing`: one per Paladin per unit.
local BUFFS = {
    PALADIN = {
        { id = 20217, who = "any", blessing = true, also = { 25898 } }, -- Kings
        { id = 19740, who = "melee", me = true, blessing = true, also = { 25782 } }, -- Might
        { id = 19742, who = "caster", me = false, blessing = true, also = { 25894 } }, -- Wisdom
    },
    PRIEST = {
        { id = 1243, who = "any", also = { 21562 } }, -- Power Word: Fortitude
        { id = 14752, who = "mana", also = { 27681 } }, -- Divine Spirit
        { id = 588, who = "self" }, -- Inner Fire
    },
    MAGE = {
        { id = 1459, who = "mana", also = { 23028 } }, -- Arcane Intellect
        { id = 7302, who = "self", also = { 168, 6117 } }, -- Ice Armor (Frost/Mage Armor count)
        { id = 168, who = "self", also = { 7302, 6117 } }, -- Frost Armor
    },
    DRUID = {
        { id = 1126, who = "any", also = { 21849 } }, -- Mark of the Wild
        { id = 467, who = { WARRIOR = true }, me = true }, -- Thorns
        { id = 16864, who = "self" }, -- Omen of Clarity
    },
    WARLOCK = {
        { id = 706, who = "self", also = { 687 } }, -- Demon Armor
        { id = 687, who = "self", also = { 706 } }, -- Demon Skin
    },
    SHAMAN = { { id = 324, who = "self" } }, -- Lightning Shield
    WARRIOR = { { id = 6673, who = "self" } }, -- Battle Shout
    HUNTER = { { id = 19506, who = "self" } }, -- Trueshot Aura
}

local NO_MANA = { WARRIOR = true, ROGUE = true }
-- Might goes to these; Druids too while in a form that uses rage or energy.
-- Everyone else gets Wisdom. Hunters: Might is melee attack power only.
local MELEE = { WARRIOR = true, ROGUE = true, PALADIN = true }
local MANA_USER = { who = "mana" } -- for fits(): does the unit use mana at all
local PARTY = { "party1", "party2", "party3", "party4" }

local playerClass
local db
local ranks -- spell name -> its ranks you know, lowest level first; nil = rebuild

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
    local wanted = {}
    for _, entry in ipairs(BUFFS[playerClass] or {}) do
        local name = C_Spell.GetSpellName(entry.id)
        if name then
            wanted[name] = true
        end
    end
    local found = {}
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
            if
                item
                and item.itemType == Enum.SpellBookItemType.Spell
                and item.spellID
                and wanted[item.name]
            then
                local list = found[item.name] or {}
                found[item.name] = list
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

-- Highest rank the unit can take: a rank goes on someone up to 10 levels below it.
local function bestRank(name, unit)
    local list = ranks[name]
    if not list then
        return nil
    end
    local level = plain(UnitLevel(unit)) or 0
    if level <= 0 then -- unknown or skull: try the best, the game says if it's too high
        return list[#list]
    end
    for i = #list, 1, -1 do
        if list[i].level - 10 <= level then
            return list[i]
        end
    end
    return nil
end

local function aura(unit, id)
    local name = C_Spell.GetSpellName(id)
    return name and C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL")
end

local function has(unit, entry)
    if aura(unit, entry.id) then
        return true
    end
    for _, id in ipairs(entry.also or {}) do
        if aura(unit, id) then
            return true
        end
    end
    return false
end

local function fromMe(data)
    local source = data and plain(data.sourceUnit)
    return source and UnitIsUnit(source, "player") or false
end

-- Whether the unit carries one of your Blessings (each Paladin's replace each other).
local function hasMyBlessing(unit)
    for _, entry in ipairs(BUFFS.PALADIN) do
        if fromMe(aura(unit, entry.id)) then
            return true
        end
        for _, id in ipairs(entry.also) do
            if fromMe(aura(unit, id)) then
                return true
            end
        end
    end
    return false
end

local function fits(entry, unit, isMe)
    if isMe and entry.me ~= nil then
        return entry.me
    end
    local who = entry.who
    if who == "self" then
        return isMe
    elseif who == "any" then
        return true
    end
    local class = plain(select(2, UnitClass(unit)))
    if not class then
        return false
    elseif who == "mana" then
        return not NO_MANA[class]
    elseif who == "melee" or who == "caster" then
        local melee = MELEE[class]
            or class == "DRUID" and plain(UnitPowerType(unit)) ~= Enum.PowerType.Mana
            or false
        return melee == (who == "melee")
    end
    return who[class] or false
end

-- The rank to cast on the unit, or nil when it has everything it can get from you.
-- First the buffs that suit them. Then, as better than nothing: any Blessing (Might
-- on a caster while you don't have Wisdom yet), or with the "only buffs that suit
-- them" option off, any buff of yours they lack (Arcane Intellect on a Warrior).
local function pickFor(unit, isMe)
    local blessed -- checked lazily: only Paladins need it
    for pass = 1, 2 do
        for _, entry in ipairs(BUFFS[playerClass] or {}) do
            local name = C_Spell.GetSpellName(entry.id)
            local wanted
            if pass == 1 then
                wanted = fits(entry, unit, isMe)
            else
                -- with the option on, never a mana buff (Wisdom) on a Warrior or Rogue
                wanted = entry.who ~= "self"
                    and not fits(entry, unit, isMe)
                    and (
                        not db.onlySuitable
                        or entry.blessing and (entry.who ~= "caster" or fits(MANA_USER, unit))
                    )
            end
            if wanted and name and ranks[name] and not has(unit, entry) then
                if entry.blessing and blessed == nil then
                    blessed = hasMyBlessing(unit)
                end
                local rank = not (entry.blessing and blessed) and bestRank(name, unit)
                if rank and (isMe or plain(C_Spell.IsSpellInRange(rank.id, unit)) ~= false) then
                    return rank
                end
            end
        end
    end
    return nil
end

local function canBuff(unit)
    return UnitExists(unit)
        and UnitIsConnected(unit)
        and UnitIsVisible(unit)
        and not UnitIsDeadOrGhost(unit)
        and UnitCanAssist("player", unit)
end

-- Friendly target, then you, then your party. Returns rank, unit.
local function pick()
    ranks = ranks or buildRanks()
    if canBuff("target") and not UnitIsUnit("target", "player") then
        local rank = pickFor("target", false)
        if rank then
            return rank, "target"
        end
    end
    local rank = pickFor("player", true)
    if rank then
        return rank, "player"
    end
    for _, unit in ipairs(PARTY) do
        if canBuff(unit) then
            rank = pickFor(unit, false)
            if rank then
                return rank, unit
            end
        end
    end
    return nil
end

local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyUp")
button:SetAttribute("useOnKeyDown", false) -- act on release, same for keys and /click

button:SetScript("PreClick", function(self)
    if InCombatLockdown() then
        say("can't pick buffs in combat")
        return
    end
    local rank, unit = pick()
    if rank then
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", rank.id)
        self:SetAttribute("unit", unit)
    else
        self:SetAttribute("type", nil)
        say(BUFFS[playerClass] and "everyone has your buffs" or "no buffs for your class")
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
    local rank, unit = pick()
    local next_ = rank
            and unit
            and ("%s (%s) on %s"):format(
                C_Spell.GetSpellName(rank.id) or "?",
                C_Spell.GetSpellSubtext(rank.id) or "",
                UnitName(unit) or unit
            )
        or "nothing"
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
        "On: mana buffs only for mana users, Might for melee, Wisdom for casters (a "
            .. "Blessing they can't make full use of is still given when it's all you have). "
            .. "Off: once they have what suits them, give them anything else of yours they "
            .. "lack, e.g. Arcane Intellect on a Warrior passing by."
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
            if next(ranks) and not reachable() then
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
        if BUFFS[class] then -- no reminder for classes without buffs (Rogues)
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
        end
    end
end)
