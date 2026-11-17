-- CrateExpectations' plain logic: the known Waylaid Crate shipments, reading a crate's
-- bundles from its tooltip text, and which crates want an item. No game API here.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

-- Every shipment and the bundles it takes (one complete bundle fills a crate), by item name
-- on an English client. From method.gg's Waylaid Crates guide (3 Nov 2026, beta data; checked
-- 2026-11-16). Crates seen in game are read from their tooltips and added to this, so a
-- change in game or another client language still gets picked up.
Logic.SHIPMENTS = {
    { "Apprentice Ore", { { 20, "Copper Ore" }, { 20, "Tin Ore" } } },
    { "Journeyman Ore", { { 10, "Silver Ore" }, { 20, "Iron Ore" } } },
    { "Expert Ore", { { 10, "Gold Ore" }, { 20, "Mithril Ore" } } },
    { "Artisan Ore", { { 10, "Truesilver Ore" }, { 20, "Thorium Ore" }, { 20, "Dark Iron Ore" } } },

    { "Apprentice Ingots", { { 20, "Copper Bar" }, { 20, "Tin Bar" }, { 10, "Bronze Bar" } } },
    { "Journeyman Ingots", { { 10, "Silver Bar" }, { 20, "Iron Bar" } } },
    { "Expert Ingots", { { 20, "Mithril Bar" }, { 15, "Steel Bar" }, { 10, "Gold Bar" } } },
    {
        "Artisan Ingots",
        { { 2, "Dark Iron Bar" }, { 10, "Truesilver Bar" }, { 20, "Thorium Bar" } },
    },

    {
        "Apprentice Herbs",
        {
            { 20, "Peacebloom" },
            { 20, "Silverleaf" },
            { 10, "Earthroot" },
            { 10, "Mageroyal" },
            { 10, "Briarthorn" },
        },
    },
    {
        "Journeyman Herbs",
        {
            { 10, "Stranglekelp" },
            { 10, "Bruiseweed" },
            { 10, "Wild Steelbloom" },
            { 10, "Grave Moss" },
            { 10, "Kingsblood" },
        },
    },
    {
        "Earthly Expert Herbs",
        {
            { 20, "Liferoot" },
            { 10, "Fadeleaf" },
            { 10, "Goldthorn" },
            { 10, "Khadgar's Whisker" },
        },
    },
    {
        "Flowering Expert Herbs",
        {
            { 10, "Wintersbite" },
            { 10, "Firebloom" },
            { 20, "Purple Lotus" },
            { 10, "Arthas' Tears" },
        },
    },
    {
        "Earthly Artisan Herbs",
        {
            { 10, "Golden Sansam" },
            { 20, "Sungrass" },
            { 10, "Blindweed" },
            { 10, "Ghost Mushroom" },
            { 10, "Gromsblood" },
        },
    },
    {
        "Flowering Artisan Herbs",
        {
            { 20, "Dreamfoil" },
            { 20, "Mountain Silversage" },
            { 20, "Plaguebloom" },
            { 20, "Icecap" },
        },
    },

    {
        "Apprentice Parts",
        { { 16, "Handful of Copper Bolts" }, { 16, "Copper Tube" }, { 4, "Copper Modulator" } },
    },
    {
        "Journeyman Parts",
        {
            { 8, "Bronze Tube" },
            { 7, "Whirring Bronze Gizmo" },
            { 4, "Bronze Framework" },
            { 45, "Gold Power Core" },
        },
    },
    {
        "Expert Parts",
        {
            { 8, "Iron Strut" },
            { 5, "Mithril Tube" },
            { 12, "Unstable Trigger" },
            { 5, "Mithril Casing" },
        },
    },
    {
        "Artisan Parts",
        { { 5, "Thorium Widget" }, { 5, "Truesilver Transformer" }, { 2, "Thorium Tube" } },
    },

    { "Apprentice Textiles", { { 40, "Linen Cloth" }, { 20, "Light Leather" } } },
    {
        "Journeyman Textiles",
        { { 20, "Wool Cloth" }, { 40, "Silk Cloth" }, { 20, "Medium Leather" } },
    },
    { "Expert Textiles", { { 40, "Mageweave Cloth" }, { 20, "Heavy Leather" } } },
    {
        "Artisan Textiles",
        { { 40, "Runecloth" }, { 20, "Thick Leather" }, { 20, "Rugged Leather" } },
    },

    { "Apprentice Fabrics", { { 2, "Cured Light Hide" }, { 20, "Bolt of Linen Cloth" } } },
    {
        "Journeyman Fabrics",
        { { 6, "Bolt of Woolen Cloth" }, { 10, "Bolt of Silk Cloth" }, { 2, "Cured Medium Hide" } },
    },
    { "Expert Fabrics", { { 8, "Bolt of Mageweave" }, { 2, "Cured Heavy Hide" } } },
    { "Artisan Fabrics", { { 8, "Bolt of Runecloth" }, { 2, "Cured Thick Hide" } } },

    {
        "Apprentice Curiosities",
        {
            { 20, "Strange Dust" },
            { 4, "Greater Magic Essence" },
            { 6, "Small Glimmering Shard" },
            { 2, "Large Glimmering Shard" },
        },
    },
    {
        "Journeyman Curiosities",
        {
            { 20, "Soul Dust" },
            { 4, "Greater Astral Essence" },
            { 6, "Small Glowing Shard" },
            { 2, "Large Glowing Shard" },
        },
    },
    {
        "Expert Curiosities",
        {
            { 20, "Vision Dust" },
            { 4, "Greater Mystic Essence" },
            { 6, "Small Radiant Shard" },
            { 2, "Large Radiant Shard" },
        },
    },
    {
        "Artisan Curiosities",
        {
            { 20, "Dream Dust" },
            { 4, "Greater Nether Essence" },
            { 6, "Small Brilliant Shard" },
            { 2, "Large Brilliant Shard" },
        },
    },
}

---Text without color codes and texture/atlas escapes.
---@param text string
---@return string
function Logic.plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text
end

---A bundle line ("- 6 Bolt of Woolen Cloth"): its count and item name, or nil.
---@param line string
---@return number|nil
---@return string|nil
function Logic.bundleOf(line)
    local count, name = line:match("^%s*%-%s*(%d+)%s+(.-)%s*$")
    if count and name ~= "" then
        return tonumber(count), name
    end
end

-- Every bundle in one tooltip line's text, which may hold several lines of its own.
local function bundlesIn(text, out)
    local found = false
    for part in (text .. "\n"):gmatch("(.-)\r?\n") do
        local count, name = Logic.bundleOf(part)
        if count then
            out[#out + 1] = { count, name }
            found = true
        end
    end
    return found
end

---The bundles a crate's tooltip lists in and right after its Use line, empty for anything
---else. `lines` are the tooltip's left texts in order, color codes already removed.
---@param lines string[]
---@param use string the client's "Use:"
---@return table bundles { { count, name } }
function Logic.parseBundles(lines, use)
    local bundles, inUse = {}, false
    for _, text in ipairs(lines) do
        if not inUse then
            if text:find(use, 1, true) == 1 then
                inUse = true
                bundlesIn(text, bundles)
            end
        elseif not bundlesIn(text, bundles) then
            break
        end
    end
    return bundles
end

---A crate's shipment name from its item name: "Waylaid Crate: Expert Parts" -> "Expert Parts".
---@param itemName string
---@return string
function Logic.shipmentName(itemName)
    return itemName:match("^[^:]*[Cc]rate[^:]*:%s*(.+)$") or itemName
end

---Item name -> the shipments that take it: { { shipment, count } }, sorted by shipment.
---Learned shipments (seen in game) replace a seeded one of the same name.
---@param seed table Logic.SHIPMENTS' shape: { { shipment, bundles } }
---@param learned table shipment -> bundles
---@return table
function Logic.index(seed, learned)
    local all = {}
    for _, s in ipairs(seed) do
        all[s[1]] = s[2]
    end
    for shipment, bundles in pairs(learned or {}) do
        all[shipment] = bundles
    end
    local byItem = {}
    for shipment, bundles in pairs(all) do
        for _, b in ipairs(bundles) do
            local list = byItem[b[2]] or {}
            byItem[b[2]] = list
            list[#list + 1] = { shipment, b[1] }
        end
    end
    for _, list in pairs(byItem) do
        table.sort(list, function(a, b)
            return a[1] < b[1]
        end)
    end
    return byItem
end

---Adds `new` bundles to a saved shipment's `old` ones: items not there yet are appended, an
---item already there takes the new count. Kept as a union because crates whose item name
---doesn't say the shipment all save under the same name.
---@param old table|nil
---@param new table
---@return table merged
---@return boolean changed
function Logic.merge(old, new)
    local merged, at, changed = {}, {}, old == nil
    for i, b in ipairs(old or {}) do
        merged[i] = { b[1], b[2] }
        at[b[2]] = i
    end
    for _, b in ipairs(new) do
        local i = at[b[2]]
        if not i then
            merged[#merged + 1] = { b[1], b[2] }
            at[b[2]] = #merged
            changed = true
        elseif merged[i][1] ~= b[1] then
            merged[i][1] = b[1]
            changed = true
        end
    end
    return merged, changed
end

---The tooltip line for an item the crates take: "Apprentice Herbs (20), Journeyman Herbs (10)".
---@param list table { { shipment, count } }
---@return string
function Logic.describe(list)
    local parts = {}
    for _, entry in ipairs(list) do
        parts[#parts + 1] = ("%s (%d)"):format(entry[1], entry[2])
    end
    return table.concat(parts, ", ")
end
