-- DustToDust: saved settings, shared helpers, the material prices everything is valued at.
local addonName, ns = ...
local Data, Logic = ns.Data, ns.Logic

local ENCHANTING = 333 -- skill line
local STALE = 2 * 86400 -- a price older than this is shown as stale

local DEFAULTS = {
    cut = 5, -- percent
    duration = 3, -- 1 = 2 h, 2 = 8 h, 3 = 24 h
    useMyself = false,
    minProfit = 1, -- silver
    minMargin = 10, -- percent of the buyout
    maxLoss = 50, -- percent
    onlyDeals = false,
    onlySkill = false,
    brackets = {}, -- band max -> true
    prices = {}, -- material -> our last check { lowest, depth, total, deposits = {d1, d2, d3}, at }
    observed = {}, -- bucket key -> { n, got = { "mat:qty" -> count } }
}

ns.matNames = {}
for _, m in ipairs(Data.MATERIALS) do
    ns.matNames[m[1]] = m[2]
end

function ns.chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99DustToDust|r: " .. msg)
end

function ns.money(copper)
    if not copper then
        return "?"
    end
    copper = math.floor(copper + 0.5)
    if copper < 0 then
        return "-" .. GetMoneyString(-copper, true)
    end
    return GetMoneyString(copper, true)
end

function ns.matName(mat)
    return C_Item.GetItemInfo(mat) or ns.matNames[mat] or ("item " .. mat)
end

-- "3 min", "5 h", "2 days"
function ns.age(seconds)
    if seconds < 3600 then
        return ("%d min"):format(math.max(1, math.floor(seconds / 60)))
    elseif seconds < 86400 then
        return ("%d h"):format(math.floor(seconds / 3600))
    end
    return ("%d days"):format(math.floor(seconds / 86400))
end

-- The settings as Logic wants them.
function ns.opts()
    local db = ns.db
    return {
        cut = db.cut / 100,
        useMyself = db.useMyself,
        minProfit = db.minProfit * 100,
        minMargin = db.minMargin / 100,
        maxLoss = db.maxLoss / 100,
    }
end

-- Your Enchanting skill, or nil without Enchanting.
function ns.enchanting()
    local p1, p2 = GetProfessions()
    for _, index in ipairs({ p1 or 0, p2 or 0 }) do
        if index > 0 then
            local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
            if skillLine == ENCHANTING then
                return rank
            end
        end
    end
end

---------------------------------------------------------------------------
-- Material prices: our own last check, or Auctionator's when it's at least as recent.
---------------------------------------------------------------------------
local function auctionator(mat)
    local atr = _G["Auctionator"] -- optional dependency
    local api = atr and atr.API and atr.API.v1
    if not api then
        return nil
    end
    local ok, price = pcall(api.GetAuctionPriceByItemID, addonName, mat)
    if not ok or not price or price <= 0 then
        return nil
    end
    local okAge, days = pcall(api.GetAuctionAgeByItemID, addonName, mat)
    return price, okAge and days or nil
end

-- A material's price: { lowest, deposit (per unit, for the chosen duration; nil when not
-- known), source ("checked" or "Auctionator"), age (seconds; nil when unknown), stale,
-- depth }. Nil when nobody has a price.
function ns.matPrice(mat)
    local own = ns.db.prices[mat]
    local ownAge = own and (time() - own.at)
    local deposit = own and own.deposits and own.deposits[ns.db.duration]
    local price, days = auctionator(mat)
    if own and (not price or not days or math.floor(ownAge / 86400) <= days) then
        return {
            lowest = own.lowest,
            deposit = deposit,
            source = "checked",
            age = ownAge,
            stale = ownAge > STALE,
            depth = own.depth,
        }
    end
    if price then
        local age = days and days * 86400
        return {
            lowest = price,
            deposit = deposit,
            source = "Auctionator",
            age = age,
            stale = not age or age > STALE,
        }
    end
end

local nets -- material -> net price per unit, for the current settings and prices

-- What each material is worth to you per unit (Logic.net), built once until something
-- changes.
function ns.netPrices()
    if not nets then
        nets = {}
        local opts = ns.opts()
        for _, m in ipairs(Data.MATERIALS) do
            local p = ns.matPrice(m[1])
            if p then
                nets[m[1]] = Logic.net(p.lowest, p.deposit, opts)
            end
        end
    end
    return nets
end

-- Prices or settings changed: everything is valued again.
local listeners = {}
function ns.onChange(fn)
    listeners[#listeners + 1] = fn
end

function ns.changed()
    nets = nil
    for _, fn in ipairs(listeners) do
        fn()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    DustToDustDB = DustToDustDB or {}
    for k, v in pairs(DEFAULTS) do
        if DustToDustDB[k] == nil then
            DustToDustDB[k] = type(v) == "table" and {} or v
        end
    end
    DustToDustDB.panelShown = nil -- from version 1; the panel now always starts closed
    ns.db = DustToDustDB
    if ns.registerSettings then
        ns.registerSettings()
    end
end)

SLASH_DUSTTODUST1 = "/dtd"
SLASH_DUSTTODUST2 = "/dusttodust"
SlashCmdList.DUSTTODUST = function(msg)
    local cmd = (msg or ""):lower():match("^(%S*)")
    if cmd == "data" then
        ns.showData()
    elseif cmd == "prices" then
        for _, m in ipairs(Data.MATERIALS) do
            local p = ns.matPrice(m[1])
            local net = ns.netPrices()[m[1]]
            ns.chat(
                p
                        and ("%s: %s, worth %s to you (%s, %s)"):format(
                            ns.matName(m[1]),
                            ns.money(p.lowest),
                            ns.money(net),
                            p.source,
                            p.age and ns.age(p.age) .. " old" or "age unknown"
                        )
                    or (ns.matName(m[1]) .. ": no price")
            )
        end
    elseif cmd == "options" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory:GetID())
        end
    else
        ns.chat("/dtd data (your disenchants vs the table), /dtd prices, /dtd options")
        ns.chat("The panel is next to the auction house: its Dust tab shows or hides it.")
    end
end
