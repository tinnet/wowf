-- KindHands' buff choice: plain data in, plain data out, no game API calls, so
-- tests/ can run it under busted. KindHands.lua reads the game and calls in here.
local _, ns = ...
local Logic = {}
ns.Logic = Logic

-- Rank 1 spell IDs (Classic numbering); names come from the client, ranks from
-- your spellbook. `who` is what suits them: "any", "mana", "melee", "caster",
-- "self", or a set of classes. `me` overrides `who` for yourself. `also`: auras that
-- count as having it (group versions, other armors). `blessing`: each Paladin's
-- Blessings replace each other, so one of yours per unit. `standsIn`: with "only buffs
-- that suit them" on, this may go to someone that buff suits while you don't know it.
Logic.BUFFS = {
    PALADIN = {
        { id = 20217, who = "any", blessing = true, also = { 25898 } }, -- Kings
        -- Might stands in for Wisdom (better than nothing) while you don't know Wisdom
        {
            id = 19740,
            who = "melee",
            me = true,
            blessing = true,
            also = { 25782 },
            standsIn = 19742,
        },
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
    -- No Warrior entry: Battle Shout is a 2 minute combat shout, not a buff you hand
    -- out between fights. Rogues have nothing either.
    HUNTER = { { id = 19506, who = "self" } }, -- Trueshot Aura
}

local NO_MANA = { WARRIOR = true, ROGUE = true }
-- Might goes to these, and to Druids in a form that uses rage or energy; everyone
-- else gets Wisdom. Hunters: in Classic, Might is melee attack power only.
local MELEE = { WARRIOR = true, ROGUE = true, PALADIN = true }

-- Every spell ID the class's buffs look for on a unit (the buffs and their `also`).
function Logic.watchedIDs(class)
    local ids = {}
    for _, entry in ipairs(Logic.BUFFS[class] or {}) do
        ids[#ids + 1] = entry.id
        for _, id in ipairs(entry.also or {}) do
            ids[#ids + 1] = id
        end
    end
    return ids
end

-- A unit, as KindHands.lua reads it:
--   class  "WARRIOR", ... or nil when unknown
--   power  power token: "MANA", "RAGE", "ENERGY", ... or nil
--   level  number, 0 when unknown (skull)
--   isMe   it's you
--   has    { [spellID] = true } auras on it, from anyone
--   mine   { [spellID] = true } the ones you cast

local function usesMana(unit)
    return unit.class ~= nil and not NO_MANA[unit.class]
end

local function isMelee(unit)
    return MELEE[unit.class] or unit.class == "DRUID" and unit.power ~= nil and unit.power ~= "MANA"
end

-- Whether the buff suits the unit.
function Logic.fits(entry, unit)
    if unit.isMe and entry.me ~= nil then
        return entry.me
    end
    local who = entry.who
    if who == "self" then
        return unit.isMe or false
    elseif who == "any" then
        return true
    elseif not unit.class then
        return false
    elseif who == "mana" then
        return usesMana(unit)
    elseif who == "melee" then
        return isMelee(unit) or false
    elseif who == "caster" then
        return not isMelee(unit)
    end
    return who[unit.class] or false
end

-- Highest rank the unit can take: a rank goes on someone up to 10 levels below it.
-- `ranks` is lowest level first. Unknown level (0): the best, the game says if not.
function Logic.bestRank(ranks, level)
    if not ranks or #ranks == 0 then
        return nil
    end
    if not level or level <= 0 then
        return ranks[#ranks]
    end
    for i = #ranks, 1, -1 do
        if ranks[i].level - 10 <= level then
            return ranks[i]
        end
    end
    return nil
end

local function present(entry, unit)
    if unit.has[entry.id] then
        return true
    end
    for _, id in ipairs(entry.also or {}) do
        if unit.has[id] then
            return true
        end
    end
    return false
end

local function hasMyBlessing(unit)
    for _, entry in ipairs(Logic.BUFFS.PALADIN) do
        if unit.mine[entry.id] then
            return true
        end
        for _, id in ipairs(entry.also or {}) do
            if unit.mine[id] then
                return true
            end
        end
    end
    return false
end

-- The ranks to try on the unit, best choice first (the caller skips ones out of
-- range). `known` maps a buff's rank 1 ID to the ranks you know, lowest level first.
-- First the buffs that suit them. Then, with onlySuitable on, only a stand-in for a
-- suitable buff you don't know yet (Might on a caster before you learn Wisdom); with
-- it off, any buff of yours they lack.
function Logic.candidates(class, unit, known, onlySuitable)
    local byID = {}
    for _, entry in ipairs(Logic.BUFFS[class] or {}) do
        byID[entry.id] = entry
    end
    local out = {}
    local blessed = hasMyBlessing(unit)
    for pass = 1, 2 do
        for _, entry in ipairs(Logic.BUFFS[class] or {}) do
            local suits = Logic.fits(entry, unit)
            local wanted
            if pass == 1 then
                wanted = suits
            else
                local stood = entry.standsIn and byID[entry.standsIn]
                wanted = not suits
                    and entry.who ~= "self"
                    and (
                        not onlySuitable
                        or stood ~= nil and not known[stood.id] and Logic.fits(stood, unit)
                    )
            end
            if wanted and not present(entry, unit) and not (entry.blessing and blessed) then
                local rank = Logic.bestRank(known[entry.id], unit.level)
                if rank then
                    out[#out + 1] = rank
                end
            end
        end
    end
    return out
end
