-- Options panel on the Settings API: General, Friendly and Enemy, one page each.
local ADDON, ns = ...

local HEALTH_FORMATS = {
	{ "losthealth", "Missing" },
	{ "health", "Current" },
	{ "health-full", "Current / Max" },
	{ "perc", "Current Percent" },
	{ "perc-full", "Current / Max - Percent" },
}

local QUEST_ICON_ANCHORS = { { "TOP", "Top" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }

local STYLES = { { "standard", "Standard" }, { "modern", "Modern" } }
local MODERN_ON = { { "enemy", "Enemy NamePlates" }, { "all", "Enemy And Friendly NamePlates" } }
local MODERN_POWER = { { "all", "All Units" }, { "players", "Players Only" } }

local FONT_FLAGS = {
	{ "NONE", "None" },
	{ "OUTLINE", "Outline" },
	{ "THICKOUTLINE", "Thick Outline" },
}

local function MediaChoices(kind)
	local choices = {}
	for _, name in ipairs(ns.MediaList(kind)) do choices[#choices + 1] = { name, name } end
	return choices
end

-- Walks ns.db and ns.defaults along the same path, so every control knows its default.
local function Resolve(path)
	local tbl, defaults = ns.db, ns.defaults
	for i = 1, #path - 1 do
		tbl, defaults = tbl[path[i]], defaults[path[i]]
	end
	local key = path[#path]
	return tbl, key, defaults[key], "DenoNameplate_" .. table.concat(path, "_")
end

-- Friendly and Enemy settings belong to the style those plates wear now: Standard's or Modern's own.
-- So those controls read and write through the current set, and re-read it when the style changes.
local groupSettings = {}

local function GroupRegister(category, path, varType, label)
	local group = path[1]
	local function Walk(root)
		local tbl = root
		for i = 2, #path - 1 do tbl = tbl[path[i]] end
		return tbl, path[#path]
	end
	local variable = "DenoNameplate_" .. table.concat(path, "_")
	local setting = Settings.RegisterProxySetting(category, variable, varType, label,
		ns.Watched("Options default", function()
			local tbl, key = Walk(ns.GroupDefaults(group))
			return tbl[key]
		end),
		ns.Watched("Options get", function()
			local tbl, key = Walk(ns.GroupOptions(group))
			return tbl[key]
		end),
		ns.Watched("Options set", function(value)
			local tbl, key = Walk(ns.GroupOptions(group))
			tbl[key] = value
		end))
	Settings.SetOnValueChangedCallback(variable, ns.Refresh)
	groupSettings[#groupSettings + 1] = setting
	return setting
end

-- After a style change: the Friendly and Enemy pages show the other set's values.
local ReloadGroupSettings = ns.Watched("Options reload", function()
	for _, setting in ipairs(groupSettings) do setting:NotifyUpdate() end
end)

local function Register(category, path, varType, label)
	if path[1] == "friendly" or path[1] == "enemy" then
		return GroupRegister(category, path, varType, label)
	end
	local tbl, key, default, variable = Resolve(path)
	local setting = Settings.RegisterAddOnSetting(category, variable, key, tbl, varType, label, default)
	Settings.SetOnValueChangedCallback(variable, ns.Refresh)
	if key == "style" or key == "modernOn" then
		Settings.SetOnValueChangedCallback(variable, ReloadGroupSettings)
	end
	return setting
end

local function Toggle(category, path, label, tooltip)
	Settings.CreateCheckbox(category, Register(category, path, Settings.VarType.Boolean, label), tooltip)
end

local function Range(category, path, label, tooltip, low, high, step)
	local options = Settings.CreateSliderOptions(low, high, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	Settings.CreateSlider(category, Register(category, path, Settings.VarType.Number, label), options, tooltip)
end

local function Select(category, path, label, tooltip, choices)
	local GetOptions = ns.Watched("Options choices", function()
		local container = Settings.CreateControlTextContainer()
		local list = type(choices) == "function" and choices() or choices
		for _, choice in ipairs(list) do container:Add(choice[1], choice[2]) end
		return container:GetData()
	end)
	Settings.CreateDropdown(category, Register(category, path, Settings.VarType.String, label), GetOptions, tooltip)
end

local function Header(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function FontControls(category, group, prefix)
	Select(category, { group, prefix, "font" }, "Font", nil, function() return MediaChoices("font") end)
	Range(category, { group, prefix, "fontSize" }, "Font Size", nil, 8, 18, 1)
	Select(category, { group, prefix, "fontFlags" }, "Font Outline", nil, FONT_FLAGS)
end

-- A colour: the Settings API has no colour control, so a button opens the picker. `key` is the
-- colour's name under health: backgroundColor, or playerColor (his own enemy player colour).
local function ColorButtons(layout, group, key, label, tooltip)
	local Open = ns.Watched("Options colour open", function()
		local color = ns.GroupOptions(group).health[key]
		local previous = { color[1], color[2], color[3], color[4] }
		local Apply = ns.Watched("Options colour apply", function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			color[1], color[2], color[3], color[4] = r, g, b, ColorPickerFrame:GetColorAlpha()
			ns.UpdateAllPlates()
		end)
		ColorPickerFrame:SetupColorPickerAndShow({
			r = color[1], g = color[2], b = color[3], opacity = color[4], hasOpacity = true,
			swatchFunc = Apply,
			opacityFunc = Apply,
			cancelFunc = ns.Watched("Options colour cancel", function()
				color[1], color[2], color[3], color[4] = previous[1], previous[2], previous[3], previous[4]
				ns.UpdateAllPlates()
			end),
		})
	end)
	local Reset = ns.Watched("Options colour reset", function()
		local color, default = ns.GroupOptions(group).health[key], ns.GroupDefaults(group).health[key]
		color[1], color[2], color[3], color[4] = default[1], default[2], default[3], default[4]
		ns.UpdateAllPlates()
	end)
	layout:AddInitializer(CreateSettingsButtonInitializer(label, "Choose", Open, tooltip, true))
	layout:AddInitializer(CreateSettingsButtonInitializer("Reset " .. label, "Reset", Reset, nil, true))
end

local function BuildUnitPage(parent, group, title)
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, title)
	local isFriendly = group == "friendly"

	Header(layout, "Name")
	Toggle(category, { group, "name", "displayName" }, "Display Name")
	FontControls(category, group, "name")

	Header(layout, "Health")
	if isFriendly then
		Toggle(category, { group, "health", "nameOnly" }, "Name Only",
			"Only show the name on the NamePlate (no health bar).")
	end
	Range(category, { group, "health", "width" }, "Bar Width",
		"Sets the width of the NamePlate health bar. This will not change the clickable area.",
		40, 200, 1)
	Range(category, { group, "health", "height" }, "Bar Height",
		"Sets the height of the NamePlate health bar. This will not change the clickable area.",
		4, 60, 1)
	Select(category, { group, "health", "textFormat" }, "Text Format", nil, HEALTH_FORMATS)
	Toggle(category, { group, "health", "showTextFormat" }, "Show Health Text")
	FontControls(category, group, "health")
	Select(category, { group, "health", "statusBar" }, "Bar Texture", nil,
		function() return MediaChoices("statusbar") end)
	Toggle(category, { group, "health", "useClassColor" }, "Use Class Color",
		isFriendly and "Use the player's class color for the health bar."
		or "Use the player's class color for the health bar. Off: enemy players take the Enemy Player Color below.")
	-- his ask, 2026-10-19: on the Enemy page the background colour button gives way to his own player colour
	if isFriendly then
		ColorButtons(layout, group, "backgroundColor", "Background Color", "Colour behind the health bar.")
	else
		ColorButtons(layout, group, "playerColor", "Enemy Player Color",
			"Health bar colour of enemy players while Use Class Color is off. Mobs keep their usual colours.")
	end

	Header(layout, "Cast Bar")
	Toggle(category, { group, "castBar", "enabled" }, "Enabled")
	FontControls(category, group, "castBar")
	Select(category, { group, "castBar", "statusBar" }, "Bar Texture", nil,
		function() return MediaChoices("statusbar") end)
	Range(category, { group, "castBar", "height" }, "Height", nil, 4, 32, 1)
	Range(category, { group, "power", "height" }, "Power Bar Height",
		"Height of the power bar (mana, energy, rage). Modern Style only.", 2, 20, 1)

	Header(layout, "Level Indicator")
	Toggle(category, { group, "levelIndicator", "showPlayerLevel" }, "Player Level")
	Toggle(category, { group, "levelIndicator", "showNPCLevel" }, "NPC Level")

	Header(layout, "Objective Icons")
	Toggle(category, { group, "objectiveIcons", "showQuestObjectives" }, "Show Quest Objectives",
		"Show an icon on units that count for one of your quests.")
	Range(category, { group, "objectiveIcons", "iconScale" }, "Icon Scale", nil, 0.5, 2, 0.05)
	Select(category, { group, "objectiveIcons", "anchor" }, "Icon Anchor",
		"Sets where the icon should appear next to the unit's name.", QUEST_ICON_ANCHORS)
end

function ns.BuildOptions()
	local category, layout = Settings.RegisterVerticalLayoutCategory("Deno Nameplate")
	ns.category = category

	Header(layout, "General")
	Select(category, { "general", "style" }, "Style",
		"Standard: the compact Deno Nameplate look. Modern: name above a tall health bar with one-decimal percent, "
		.. "a power bar (mana, energy, rage; it follows form changes) and the cast bar with spell name, time left and icon.",
		STYLES)
	Select(category, { "general", "modernOn" }, "Modern Style On",
		"Which NamePlates take the Modern look. The others keep the Standard look.", MODERN_ON)
	Select(category, { "general", "modernPower" }, "Modern Power Bar",
		"Which units show a power bar in the Modern look. Units without power never show one.", MODERN_POWER)
	Toggle(category, { "general", "showAuras" }, "Show My Debuffs",
		"Show your debuffs above enemy NamePlates. Takes effect on plates created after the change.")
	Toggle(category, { "general", "showCC" }, "Show Crowd Control",
		"Fear, Polymorph, Sap, stuns and the like as a larger icon over the middle of the enemy NamePlate, "
		.. "with a glow before it ends. Yours and every other player's.")
	Range(category, { "general", "ccGlowSeconds" }, "Crowd Control Glow",
		"How many seconds before the crowd control ends the icon starts to glow and its number turns red.",
		ns.CC_GLOW_MIN, ns.CC_GLOW_MAX, 1)
	Toggle(category, { "general", "showPurge" }, "Show Removable Enemy Buffs",
		"Magic buffs on an enemy that can be dispelled or purged, in a blue frame beside its NamePlate. Only while "
		.. "you can remove one: with a Felhunter out, or as a Shaman or Priest.")
	Toggle(category, { "general", "showDR" }, "Show Crowd Control Diminishing Returns",
		"Left of an enemy player's NamePlate: one icon per kind of crowd control, whoever applied it, framed yellow (the next one lasts "
		.. "half), orange (a quarter) or red (immune), with the seconds until it resets. A grey icon is partly an "
		.. "estimate. Tracking by Forever Simple DR (Tarolg).")
	Toggle(category, { "general", "drNPCs" }, "Diminishing Returns On NPCs Too",
		"Also show it on hostile NPCs, counted by the rules for players. Whether and how an NPC diminishes "
		.. "is not known, so on NPCs this is a guess.")
	Toggle(category, { "general", "showHealPrediction" }, "Show Incoming Heals",
		"Heals being cast on the unit show as a green part after its health.")
	Toggle(category, { "general", "showAbsorbs" }, "Show Absorb Shields",
		"Shields such as Power Word: Shield show as a striped part after its health. "
		.. "A shield bigger than the missing health makes the end of the bar glow.")
	Toggle(category, { "general", "executeColor" }, "Execute Color",
		"An enemy health bar turns orange once its health is under the percent below.")
	Range(category, { "general", "executePercent" }, "Execute Percent",
		"Health percent under which the bar turns orange. 25 suits Drain Soul.", 5, 50, 5)
	Toggle(category, { "general", "hideWorldNames" }, "Hide The Game's Large Names",
		"The game writes a large name over every player and creature that has no NamePlate (too far away or out of sight). "
		.. "On: players and mobs are named on their NamePlate only; quest givers, vendors and trainers keep their name. "
		.. "Off (default): the addon does not touch the game's name settings. Applied out of combat.")
	Range(category, { "general", "maxDistance" }, "View Distance",
		"How far away NamePlates are shown, in yards. 40 is the most the game allows.", 20, ns.MAX_DISTANCE, 1)

	Toggle(category, { "general", "minimap", "show" }, "Show Minimap Button",
		"Show the Deno Nameplate button on the minimap.")

	Header(layout, "Size")
	Range(category, { "general", "clickable", "height" }, "Clickable-Height",
		"Controls the clickable area of the NamePlate. Applied out of combat.", 10, 120, 1)
	Range(category, { "general", "clickable", "width" }, "Clickable-Width",
		"Controls the clickable area of the NamePlate. Applied out of combat.", 40, 300, 1)
	Toggle(category, { "general", "showBox" }, "Show Clickable Box",
		"Draw a white box over the clickable area on all NamePlates.")
	Range(category, { "general", "clickable", "targetScale" }, "Target Scale",
		"Sets the scale of the NamePlate when it is the target.", 0.8, 1.4, 0.1)

	BuildUnitPage(category, "friendly", "Friendly")
	BuildUnitPage(category, "enemy", "Enemy")

	Settings.RegisterAddOnCategory(category)
end
