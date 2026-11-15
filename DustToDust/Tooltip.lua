-- A line on disenchantable items: what disenchanting it is worth to you after the auction
-- house costs (the same value as the panel's DE value column).
local _, ns = ...
local Logic = ns.Logic

local function addLine(tooltip)
    if not ns.db or (tooltip.IsForbidden and tooltip:IsForbidden()) or not tooltip.GetItem then
        return
    end
    local _, link = tooltip:GetItem()
    if not link then
        return
    end
    local _, _, quality, ilvl, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(link)
    if not quality then
        return
    end
    ilvl = C_Item.GetDetailedItemLevelInfo(link) or ilvl
    local key, outcomes = Logic.bucket(classID, quality, ilvl, (C_Item.GetItemInfoInstant(link)))
    if not key then
        return
    end
    local value = Logic.value(outcomes, ns.netPrices())
    tooltip:AddDoubleLine(
        "Disenchant value:",
        value and ns.money(value) or "no material prices",
        1,
        0.82,
        0,
        1,
        1,
        1
    )
    local skill, need = ns.enchanting(), Logic.skillNeeded(ilvl)
    if skill and skill < need then
        tooltip:AddLine(("Needs Enchanting %d (you have %d)"):format(need, skill), 1, 0.3, 0.3)
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addLine)
