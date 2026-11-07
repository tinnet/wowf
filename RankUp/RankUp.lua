local ADDON = ...
local NUM_SLOTS = 120
local BOOKTYPE = BOOKTYPE_SPELL or "spell"

local f = CreateFrame("Frame")
local pending = false   -- a scan is queued (debounce)

local function print_(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RankUp|r: " .. msg)
end

local function rankOf(spellID)
    local sub = GetSpellSubtext and GetSpellSubtext(spellID)
    return sub and tonumber(sub:match("(%d+)"))
end

-- name -> { id = spellID, rank = n } for the highest rank in the spellbook
local function buildBestRanks()
    local best = {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for i = offset + 1, offset + numSpells do
            local kind, id = GetSpellBookItemInfo(i, BOOKTYPE)
            if kind == "SPELL" and id then
                local name = GetSpellInfo(id)
                local rank = rankOf(id)
                if name and rank and (not best[name] or rank > best[name].rank) then
                    best[name] = { id = id, rank = rank }
                end
            end
        end
    end
    return best
end

local function scan()
    pending = false
    if InCombatLockdown() then
        -- only listen for leaving combat while a scan is waiting on it
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if GetCursorInfo() then
        -- don't clobber whatever the player is dragging; try again shortly
        pending = true
        C_Timer.After(1, scan)
        return
    end

    local best = buildBestRanks()
    local ignore = RankUpDB.ignore

    for slot = 1, NUM_SLOTS do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and id then
            local name = GetSpellInfo(id)
            local b = name and best[name]
            local cur = rankOf(id)
            if b and cur and b.id ~= id and b.rank > cur and not ignore[name] then
                PickupSpell(b.id)
                PlaceAction(slot)
                ClearCursor()
                print_(("%s: rank %d -> %d (slot %d)"):format(name, cur, b.rank, slot))
            end
        end
    end
end

local function queueScan(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 0.5, scan)
end

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        RankUpDB = RankUpDB or {}
        RankUpDB.ignore = RankUpDB.ignore or {}
        f:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        queueScan(2)
    elseif event == "LEARNED_SPELL_IN_TAB" or event == "CHARACTER_POINTS_CHANGED" then
        queueScan()
    elseif event == "PLAYER_REGEN_ENABLED" then
        f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        queueScan()
    end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("LEARNED_SPELL_IN_TAB")
f:RegisterEvent("CHARACTER_POINTS_CHANGED") -- talents can grant spells/ranks

SLASH_RANKUP1 = "/rankup"
SlashCmdList.RANKUP = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "ignore" and rest ~= "" then
        RankUpDB.ignore[rest] = true
        print_("ignoring " .. rest)
    elseif cmd == "unignore" and rest ~= "" then
        RankUpDB.ignore[rest] = nil
        print_("no longer ignoring " .. rest)
    elseif cmd == "list" then
        local n = 0
        for name in pairs(RankUpDB.ignore) do
            print_("  " .. name)
            n = n + 1
        end
        if n == 0 then print_("ignore list is empty") end
    elseif cmd == "scan" then
        scan()
    else
        print_("/rankup scan | ignore <Spell Name> | unignore <Spell Name> | list")
    end
end
