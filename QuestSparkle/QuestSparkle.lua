-- The game can sparkle lootable quest objects, but only while this CVar is on,
-- and changing graphics quality presets switches it back off. Keep it on.
local CVAR = "outlineModeShowLootEffectWhenDisabled"

-- CVars whose change can reset ours (compared lowercase)
local RESETTERS = {
    graphicsquality = true,
    raidgraphicsquality = true,
    [CVAR:lower()] = true,
}

local f = CreateFrame("Frame")
local queued = false

local function apply()
    queued = false
    if InCombatLockdown() then
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if C_CVar.GetCVar(CVAR) ~= "1" then
        C_CVar.SetCVar(CVAR, "1")
    end
end

f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_ENABLED" then
        f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        apply()
    elseif event == "CVAR_UPDATE" then
        -- a preset changes many CVars at once; settle, then check once
        if name and RESETTERS[name:lower()] and not queued then
            queued = true
            C_Timer.After(1, apply)
        end
    else -- PLAYER_LOGIN
        apply()
    end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CVAR_UPDATE")
