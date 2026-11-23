-- PriceIsRight's reading of Auctionator's database (PriceIsRight/Logic.lua). Plain data only.
local ns = {}
assert(loadfile("PriceIsRight/Logic.lua"))("PriceIsRight", ns)
local Logic = ns.Logic

describe("reading Auctionator's keys", function()
    it("takes item IDs, random suffixes and item levels", function()
        assert.same({ 2770 }, { Logic.parseKey("2770") })
        assert.same({ 9807, "of the Boar", "gr" }, { Logic.parseKey("gr:9807:of the Boar") })
        assert.same({ 1234, "60", "g" }, { Logic.parseKey("g:1234:60") })
    end)

    it("skips pets and bookkeeping keys", function()
        assert.is_nil(Logic.parseKey("p:39"))
        assert.is_nil(Logic.parseKey("__dbversion"))
        assert.is_nil(Logic.parseKey("version"))
        assert.is_nil(Logic.parseKey(8))
    end)
end)

describe("an entry's history", function()
    -- the layout Auctionator's DatabaseMixin:SetPrice writes
    local entry = {
        m = 120,
        h = { ["2515"] = 150, ["2517"] = 120 },
        l = { ["2515"] = 90 },
        a = { ["2517"] = 4 },
    }

    it("lists days newest first, low falling back to high", function()
        assert.same({
            { day = 2517, low = 120, high = 120, available = 4 },
            { day = 2515, low = 90, high = 150 },
        }, Logic.history(entry))
        assert.equal(2517, Logic.lastDay(entry))
    end)

    it("copes with number day keys and missing fields", function()
        assert.same({ { day = 7, low = 5, high = 5 } }, Logic.history({ h = { [7] = 5 } }))
        assert.same({}, Logic.history({}))
        assert.is_nil(Logic.lastDay({}))
    end)
end)

describe("searching", function()
    local items = {
        { key = "2771", itemID = 2771, name = "Tin Ore" },
        { key = "2770", itemID = 2770, name = "Copper Ore" },
        { key = "2772", itemID = 2772, name = "Iron Ore" },
        { key = "2775", itemID = 2775 }, -- name not loaded yet
    }

    local function names(found)
        local list = {}
        for _, item in ipairs(found) do
            list[#list + 1] = item.name
        end
        return list
    end

    it("matches every word, any case, sorted by name", function()
        assert.same({ "Copper Ore", "Iron Ore", "Tin Ore" }, names(Logic.search(items, "ore")))
        assert.same({ "Copper Ore" }, names(Logic.search(items, "ORE cop")))
        assert.same({}, names(Logic.search(items, "bar")))
    end)

    it("lists everything named for an empty query, and finds item IDs", function()
        assert.equal(3, #Logic.search(items, ""))
        assert.same({ "Iron Ore" }, names(Logic.search(items, " 2772 ")))
    end)
end)
