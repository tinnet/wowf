-- LayerCake's plain logic: reading the zone ID out of an NPC's GUID, and numbering the zone
-- IDs seen in a zone. No game API here.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

-- Zone IDs not seen for this long are dropped: layers come and go, and every ID changes
-- when the servers restart.
Logic.MAX_AGE = 3 * 60 * 60

-- Unit kinds whose GUID carries the zone ID of the layer they live on. Players and pets
-- are left out (a player's GUID has no zone, a pet's follows its owner).
local NPC_KINDS = { Creature = true, Vehicle = true }

-- "Creature-0-5250-0-1234-3100-0000ABCDEF": kind-0-server-instance-zoneUID-npcID-spawnUID.
-- Returns zoneUID and npcID as numbers, or nil for anything that isn't an NPC's GUID.
function Logic.parseGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local kind, zone, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-(%d+)%-(%d+)%-%x+$")
    if not kind or not NPC_KINDS[kind] then
        return nil
    end
    return tonumber(zone), tonumber(npc)
end

-- seen: zoneUID -> last time seen. Drops IDs older than maxAge (default MAX_AGE).
function Logic.prune(seen, now, maxAge)
    maxAge = maxAge or Logic.MAX_AGE
    for zone, at in pairs(seen) do
        if now - at > maxAge then
            seen[zone] = nil
        end
    end
end

-- The zone IDs in seen, lowest first.
function Logic.sorted(seen)
    local list = {}
    for zone in pairs(seen) do
        list[#list + 1] = zone
    end
    table.sort(list)
    return list
end

-- Layer number of zone among the IDs seen (lowest ID is layer 1, the order layers were
-- made in), and how many there are. nil if zone isn't among them.
function Logic.rank(seen, zone)
    local list = Logic.sorted(seen)
    for i, z in ipairs(list) do
        if z == zone then
            return i, #list
        end
    end
    return nil, #list
end

-- "12s", "4m", "2h"
function Logic.ago(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds < 60 then
        return seconds .. "s"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m"
    end
    return math.floor(seconds / 3600) .. "h"
end
