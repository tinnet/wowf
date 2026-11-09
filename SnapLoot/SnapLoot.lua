-- SnapLoot: when the game decides to auto loot (auto loot setting on, or the
-- auto-loot modifier held), take every slot in one go on LOOT_READY instead of
-- waiting for the default loot frame to work through them.
-- Left to the game: locked slots (group loot rolls), bind-on-pickup
-- confirmations, and anything that doesn't fit in your bags (the loot window
-- then stays open as usual).

local THROTTLE = 0.3 -- LOOT_READY can fire twice for the same loot window
local last = 0

local f = CreateFrame("Frame")
f:RegisterEvent("LOOT_READY")
f:SetScript("OnEvent", function(_, _, autoloot)
    if not autoloot then
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
end)
