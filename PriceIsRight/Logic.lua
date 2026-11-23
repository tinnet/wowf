-- PriceIsRight's plain logic: reading Auctionator's price database keys and entries, and
-- matching item names. No game API here.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

-- Auctionator's database key for an item: "12345" (item ID), "gr:12345:of the Bear" (gear
-- with a random suffix, Forever and Classic), "g:12345:60" (gear by item level, other
-- clients). Returns item ID, then the suffix or item level and "gr" or "g" (both nil for
-- plain items); nil for anything else (pets, "__dbversion", ...).
function Logic.parseKey(key)
    if type(key) ~= "string" then
        return nil
    end
    local id = key:match("^(%d+)$")
    if id then
        return tonumber(id)
    end
    local kind, extra
    kind, id, extra = key:match("^(gr?):(%d+):(.+)$")
    if id then
        return tonumber(id), extra, kind
    end
    return nil
end

-- The days in an entry, newest first, as { number, key }. Auctionator writes day keys as
-- strings ("2517"); the original key is kept for lookups either way.
local function days(entry)
    local list = {}
    for key in pairs(entry.h or {}) do
        local day = tonumber(key)
        if day then
            list[#list + 1] = { day, key }
        end
    end
    table.sort(list, function(a, b)
        return a[1] > b[1]
    end)
    return list
end

-- An entry's history, newest first: { day, low, high, available } per day seen. Auctionator
-- keeps "l" (lowest price that day) only when it differs from "h" (highest lowest price).
function Logic.history(entry)
    local rows = {}
    for _, d in ipairs(days(entry)) do
        local k = d[2]
        rows[#rows + 1] = {
            day = d[1],
            low = (entry.l and entry.l[k]) or entry.h[k],
            high = entry.h[k],
            available = entry.a and entry.a[k],
        }
    end
    return rows
end

-- The last day the entry was seen, or nil.
function Logic.lastDay(entry)
    local newest = days(entry)[1]
    return newest and newest[1]
end

-- Lower-cased, every word of the query must be somewhere in the text. "" matches all.
function Logic.matches(text, query)
    text = text:lower()
    for word in query:lower():gmatch("%S+") do
        if not text:find(word, 1, true) then
            return false
        end
    end
    return true
end

-- items: { key, itemID, name (nil until known) }. Those whose name matches the query, or
-- whose item ID is the query, sorted by name. Items without a name yet are left out.
function Logic.search(items, query)
    local id = tonumber(query:match("^%s*(%d+)%s*$"))
    local found = {}
    for _, item in ipairs(items) do
        if item.name and (item.itemID == id or Logic.matches(item.name, query)) then
            found[#found + 1] = item
        end
    end
    table.sort(found, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.key < b.key
    end)
    return found
end
