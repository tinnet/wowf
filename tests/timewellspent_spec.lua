-- TimeWellSpent's durations and class breakdown (TimeWellSpent/Logic.lua). Plain data only.
local ns = {}
assert(loadfile("TimeWellSpent/Logic.lua"))("TimeWellSpent", ns)
local Logic = ns.Logic

describe("durations", function()
    it("shows days and hours, hours and minutes, or minutes", function()
        assert.equal("3d 4h", Logic.duration(3 * 86400 + 4 * 3600 + 59 * 60))
        assert.equal("4h 12m", Logic.duration(4 * 3600 + 12 * 60 + 30))
        assert.equal("0m", Logic.duration(59))
        assert.equal("0m", Logic.duration(nil))
        assert.equal("0m", Logic.duration(-5))
    end)
end)

describe("the class breakdown", function()
    local chars = {
        ["Ann-R"] = { class = "DRUID", className = "Druid", played = 100 },
        ["Bob-R"] = { class = "WARRIOR", className = "Warrior", played = 300 },
        ["Cid-R"] = { class = "DRUID", className = "Druid", played = 250 },
        ["Dot-R"] = { class = "ROGUE", className = "Rogue" }, -- never got a reply
        ["Eve-R"] = { class = "ROGUE", className = "Rogue", played = 300 },
    }

    it("sums the account and each class, most played first", function()
        local total, classes = Logic.breakdown(chars)
        assert.equal(950, total)
        assert.same({ "DRUID", "ROGUE", "WARRIOR" }, {
            classes[1].class,
            classes[2].class,
            classes[3].class,
        })
        assert.equal(350, classes[1].played)
    end)

    it("sorts characters in a class by time and skips ones without a time", function()
        local _, classes = Logic.breakdown(chars)
        assert.equal("Cid-R", classes[1].chars[1].key)
        assert.equal("Ann-R", classes[1].chars[2].key)
        assert.equal(1, #classes[2].chars)
    end)

    it("is empty with no characters", function()
        local total, classes = Logic.breakdown({})
        assert.equal(0, total)
        assert.same({}, classes)
    end)
end)
