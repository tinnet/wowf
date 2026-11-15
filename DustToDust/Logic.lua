-- DustToDust's arithmetic: plain data in, plain data out, no game API calls, so tests/ can
-- run it under busted. All money is in copper.
--
-- An item's disenchant value depends only on its bucket: quality, class (for greens) and
-- item level band. There are about 60 buckets, so a scan prices each auction by looking up
-- its bucket's outcomes, never by asking the game about the item.
local _, ns = ...
local Data = ns.Data
local Logic = {}
ns.Logic = Logic

Logic.UNDERCUT = 1 -- copper under the cheapest listing when you sell
Logic.DEPTH_RANGE = 1.1 -- "depth": units listed within 10% of the cheapest

local function rowFor(rows, ilvl)
    for _, row in ipairs(rows) do
        if ilvl <= row.max then
            return row
        end
    end
end

-- One result of a table row as outcomes: "4-6 dust at 75%" is 4, 5 and 6 at 25% each.
local function spread(out, chance, mat, min, max)
    if chance <= 0 then
        return
    end
    local n = max - min + 1
    for qty = min, max do
        out[#out + 1] = { p = chance / 100 / n, mat = mat, qty = qty }
    end
end

local buckets = {} -- key -> outcomes, built once each

-- The bucket of a weapon or armor piece: its key and its outcomes, a list of
-- { p = chance 0..1, mat = itemID, qty }. Nil when it can't be disenchanted.
function Logic.bucket(classID, quality, ilvl, itemID)
    if classID ~= Data.WEAPON and classID ~= Data.ARMOR then
        return nil
    end
    if itemID and Data.NOT_DISENCHANTABLE[itemID] then
        return nil
    end
    if not ilvl or ilvl <= 0 then
        return nil
    end
    local key, rows, uncommon
    if quality == Data.UNCOMMON_QUALITY then
        rows, uncommon = Data.UNCOMMON, true
    elseif
        quality == Data.RARE_QUALITY or (quality == Data.EPIC_QUALITY and ilvl < Data.EPIC_MIN)
    then
        rows = Data.RARE
    elseif quality == Data.EPIC_QUALITY then
        rows = Data.EPIC
    else
        return nil
    end
    local row = rowFor(rows, ilvl)
    if not row then
        return nil
    end
    key = quality .. ":" .. (uncommon and classID or 0) .. ":" .. row.max
    local outcomes = buckets[key]
    if outcomes then
        return key, outcomes
    end
    outcomes = {}
    if uncommon then
        local chances = classID == Data.WEAPON and row.weapon or row.armor
        spread(outcomes, chances[1], row.dust[1], row.dust[2], row.dust[3])
        spread(outcomes, chances[2], row.essence[1], row.essence[2], row.essence[3])
        if row.shard then
            spread(outcomes, chances[3], row.shard, 1, 1)
        end
    else
        for _, result in ipairs(row) do
            spread(outcomes, result[1], result[2], result[3], result[4])
        end
    end
    buckets[key] = outcomes
    return key, outcomes
end

-- Enchanting skill needed to disenchant an item of this level.
function Logic.skillNeeded(ilvl)
    for _, step in ipairs(Data.SKILL) do
        if ilvl <= step[1] then
            return step[2]
        end
    end
    return Data.SKILL[#Data.SKILL][2]
end

-- From a material's listings ({ unitPrice, quantity }, any order): the cheapest unit
-- price, the units listed within DEPTH_RANGE of it, and all units listed.
function Logic.summarize(listings)
    local lowest, total = nil, 0
    for _, l in ipairs(listings) do
        if l.unitPrice and l.unitPrice > 0 then
            total = total + (l.quantity or 0)
            if not lowest or l.unitPrice < lowest then
                lowest = l.unitPrice
            end
        end
    end
    if not lowest then
        return nil, 0, 0
    end
    local depth = 0
    for _, l in ipairs(listings) do
        if l.unitPrice and l.unitPrice > 0 and l.unitPrice <= lowest * Logic.DEPTH_RANGE then
            depth = depth + (l.quantity or 0)
        end
    end
    return lowest, depth, total
end

-- What one unit of a material is worth to you: listed a copper under the cheapest, minus
-- the auction house cut and the deposit. Never below 0. With useMyself, its market price.
-- opts: { cut = 0..1, useMyself = bool }; deposit is per unit (0 when unknown).
function Logic.net(lowest, deposit, opts)
    if not lowest then
        return nil
    end
    if opts.useMyself then
        return lowest
    end
    local sell = math.max(lowest - Logic.UNDERCUT, 0)
    return math.max(sell * (1 - opts.cut) - (deposit or 0), 0)
end

-- Expected value of a bucket's outcomes at these per-unit prices (mat -> copper). When a
-- material has no price, nil and that material.
function Logic.value(outcomes, prices)
    local total = 0
    for _, o in ipairs(outcomes) do
        local price = prices[o.mat]
        if not price then
            return nil, o.mat
        end
        total = total + o.p * o.qty * price
    end
    return total
end

-- Chance (0..1) that what you get is worth less than the buyout. Nil without prices.
function Logic.lossChance(outcomes, prices, buyout)
    local loss = 0
    for _, o in ipairs(outcomes) do
        local price = prices[o.mat]
        if not price then
            return nil
        end
        if o.qty * price < buyout then
            loss = loss + o.p
        end
    end
    return loss
end

-- Fills in an auction's value, profit and loss chance from its bucket. `values` caches
-- bucket values for these prices (key -> value or false); clear it when prices change.
function Logic.price(result, outcomes, prices, values)
    local value = values[result.bucket]
    if value == nil then
        value = Logic.value(outcomes, prices) or false
        values[result.bucket] = value
    end
    if not value or not result.buyout then
        result.value, result.profit, result.loss = nil, nil, nil
        return
    end
    result.value = math.floor(value)
    result.profit = result.value - result.buyout
    result.loss = Logic.lossChance(outcomes, prices, result.buyout)
end

-- Whether an auction counts as a deal. opts: { minProfit = copper, minMargin = 0..1,
-- maxLoss = 0..1 }.
function Logic.isDeal(result, opts)
    return result.profit ~= nil
        and result.profit >= opts.minProfit
        and result.profit >= result.buyout * opts.minMargin
        and (result.loss or 1) <= opts.maxLoss
end

local function compare(key, desc)
    return function(a, b)
        local x, y = a[key], b[key]
        if x == y then
            return (a.buyout or 0) < (b.buyout or 0)
        end
        if x == nil then
            return false -- unpriced last, either way round
        end
        if y == nil then
            return true
        end
        if desc then
            return x > y
        end
        return x < y
    end
end

-- The results the panel shows, sorted. filter: { onlyDeals, opts (isDeal), skill (your
-- Enchanting, nil: don't filter), brackets (band max -> true; empty: all) }.
function Logic.view(results, filter, sortKey, desc)
    local out = {}
    local anyBracket = filter.brackets and next(filter.brackets) ~= nil
    for _, r in ipairs(results) do
        if
            (not filter.onlyDeals or Logic.isDeal(r, filter.opts))
            and (not filter.skill or Logic.skillNeeded(r.ilvl) <= filter.skill)
            and (not anyBracket or filter.brackets[r.band])
        then
            out[#out + 1] = r
        end
    end
    table.sort(out, compare(sortKey, desc))
    return out
end

-- The uncommon item level band an item level falls in (its row's max), for the filters.
function Logic.band(ilvl)
    local row = rowFor(Data.UNCOMMON, ilvl)
    return row and row.max
end

-- Your disenchants against the table. observed: { n, got = { "mat:qty" -> count } }.
-- Returns one row per material: { mat, expected share, seen share, expectedQty (average
-- per disenchant that gave it), seenQty, off (more than 2 standard errors from the table) }.
function Logic.compare(observed, outcomes)
    local n = observed.n or 0
    local mats, order = {}, {}
    local function entry(mat)
        local e = mats[mat]
        if not e then
            e = { mat = mat, expected = 0, seen = 0, expectedUnits = 0, seenUnits = 0 }
            mats[mat] = e
            order[#order + 1] = e
        end
        return e
    end
    for _, o in ipairs(outcomes) do
        local e = entry(o.mat)
        e.expected = e.expected + o.p
        e.expectedUnits = e.expectedUnits + o.p * o.qty
    end
    for k, count in pairs(observed.got or {}) do
        local mat, qty = k:match("^(%d+):(%d+)$")
        local e = entry(tonumber(mat))
        e.seen = e.seen + count
        e.seenUnits = e.seenUnits + count * tonumber(qty)
    end
    for _, e in ipairs(order) do
        e.expectedQty = e.expected > 0 and e.expectedUnits / e.expected or 0
        e.seenQty = e.seen > 0 and e.seenUnits / e.seen or 0
        e.seen = n > 0 and e.seen / n or 0
        local se = math.sqrt(math.max(e.expected * (1 - e.expected), 0.0001) / math.max(n, 1))
        e.off = n > 0 and math.abs(e.seen - e.expected) > 2 * se
        e.expectedUnits, e.seenUnits = nil, nil
    end
    return order
end
