-- SnapLoot: when the game decides to auto loot (auto loot setting on, or the
-- auto-loot modifier held), take every slot in one go on LOOT_READY instead of
-- waiting for the default loot frame to work through them.
-- Left to the game: locked slots (group loot rolls), bind-on-pickup
-- confirmations, and anything that doesn't fit in your bags (the loot window
-- then stays open as usual).
-- Options > AddOns > SnapLoot: on/off, plus the game's own Auto Loot setting.

local ADDON = ...
local db
-- LOOT_READY can fire twice for the same loot window; act once per window
-- (reset on LOOT_CLOSED; the timeout only guards against a missed close).
local handledAt

local function onLootReady(autoloot)
    if not (db.enabled and autoloot) then
        return
    end
    local now = GetTime()
    if handledAt and now - handledAt < 2 then
        return
    end
    handledAt = now
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

    -- Read-only mirror of the game's Auto Loot CVar, since SnapLoot only acts
    -- when auto loot applies. Never write it from here: Forever's action bar
    -- (Blizzard_GamepadActionBars) caches autoLootDefault via a CVar callback,
    -- so an addon-side SetCVar taints that bar and blocks its interact key.
    local autoLoot = Settings.RegisterProxySetting(
        category,
        "SNAPLOOT_AUTO_LOOT_CVAR",
        Settings.VarType.Boolean,
        "Auto Loot (game setting)",
        false,
        function()
            return C_CVar.GetCVarBool("autoLootDefault")
        end,
        function() end
    )
    local initializer = Settings.CreateCheckbox(
        category,
        autoLoot,
        "Shows the game's Auto Loot setting; change it in Options > Controls. "
            .. "Holding the Loot Key (Shift by default; called Auto Loot Key while Auto Loot "
            .. "is off) inverts it per loot window."
    )
    initializer:AddModifyPredicate(function()
        return false
    end)

    Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg)
    if event == "LOOT_READY" then
        onLootReady(arg)
    elseif event == "LOOT_CLOSED" then
        handledAt = nil
    elseif arg == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        SnapLootDB = SnapLootDB or {}
        db = SnapLootDB
        registerSettings() -- fills db.enabled with the default if unset
        self:RegisterEvent("LOOT_READY")
        self:RegisterEvent("LOOT_CLOSED")
    end
end)
