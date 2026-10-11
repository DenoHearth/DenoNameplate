-- Taken from Forever Simple DR 0.8.0 by Tarolg (CurseForge project 1724602), MIT License,
-- see DR/LICENSE-ForeverDR. Changed here: the file's table is Deno Nameplate's own `DR` table
-- instead of the addon table, and the chat prefix. The rules and sources are his.
local _, addon = ...
addon.DR = addon.DR or {}
local ns = addon.DR
ns.VERSION = "0.8.0"
ns.SCHEMA = 1

-- Display order. Keys are the names of Enum.SpellDiminishCategory fields; the
-- numeric enum values are only ever resolved by name at runtime.
ns.CATEGORIES = { "Stun", "Incapacitate", "Disorient", "Silence", "Root", "Disarm", "Taunt", "AoEKnockback" }
ns.CATEGORY_LABELS = {
    Stun = "Stun", Incapacitate = "Incapacitate", Disorient = "Disorient / fear",
    Silence = "Silence", Root = "Root", Disarm = "Disarm", Taunt = "Taunt", AoEKnockback = "Knockback",
}
local isCategory = {}
for _, name in ipairs(ns.CATEGORIES) do isCategory[name] = true end
function ns.IsCategory(name) return isCategory[name] == true end

-- Always printed: slash replies, failures, refusals and requested status.
function ns.Print(message) print("|cffffcc59Deno Nameplate, diminishing returns:|r " .. message) end
-- Confirmations the settings panel already shows obey Chat messages.
-- Before saved settings load, chat counts as on.
function ns.Notice(message)
    if ns.db and ns.db.chat == false then return end
    ns.Print(message)
end

-- A value is usable by addon logic only when it is not secret. Tables must
-- also permit indexing: a public table reference can still guard its contents.
function ns.Public(value)
    return type(issecretvalue) == "function" and not issecretvalue(value)
        and (type(value) ~= "table" or canaccesstable(value))
end
function ns.Number(value, low, high)
    return ns.Public(value) and type(value) == "number" and value == value
        and value >= (low or -math.huge) and value <= (high or math.huge)
end
function ns.Text(value)
    return ns.Public(value) and type(value) == "string" and value ~= ""
end
function ns.Bool(value)
    return ns.Public(value) and type(value) == "boolean"
end

local sources = { native = true, auras = true, casts = true, group = true, feedback = true, assume = true }
ns.SOURCE_KEYS = sources
local defaults = {
    enabled = true, target = true, nameplates = true, npcs = false, locked = true,
    x = 0, y = -150, filter = "mine", items = true, resetTime = 18,
    iconSize = 30, plateSize = 20, plateOffset = 4, plateAnchor = "TOP",
    stackStyle = "pips", timer = true, swipe = true, iconSource = "spell",
    chat = true,
}
-- Options with a fixed range or value set. Colors are fixed by meaning.
local rules = {
    x = { -3000, 3000 }, y = { -3000, 3000 }, resetTime = { 10, 30 },
    iconSize = { 16, 64 }, plateSize = { 12, 40 }, plateOffset = { -40, 60 },
    filter = { mine = true, all = true }, plateAnchor = { TOP = true, BOTTOM = true },
    stackStyle = { pips = true, number = true, next = true }, iconSource = { spell = true, category = true },
}
ns.LIMITS = rules
local CATEGORY_MODES = { always = true, never = true }

local function Valid(key, value)
    local default = defaults[key]
    if default == nil or type(value) ~= type(default) then return false end
    local rule = rules[key]
    if type(value) == "number" then
        if value ~= value then return false end
        return not rule or (value >= rule[1] and value <= rule[2])
    elseif type(value) == "string" and rule then
        return rule[value] == true
    end
    return true
end

local function Fresh()
    ---@type table
    local db = { schema = ns.SCHEMA, sources = {}, categories = { Taunt = "never", AoEKnockback = "never" },
        custom = {}, learned = {} }
    for key, value in pairs(defaults) do rawset(db, key, value) end
    for key, value in pairs(sources) do db.sources[key] = value end
    return db
end

-- Validate without modifying the saved table. Unknown keys are retained.
local function Check(saved)
    if type(saved) ~= "table" then return "settings root is not a table" end
    if saved.schema ~= ns.SCHEMA then
        if type(saved.schema) == "number" and saved.schema > ns.SCHEMA then return "settings from a newer version" end
        return "unsupported settings schema"
    end
    for key in pairs(defaults) do
        if saved[key] ~= nil and not Valid(key, saved[key]) then return "invalid setting " .. key end
    end
    for _, key in ipairs({ "sources", "categories", "custom", "learned" }) do
        if saved[key] ~= nil and type(saved[key]) ~= "table" then return "invalid " .. key end
    end
    for key, value in pairs(saved.sources or {}) do
        if sources[key] ~= nil and type(value) ~= "boolean" then return "invalid source " .. tostring(key) end
    end
    for key, value in pairs(saved.categories or {}) do
        if isCategory[key] and not CATEGORY_MODES[value] then return "invalid category mode " .. tostring(key) end
    end
    for id, category in pairs(saved.custom or {}) do
        if type(id) ~= "number" or not isCategory[category] then return "invalid custom spell" end
    end
    return nil
end

-- Settings headings the player opened or closed (0.3.3): heading title to
-- true or false. UI state, not a setting: Check never looks at it, a bad one
-- is replaced with an empty table, and no reset clears it.
local MAX_OPEN_GROUPS = 200
local function ValidOpenGroups(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key, open in pairs(value) do
        count = count + 1
        if count > MAX_OPEN_GROUPS or type(key) ~= "string" or type(open) ~= "boolean" then return false end
    end
    return true
end

-- Whether a settings heading was left open (true), closed (false) or never
-- clicked (nil).
function ns.GroupOpen(key)
    local saved = ns.db and ns.db.openGroups
    if type(saved) ~= "table" then return nil end
    return saved[key]
end
function ns.SetGroupOpen(key, open)
    local db = ns.db
    if not db or type(key) ~= "string" or type(open) ~= "boolean" then return false end
    if type(db.openGroups) ~= "table" then db.openGroups = {} end
    local saved = db.openGroups
    if saved[key] == nil then
        local count = 0
        for _ in pairs(saved) do count = count + 1 end
        if count >= MAX_OPEN_GROUPS then return false end
    end
    saved[key] = open
    return true
end

-- Returns the live settings table, or nil and a reason. A rejected root is
-- left untouched so a newer or damaged save is never overwritten on logout.
function ns.LoadSettings(saved)
    if saved == nil then return Fresh() end
    local problem = Check(saved)
    if problem then return nil, problem end
    for key, value in pairs(defaults) do if saved[key] == nil then saved[key] = value end end
    saved.sources = saved.sources or {}
    for key, value in pairs(sources) do if saved.sources[key] == nil then saved.sources[key] = value end end
    saved.categories = saved.categories or {}
    saved.custom = saved.custom or {}
    -- Learned durations are a derived cache; drop malformed entries only.
    local learned = type(saved.learned) == "table" and saved.learned or {}
    for id, seconds in pairs(learned) do
        if type(id) ~= "number" or type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 or seconds > 600 then
            learned[id] = nil
        end
    end
    saved.learned = learned
    if not ValidOpenGroups(saved.openGroups) then saved.openGroups = {} end
    return saved
end

local listeners = {}
function ns.OnSettingChanged(callback) listeners[#listeners + 1] = callback end
local function Changed(key)
    for _, callback in ipairs(listeners) do callback(key) end
end

function ns.Get(key) return ns.db and ns.db[key] end
-- A setting's default, for the settings page's reset arrows.
function ns.Default(key) return defaults[key] end
function ns.Set(key, value)
    if not ns.db or not Valid(key, value) then return false end
    if ns.db[key] == value then return true end
    ns.db[key] = value
    Changed(key)
    return true
end
function ns.GetSource(key) return ns.db and ns.db.sources[key] == true end
function ns.SetSource(key, enabled)
    if not ns.db or sources[key] == nil or type(enabled) ~= "boolean" then return false end
    ns.db.sources[key] = enabled
    Changed("sources")
    return true
end
-- "auto" follows the global filter; "always" and "never" override it.
function ns.GetCategoryMode(category)
    return ns.db and ns.db.categories[category] or "auto"
end
function ns.SetCategoryMode(category, mode)
    if not ns.db or not isCategory[category] then return false end
    if mode == "auto" then ns.db.categories[category] = nil
    elseif CATEGORY_MODES[mode] then ns.db.categories[category] = mode
    else return false end
    Changed("categories")
    return true
end
local MAX_CUSTOM = 128
function ns.SetCustomSpell(id, category)
    if not ns.db or type(id) ~= "number" or id < 1 or id > 10000000 or id % 1 ~= 0 then return false end
    if category == nil then ns.db.custom[id] = nil
    elseif isCategory[category] then
        if ns.db.custom[id] == nil then
            local count = 0
            for _ in pairs(ns.db.custom) do count = count + 1 end
            if count >= MAX_CUSTOM then return false end
        end
        ns.db.custom[id] = category
    else return false end
    Changed("custom")
    return true
end

local MAX_LEARNED = 256
-- Longest full duration observed on an enemy player, per exact spell ID.
function ns.Learn(id, seconds)
    local learned = ns.db and ns.db.learned
    if not learned or type(id) ~= "number" or type(seconds) ~= "number" or seconds <= 0 or seconds > 600 then return end
    if learned[id] and learned[id] >= seconds then return end
    if not learned[id] then
        local count = 0
        for _ in pairs(learned) do count = count + 1 end
        if count >= MAX_LEARNED then return end
    end
    learned[id] = seconds
end
function ns.Learned(id) return ns.db and ns.db.learned[id] end

function ns.ResetDisplaySettings()
    if not ns.db then return end
    for _, key in ipairs({ "iconSize", "plateSize", "plateOffset", "plateAnchor", "stackStyle", "timer", "swipe", "iconSource" }) do
        ns.db[key] = defaults[key]
    end
    Changed("appearance")
end
function ns.ResetPosition()
    if not ns.db then return end
    ns.db.x, ns.db.y = defaults.x, defaults.y
    Changed("position")
end
