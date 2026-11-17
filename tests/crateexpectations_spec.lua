-- CrateExpectations' crate reading and lookup (CrateExpectations/Logic.lua). Plain data only.
local ns = {}
assert(loadfile("CrateExpectations/Logic.lua"))("CrateExpectations", ns)
local Logic = ns.Logic

describe("reading a crate's tooltip", function()
    it("takes the bundles in and after the Use line, until the list ends", function()
        local lines = {
            "Waylaid Crate: Journeyman Fabrics",
            "Unique",
            "Use: Fill with one of:\r\n- 6 Bolt of Woolen Cloth\r\n- 10 Bolt of Silk Cloth",
            "- 2 Cured Medium Hide",
            "- not a bundle",
            "- 3 Too Late",
        }
        assert.same({
            { 6, "Bolt of Woolen Cloth" },
            { 10, "Bolt of Silk Cloth" },
            { 2, "Cured Medium Hide" },
        }, Logic.parseBundles(lines, "Use:"))
    end)

    it("finds nothing on other items", function()
        assert.same({}, Logic.parseBundles({ "Linen Cloth", "- 5 Something" }, "Use:"))
        assert.same({}, Logic.parseBundles({ "Potion", "Use: Restores 70 health." }, "Use:"))
    end)

    it("strips color codes", function()
        assert.equal("- 4 Copper Tube", Logic.plain("|cffffffff- 4 Copper Tube|r"))
    end)

    it("names the shipment from the crate's item name", function()
        assert.equal("Expert Parts", Logic.shipmentName("Waylaid Crate: Expert Parts"))
        assert.equal("Waylaid Crate", Logic.shipmentName("Waylaid Crate"))
    end)
end)

describe("which crates want an item", function()
    it("lists every seeded shipment that takes it", function()
        local index = Logic.index(Logic.SHIPMENTS, {})
        assert.same({ { "Apprentice Herbs", 20 } }, index["Peacebloom"])
        assert.same({ { "Artisan Ingots", 20 } }, index["Thorium Bar"])
        assert.is_nil(index["Hearthstone"])
    end)

    it("lets a crate seen in game replace the seeded one and add new items", function()
        local learned =
            { ["Apprentice Herbs"] = { { 15, "Peacebloom" } }, Cooking = { { 5, "Fish" } } }
        local index = Logic.index(Logic.SHIPMENTS, learned)
        assert.same({ { "Apprentice Herbs", 15 } }, index["Peacebloom"])
        assert.is_nil(index["Silverleaf"])
        assert.same({ { "Cooking", 5 } }, index["Fish"])
    end)

    it("sorts and describes shipments", function()
        local index = Logic.index({ { "B", { { 2, "X" } } }, { "A", { { 1, "X" } } } }, {})
        assert.equal("A (1), B (2)", Logic.describe(index["X"]))
    end)
end)

describe("saving a crate", function()
    it("adds new items, updates counts, and reports when nothing changed", function()
        local merged, changed = Logic.merge(nil, { { 2, "A" } })
        assert.is_true(changed)
        merged, changed = Logic.merge(merged, { { 2, "A" } })
        assert.is_false(changed)
        merged, changed = Logic.merge(merged, { { 3, "A" }, { 1, "B" } })
        assert.is_true(changed)
        assert.same({ { 3, "A" }, { 1, "B" } }, merged)
    end)
end)
