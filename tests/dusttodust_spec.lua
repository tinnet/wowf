-- DustToDust's arithmetic (DustToDust/Logic.lua) and tables (Data.lua). Plain data only.
local ns = {}
assert(loadfile("DustToDust/Data.lua"))("DustToDust", ns)
assert(loadfile("DustToDust/Logic.lua"))("DustToDust", ns)
local Logic, Data = ns.Logic, ns.Data

local WEAPON, ARMOR = Data.WEAPON, Data.ARMOR
local STRANGE_DUST, LESSER_ASTRAL, SMALL_GLIMMERING = 10940, 10998, 10978
local LARGE_BRILLIANT, NEXUS = 14344, 20725

local function near(expected, actual)
    assert.is_true(
        math.abs(expected - actual) < 1e-9,
        ("expected %s, got %s"):format(expected, actual)
    )
end

local function total(outcomes)
    local p = 0
    for _, o in ipairs(outcomes) do
        p = p + o.p
    end
    return p
end

describe("buckets", function()
    it("spread a green's quantities evenly", function()
        local key, outcomes = Logic.bucket(ARMOR, 2, 23)
        assert.equal("2:4:25", key)
        -- 75% 4-6 Strange Dust, 15% 1-2 Lesser Astral, 10% shard
        assert.same({ p = 0.25, mat = STRANGE_DUST, qty = 4 }, outcomes[1])
        assert.same({ p = 0.25, mat = STRANGE_DUST, qty = 6 }, outcomes[3])
        assert.same({ p = 0.075, mat = LESSER_ASTRAL, qty = 2 }, outcomes[5])
        assert.same({ p = 0.1, mat = SMALL_GLIMMERING, qty = 1 }, outcomes[6])
        near(1, total(outcomes))
    end)

    it("give weapons mostly essence, with their own chances from item level 51", function()
        local _, w = Logic.bucket(WEAPON, 2, 23)
        near(0.15, w[1].p * 3) -- dust 15%
        local _, w55 = Logic.bucket(WEAPON, 2, 55)
        near(0.22, w55[1].p * 4) -- 2-5 dust at 22%
        assert.equal(0.03, w55[#w55].p) -- shard 3%
        near(1, total(w55))
        local _, a55 = Logic.bucket(ARMOR, 2, 55)
        assert.equal(0.05, a55[#a55].p)
    end)

    it("are the same for rare armor and weapons, and epics below 40 count as rares", function()
        local ka = Logic.bucket(ARMOR, 3, 58)
        local kw, rare = Logic.bucket(WEAPON, 3, 58)
        assert.equal(ka, kw)
        assert.same({ p = 0.995, mat = LARGE_BRILLIANT, qty = 1 }, rare[1])
        assert.same({ p = 0.005, mat = NEXUS, qty = 1 }, rare[2])
        local _, epic = Logic.bucket(ARMOR, 4, 35)
        assert.equal(11138, epic[1].mat) -- Small Glowing Shard, like a rare of 31-35
        local _, epic63 = Logic.bucket(ARMOR, 4, 63)
        assert.same({ p = 0.5, mat = NEXUS, qty = 2 }, epic63[2])
    end)

    it("skip what can't be disenchanted", function()
        assert.is_nil(Logic.bucket(15, 2, 20)) -- miscellaneous
        assert.is_nil(Logic.bucket(ARMOR, 1, 20)) -- white
        assert.is_nil(Logic.bucket(ARMOR, 5, 60)) -- legendary
        assert.is_nil(Logic.bucket(WEAPON, 2, 30, 11288)) -- Greater Magic Wand
        assert.is_nil(Logic.bucket(ARMOR, 2, 0))
    end)

    it("cover every row of every table with chances adding up to 100%", function()
        for ilvl = 1, 70 do
            for _, class in ipairs({ ARMOR, WEAPON }) do
                for quality = 2, 4 do
                    local _, outcomes = Logic.bucket(class, quality, ilvl)
                    near(1, total(outcomes))
                end
            end
        end
    end)
end)

describe("skill needed", function()
    it("follows the item level", function()
        assert.equal(1, Logic.skillNeeded(5))
        assert.equal(1, Logic.skillNeeded(20))
        assert.equal(25, Logic.skillNeeded(21))
        assert.equal(200, Logic.skillNeeded(60))
        assert.equal(225, Logic.skillNeeded(63))
    end)
end)

describe("material prices", function()
    it("summarize the cheapest price and how much is listed near it", function()
        local lowest, depth, all = Logic.summarize({
            { unitPrice = 120, quantity = 5 },
            { unitPrice = 100, quantity = 20 },
            { unitPrice = 110, quantity = 7 },
            { unitPrice = 111, quantity = 3 },
        })
        assert.equal(100, lowest)
        assert.equal(27, depth)
        assert.equal(35, all)
        assert.is_nil(Logic.summarize({}))
    end)

    it("net out the undercut, cut and deposit", function()
        local opts = { cut = 0.05 }
        assert.equal((1000 - 1) * 0.95 - 12, Logic.net(1000, 12, opts))
        assert.equal(0, Logic.net(1, 5, opts))
        assert.equal(1000, Logic.net(1000, 12, { cut = 0.05, useMyself = true }))
        assert.is_nil(Logic.net(nil, 0, opts))
    end)
end)

describe("value, profit and loss", function()
    local _, outcomes = Logic.bucket(ARMOR, 2, 23)
    local prices = { [STRANGE_DUST] = 100, [LESSER_ASTRAL] = 400, [SMALL_GLIMMERING] = 900 }

    it("weighs every outcome", function()
        -- dust 0.75 * 5 * 100 = 375, essence 0.15 * 1.5 * 400 = 90, shard 0.1 * 900 = 90
        near(555, Logic.value(outcomes, prices))
    end)

    it("names a material without a price", function()
        local value, missing = Logic.value(outcomes, { [STRANGE_DUST] = 100 })
        assert.is_nil(value)
        assert.equal(LESSER_ASTRAL, missing)
    end)

    it("counts the outcomes worth less than the buyout", function()
        -- 4 dust 400, 5 dust 500, 6 dust 600, 1 essence 400, 2 essence 800, shard 900
        near(0.25 + 0.075, Logic.lossChance(outcomes, prices, 450))
        near(0, Logic.lossChance(outcomes, prices, 400))
        assert.is_nil(Logic.lossChance(outcomes, {}, 400))
    end)

    it("prices an auction from its bucket, once per bucket", function()
        local values = {}
        local r = { bucket = "2:4:25", buyout = 450 }
        Logic.price(r, outcomes, prices, values)
        assert.equal(555, r.value)
        assert.equal(105, r.profit)
        near(0.325, r.loss)
        assert.equal(555, values["2:4:25"])
        local unpriced = { bucket = "x", buyout = 450 }
        Logic.price(unpriced, outcomes, {}, values)
        assert.is_nil(unpriced.value)
        assert.is_false(values.x)
    end)

    it("calls it a deal only above the floor, the margin and under the loss limit", function()
        local opts = { minProfit = 100, minMargin = 0.1, maxLoss = 0.5 }
        assert.is_true(Logic.isDeal({ profit = 150, buyout = 1000, loss = 0.2 }, opts))
        assert.is_false(Logic.isDeal({ profit = 99, buyout = 100, loss = 0 }, opts))
        assert.is_false(Logic.isDeal({ profit = 150, buyout = 2000, loss = 0 }, opts))
        assert.is_false(Logic.isDeal({ profit = 500, buyout = 1000, loss = 0.6 }, opts))
        assert.is_false(Logic.isDeal({ buyout = 1000 }, opts))
    end)
end)

describe("the list", function()
    local opts = { minProfit = 100, minMargin = 0.1, maxLoss = 0.5 }
    local results = {
        { name = "a", ilvl = 23, band = 25, buyout = 300, profit = 255, loss = 0 },
        { name = "b", ilvl = 58, band = 60, buyout = 1000, profit = 50, loss = 0.3 },
        { name = "c", ilvl = 45, band = 45, buyout = 500 },
        { name = "d", ilvl = 33, band = 35, buyout = 800, profit = 900, loss = 0.1 },
    }

    it("sorts with unpriced items last both ways", function()
        local down = Logic.view(results, {}, "profit", true)
        assert.same(
            { "d", "a", "b", "c" },
            { down[1].name, down[2].name, down[3].name, down[4].name }
        )
        local up = Logic.view(results, {}, "profit", false)
        assert.same({ "b", "a", "d", "c" }, { up[1].name, up[2].name, up[3].name, up[4].name })
    end)

    it("filters deals, skill and brackets", function()
        assert.equal(2, #Logic.view(results, { onlyDeals = true, opts = opts }, "profit", true))
        local low = Logic.view(results, { skill = 75 }, "profit", true)
        assert.equal(2, #low) -- a (25) and d (75)
        local only = Logic.view(results, { brackets = { [60] = true } }, "profit", true)
        assert.equal("b", only[1].name)
        assert.equal(1, #only)
    end)

    it("puts item levels in the green bands", function()
        assert.equal(15, Logic.band(3))
        assert.equal(25, Logic.band(21))
        assert.equal(999, Logic.band(63))
    end)
end)

describe("comparing your disenchants with the table", function()
    it("flags a share far from the table", function()
        local _, outcomes = Logic.bucket(ARMOR, 2, 23)
        local rows = Logic.compare({
            n = 100,
            got = {
                ["10940:4"] = 20,
                ["10940:5"] = 20,
                ["10940:6"] = 20,
                ["10998:1"] = 30,
                ["10978:1"] = 10,
            },
        }, outcomes)
        assert.equal(STRANGE_DUST, rows[1].mat)
        near(0.75, rows[1].expected)
        near(0.6, rows[1].seen)
        near(5, rows[1].seenQty)
        assert.is_true(rows[1].off) -- 60% vs 75%: 3.5 standard errors
        near(0.3, rows[2].seen)
        assert.is_true(rows[2].off)
        assert.is_false(rows[3].off) -- shard 10% as the table says
    end)
end)
