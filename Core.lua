-- Deno Nameplate for WoW: Forever (interface 16001).
-- Clean, compact nameplates in the style Project Ascension's client uses, written from
-- scratch for Forever. Everything follows the Forever display rules: a secret value goes
-- from the API straight into a widget, a curve or a formatter, never through a Lua operator.
local ADDON, ns = ...

ns.WHITE = "Interface\\Buttons\\WHITE8X8"

-- Largest value the client accepts for nameplateMaxDistance (0-60 yards).
ns.MAX_DISTANCE = 60

------------------------------------------------------------------------------------------
-- Defaults: target scale 1.2, enemy health bar 112x10 with health text shown in a
-- monochrome outline; everything else small and plain.
------------------------------------------------------------------------------------------
local function UnitGroup(isEnemy)
	return {
		name = { displayName = true, font = "Friz Quadrata TT", fontSize = 8, fontFlags = "NONE" },
		health = {
			nameOnly = false,
			width = 110,
			height = 4,
			textFormat = "perc",
			showTextFormat = false,
			font = "Friz Quadrata TT",
			fontSize = 8,
			fontFlags = "NONE",
			statusBar = "Blizzard2",
			useClassColor = true,
			backgroundColor = { 0.2, 0.2, 0.2, 0.85 },
		},
		castBar = {
			enabled = isEnemy,
			font = "Friz Quadrata TT",
			fontSize = 8,
			fontFlags = "NONE",
			statusBar = "Blizzard2",
			height = 10,
		},
		levelIndicator = { showPlayerLevel = true, showNPCLevel = isEnemy },
		objectiveIcons = { showQuestObjectives = true, iconScale = 0.65, anchor = "LEFT" },
	}
end

ns.defaults = {
	general = {
		useClassicStyle = false,
		maxDistance = ns.MAX_DISTANCE,
		showAuras = true,
		showCC = true,          -- your own crowd control as a larger icon over the plate
		ccGlowSeconds = 3,      -- its glow and red number start this many seconds before the end
		showPurge = true,       -- enemy magic buffs you can remove, beside the plate
		showDR = true,          -- diminishing returns of crowd control, left of the plate
		drNPCs = false,         -- also on hostile NPCs (by the rules for players: a guess there)
		executeColor = true,    -- enemy health bar turns orange in execute range
		executePercent = 25,
		hideWorldNames = false, -- the game's own floating names; off: the addon never touches them unless he switches this on
		showBox = false,
		minimap = { show = true, angle = 200 },
		clickable = { width = 0, height = 0, targetScale = 1.2 },
	},
	friendly = UnitGroup(false),
	enemy = UnitGroup(true),
}
ns.defaults.enemy.health.showTextFormat = true
ns.defaults.enemy.health.width = 112
ns.defaults.enemy.health.height = 10
ns.defaults.enemy.health.fontFlags = "OUTLINE"

local function CopyDefaults(src, dst)
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then dst[key] = {} end
			CopyDefaults(value, dst[key])
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
	return dst
end

------------------------------------------------------------------------------------------
-- Media. Built-in lists so the addon needs no library; LibSharedMedia entries are added
-- when another addon has loaded it.
------------------------------------------------------------------------------------------
ns.fonts = {
	["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
	["Arial Narrow"] = "Fonts\\ARIALN.TTF",
	["Morpheus"] = "Fonts\\MORPHEUS.TTF",
	["Skurri"] = "Fonts\\SKURRI.TTF",
}

ns.statusBars = {
	["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
	["Blizzard2"] = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",
	["Raid"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
	["Flat"] = ns.WHITE,
}

ns.fontFlags = {
	NONE = "",
	OUTLINE = "OUTLINE",
	THICKOUTLINE = "THICKOUTLINE",
}

-- Monochrome draws text without smoothing, which looks jagged on a 4K screen (his words,
-- 2026-10-18: "make all fonts 4k"). Saved monochrome choices become the smooth equivalent.
local SMOOTH = { MONOCHROME = "NONE", MONOCHROMEOUTLINE = "OUTLINE" }

local function SmoothFonts(db)
	for _, group in ipairs({ "friendly", "enemy" }) do
		for _, part in ipairs({ "name", "health", "castBar" }) do
			local options = db[group] and db[group][part]
			if options and SMOOTH[options.fontFlags] then options.fontFlags = SMOOTH[options.fontFlags] end
		end
	end
end

local function SharedMedia()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function ns.MediaList(kind)
	local builtin = kind == "font" and ns.fonts or ns.statusBars
	local list = {}
	for name in pairs(builtin) do list[#list + 1] = name end
	local lsm = SharedMedia()
	if lsm then
		for _, name in ipairs(lsm:List(kind)) do
			if not builtin[name] then list[#list + 1] = name end
		end
	end
	table.sort(list)
	return list
end

function ns.FetchFont(name)
	local lsm = SharedMedia()
	return ns.fonts[name] or (lsm and lsm:Fetch("font", name, true)) or ns.fonts["Friz Quadrata TT"]
end

function ns.FetchStatusBar(name)
	local lsm = SharedMedia()
	return ns.statusBars[name] or (lsm and lsm:Fetch("statusbar", name, true)) or ns.statusBars["Blizzard2"]
end

function ns.SetFont(fontString, name, size, flags)
	fontString:SetFont(ns.FetchFont(name), size, ns.fontFlags[flags] or "")
end

------------------------------------------------------------------------------------------
-- Client settings the addon owns.
------------------------------------------------------------------------------------------
local pendingClientSettings = false

-- The game writes a large name over every NPC that has no NamePlate (too far, out of sight), which
-- reads as a second set of names beside the plates. Measured in client 70338: with these values
-- mobs carry a name only on their NamePlate, and quest givers, vendors and trainers keep theirs.
-- Player names too (2026-10-18, his picture: large names behind trees, no plate under them).
local WORLD_NAMES = {
	UnitNameFriendlyPlayerName = "0",
	UnitNameEnemyPlayerName = "0",
	UnitNameNPC = "0",
	UnitNameHostleNPC = "0",
	UnitNameFriendlySpecialNPCName = "1",
	UnitNameInteractiveNPC = "1",
}

-- The player's own values are kept in the saved settings and put back when the option is off.
local function ApplyWorldNames(general)
	if general.hideWorldNames then
		-- keys added in a later version are kept the first time they are changed
		local before = general.worldNamesBefore or {}
		for cvar in pairs(WORLD_NAMES) do
			if before[cvar] == nil then before[cvar] = C_CVar.GetCVar(cvar) end
		end
		general.worldNamesBefore = before
		for cvar, value in pairs(WORLD_NAMES) do
			if C_CVar.GetCVar(cvar) ~= value then C_CVar.SetCVar(cvar, value) end
		end
	elseif general.worldNamesBefore then
		for cvar, value in pairs(general.worldNamesBefore) do
			if WORLD_NAMES[cvar] and type(value) == "string" then C_CVar.SetCVar(cvar, value) end
		end
		general.worldNamesBefore = nil
	end
end

-- Clickable area, view distance and the game's own names. Refused in combat, so they wait for it to end.
function ns.ApplyClientSettings()
	if InCombatLockdown() then
		pendingClientSettings = true
		return
	end
	pendingClientSettings = false
	local general = ns.db.general
	C_CVar.SetCVar("nameplateMaxDistance", general.maxDistance)
	ApplyWorldNames(general)
	local clickable = general.clickable
	if clickable.width > 0 and clickable.height > 0 then
		C_NamePlate.SetNamePlateSize(clickable.width, clickable.height)
	end
end

-- Removable enemy buffs are only worth showing while you can remove one: his ask, 2026-10-11
-- ("only show dispellable buffs if I have the current pet to remove those like felhunter out
-- but if I have like a succubus then dont show"). True while you, or the pet that is out, know
-- a spell that takes a magic buff off an enemy.
local PURGES = {
	19505, 19731, 19734, 19736,     -- Devour Magic (Felhunter)
	370, 8012,                      -- Purge (Shaman)
	527, 988,                       -- Dispel Magic (Priest)
}
local canPurge = false

local FELHUNTER = 15             -- creature family; measured in client 70170: UnitCreatureFamily("pet") gives "Felhunter", 15

local function ReadCanPurge()
	local petOut = UnitExists("pet")
	-- by its kind: a Felhunter below level 30 has not learned Devour Magic yet, but it is the pet for it
	if not issecretvalue(petOut) and petOut then
		local _, family = UnitCreatureFamily("pet")
		if not issecretvalue(family) and family == FELHUNTER then return true end
	end
	for _, id in ipairs(PURGES) do
		local known = C_SpellBook.IsSpellKnown(id)
		if not issecretvalue(known) and known then return true end
		if not issecretvalue(petOut) and petOut then
			known = C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Pet)
			if not issecretvalue(known) and known then return true end
		end
	end
	return false
end

function ns.CanPurge() return canPurge end

local purgeWaiting = false
function ns.UpdateCanPurge()
	local now = ReadCanPurge()
	if now == canPurge and not purgeWaiting then return end
	canPurge = now
	-- the icon rows may only be switched out of combat; a pet summoned in a fight counts after it
	if InCombatLockdown() then
		purgeWaiting = true
		return
	end
	purgeWaiting = false
	if ns.db then ns.UpdateAllPlates() end
end

local purgeWatch = CreateFrame("Frame")
purgeWatch:RegisterEvent("PLAYER_LOGIN")
purgeWatch:RegisterEvent("SPELLS_CHANGED")
purgeWatch:RegisterEvent("PET_BAR_UPDATE")
purgeWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
purgeWatch:RegisterUnitEvent("UNIT_PET", "player")
-- One look a moment after the events, when the pet swap has settled.
local purgeQueued = false
purgeWatch:SetScript("OnEvent", function()
	if purgeQueued then return end
	purgeQueued = true
	C_Timer.After(1.5, function()
		purgeQueued = false
		ns.UpdateCanPurge()
	end)
end)

function ns.Refresh()
	ns.SetCCGlowSeconds(ns.db.general.ccGlowSeconds)
	ns.ApplyClientSettings()
	ns.UpdateAllPlates()
	ns.UpdateMinimapButton()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON then return end
		DenoNameplateDB = CopyDefaults(ns.defaults, DenoNameplateDB or {})
		ns.db = DenoNameplateDB
		SmoothFonts(ns.db)
		-- 1.3.4: the addon no longer changes the game's name settings on its own (his words,
		-- 2026-10-18: "dont ever do those things automatcially"). Once, the old default is
		-- switched off; ApplyClientSettings then puts his own values back.
		if not ns.db.general.namesOptIn then
			ns.db.general.namesOptIn = true
			ns.db.general.hideWorldNames = false
		end
	elseif event == "PLAYER_LOGIN" then
		-- First login: take the clickable size the client is using as the starting point.
		local clickable = ns.db.general.clickable
		if clickable.width <= 0 or clickable.height <= 0 then
			local width, height = C_NamePlate.GetNamePlateSize()
			if type(width) == "number" and type(height) == "number" then
				clickable.width, clickable.height = math.floor(width + 0.5), math.floor(height + 0.5)
			end
		end
		ns.db.general.ccGlowSeconds = ns.SetCCGlowSeconds(ns.db.general.ccGlowSeconds)
		ns.ApplyClientSettings()
		ns.StartDriver()
		ns.BuildOptions()
		ns.CreateMinimapButton()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingClientSettings then ns.ApplyClientSettings() end
		ns.AfterCombat()
	end
end)

SLASH_DENONAMEPLATE1 = "/dnp"
SLASH_DENONAMEPLATE2 = "/denonameplate"
SlashCmdList.DENONAMEPLATE = function()
	if ns.category then Settings.OpenToCategory(ns.category:GetID()) end
end
