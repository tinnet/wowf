---@meta
-- FrameXML globals that the annotations in .cache/ don't declare.
-- Do NOT stub game API functions here: if LuaLS says a function is undefined,
-- check .cache/wow-ui-source-forever (see CLAUDE.md) first. Forever's API is
-- retail-style (C_Spell, C_SpellBook, ...); classic globals like GetSpellInfo
-- do not exist and stubbing them hides real load errors.

--- Frame names closed by Escape
---@type string[]
UISpecialFrames = {}

---@type table<string, fun(msg: string, editBox: table)>
SlashCmdList = {}

---@type MessageFrame
DEFAULT_CHAT_FRAME = {}

--- Blizzard_FrameXMLBase/Constants.lua
---@type integer
INVSLOT_MAINHAND = 16

--- Blizzard_Settings_Shared/Blizzard_Settings.lua (the Options panel API)
---@type table
Settings = {}
