-- NoSmallTalk: when an NPC's chat window has exactly one option and no quests (the
-- vendor's "Let me browse your goods", a flight master, a trainer), pick it right away.
-- The game already does this for some NPCs (selectOptionWhenOnlyOption); this covers
-- the rest. Hold Shift while talking to them to get the window as usual.
-- Left alone: quest-marked options ("(Quest)", they can start events or fights),
-- options you can't pick, ones that cost or give something, and NPCs the game says
-- must show their text (ForceGossip). Options asking for gold still ask.

local QUESTY = Enum.GossipOptionRecFlags.QuestLabelPrepend
    + Enum.GossipOptionRecFlags.PlayMovieLabelPrepend

local lastPicked -- option picked in this conversation, so a page that leads back to itself stops

local function onlyOption()
    if C_GossipInfo.GetNumAvailableQuests() > 0 or C_GossipInfo.GetNumActiveQuests() > 0 then
        return nil
    end
    if C_GossipInfo.ForceGossip() then
        return nil
    end
    local options = C_GossipInfo.GetOptions()
    if #options ~= 1 then
        return nil
    end
    local option = options[1]
    if
        option.selectOptionWhenOnlyOption -- the game picks it itself
        or option.status ~= Enum.GossipOptionStatus.Available
        or bit.band(option.flags, QUESTY) ~= 0
        or #option.rewards > 0
    then
        return nil
    end
    return option
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
        return
    end
    local option = onlyOption()
    if not option then
        return
    end
    local key = option.gossipOptionID or option.name
    if key == lastPicked then
        return
    end
    lastPicked = key
    if option.gossipOptionID then
        C_GossipInfo.SelectOption(option.gossipOptionID)
    else
        C_GossipInfo.SelectOptionByIndex(option.orderIndex)
    end
end)
