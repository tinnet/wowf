---@meta
-- Globals that exist on the WoW Forever (1.60.x) client but are missing from
-- Ketho's retail-oriented API annotations. Only add things verified in-game.

---@type table<string, fun(msg: string, editBox: table)>
SlashCmdList = {}

--- Frame names closed by Escape (FrameXML)
---@type string[]
UISpecialFrames = {}

---@type MessageFrame
DEFAULT_CHAT_FRAME = {}

BOOKTYPE_SPELL = "spell"
BOOKTYPE_PET = "pet"

---@param spell number|string spellID or name
---@return string? name
---@return string? rank
---@return number icon
---@return number castTime
---@return number minRange
---@return number maxRange
---@return number spellID
function GetSpellInfo(spell) end

---@param spell number|string
---@return string? subtext e.g. "Rank 3"
function GetSpellSubtext(spell) end

---@return number numTabs
function GetNumSpellTabs() end

---@param tab number
---@return string name
---@return number texture
---@return number offset
---@return number numSlots
function GetSpellTabInfo(tab) end

---@param index number spellbook slot
---@param bookType string BOOKTYPE_SPELL or BOOKTYPE_PET
---@return string? spellType "SPELL", "FUTURESPELL", "FLYOUT", ...
---@return number? id
function GetSpellBookItemInfo(index, bookType) end

---@param spell number|string
function PickupSpell(spell) end
