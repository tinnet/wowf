-- SubjectToChange: when you attach an item to a mail with an empty subject, the subject
-- becomes the item's name ("Copper Ore (20)" for stacks). The game's own mail window does
-- this (SendMailFrame_Update), but stopped on Forever after a November 2026 maintenance:
-- https://github.com/ClassicWoWCommunity/forever-bugs/issues/575
--
-- Only a subject this addon filled is ever changed or cleared again, so a subject you typed
-- stays. Remove this once Blizzard fixes it.
local MAX_ATTACHMENTS = 12

local filled -- the subject we last put in, if it's still there

local function firstItemTitle()
    for i = 1, MAX_ATTACHMENTS do
        if HasSendMailItem(i) then
            local name, _, _, count = GetSendMailItem(i)
            if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
                if count and count > 1 then
                    return ("%s (%d)"):format(name, count)
                end
                return name
            end
        end
    end
end

local function update()
    local box = _G.SendMailSubjectEditBox
    if not box then
        return
    end
    local current = box:GetText()
    if current ~= "" and current ~= filled then
        filled = nil -- the player's own subject: leave it alone
        return
    end
    local title = firstItemTitle() or ""
    if title ~= current then
        box:SetText(title)
    end
    filled = title ~= "" and title or nil
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    C_Timer.After(0, update) -- after the game's own mail window has handled the event
end)
events:RegisterEvent("MAIL_SEND_INFO_UPDATE")
