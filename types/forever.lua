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

--- Blizzard_FrameXMLBase/Constants.lua
---@type integer
NUM_BAG_SLOTS = 4

--- Blizzard_SharedXMLGame/Tooltip/TooltipDataRules.lua
---@type table
TooltipDataProcessor = {}

--- Blizzard_SharedXML (templates, scroll boxes, sliders)
---@type function
ButtonFrameTemplate_HidePortrait = nil
---@type function
PanelTemplates_TabResize = nil
---@type function
PanelTemplates_SelectTab = nil
---@type function
PanelTemplates_DeselectTab = nil
---@type function
CreateDataProvider = nil
---@type function
CreateScrollBoxListLinearView = nil
---@type table
ScrollBoxConstants = {}
---@type table
ScrollUtil = {}
---@type table
NineSliceUtil = {}
---@type table
MinimalSliderWithSteppersMixin = {}
---@type table
SOUNDKIT = {}

--- Blizzard_GameTooltip/Mainline/GameTooltip.lua
---@type function
GameTooltip_Hide = nil

--- Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua
---@type function
HandleModifiedItemClick = nil

--- Blizzard_AuctionHouseUI (load on demand: only once the auction house has opened)
---@type table
AuctionHouseUtil = {}
---@type table
AuctionHouseSearchContext = {}
