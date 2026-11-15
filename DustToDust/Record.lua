-- Records what your disenchants give, per bucket, so /dtd data can compare it with the
-- table (Data.lua isn't checked against Forever).
--
-- The item comes from your bags: while Disenchant is being cast its target is locked, and
-- the cast's target name (UNIT_SPELLCAST_SENT) picks it out. The result is the next loot
-- window within LOOT_WINDOW seconds, if everything in it is a disenchanting material.
local _, ns = ...
local Logic = ns.Logic

local DISENCHANT = 13262
local LOOT_WINDOW = 15
local QUALITY = { [2] = "Green", [3] = "Blue", [4] = "Purple" }

local targetName -- from UNIT_SPELLCAST_SENT
local pending -- { key, classID, quality, ilvl, at }

local function lockedTarget()
    local fallback
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.isLocked and info.hyperlink then
                local _, _, quality, ilvl, _, _, _, _, _, _, _, classID =
                    C_Item.GetItemInfo(info.hyperlink)
                ilvl = C_Item.GetDetailedItemLevelInfo(info.hyperlink) or ilvl
                local key = quality and Logic.bucket(classID, quality, ilvl, info.itemID)
                if key then
                    local found = { key = key, classID = classID, quality = quality, ilvl = ilvl }
                    if info.itemName == targetName then
                        return found
                    end
                    fallback = fallback or found
                end
            end
        end
    end
    return fallback
end

local function record()
    local got, any = {}, false
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local mat = link and C_Item.GetItemInfoInstant(link)
        if not (mat and ns.matNames[mat]) then
            return -- not a disenchant's loot
        end
        local _, _, qty = GetLootSlotInfo(i)
        got[mat .. ":" .. (qty or 1)] = true
        any = true
    end
    if not any then
        return
    end
    local obs = ns.db.observed[pending.key]
    if not obs then
        obs = {
            n = 0,
            got = {},
            classID = pending.classID,
            quality = pending.quality,
            ilvl = pending.ilvl,
        }
        ns.db.observed[pending.key] = obs
    end
    obs.n = obs.n + 1
    for k in pairs(got) do
        obs.got[k] = (obs.got[k] or 0) + 1
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_SPELLCAST_SENT")
f:RegisterEvent("UNIT_SPELLCAST_START")
f:RegisterEvent("UNIT_SPELLCAST_FAILED")
f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
f:RegisterEvent("LOOT_READY")
f:SetScript("OnEvent", function(_, event, unit, a, b, c)
    if event == "LOOT_READY" then
        if pending and GetTime() - pending.at < LOOT_WINDOW then
            record()
        end
        pending = nil
    elseif unit ~= "player" then
        return
    elseif event == "UNIT_SPELLCAST_SENT" then
        if c == DISENCHANT then
            targetName, pending = a, nil
        end
    elseif b == DISENCHANT then
        if event == "UNIT_SPELLCAST_START" then
            local found = lockedTarget()
            if found then
                found.at = GetTime()
            end
            pending = found
        else
            pending = nil
        end
    end
end)

-- /dtd data: your disenchants per bucket next to the table.
function ns.showData()
    local keys = {}
    for key in pairs(ns.db.observed) do
        keys[#keys + 1] = key
    end
    if #keys == 0 then
        ns.chat("No disenchants recorded yet.")
        return
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local obs = ns.db.observed[key]
        local _, outcomes = Logic.bucket(obs.classID, obs.quality, obs.ilvl)
        local max = tonumber(key:match(":(%d+)$"))
        local what = obs.quality == 2 and (obs.classID == 2 and "weapons" or "armor") or "gear"
        ns.chat(
            ("%s %s, item level %s: %d disenchant(s)%s"):format(
                QUALITY[obs.quality] or "?",
                what,
                max >= 999 and "61+" or ("up to " .. max),
                obs.n,
                obs.n < 10 and " (too few to tell)" or ""
            )
        )
        if outcomes and obs.n >= 10 then
            for _, row in ipairs(Logic.compare(obs, outcomes)) do
                local line = ("  %s: %d%% (table %d%%), %.1f each (table %.1f)"):format(
                    ns.matName(row.mat),
                    math.floor(row.seen * 100 + 0.5),
                    math.floor(row.expected * 100 + 0.5),
                    row.seenQty,
                    row.expectedQty
                )
                ns.chat(row.off and ("|cffff8000" .. line .. " <- off|r") or line)
            end
        end
    end
end
