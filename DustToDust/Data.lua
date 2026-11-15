-- What weapons and armor disenchant into, and the Enchanting skill they need. Plain data.
--
-- Source: warcraft.wiki.gg "Disenchanting tables" and "Disenchanting" (fetched 2026-11-15;
-- the tables page is from 2021 and marked outdated, and isn't Classic-specific). Its rows
-- for item level 65 and below match Auctionator's Classic table. Not checked against
-- Forever yet: /dtd data compares your own disenchants with it.
local _, ns = ...
local Data = {}
ns.Data = Data

local STRANGE_DUST, SOUL_DUST, VISION_DUST, DREAM_DUST, ILLUSION_DUST =
    10940, 11083, 11137, 11176, 16204
local LESSER_MAGIC, GREATER_MAGIC = 10938, 10939
local LESSER_ASTRAL, GREATER_ASTRAL = 10998, 11082
local LESSER_MYSTIC, GREATER_MYSTIC = 11134, 11135
local LESSER_NETHER, GREATER_NETHER = 11174, 11175
local LESSER_ETERNAL, GREATER_ETERNAL = 16202, 16203
local SMALL_GLIMMERING, LARGE_GLIMMERING = 10978, 11084
local SMALL_GLOWING, LARGE_GLOWING = 11138, 11139
local SMALL_RADIANT, LARGE_RADIANT = 11177, 11178
local SMALL_BRILLIANT, LARGE_BRILLIANT = 14343, 14344
local NEXUS_CRYSTAL = 20725

-- Every material, in the order the price check asks for them, with a name for before the
-- client has loaded the item.
Data.MATERIALS = {
    { STRANGE_DUST, "Strange Dust" },
    { SOUL_DUST, "Soul Dust" },
    { VISION_DUST, "Vision Dust" },
    { DREAM_DUST, "Dream Dust" },
    { ILLUSION_DUST, "Illusion Dust" },
    { LESSER_MAGIC, "Lesser Magic Essence" },
    { GREATER_MAGIC, "Greater Magic Essence" },
    { LESSER_ASTRAL, "Lesser Astral Essence" },
    { GREATER_ASTRAL, "Greater Astral Essence" },
    { LESSER_MYSTIC, "Lesser Mystic Essence" },
    { GREATER_MYSTIC, "Greater Mystic Essence" },
    { LESSER_NETHER, "Lesser Nether Essence" },
    { GREATER_NETHER, "Greater Nether Essence" },
    { LESSER_ETERNAL, "Lesser Eternal Essence" },
    { GREATER_ETERNAL, "Greater Eternal Essence" },
    { SMALL_GLIMMERING, "Small Glimmering Shard" },
    { LARGE_GLIMMERING, "Large Glimmering Shard" },
    { SMALL_GLOWING, "Small Glowing Shard" },
    { LARGE_GLOWING, "Large Glowing Shard" },
    { SMALL_RADIANT, "Small Radiant Shard" },
    { LARGE_RADIANT, "Large Radiant Shard" },
    { SMALL_BRILLIANT, "Small Brilliant Shard" },
    { LARGE_BRILLIANT, "Large Brilliant Shard" },
    { NEXUS_CRYSTAL, "Nexus Crystal" },
}

-- Uncommon (green): dust, essence and maybe a shard, each a range of quantities split evenly
-- ("4-6" is 4, 5 or 6 at a third each). Armor and weapons share the materials but not the
-- chances: weapons give mostly essence. Chances in percent: { dust, essence, shard }.
-- A row covers item levels up to `max`, from the previous row's max + 1 (the first row
-- also covers anything lower).
local A, W = { 75, 20, 5 }, { 20, 75, 5 }
local W51 = { 22, 75, 3 } -- weapons from item level 51 up
Data.UNCOMMON = {
    -- stylua: ignore start
    { max = 15, dust = { STRANGE_DUST, 1, 2 }, essence = { LESSER_MAGIC, 1, 2 }, armor = { 80, 20, 0 }, weapon = { 20, 80, 0 } },
    { max = 20, dust = { STRANGE_DUST, 2, 3 }, essence = { GREATER_MAGIC, 1, 2 }, shard = SMALL_GLIMMERING, armor = A, weapon = W },
    { max = 25, dust = { STRANGE_DUST, 4, 6 }, essence = { LESSER_ASTRAL, 1, 2 }, shard = SMALL_GLIMMERING, armor = { 75, 15, 10 }, weapon = { 15, 75, 10 } },
    { max = 30, dust = { SOUL_DUST, 1, 2 }, essence = { GREATER_ASTRAL, 1, 2 }, shard = LARGE_GLIMMERING, armor = A, weapon = W },
    { max = 35, dust = { SOUL_DUST, 2, 5 }, essence = { LESSER_MYSTIC, 1, 2 }, shard = SMALL_GLOWING, armor = A, weapon = W },
    { max = 40, dust = { VISION_DUST, 1, 2 }, essence = { GREATER_MYSTIC, 1, 2 }, shard = LARGE_GLOWING, armor = A, weapon = W },
    { max = 45, dust = { VISION_DUST, 2, 5 }, essence = { LESSER_NETHER, 1, 2 }, shard = SMALL_RADIANT, armor = A, weapon = W },
    { max = 50, dust = { DREAM_DUST, 1, 2 }, essence = { GREATER_NETHER, 1, 2 }, shard = LARGE_RADIANT, armor = A, weapon = W },
    { max = 55, dust = { DREAM_DUST, 2, 5 }, essence = { LESSER_ETERNAL, 1, 2 }, shard = SMALL_BRILLIANT, armor = A, weapon = W51 },
    { max = 60, dust = { ILLUSION_DUST, 1, 2 }, essence = { GREATER_ETERNAL, 1, 2 }, shard = LARGE_BRILLIANT, armor = A, weapon = W51 },
    { max = 999, dust = { ILLUSION_DUST, 2, 5 }, essence = { GREATER_ETERNAL, 2, 3 }, shard = LARGE_BRILLIANT, armor = A, weapon = W51 },
    -- stylua: ignore end
}

-- Rare (blue) and epic (purple): the same for armor and weapons. Each result is
-- { chance %, material, min, max }.
Data.RARE = {
    { max = 25, { 100, SMALL_GLIMMERING, 1, 1 } },
    { max = 30, { 100, LARGE_GLIMMERING, 1, 1 } },
    { max = 35, { 100, SMALL_GLOWING, 1, 1 } },
    { max = 40, { 100, LARGE_GLOWING, 1, 1 } },
    { max = 45, { 100, SMALL_RADIANT, 1, 1 } },
    { max = 50, { 100, LARGE_RADIANT, 1, 1 } },
    { max = 55, { 100, SMALL_BRILLIANT, 1, 1 } },
    { max = 999, { 99.5, LARGE_BRILLIANT, 1, 1 }, { 0.5, NEXUS_CRYSTAL, 1, 1 } },
}

-- Epics below this item level disenchant like rares (the wiki: "fall within the ranges for
-- Uncommon/Rare items"; there are hardly any).
Data.EPIC_MIN = 40
Data.EPIC = {
    { max = 45, { 100, SMALL_RADIANT, 2, 4 } },
    { max = 50, { 100, LARGE_RADIANT, 2, 4 } },
    { max = 55, { 100, SMALL_BRILLIANT, 2, 4 } },
    { max = 60, { 100, NEXUS_CRYSTAL, 1, 1 } },
    { max = 999, { 100, NEXUS_CRYSTAL, 1, 2 } },
}

-- Enchanting skill needed, by item level ({ up to item level, skill }), any quality.
-- 225 for item level 61 and up is Classic's; the wiki's 275 for rares there is a later
-- expansion's. Not checked on Forever yet.
Data.SKILL = {
    { 20, 1 },
    { 25, 25 },
    { 30, 50 },
    { 35, 75 },
    { 40, 100 },
    { 45, 125 },
    { 50, 150 },
    { 55, 175 },
    { 60, 200 },
    { 999, 225 },
}

-- Weapons that can't be disenchanted: the wands enchanters make.
Data.NOT_DISENCHANTABLE = {
    [11287] = true, -- Lesser Magic Wand
    [11288] = true, -- Greater Magic Wand
    [11289] = true, -- Lesser Mystic Wand
    [11290] = true, -- Greater Mystic Wand
}

Data.WEAPON, Data.ARMOR = 2, 4 -- Enum.ItemClass
Data.UNCOMMON_QUALITY, Data.RARE_QUALITY, Data.EPIC_QUALITY = 2, 3, 4 -- Enum.ItemQuality
