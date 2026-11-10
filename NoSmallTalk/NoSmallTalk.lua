-- NoSmallTalk: when an NPC's chat window has exactly one option and no quests (the
-- vendor's "Let me browse your goods", a flight master, a trainer), pick it right away.
-- The game already does this for some NPCs (selectOptionWhenOnlyOption); this covers
-- the rest. Hold Shift while talking to them to get the window as usual.
-- Left alone: quest-marked options ("(Quest)", they can start events or fights),
-- options you can't pick, ones that cost or give something, and NPCs the game says
-- must show their text (ForceGossip). Options asking for gold still ask.
-- /nosmalltalk says why the last window wasn't skipped.

local QUESTY = Enum.GossipOptionRecFlags.QuestLabelPrepend
    + Enum.GossipOptionRecFlags.PlayMovieLabelPrepend

local lastPicked -- option picked in this conversation, so a page that leads back to itself stops
local lastReason = "no NPC window seen yet"

-- The option to pick, or nil and why not.
local function onlyOption()
    local available = C_GossipInfo.GetNumAvailableQuests()
    local active = C_GossipInfo.GetNumActiveQuests()
    if available > 0 or active > 0 then
        return nil, ("it has quests (%d to take, %d in progress)"):format(available, active)
    end
    local options = C_GossipInfo.GetOptions()
    if #options ~= 1 then
        return nil, ("it has %d options"):format(#options)
    end
    local option = options[1]
    local about = ('"%s": status %s, flags %s, %d rewards, game picks it itself: %s'):format(
        option.name,
        tostring(option.status),
        tostring(option.flags),
        #option.rewards,
        tostring(option.selectOptionWhenOnlyOption)
    )
    if C_GossipInfo.ForceGossip() then
        return nil, "the game says this NPC's text must show (ForceGossip); " .. about
    elseif option.selectOptionWhenOnlyOption then
        return nil, "the game picks it itself; " .. about
    elseif option.status ~= Enum.GossipOptionStatus.Available then
        return nil, "the option isn't available; " .. about
    elseif bit.band(option.flags, QUESTY) ~= 0 then
        return nil, "the option is quest-marked; " .. about
    elseif #option.rewards > 0 then
        return nil, "the option has rewards; " .. about
    end
    return option, "picked " .. about
end

local f = CreateFrame("Frame")
f:RegisterEvent("GOSSIP_SHOW")
f:RegisterEvent("GOSSIP_CLOSED")
f:SetScript("OnEvent", function(_, event)
    if event == "GOSSIP_CLOSED" then
        lastPicked = nil
        return
    end
    if IsShiftKeyDown() then
        lastReason = "Shift was held"
        return
    end
    local option, reason = onlyOption()
    lastReason = reason
    if not option then
        return
    end
    local key = option.gossipOptionID or option.name
    if key == lastPicked then
        lastReason = "it led back to the option just picked; " .. reason
        return
    end
    lastPicked = key
    if option.gossipOptionID then
        C_GossipInfo.SelectOption(option.gossipOptionID)
    else
        C_GossipInfo.SelectOptionByIndex(option.orderIndex)
    end
end)

SLASH_NOSMALLTALK1 = "/nosmalltalk"
SlashCmdList.NOSMALLTALK = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99NoSmallTalk|r last NPC window: " .. lastReason)
end
