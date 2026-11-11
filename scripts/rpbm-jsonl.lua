-- Export RichPeopleBoatMoney's saved auction scans as JSON Lines, one auction per line.
--
--   just rpbm-export [dir]                         (finds the files under WOW_DIR)
--   lua scripts/rpbm-jsonl.lua [-d dir] RichPeopleBoatMoney.lua ...
--
-- With -d, every scan gets its own file in dir, named after its time, realm and faction
-- (20261111T013450Z-camwow-eu4-realm-3-pve-alliance.jsonl). A scan whose file already
-- exists is skipped, so exporting again after every session only adds the new ones and
-- never overwrites. Without -d, all scans go to stdout.
--
-- A SavedVariables file is Lua, so it's simply run, in an empty environment so it can
-- only set its own variable. Every line carries its scan's time, realm, faction and
-- character, so files can be concatenated.

-- Must match the field order in RichPeopleBoatMoney.lua; true = number.
local ROW_FIELDS = {
    { "item_id", true },
    { "count", true },
    { "quality", true },
    { "level", true },
    { "min_bid", true },
    { "min_increment", true },
    { "buyout", true },
    { "bid", true },
    { "time_left", true },
    { "sale_status", true },
    { "owner", false },
    { "item_string", false },
}

local function jsonString(s)
    return '"'
        .. s:gsub('[%c"\\]', function(c)
            return (c == '"' or c == "\\") and "\\" .. c or ("\\u%04x"):format(c:byte())
        end)
        .. '"'
end

local function json(v)
    if v == nil then
        return "null"
    elseif type(v) == "number" then
        -- %.0f keeps big copper values out of exponent form (1.23e+11)
        return v == math.floor(v) and ("%.0f"):format(v) or ("%.17g"):format(v)
    end
    return jsonString(tostring(v))
end

-- split("a,b,,c", ",") -> { "a", "b", "", "c" }
local function split(text, sep)
    local parts, start = {}, 1
    while true do
        local at = text:find(sep, start, true)
        parts[#parts + 1] = text:sub(start, (at or 0) - 1)
        if not at then
            return parts
        end
        start = at + 1
    end
end

local function load(path)
    local chunk, err = loadfile(path)
    if not chunk then
        error(err, 0)
    end
    local env = {}
    setfenv(chunk, env)
    chunk()
    return env.RichPeopleBoatMoneyDB or {}
end

-- "CAMWOW EU4 Realm 3 PvE" -> "camwow-eu4-realm-3-pve"
local function slug(s)
    return (tostring(s or "unknown"):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

local function fileName(scan)
    return ("%s-%s-%s.jsonl"):format(
        os.date("!%Y%m%dT%H%M%SZ", scan.time or 0),
        slug(scan.realm),
        slug(scan.faction)
    )
end

local function exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
    end
    return f ~= nil
end

-- Writes one scan's auctions to out; returns how many.
local function writeScan(scan, source, out)
    local meta = ('"scan_time":%s,"realm":%s,"faction":%s,"character":%s'):format(
        json(scan.time),
        json(scan.realm),
        json(scan.faction),
        json(scan.character)
    )
    local count = 0
    -- rows come joined with ";" in chunks (older saves: one row per string)
    for _, chunk in ipairs(scan.chunks or scan.rows or {}) do
        for _, line in ipairs(split(chunk, ";")) do
            local parts = split(line, ",")
            if #parts ~= #ROW_FIELDS then
                io.stderr:write(("%s: skipping odd row %q\n"):format(source, line))
            else
                local fields = { meta }
                for i, field in ipairs(ROW_FIELDS) do
                    local raw = parts[i]
                    local value
                    if field[2] then
                        value = tonumber(raw)
                    elseif raw ~= "" then
                        value = raw
                    end
                    fields[#fields + 1] = jsonString(field[1]) .. ":" .. json(value)
                end
                out:write("{", table.concat(fields, ","), "}\n")
                count = count + 1
            end
        end
    end
    return count
end

local paths, dir = {}, nil
local i = 1
while arg[i] do
    if arg[i] == "-d" then
        dir = arg[i + 1]
        i = i + 1
    else
        paths[#paths + 1] = arg[i]
    end
    i = i + 1
end
if #paths == 0 or (arg[#arg] == "-d") then
    io.stderr:write("usage: lua scripts/rpbm-jsonl.lua [-d dir] RichPeopleBoatMoney.lua ...\n")
    os.exit(1)
end

local total, written, skipped = 0, 0, 0
for _, path in ipairs(paths) do
    for _, scan in ipairs(load(path).scans or {}) do
        if not dir then
            total = total + writeScan(scan, path, io.stdout)
        else
            local target = dir .. "/" .. fileName(scan)
            if exists(target) then
                skipped = skipped + 1
            else
                -- write next to it and rename, so an interrupted export leaves no half file
                local tmp = target .. ".part"
                local out = assert(io.open(tmp, "w"))
                local n = writeScan(scan, path, out)
                out:close()
                assert(os.rename(tmp, target))
                io.stderr:write(("%s: %d auctions\n"):format(target, n))
                total, written = total + n, written + 1
            end
        end
    end
end
if dir then
    io.stderr:write(
        ("%d new scan(s), %d auctions; %d already exported\n"):format(written, total, skipped)
    )
else
    io.stderr:write(("%d auctions from %d file(s)\n"):format(total, #paths))
end
