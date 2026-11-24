-- TimeWellSpent's plain logic: formatting durations and grouping characters by class.
-- No game API here.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

-- "3d 4h", "4h 12m", "12m". Days above a day, minutes below one, never seconds.
function Logic.duration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then
        return ("%dd %dh"):format(days, hours)
    elseif hours > 0 then
        return ("%dh %dm"):format(hours, minutes)
    end
    return ("%dm"):format(minutes)
end

-- chars: key -> { name, realm, class, className, level, played }. Returns the account
-- total and the classes, most played first, each { class, className, played, chars }
-- with its characters most played first. Characters without a played time are skipped.
function Logic.breakdown(chars)
    local total, byClass, classes = 0, {}, {}
    for key, char in pairs(chars) do
        if type(char) == "table" and type(char.played) == "number" then
            local class = char.class or "UNKNOWN"
            local group = byClass[class]
            if not group then
                group =
                    { class = class, className = char.className or class, played = 0, chars = {} }
                byClass[class] = group
                classes[#classes + 1] = group
            end
            group.played = group.played + char.played
            group.chars[#group.chars + 1] = { key = key, char = char }
            total = total + char.played
        end
    end
    local function byPlayed(a, b)
        local pa = a.played or a.char.played
        local pb = b.played or b.char.played
        if pa ~= pb then
            return pa > pb
        end
        return (a.key or a.class) < (b.key or b.class)
    end
    table.sort(classes, byPlayed)
    for _, group in ipairs(classes) do
        table.sort(group.chars, byPlayed)
    end
    return total, classes
end
