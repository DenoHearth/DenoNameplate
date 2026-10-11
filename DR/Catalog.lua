-- Taken from Forever Simple DR 0.8.0 by Tarolg (CurseForge project 1724602), MIT License,
-- see DR/LICENSE-ForeverDR. Changed here: the file's table is Deno Nameplate's own `DR` table
-- instead of the addon table, and the chat prefix. The rules and sources are his.
local _, addon = ...
addon.DR = addon.DR or {}
local ns = addon.DR
-- Provisional spell -> DR category catalog, revision 1.
--
-- Forever's generated API exposes Blizzard's modern SpellDiminishCategory set
-- (Stun, Incapacitate, Disorient, Silence, Root, Disarm, Taunt, AoEKnockback).
-- The server's per-spell assignment is not published: public Forever spell
-- data lists mechanics, not DR categories. These entries therefore follow the
-- modern category of each Classic-era effect and are only a fallback. When the
-- native feed is readable, its category always wins over this table, and users
-- can override any ID in Options -> AddOns -> Forever DR -> Custom spells.
--
-- Spell and item IDs shared with ForeverCooldowns (CCRules/Candidates/ForeverCooldowns)
-- were checked there against exact Forever pages; the rest are Classic-era IDs
-- that are still unverified on Forever and are marked with "unverified" below.
ns.CATALOG_REVISION = 1
ns.spells = {}

-- via: IDs whose knowledge means *you* can produce the effect (parent ability,
-- pet ability or item). Without via, the effect ID itself is checked.
-- aoe: the effect has no single cast target; only per-unit evidence applies it.
local function Add(category, ids, options)
    for _, id in ipairs(ids) do
        local entry = { category = category }
        for key, value in pairs(options or {}) do entry[key] = value end
        ns.spells[id] = entry
    end
end
local function Item(category, itemID, ids, options)
    options = options or {}
    options.item = itemID
    Add(category, ids, options)
end

-- Stun
Add("Stun", { 1833 }) -- Cheap Shot (unverified)
Add("Stun", { 408, 8643 }) -- Kidney Shot
Add("Stun", { 853, 5588, 5589, 10308 }) -- Hammer of Justice
Add("Stun", { 5211, 6798, 8983 }) -- Bash
Add("Stun", { 9005, 9823, 9827 }) -- Pounce (unverified)
Add("Stun", { 7922 }, { via = { 100, 6178, 11578 } }) -- Charge Stun
Add("Stun", { 20253 }, { via = { 20252 } }) -- Intercept Stun ranks
Add("Stun", { 20614 }, { via = { 20616 } })
Add("Stun", { 20615 }, { via = { 20617 } })
Add("Stun", { 12809 }) -- Concussion Blow
Add("Stun", { 19577, 24394 }, { via = { 19577 } }) -- Intimidation and its pet stun (24394 unverified)
Add("Stun", { 20549 }, { aoe = true }) -- War Stomp
Add("Stun", { 12355 }, { proc = true }) -- Impact (unverified)
Add("Stun", { 15269 }, { proc = true }) -- Blackout (unverified)
Add("Stun", { 5530 }, { proc = true }) -- Mace Stun Effect (unverified)
Add("Stun", { 12798 }, { proc = true }) -- Revenge Stun (unverified)
Add("Stun", { 20170 }, { proc = true }) -- Seal of Justice stun (unverified)
Add("Stun", { 19410 }, { proc = true }) -- Improved Concussive Shot (unverified)
Item("Stun", 1404, { 835 }, { aoe = true }) -- Tidal Charm (item ID unverified)
Item("Stun", 4370, { 4065 }, { aoe = true }) -- Large Copper Bomb
Item("Stun", 4374, { 4066 }, { aoe = true }) -- Small Bronze Bomb
Item("Stun", 4380, { 4067 }, { aoe = true }) -- Big Bronze Bomb
Item("Stun", 4390, { 4068 }, { aoe = true }) -- Iron Grenade
Item("Stun", 4394, { 4069 }, { aoe = true }) -- Big Iron Bomb
Item("Stun", 10562, { 12543 }, { aoe = true }) -- Hi-Explosive Bomb
Item("Stun", 15993, { 19769 }, { aoe = true }) -- Thorium Grenade
Item("Stun", 16005, { 19784 }, { aoe = true }) -- Dark Iron Bomb
Item("Stun", 10588, { 22641, 13327 }) -- Goblin Rocket Helmet: Reckless Charge use and its stun

-- Incapacitate
Add("Incapacitate", { 118, 12824, 12825, 12826, 28271, 28272 }) -- Polymorph (incl. Turtle/Pig)
Add("Incapacitate", { 6770, 2070, 11297 }) -- Sap
Add("Incapacitate", { 1776, 1777, 8629, 11285, 11286 }) -- Gouge
Add("Incapacitate", { 20066 }) -- Repentance
Add("Incapacitate", { 3355 }, { via = { 1499 }, aoe = true }) -- Freezing Trap effects
Add("Incapacitate", { 14308 }, { via = { 14310 }, aoe = true })
Add("Incapacitate", { 14309 }, { via = { 14311 }, aoe = true })
Add("Incapacitate", { 2637, 18657, 18658 }) -- Hibernate (druids in forms)
Add("Incapacitate", { 9484, 9485, 10955 }) -- Shackle Undead (unverified)
Add("Incapacitate", { 19386, 24132, 24133 }) -- Wyvern Sting
Add("Incapacitate", { 6789, 17925, 17926 }) -- Death Coil (horror)
Add("Incapacitate", { 19503 }) -- Scatter Shot

-- Disorient (fears, Blind, Seduction, Mind Control)
Add("Disorient", { 5782, 6213, 6215 }) -- Fear
Add("Disorient", { 5484, 17928 }, { aoe = true }) -- Howl of Terror
Add("Disorient", { 8122, 8124, 10888, 10890 }, { aoe = true }) -- Psychic Scream
Add("Disorient", { 5246 }, { aoe = true }) -- Intimidating Shout
Add("Disorient", { 20511 }, { via = { 5246 } }) -- Intimidating Shout primary-target effect
Add("Disorient", { 6358 }, { pet = true }) -- Seduction (Succubus)
Add("Disorient", { 2094 }) -- Blind
Add("Disorient", { 605, 10911, 10912 }) -- Mind Control
Item("Disorient", 10726, { 13180, 13181 }) -- Gnomish Mind Control Cap
Item("Disorient", 4852, { 5134 }, { aoe = true }) -- Flash Bomb (beasts, incl. feral druids)

-- Silence
Add("Silence", { 15487 }) -- Silence
Add("Silence", { 24259 }, { via = { 19244, 19647 }, pet = true }) -- Spell Lock silence
Add("Silence", { 18469 }, { via = { 2139 } }) -- Counterspell - Silenced (talent)
Add("Silence", { 18425 }, { via = { 1766, 1767, 1768, 1769 } }) -- Improved Kick silence
Add("Silence", { 18498 }, { via = { 72, 1671, 1672 } }) -- Improved Shield Bash silence
Item("Silence", 16040, { 19821 }, { aoe = true }) -- Arcane Bomb (unverified)

-- Root
Add("Root", { 339, 1062, 5195, 5196, 9852, 9853 }) -- Entangling Roots
Add("Root", { 122, 865, 6131, 10230 }, { aoe = true }) -- Frost Nova
Add("Root", { 19970, 19971, 19972, 19973, 19974, 19975 }, -- Nature's Grasp roots (unverified)
    { via = { 16689, 16810, 16811, 16812, 16813, 17329 } })
Add("Root", { 12494 }, { proc = true }) -- Frostbite (unverified)
Add("Root", { 23694 }, { proc = true }) -- Improved Hamstring (unverified)
Add("Root", { 19185 }, { proc = true }) -- Entrapment (unverified)
Add("Root", { 19306, 20909, 20910 }) -- Counterattack (unverified)
Item("Root", 10720, { 13099, 13120 }) -- Net-o-Matic Projector (13099 unverified)

-- Disarm
Add("Disarm", { 676 }) -- Disarm (unverified)
Add("Disarm", { 14251 }) -- Riposte (unverified)

-- Taunt (hidden by default: taunts do not control players)
Add("Taunt", { 355, 694, 7400, 7402, 20559, 20560, 1161, 6795, 5209 }) -- (unverified)

-- User rules override the bundled category of the same ID.
function ns.CategoryOf(id)
    if type(id) ~= "number" then return end
    local custom = ns.db and ns.db.custom[id]
    if custom then return custom end
    local entry = ns.spells[id]
    return entry and entry.category
end
function ns.SpellEntry(id)
    local entry = ns.spells[id]
    local custom = ns.db and ns.db.custom[id]
    if custom and (not entry or entry.category ~= custom) then return { category = custom, custom = true } end
    return entry
end

-- Every tracked ID, including user rules. Rebuilt when rules change.
function ns.TrackedIDs()
    local ids = {}
    for id in pairs(ns.spells) do ids[id] = true end
    for id in pairs(ns.db and ns.db.custom or {}) do ids[id] = true end
    return ids
end

-- Icons stand in for a category when no spell icon or native icon exists.
ns.CATEGORY_ICON_SPELLS = {
    Stun = 408, Incapacitate = 118, Disorient = 5782, Silence = 15487,
    Root = 122, Disarm = 676, Taunt = 355, AoEKnockback = nil,
}
local QUESTION_MARK = 134400
local iconCache, nativeIcons = {}, {}
function ns.SetNativeCategoryIcon(category, icon)
    if ns.IsCategory(category) and ns.Number(icon, 1) then nativeIcons[category] = icon end
end
function ns.SpellIcon(id)
    if type(id) ~= "number" then return end
    if iconCache[id] then return iconCache[id] end
    local icon = C_Spell.GetSpellTexture(id)
    if ns.Number(icon, 1) or ns.Text(icon) then
        iconCache[id] = icon
        return icon
    end
end
function ns.CategoryIcon(category)
    if nativeIcons[category] then return nativeIcons[category] end
    return ns.SpellIcon(ns.CATEGORY_ICON_SPELLS[category]) or QUESTION_MARK
end
function ns.SpellName(id)
    local name = type(id) == "number" and C_Spell.GetSpellName(id)
    if ns.Text(name) then return name end
    return type(id) == "number" and ("Spell " .. id) or "Unknown"
end

-- Categories the player can produce: known class/racial spells, known pet
-- spells, and (optionally) catalog items currently in the bags.
ns.mine = {}
local function Known(id)
    local known = C_SpellBook.IsSpellKnown(id)
    if ns.Bool(known) and known then return true end
    local pet = C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Pet)
    return ns.Bool(pet) and pet
end
local function HasItem(itemID)
    local count = C_Item.GetItemCount(itemID)
    return ns.Number(count, 1)
end
function ns.RefreshMine()
    local mine, useItems = {}, ns.db and ns.db.items
    local function Check(id, entry)
        if mine[entry.category] then return end
        if entry.item then
            if useItems and HasItem(entry.item) then mine[entry.category] = true end
            return
        end
        for _, parent in ipairs(entry.via or { id }) do
            if Known(parent) then mine[entry.category] = true; return end
        end
    end
    for id, entry in pairs(ns.spells) do Check(id, entry) end
    for id, category in pairs(ns.db and ns.db.custom or {}) do Check(id, { category = category }) end
    ns.mine = mine
end

function ns.ShouldShow(category)
    local mode = ns.GetCategoryMode(category)
    if mode == "always" then return true end
    if mode == "never" then return false end
    return ns.db.filter == "all" or ns.mine[category] == true
end
