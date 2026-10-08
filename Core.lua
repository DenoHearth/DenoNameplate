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
ns.defaults.enemy.health.fontFlags = "MONOCHROMEOUTLINE"

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
	MONOCHROME = "MONOCHROME",
	MONOCHROMEOUTLINE = "MONOCHROME, OUTLINE",
}

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

-- Clickable area and view distance. Both are refused in combat, so they wait for it to end.
function ns.ApplyClientSettings()
	if InCombatLockdown() then
		pendingClientSettings = true
		return
	end
	pendingClientSettings = false
	local general = ns.db.general
	C_CVar.SetCVar("nameplateMaxDistance", general.maxDistance)
	local clickable = general.clickable
	if clickable.width > 0 and clickable.height > 0 then
		C_NamePlate.SetNamePlateSize(clickable.width, clickable.height)
	end
end

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
