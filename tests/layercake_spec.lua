-- LayerCake's GUID reading and layer numbering (LayerCake/Logic.lua). Plain data only.
local ns = {}
assert(loadfile("LayerCake/Logic.lua"))("LayerCake", ns)
local Logic = ns.Logic

describe("reading a GUID", function()
    it("takes the zone ID and NPC ID from creatures and vehicles", function()
        assert.same({ 1234, 3100 }, { Logic.parseGUID("Creature-0-5250-0-1234-3100-0000ABCDEF") })
        assert.same({ 77, 28605 }, { Logic.parseGUID("Vehicle-0-4372-571-77-28605-00004E8A2B") })
    end)

    it("ignores players, pets, objects and anything else", function()
        assert.is_nil(Logic.parseGUID("Player-4372-0123ABCD"))
        assert.is_nil(Logic.parseGUID("Pet-0-4372-0-1234-165189-0102FBC3A1"))
        assert.is_nil(Logic.parseGUID("GameObject-0-4372-0-1234-1617-0000ABCDEF"))
        assert.is_nil(Logic.parseGUID("Creature-0-5250-0-1234"))
        assert.is_nil(Logic.parseGUID(""))
        assert.is_nil(Logic.parseGUID(nil))
    end)
end)

describe("numbering layers", function()
    it("numbers the zone IDs seen, lowest first", function()
        local seen = { [900] = 1, [120] = 1, [450] = 1 }
        assert.same({ 1, 3 }, { Logic.rank(seen, 120) })
        assert.same({ 2, 3 }, { Logic.rank(seen, 450) })
        assert.same({ 3, 3 }, { Logic.rank(seen, 900) })
        assert.same({ nil, 3 }, { Logic.rank(seen, 5) })
    end)

    it("drops zone IDs not seen for too long", function()
        local seen = { [1] = 100, [2] = 500, [3] = 1000 }
        Logic.prune(seen, 1000, 500)
        assert.same({ [2] = 500, [3] = 1000 }, seen)
    end)
end)

describe("ago", function()
    it("rounds down to seconds, minutes or hours", function()
        assert.equal("0s", Logic.ago(-3))
        assert.equal("59s", Logic.ago(59.9))
        assert.equal("4m", Logic.ago(4 * 60 + 59))
        assert.equal("2h", Logic.ago(2 * 3600 + 100))
    end)
end)
