-- SnapLoot: when the game decides to auto loot (auto loot setting on, or the
-- auto-loot modifier held), take every slot in one go on LOOT_READY instead of
-- waiting for the default loot frame to work through them.
-- Left to the game: locked slots (group loot rolls), bind-on-pickup
-- confirmations, and anything that doesn't fit in your bags (the loot window
-- then stays open as usual).
-- Options > AddOns > SnapLoot: on/off, plus the game's own Auto Loot setting.

local THROTTLE = 0.3 -- LOOT_READY can fire twice for the same loot window
local last = 0
local db

local function onLootReady(autoloot)
    if not (db.enabled and autoloot) then
        return
    end
    local now = GetTime()
    if now - last < THROTTLE then
        return
    end
    last = now
    for slot = GetNumLootItems(), 1, -1 do
        local locked = select(6, GetLootSlotInfo(slot))
        if not locked then
            LootSlot(slot)
        end
    end
end

local function registerSettings()
    local category = Settings.RegisterVerticalLayoutCategory("SnapLoot")

    local enabled = Settings.RegisterAddOnSetting(
        category,
        "SNAPLOOT_ENABLED",
        "enabled",
        db,
        Settings.VarType.Boolean,
        "Enable SnapLoot",
        Settings.Default.True
    )
    Settings.CreateCheckbox(
        category,
        enabled,
        "Take all loot at once whenever the game auto loots."
    )

    -- Mirrors the game's own CVar (also under Options > Controls), since
    -- SnapLoot only acts when auto loot applies.
    local autoLoot = Settings.RegisterProxySetting(
        category,
        "SNAPLOOT_AUTO_LOOT_CVAR",
        Settings.VarType.Boolean,
        "Auto Loot (game setting)",
        false,
        function()
            return C_CVar.GetCVarBool("autoLootDefault")
        end,
        function(value)
            C_CVar.SetCVar("autoLootDefault", value and "1" or "0")
        end
    )
    Settings.CreateCheckbox(
        category,
        autoLoot,
        "The game's Auto Loot setting (same as Options > Controls). "
            .. "Holding the Loot Key (Options > Controls, Shift by default) inverts it per loot window."
    )

    Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg)
    if event == "LOOT_READY" then
        onLootReady(arg)
    elseif arg == "SnapLoot" then
        self:UnregisterEvent("ADDON_LOADED")
        SnapLootDB = SnapLootDB or {}
        db = SnapLootDB
        registerSettings() -- fills db.enabled with the default if unset
        self:RegisterEvent("LOOT_READY")
    end
end)
