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

local FONT_FLAGS = {
	{ "NONE", "None" },
	{ "OUTLINE", "Outline" },
	{ "THICKOUTLINE", "Thick Outline" },
	{ "MONOCHROME", "Monochrome" },
	{ "MONOCHROMEOUTLINE", "Monochrome Outline" },
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

local function Register(category, path, varType, label)
	local tbl, key, default, variable = Resolve(path)
	local setting = Settings.RegisterAddOnSetting(category, variable, key, tbl, varType, label, default)
	Settings.SetOnValueChangedCallback(variable, ns.Refresh)
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
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		local list = type(choices) == "function" and choices() or choices
		for _, choice in ipairs(list) do container:Add(choice[1], choice[2]) end
		return container:GetData()
	end
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

-- Background colour: the Settings API has no colour control, so a button opens the picker.
local function ColorButtons(layout, group)
	local function Open()
		local color = ns.db[group].health.backgroundColor
		local previous = { color[1], color[2], color[3], color[4] }
		local function Apply()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			color[1], color[2], color[3], color[4] = r, g, b, ColorPickerFrame:GetColorAlpha()
			ns.UpdateAllPlates()
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = color[1], g = color[2], b = color[3], opacity = color[4], hasOpacity = true,
			swatchFunc = Apply,
			opacityFunc = Apply,
			cancelFunc = function()
				color[1], color[2], color[3], color[4] = previous[1], previous[2], previous[3], previous[4]
				ns.UpdateAllPlates()
			end,
		})
	end
	local function Reset()
		local color, default = ns.db[group].health.backgroundColor, ns.defaults[group].health.backgroundColor
		color[1], color[2], color[3], color[4] = default[1], default[2], default[3], default[4]
		ns.UpdateAllPlates()
	end
	layout:AddInitializer(CreateSettingsButtonInitializer("Background Color", "Choose", Open,
		"Colour behind the health bar.", true))
	layout:AddInitializer(CreateSettingsButtonInitializer("Reset Background Color", "Reset", Reset, nil, true))
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
		"Sets the width of the NamePlate health bar. This will not change the clickable area. Ignored in Classic Style.",
		40, 200, 1)
	Range(category, { group, "health", "height" }, "Bar Height",
		"Sets the height of the NamePlate health bar. This will not change the clickable area. Ignored in Classic Style.",
		4, 60, 1)
	Select(category, { group, "health", "textFormat" }, "Text Format", nil, HEALTH_FORMATS)
	Toggle(category, { group, "health", "showTextFormat" }, "Show Health Text")
	FontControls(category, group, "health")
	Select(category, { group, "health", "statusBar" }, "Bar Texture", nil,
		function() return MediaChoices("statusbar") end)
	Toggle(category, { group, "health", "useClassColor" }, "Use Class Color",
		"Use the player's class color for the health bar.")
	ColorButtons(layout, group)

	Header(layout, "Cast Bar")
	Toggle(category, { group, "castBar", "enabled" }, "Enabled")
	FontControls(category, group, "castBar")
	Select(category, { group, "castBar", "statusBar" }, "Bar Texture", nil,
		function() return MediaChoices("statusbar") end)
	Range(category, { group, "castBar", "height" }, "Height", "Ignored in Classic Style.", 4, 32, 1)

	Header(layout, "Level Indicator")
	Toggle(category, { group, "levelIndicator", "showPlayerLevel" }, "Player Level", "Always shown in Classic Style.")
	Toggle(category, { group, "levelIndicator", "showNPCLevel" }, "NPC Level", "Always shown in Classic Style.")

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
	Toggle(category, { "general", "useClassicStyle" }, "Classic Style", "Use classic style textures.")
	Toggle(category, { "general", "showAuras" }, "Show My Debuffs",
		"Show your debuffs above enemy NamePlates. Takes effect on plates created after the change.")
	Toggle(category, { "general", "showCC" }, "Show My Crowd Control",
		"Your own Fear, Polymorph, Sap and the like as a larger icon over the middle of the enemy NamePlate, "
		.. "with a glow before it ends. Only yours, never another player's.")
	Range(category, { "general", "ccGlowSeconds" }, "Crowd Control Glow",
		"How many seconds before your crowd control ends the icon starts to glow and its number turns red.",
		ns.CC_GLOW_MIN, ns.CC_GLOW_MAX, 1)
	Range(category, { "general", "maxDistance" }, "View Distance",
		"How far away NamePlates are shown, in yards. 60 is the most the game allows.", 20, ns.MAX_DISTANCE, 1)

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
