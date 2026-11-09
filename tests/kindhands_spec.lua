-- KindHands' buff choice (KindHands/Logic.lua). Plain data only: no game API is
-- faked here, so these test our rules, not guesses about the client.
local ns = {}
assert(loadfile("KindHands/Logic.lua"))("KindHands", ns)
local Logic = ns.Logic

local KINGS, MIGHT, WISDOM = 20217, 19740, 19742
local GREATER_MIGHT = 25782
local AI, ICE_ARMOR, FROST_ARMOR, MAGE_ARMOR = 1459, 7302, 168, 6117
local MOTW, THORNS, OMEN = 1126, 467, 16864
local FORT, SPIRIT, INNER_FIRE = 1243, 14752, 588

local function set(list)
    local out = {}
    for _, id in ipairs(list or {}) do
        out[id] = true
    end
    return out
end

local function unit(class, opts)
    opts = opts or {}
    return {
        class = class,
        power = opts.power
            or (class == "WARRIOR" and "RAGE" or class == "ROGUE" and "ENERGY")
            or "MANA",
        level = opts.level or 30,
        isMe = opts.isMe or false,
        has = set(opts.has),
        mine = set(opts.mine),
    }
end

-- one rank per buff, learned at level 1, with the buff's own ID
local function knows(...)
    local known = {}
    for _, id in ipairs({ ... }) do
        known[id] = { { id = id, level = 1 } }
    end
    return known
end

-- the first choice's ID (what the button casts), or nil
local function first(class, target, known, onlySuitable)
    if onlySuitable == nil then
        onlySuitable = true
    end
    local options = Logic.candidates(class, target, known, onlySuitable)
    return options[1] and options[1].id
end

describe("Paladin blessings", function()
    local all = knows(KINGS, MIGHT, WISDOM)
    local noKings = knows(MIGHT, WISDOM)

    it("gives Kings first when known", function()
        assert.equal(KINGS, first("PALADIN", unit("MAGE"), all))
    end)

    it("gives Might to Warriors, Rogues and Paladins", function()
        for _, class in ipairs({ "WARRIOR", "ROGUE", "PALADIN" }) do
            assert.equal(MIGHT, first("PALADIN", unit(class), noKings), class)
        end
    end)

    it("gives Might to Druids in cat or bear form, Wisdom otherwise", function()
        assert.equal(MIGHT, first("PALADIN", unit("DRUID", { power = "ENERGY" }), noKings))
        assert.equal(MIGHT, first("PALADIN", unit("DRUID", { power = "RAGE" }), noKings))
        assert.equal(WISDOM, first("PALADIN", unit("DRUID", { power = "MANA" }), noKings))
    end)

    it("gives Wisdom to casters and Hunters", function()
        for _, class in ipairs({ "MAGE", "PRIEST", "WARLOCK", "SHAMAN", "HUNTER" }) do
            assert.equal(WISDOM, first("PALADIN", unit(class), noKings), class)
        end
    end)

    it("gives yourself Might", function()
        assert.equal(MIGHT, first("PALADIN", unit("PALADIN", { isMe = true }), noKings))
    end)

    it("gives a caster Might while you don't know Wisdom yet", function()
        assert.equal(MIGHT, first("PALADIN", unit("MAGE"), knows(MIGHT)))
    end)

    it("gives a caster nothing more once Wisdom is on them, from anyone", function()
        local target = unit("MAGE", { has = { KINGS, WISDOM } })
        assert.is_nil(first("PALADIN", target, all))
        assert.is_nil(first("PALADIN", unit("MAGE", { has = { WISDOM } }), noKings))
    end)

    it("hands out Might to a caster with the option off", function()
        local target = unit("MAGE", { has = { KINGS, WISDOM } })
        assert.equal(MIGHT, first("PALADIN", target, all, false))
    end)

    it("doesn't stand Might in for Wisdom when the caster is too low for Wisdom", function()
        local known = {
            [MIGHT] = { { id = MIGHT, level = 4 } },
            [WISDOM] = { { id = WISDOM, level = 14 } },
        }
        assert.is_nil(first("PALADIN", unit("MAGE", { level = 2 }), known))
    end)

    it("gives an unknown class no Might or Wisdom with the option on", function()
        assert.is_nil(first("PALADIN", unit(nil, { power = nil }), noKings))
    end)

    it("never gives Wisdom to a Warrior or Rogue", function()
        local target = unit("WARRIOR", { has = { MIGHT } })
        assert.is_nil(first("PALADIN", target, noKings))
        assert.is_nil(first("PALADIN", unit("ROGUE"), knows(WISDOM)))
    end)

    it("doesn't replace one of your own Blessings", function()
        local target = unit("MAGE", { has = { MIGHT }, mine = { MIGHT } })
        assert.is_nil(first("PALADIN", target, all))
    end)

    it("counts a Greater Blessing as having it", function()
        local target = unit("WARRIOR", { has = { GREATER_MIGHT } })
        assert.equal(KINGS, first("PALADIN", target, all))
        assert.is_nil(first("PALADIN", target, knows(MIGHT)))
    end)
end)

describe("other classes", function()
    it("Mage: Arcane Intellect only for mana users unless the option is off", function()
        assert.equal(AI, first("MAGE", unit("PRIEST"), knows(AI)))
        assert.is_nil(first("MAGE", unit("WARRIOR"), knows(AI)))
        assert.equal(AI, first("MAGE", unit("WARRIOR"), knows(AI), false))
    end)

    it("Mage: Ice Armor on yourself, any armor counts", function()
        local known = knows(AI, ICE_ARMOR, FROST_ARMOR)
        local me = unit("MAGE", { isMe = true, has = { AI } })
        assert.equal(ICE_ARMOR, first("MAGE", me, known))
        me.has[MAGE_ARMOR] = true
        assert.is_nil(first("MAGE", me, known))
    end)

    it("Druid: Thorns on Warriors and yourself only", function()
        local known = knows(MOTW, THORNS, OMEN)
        assert.equal(THORNS, first("DRUID", unit("WARRIOR", { has = { MOTW } }), known))
        assert.is_nil(first("DRUID", unit("MAGE", { has = { MOTW } }), known))
        local me = unit("DRUID", { isMe = true, has = { MOTW } })
        assert.equal(THORNS, first("DRUID", me, known))
    end)

    it("never casts a self-only buff on someone else, option or not", function()
        local target = unit("WARRIOR", { has = { FORT } })
        local known = knows(FORT, SPIRIT, INNER_FIRE)
        assert.is_nil(first("PRIEST", target, known))
        assert.equal(SPIRIT, first("PRIEST", target, known, false))
        target.has[SPIRIT] = true
        assert.is_nil(first("PRIEST", target, known, false))
    end)

    it("Rogues and Warriors have nothing to give (Battle Shout is a combat shout)", function()
        assert.is_nil(first("ROGUE", unit("WARRIOR"), {}))
        assert.is_nil(first("WARRIOR", unit("WARRIOR", { isMe = true }), knows(6673)))
    end)

    it("an unknown class still gets buffs for anyone", function()
        local target = unit(nil, { power = nil })
        assert.equal(MOTW, first("DRUID", target, knows(MOTW, THORNS)))
        assert.equal(KINGS, first("PALADIN", target, knows(KINGS, MIGHT, WISDOM)))
    end)
end)

describe("ranks", function()
    local ranks = { { id = 1, level = 4 }, { id = 2, level = 12 }, { id = 3, level = 22 } }

    it("picks the highest rank at most 10 levels above the target", function()
        assert.equal(3, Logic.bestRank(ranks, 30).id)
        assert.equal(3, Logic.bestRank(ranks, 12).id)
        assert.equal(2, Logic.bestRank(ranks, 11).id)
        assert.equal(1, Logic.bestRank(ranks, 1).id)
    end)

    it("picks the best rank when the level is unknown", function()
        assert.equal(3, Logic.bestRank(ranks, 0).id)
    end)

    it("has nothing when every rank is too high", function()
        assert.is_nil(Logic.bestRank({ { id = 9, level = 20 } }, 5))
    end)

    it("skips a buff the target is too low for", function()
        local known =
            { [KINGS] = { { id = KINGS, level = 20 } }, [MIGHT] = { { id = MIGHT, level = 4 } } }
        assert.equal(MIGHT, first("PALADIN", unit("WARRIOR", { level = 5 }), known))
    end)
end)
