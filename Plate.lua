-- One plate: health bar, name, cast bar, level, classification, raid and quest icons.
local ADDON, ns = ...

-- Modern style (his picture, 2026-10-19). Name above,
-- left; a tall health bar; under it a thin power bar and the cast bar, every bar in a 1 px black
-- frame; spell name under the cast bar on the left, time left on the right, spell icon to its right.
-- Sizes, fonts and textures come from the Modern style's own Friendly/Enemy settings (Core.lua), which
-- start as the picture. Fixed here: the 1 px gap between bars and the cast colour.
local MODERN_GAP = 1
local MODERN_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"     -- the picture's light-to-dark bars
local MODERN_TRACK = { 0.07, 0.06, 0.06, 1 }
local MODERN_CAST_COLOR = { 0.9, 0.62, 0.1 }

-- The client has no PowerBarColor table (measured in client 70338), so the plain colours are here.
local POWER_COLORS = {
	MANA = { 0, 0, 1 },
	RAGE = { 1, 0, 0 },
	FOCUS = { 1, 0.5, 0.25 },
	ENERGY = { 1, 1, 0 },
	RUNIC_POWER = { 0, 0.82, 1 },
}

-- Time left on a cast, one decimal ("0.8"), counted by the client.
local castTimeFormat
if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
	castTimeFormat = C_StringUtil.CreateNumericRuleFormatter()
	castTimeFormat:SetBreakpoints({
		{ threshold = 0, format = "%.1f", step = 0.1, rounding = Enum.NumericRuleFormatRounding.Up },
	})
end

local Plate = {}

-- A secret value must not reach a Lua operator or branch. Returns nil for one.
local function Plain(value)
	if issecretvalue(value) then return nil end
	return value
end

-- Health percent arrives as 0-1; this curve scales it to 0-100 inside the client.
local percentCurve = C_CurveUtil.CreateCurve()
percentCurve:SetType(Enum.LuaCurveType.Linear)
percentCurve:AddPoint(0, 0)
percentCurve:AddPoint(1, 100)

-- Execute range: under a chosen health percent an enemy bar turns orange. Health is hidden
-- from addon code, so the client picks the colour: a step curve that holds the execute
-- colour below the threshold and the plate's normal colour above it. One curve per normal
-- colour and threshold, kept for reuse.
local EXECUTE_COLOR = CreateColor(1, 0.55, 0.1, 1)
local executeCurves = {}

local function ExecuteCurve(r, g, b, percent)
	local key = string.format("%.2f:%.2f:%.2f:%d", r, g, b, percent)
	local curve = executeCurves[key]
	if not curve then
		curve = C_CurveUtil.CreateColorCurve()
		curve:SetType(Enum.LuaCurveType.Step)
		curve:AddPoint(0, EXECUTE_COLOR)
		curve:AddPoint(percent / 100, CreateColor(r, g, b, 1))
		executeCurves[key] = curve
	end
	return curve
end

-- The bar colour from the curve, read in our own code. Never color:GetRGB(): that is Blizzard
-- code reading a colour our addon made, which taints the whole event run, and Blizzard's own
-- handlers later in the same run were blocked (taint.log 2026-10-19: StanceButton:SetShown()).
local function SetExecuteColor(bar, unit, curve)
	local color = UnitHealthPercent(unit, true, curve)
	if not canaccessvalue(color) then return end
	bar:SetStatusBarColor(color.r, color.g, color.b)
end

local UNIT_EVENTS = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS",
	"UNIT_THREAT_LIST_UPDATE", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED",
}

-- Only while a plate wears the Modern style.
local POWER_EVENTS = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }

local CAST_EVENTS = {
	UNIT_SPELLCAST_START = "cast",
	UNIT_SPELLCAST_CHANNEL_START = "channel",
	UNIT_SPELLCAST_DELAYED = "cast",
	UNIT_SPELLCAST_CHANNEL_UPDATE = "channel",
	UNIT_SPELLCAST_INTERRUPTIBLE = "refresh",
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = "refresh",
	UNIT_SPELLCAST_STOP = "stop",
	UNIT_SPELLCAST_CHANNEL_STOP = "stop",
	UNIT_SPELLCAST_INTERRUPTED = "stop",
	UNIT_SPELLCAST_FAILED = "stop",
}

------------------------------------------------------------------------------------------
-- Crowd control: your own Fear, Polymorph, Sap ... as one larger icon above the middle of
-- the plate, glowing during its last seconds.
--
-- Addon code may not read the time left on an aura, and no script runs inside an aura
-- button. So the timer colour is a curve the client evaluates, and the glow is a second,
-- otherwise empty aura slot whose "time text" comes from a number formatter with one rule
-- per 1/30 second: each rule's text is one frame of the action bar proc glow as an inline
-- picture, and from the chosen number of seconds up the text is blank. The client picks
-- the rule from the time left, so it plays the animation and starts it by itself.
------------------------------------------------------------------------------------------
local CC_KEY = "cc"
local CC_ICON = 26
local CC_GLOW_SIZE = 40
local CC_GLOW_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local CC_GLOW_COLUMNS, CC_GLOW_ROWS, CC_GLOW_FRAMES = 5, 6, 30   -- as in ActionButtonSpellAlerts.xml
ns.CC_GLOW_MIN, ns.CC_GLOW_MAX = 1, 10

local ccTimeColor = C_CurveUtil.CreateColorCurve()
ccTimeColor:SetType(Enum.LuaCurveType.Step)

local ccTimeFormat, ccGlowFormat, ccGlowBinding, ccGlowFrames
if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
	-- whole seconds, rounded up
	ccTimeFormat = C_StringUtil.CreateNumericRuleFormatter()
	ccTimeFormat:SetBreakpoints({
		{ threshold = 0, format = "%d", step = 1, rounding = Enum.NumericRuleFormatRounding.Up },
	})
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(CC_GLOW_ATLAS)
	if info then
		-- the atlas entry in pixels of its file
		local fileWidth = info.width / (info.rightTexCoord - info.leftTexCoord)
		local fileHeight = info.height / (info.bottomTexCoord - info.topTexCoord)
		local left, top = info.leftTexCoord * fileWidth, info.topTexCoord * fileHeight
		local cellWidth, cellHeight = info.width / CC_GLOW_COLUMNS, info.height / CC_GLOW_ROWS
		local file = info.file or info.filename
		ccGlowFrames = {}
		for frame = 0, CC_GLOW_FRAMES - 1 do
			local x = left + (frame % CC_GLOW_COLUMNS) * cellWidth
			local y = top + math.floor(frame / CC_GLOW_COLUMNS) * cellHeight
			ccGlowFrames[frame] = string.format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t", tostring(file), CC_GLOW_SIZE,
				CC_GLOW_SIZE, fileWidth + 0.5, fileHeight + 0.5, x + 0.5, x + cellWidth + 0.5, y + 0.5, y + cellHeight + 0.5)
		end
		ccGlowFormat = C_StringUtil.CreateNumericRuleFormatter()
		-- redrawn every frame of the animation
		ccGlowBinding = C_DurationUtil.CreateDurationTextBinding()
		ccGlowBinding:SetUpdateInterval(1 / CC_GLOW_FRAMES)
	end
end

-- How many seconds before the end the glow starts and the number turns red. Every plate
-- shares the formatter and the curve, so a change shows at once.
function ns.SetCCGlowSeconds(seconds)
	seconds = math.max(ns.CC_GLOW_MIN, math.min(ns.CC_GLOW_MAX, math.floor(tonumber(seconds) or 3)))
	ccTimeColor:ClearPoints()
	ccTimeColor:AddPoint(0, CreateColor(1, 0.25, 0.25, 1))
	ccTimeColor:AddPoint(seconds, CreateColor(1, 0.85, 0.2, 1))
	ccTimeColor:AddPoint(seconds + 2, CreateColor(1, 1, 1, 1))
	if ccGlowFormat then
		local rules = {}
		local steps = seconds * CC_GLOW_FRAMES
		for step = 0, steps - 1 do
			-- time runs down, the animation runs forward
			rules[#rules + 1] = { threshold = step / CC_GLOW_FRAMES, format = ccGlowFrames[(steps - 1 - step) % CC_GLOW_FRAMES] }
		end
		rules[#rules + 1] = { threshold = seconds, format = " " }
		ccGlowFormat:SetBreakpoints(rules)
	end
	return seconds
end
ns.SetCCGlowSeconds(3)

------------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------------
local function HasAuraContainer()
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo
		and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil
end

function ns.CreatePlate(base)
	local plate = CreateFrame("Frame", nil, base)
	Mixin(plate, Plate)
	plate.base = base
	plate:SetPoint("CENTER")
	plate:SetSize(1, 1)
	plate:Hide()

	local health = CreateFrame("StatusBar", nil, plate)
	plate.health = health
	health:SetPoint("CENTER")
	health:SetStatusBarTexture(ns.statusBars["Blizzard2"])

	health.border = health:CreateTexture(nil, "BACKGROUND", nil, -8)
	health.border:SetPoint("TOPLEFT", -1, 1)
	health.border:SetPoint("BOTTOMRIGHT", 1, -1)
	health.border:SetColorTexture(1, 1, 1, 1)

	health.background = health:CreateTexture(nil, "BACKGROUND", nil, -7)
	health.background:SetAllPoints()
	health.background:SetColorTexture(1, 1, 1, 1)

	health.selection = health:CreateTexture(nil, "ARTWORK", nil, 2)
	health.selection:SetAllPoints()
	health.selection:SetTexture(ns.statusBars["Blizzard2"])
	health.selection:SetBlendMode("ADD")
	health.selection:SetAlpha(0.25)
	health.selection:Hide()

	health.aggro = health:CreateTexture(nil, "ARTWORK", nil, 3)
	health.aggro:SetAllPoints()
	health.aggro:SetTexture(ns.statusBars["Blizzard2"])
	health.aggro:SetBlendMode("ADD")
	health.aggro:SetVertexColor(1, 0, 0)
	health.aggro:Hide()

	health.text = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	health.text:SetPoint("CENTER", 0, 1)

	plate.name = plate:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	plate.name:SetPoint("BOTTOM", health, "TOP", 0, 4)
	plate.name:SetWordWrap(false)

	-- Modern style only: mana, energy, rage ... of the unit, whichever it shows now.
	local power = CreateFrame("StatusBar", nil, plate)
	plate.power = power
	power:SetStatusBarTexture(MODERN_TEXTURE)
	power:Hide()
	power.border = power:CreateTexture(nil, "BACKGROUND", nil, -8)
	power.border:SetPoint("TOPLEFT", -1, 1)
	power.border:SetPoint("BOTTOMRIGHT", 1, -1)
	power.border:SetColorTexture(1, 1, 1, 1)
	power.background = power:CreateTexture(nil, "BACKGROUND", nil, -7)
	power.background:SetAllPoints()
	power.background:SetColorTexture(MODERN_TRACK[1], MODERN_TRACK[2], MODERN_TRACK[3], MODERN_TRACK[4])

	local cast = CreateFrame("StatusBar", nil, plate)
	plate.cast = cast
	cast:SetStatusBarTexture(ns.statusBars["Blizzard2"])
	cast:SetStatusBarColor(1, 0.7, 0)
	cast:Hide()
	cast.border = cast:CreateTexture(nil, "BACKGROUND", nil, -8)
	cast.border:SetPoint("TOPLEFT", -1, 1)
	cast.border:SetPoint("BOTTOMRIGHT", 1, -1)
	cast.border:SetColorTexture(1, 1, 1, 1)
	cast.border:Hide()
	cast.background = cast:CreateTexture(nil, "BACKGROUND", nil, -7)
	cast.background:SetAllPoints()
	cast.background:SetColorTexture(0.2, 0.2, 0.2, 0.85)
	cast.text = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cast.text:SetWordWrap(false)
	-- Modern style: seconds left, under the right end of the bar
	cast.time = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cast.time:SetPoint("TOPRIGHT", cast, "BOTTOMRIGHT", 0, -2)
	cast.time:SetJustifyH("RIGHT")
	cast.time:Hide()
	if castTimeFormat then
		cast.timeBinding = C_DurationUtil.CreateDurationTextBinding()
		cast.timeBinding:SetFormatter(castTimeFormat)
		cast.timeBinding:SetFontString(cast.time)
		cast.timeBinding:SetUpdateInterval(0.1)
		cast.timeBinding:SetEnabled(false)
	end
	cast.icon = cast:CreateTexture(nil, "OVERLAY")
	cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cast.iconBorder = cast:CreateTexture(nil, "ARTWORK")
	cast.iconBorder:SetPoint("TOPLEFT", cast.icon, "TOPLEFT", -1, 1)
	cast.iconBorder:SetPoint("BOTTOMRIGHT", cast.icon, "BOTTOMRIGHT", 1, -1)
	cast.iconBorder:SetColorTexture(0, 0, 0, 1)
	cast.iconBorder:Hide()
	cast.shield = cast:CreateTexture(nil, "OVERLAY", nil, 1)
	cast.shield:SetAtlas("nameplates-InterruptShield")
	cast.shield:SetPoint("CENTER", cast, "LEFT", 0, 0)
	cast.shield:SetAlpha(0)

	local level = CreateFrame("Frame", nil, plate)
	plate.level = level
	level:SetSize(18, 18)
	level:SetPoint("LEFT", health, "RIGHT", 1, 0)
	level:SetFrameLevel(plate:GetFrameLevel() + 4)
	level.icon = level:CreateTexture(nil, "ARTWORK")
	level.icon:SetPoint("TOPLEFT", 1, -2)
	level.icon:SetPoint("BOTTOMRIGHT", -1, 2)
	level.icon:SetColorTexture(0, 0, 0, 0.6)
	level.skull = level:CreateTexture(nil, "OVERLAY")
	level.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
	level.skull:SetSize(12, 12)
	level.skull:SetPoint("CENTER")
	level.skull:Hide()
	level.text = level:CreateFontString(nil, "OVERLAY", "GameFontWhiteTiny2")
	level.text:SetPoint("CENTER", 1, 0)
	level:Hide()

	plate.classification = plate:CreateTexture(nil, "OVERLAY")
	plate.classification:SetSize(14, 13)
	plate.classification:SetPoint("RIGHT", health, "LEFT", 0, 0)
	plate.classification:Hide()

	plate.raidIcon = plate:CreateTexture(nil, "OVERLAY")
	plate.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	plate.raidIcon:SetSize(22, 22)
	plate.raidIcon:SetPoint("RIGHT", health, "LEFT", -15, 0)
	plate.raidIcon:Hide()

	plate.questIcon = plate:CreateTexture(nil, "ARTWORK")
	plate.questIcon:SetAtlas("QuestNormal")
	plate.questIcon:Hide()

	plate:SetScript("OnEvent", plate.OnEvent)
	return plate
end

-- The debuff row is drawn by Blizzard's aura container: addon code may not read auras in
-- combat. The container has to be built out of combat.
function Plate:EnsureAuras()
	if self.auras or not ns.db.general.showAuras or InCombatLockdown() or not HasAuraContainer() then
		return
	end
	local container = CreateFrame("AuraContainer", nil, self, "CustomAuraContainerTemplate")
	self.auras = container
	container:SetSize(1, 1)
	container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
	container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
	container:SetFlowLayoutMaximumLineSize(24 * 5)
	container:AddAuraGroup("debuffs", "HARMFUL|PLAYER", {
		-- crowd control has its own, larger icon
		candidateFilters = { excludeSpellIDs = ns.ccSpells },
		maxFrameCount = 5,
		sortMethod = AuraContainerSortMethod.Expiration,
		sortDirection = AuraContainerSortDirection.Normal,
		layout = { elementWidth = 20, elementHeight = 14, elementSpacing = 4, lineSpacing = 4 },
		-- Every region is built and handed over here; the button is sealed afterwards.
		initializeFrame = function(button)
			button:SetSize(20, 14)
			local border = button:CreateTexture(nil, "BACKGROUND")
			border:SetAllPoints()
			border:SetColorTexture(0, 0, 0, 1)
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetSize(18, 12)
			icon:SetPoint("CENTER")
			icon:SetTexCoord(0.05, 0.95, 0.1, 0.6)
			button:SetIcon(icon)
			local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
			count:SetPoint("BOTTOMRIGHT", 3, -2)
			button:SetApplicationCount(count)
			-- Forever has no outlined tiny font object: take the tiny one and outline it here.
			local time = button:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
			local fontFile, fontHeight = time:GetFont()
			time:SetFont(fontFile, fontHeight, "OUTLINE")
			time:SetPoint("CENTER", 0, 1)
			button:SetDurationText(time, {})
		end,
	})
	self:EnsureCC()
	self:EnsurePurge()
end

-- Enemy buffs you can take off: the magic ones, in a blue frame beside the plate.
function Plate:EnsurePurge()
	if self.purge then return end
	local container = CreateFrame("AuraContainer", nil, self, "CustomAuraContainerTemplate")
	self.purge = container
	container:SetSize(1, 1)
	container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
	container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
	container:SetFlowLayoutMaximumLineSize(22 * 3)
	container:AddAuraGroup("purge", "HELPFUL", {
		candidateFilters = { includeDispelTypes = { Magic = true } },
		maxFrameCount = 3,
		sortMethod = AuraContainerSortMethod.Expiration,
		sortDirection = AuraContainerSortDirection.Normal,
		layout = { elementWidth = 18, elementHeight = 18, elementSpacing = 4, lineSpacing = 4 },
		initializeFrame = function(button)
			button:SetSize(18, 18)
			local border = button:CreateTexture(nil, "BACKGROUND")
			border:SetAllPoints()
			border:SetColorTexture(0.3, 0.6, 1, 1)
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("TOPLEFT", 1, -1)
			icon:SetPoint("BOTTOMRIGHT", -1, 1)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			button:SetIcon(icon)
		end,
	})
end

-- The crowd control icon and, over it, the glow. Built out of combat with the debuff row.
function Plate:EnsureCC()
	if self.cc then return end
	local filters = { includeSpellIDs = ns.ccSpells }
	local cc = CreateFrame("AuraContainer", nil, self, "CustomAuraContainerTemplate")
	self.cc = cc
	cc:SetSize(CC_ICON, CC_ICON)
	cc:SetFrameLevel(self:GetFrameLevel() + 6)
	-- anybody's crowd control, not only ours: a mob another player feared is just as feared
	cc:AddAuraSlot(CC_KEY, "HARMFUL", {
		candidateFilters = filters,
		-- Every region is built and handed over here; the button is sealed afterwards.
		initializeFrame = function(button)
			button:SetSize(CC_ICON, CC_ICON)
			button:SetPoint("CENTER", cc, "CENTER")
			local border = button:CreateTexture(nil, "BACKGROUND")
			border:SetAllPoints()
			border:SetColorTexture(0, 0, 0, 1)
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("TOPLEFT", 1, -1)
			icon:SetPoint("BOTTOMRIGHT", -1, 1)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			button:SetIcon(icon)
			local time = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
			time:SetPoint("CENTER", 0, 0)
			button:SetDurationText(time, {
				textFormatter = ccTimeFormat,
				textColor = { curve = ccTimeColor, property = Enum.DurationTextBindingProperty.RemainingDuration },
			})
		end,
	})
	if not ccGlowFormat then return end
	local glow = CreateFrame("AuraContainer", nil, self, "CustomAuraContainerTemplate")
	self.ccGlow = glow
	glow:SetPoint("CENTER", cc, "CENTER")
	glow:SetSize(CC_ICON, CC_ICON)
	glow:SetFrameLevel(self:GetFrameLevel() + 10)
	glow:AddAuraSlot(CC_KEY, "HARMFUL|PLAYER", {
		candidateFilters = filters,
		initializeFrame = function(button)
			button:SetSize(CC_ICON, CC_ICON)
			button:SetPoint("CENTER", glow, "CENTER")
			local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			text:SetPoint("CENTER", 0, 0)
			button:SetDurationText(text, { binding = ccGlowBinding, textFormatter = ccGlowFormat })
		end,
	})
end

------------------------------------------------------------------------------------------
-- Options
------------------------------------------------------------------------------------------
function Plate:ApplyOptions()
	local general = ns.db.general
	local group = self.isFriend and "friendly" or "enemy"
	local options = ns.GroupOptions(group)
	self.options = options
	local health, cast = self.health, self.cast
	self.nameOnly = self.isFriend and options.health.nameOnly
	local modern = ns.IsModern(group) and not self.nameOnly
	self.modern = modern

	local width, height = options.health.width, options.health.height
	self.barWidth = width

	health:SetSize(width, height)
	health:SetStatusBarTexture(ns.FetchStatusBar(options.health.statusBar))
	health:SetShown(not self.nameOnly)
	local bg = options.health.backgroundColor
	health.background:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
	ns.SetFont(health.text, options.health.font, options.health.fontSize, options.health.fontFlags)

	self.name:ClearAllPoints()
	if self.nameOnly then
		self.name:SetPoint("BOTTOM", health, "BOTTOM", 0, 4)
	elseif modern then
		self.name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 3)
	else
		self.name:SetPoint("BOTTOM", health, "TOP", 0, 4)
	end
	self.name:SetJustifyH(modern and "LEFT" or "CENTER")
	self.name:SetShown(options.name.displayName)
	ns.SetFont(self.name, options.name.font, options.name.fontSize, options.name.fontFlags)

	local castFont = options.castBar
	ns.SetFont(cast.text, castFont.font, castFont.fontSize, castFont.fontFlags)
	cast.text:ClearAllPoints()
	cast.icon:ClearAllPoints()
	if modern then
		local castHeight, powerHeight = options.castBar.height, options.power.height
		cast:SetSize(width, castHeight)
		cast:SetStatusBarTexture(ns.FetchStatusBar(options.castBar.statusBar))
		cast:SetStatusBarColor(MODERN_CAST_COLOR[1], MODERN_CAST_COLOR[2], MODERN_CAST_COLOR[3])
		cast.background:SetColorTexture(MODERN_TRACK[1], MODERN_TRACK[2], MODERN_TRACK[3], MODERN_TRACK[4])
		cast.border:Show()
		cast.text:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -2)
		cast.text:SetPoint("RIGHT", cast.time, "LEFT", -4, 0)
		cast.text:SetJustifyH("LEFT")
		-- time left a little smaller than the spell name, as in his picture
		ns.SetFont(cast.time, castFont.font, math.max(castFont.fontSize - 2, 6), castFont.fontFlags)
		-- right of the bars, level with the power and cast bars
		local iconSize = powerHeight + MODERN_GAP + castHeight + 2
		cast.icon:SetSize(iconSize, iconSize)
		cast.icon:SetPoint("BOTTOMLEFT", cast, "BOTTOMRIGHT", 5, 0)
		cast.iconBorder:Show()
		cast.shield:SetSize(castHeight, castHeight * 1.2)
	else
		local castHeight = options.castBar.height
		cast:SetSize(math.max(width - castHeight, 10), castHeight)
		cast:SetStatusBarTexture(ns.FetchStatusBar(options.castBar.statusBar))
		cast:SetStatusBarColor(1, 0.7, 0)
		cast.background:SetColorTexture(0.2, 0.2, 0.2, 0.85)
		cast.border:Hide()
		cast.text:SetAllPoints()
		cast.text:SetJustifyH("CENTER")
		cast.time:Hide()
		cast.icon:SetSize(castHeight, castHeight)
		cast.icon:SetPoint("RIGHT", cast, "LEFT", 0, 0)
		cast.iconBorder:Hide()
		cast.shield:SetSize(castHeight, castHeight * 1.2)
	end
	if modern then
		self.power:SetSize(width, options.power.height)
		self.power:SetStatusBarTexture(ns.FetchStatusBar(options.health.statusBar))
	end
	self:LayoutBars()

	local anchor = options.objectiveIcons.anchor
	local size = 32 * options.objectiveIcons.iconScale * 0.5
	self.questIcon:SetSize(size, size)
	self.questIcon:ClearAllPoints()
	if anchor == "LEFT" then
		self.questIcon:SetPoint("RIGHT", self.name, "LEFT", -2, 0)
	elseif anchor == "RIGHT" then
		self.questIcon:SetPoint("LEFT", self.name, "RIGHT", 2, 0)
	else
		self.questIcon:SetPoint("BOTTOM", self.name, "TOP", 0, 2)
	end

	-- Clickable-area box, drawn over the client's own nameplate frame.
	if general.showBox then
		if not self.clickBox then
			self.clickBox = self:CreateTexture(nil, "BACKGROUND")
			self.clickBox:SetColorTexture(1, 1, 1, 0.5)
		end
		-- Forever refuses anchors to the nameplate base frame ("anchor family connection"), which
		-- is why the box never showed; the client's UnitFrame covers the same click area.
		-- drawn over the hit frame UpdateHitArea hands to the game: exactly where clicks land
		local box = self.clickBox
		if not self.hit then self.hit = CreateFrame("Frame", nil, self) end
		box:ClearAllPoints()
		box:SetAllPoints(self.hit)
		box:Show()
	elseif self.clickBox then
		self.clickBox:Hide()
	end

	if self.auras then
		self.auras:ClearAllPoints()
		if options.name.displayName then
			self.auras:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, options.name.fontSize + 9)
		else
			self.auras:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 4)
		end
		self.auras:SetEnabled(general.showAuras and not self.isFriend)
	end
	if self.purge then
		-- to the right of the bar, past the level box
		self.purge:ClearAllPoints()
		self.purge:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT", 24, -3)
		self.purge:SetEnabled(general.showPurge and not self.isFriend and ns.CanPurge())
	end
	if self.cc then
		-- top middle: over the name, and over the debuff row when that is shown
		local lift = (options.name.displayName and options.name.fontSize + 9 or 4) + (general.showAuras and 20 or 0)
		local shown = general.showCC and not self.isFriend
		self.cc:ClearAllPoints()
		-- by its centre: the client resizes a container around its slot
		self.cc:SetPoint("CENTER", health, "TOP", 0, lift + CC_ICON / 2)
		self.cc:SetEnabled(shown)
		if self.ccGlow then self.ccGlow:SetEnabled(shown) end
	end
end

------------------------------------------------------------------------------------------
-- Unit assignment
------------------------------------------------------------------------------------------
-- Stacking (his report, 2026-10-18: stacking on in the game settings, plates did not stack).
-- Forever stacks plates by the drawn area of a "stacking bounds" frame; by default that is the
-- client's own plate, which this addon keeps at alpha 0, so nothing was there to stack by. A
-- see-through frame over our name, bar and cast bar is given instead (as EllesmereUI does on
-- Forever: the bounds come from the frame's regions, not its size, hence the texture).
function Plate:UpdateStackBounds()
	local base = self.base
	if not base.SetStackingBoundsFrame then return end
	-- the client's stacking frame is left alone in a fight, like the hit frame; redone after it
	if self.stackBounds and InCombatLockdown() then return end
	if not self.stackBounds then
		local bounds = CreateFrame("Frame", nil, base)
		local fill = bounds:CreateTexture(nil, "BACKGROUND")
		fill:SetColorTexture(0, 0, 0, 0)
		fill:SetAllPoints()
		self.stackBounds = bounds
	end
	local bounds, options, health = self.stackBounds, self.options, self.health
	local top = options.name.displayName and (options.name.fontSize + 4) or 0
	local bottom = (not self.isFriend and options.castBar.enabled) and (options.castBar.height + 2) or 0
	if self.modern then
		bottom = self.power:IsShown() and (options.power.height + MODERN_GAP) or 0
		if options.castBar.enabled then
			bottom = bottom + options.castBar.height + MODERN_GAP + options.castBar.fontSize + 2
		end
	end
	bounds:ClearAllPoints()
	bounds:SetPoint("TOPLEFT", health, "TOPLEFT", 0, top)
	bounds:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, -bottom)
	bounds:Show()
	base:SetStackingBoundsFrame(bounds)
end

-- Clicks (his report, 2026-10-18: "I have to click on their body"). On Forever the mouse area of
-- a nameplate is its hit-test points; left alone they stay on the client's own plate, which this
-- addon hides. A frame the size of the Clickable-Width/Height options, centred on our plate, is
-- handed over instead (as Plater, Tempus and ShestakUI do on Forever). Allowed for addon code
-- out of combat and on the tick a unit is first assigned (CanChangeHitTestPoints).
function Plate:UpdateHitArea()
	local base = self.base
	if not self.hit then self.hit = CreateFrame("Frame", nil, self) end
	local hit, clickable = self.hit, ns.db.general.clickable
	local width, height = clickable.width, clickable.height
	if width <= 0 or height <= 0 then
		width = self.barWidth or self.options.health.width
		height = (self.stackBounds and self.stackBounds:GetHeight()) or 20
	end
	-- Our own frame is the click area, as Plater, Tempus and EllesmereUI do: the client's own
	-- does not cover our plates (his report 1.3.7: "can't click plates"; again 2026-10-19 when
	-- it was taken out). Once handed over it may only change while the client allows it (a
	-- change in combat was refused); otherwise it waits for the end of the fight (AfterCombat).
	if not (base.CanChangeHitTestPoints and base:CanChangeHitTestPoints()) then return end
	hit:ClearAllPoints()
	hit:SetSize(width, height)
	hit:SetPoint("CENTER", self.stackBounds or self.health, "CENTER")
	base:ClearAllHitTestPoints()
	base:SetAllHitTestPoints(hit)
end

-- The cast bar sits under the power bar when one is shown, else under the health bar.
function Plate:LayoutBars()
	local cast, health, power = self.cast, self.health, self.power
	cast:ClearAllPoints()
	power:ClearAllPoints()
	if self.modern then
		power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -MODERN_GAP)
		local above = power:IsShown() and power or health
		cast:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -MODERN_GAP)
	else
		cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -2)
	end
end

-- Power events are only wanted while the plate wears the Modern style.
function Plate:RegisterEvents()
	local unit = self.unit
	self:UnregisterAllEvents()
	for _, event in ipairs(UNIT_EVENTS) do self:RegisterUnitEvent(event, unit) end
	for event in pairs(CAST_EVENTS) do self:RegisterUnitEvent(event, unit) end
	if self.modern then
		for _, event in ipairs(POWER_EVENTS) do self:RegisterUnitEvent(event, unit) end
	end
	self.eventsModern = self.modern
end

function Plate:SetUnit(unit)
	self.unit = unit
	self.eventsModern = nil
	self:EnsureAuras()
	if self.auras then self.auras:SetUnit(unit) end
	if self.cc then self.cc:SetUnit(unit) end
	if self.purge then self.purge:SetUnit(unit) end
	if self.ccGlow then self.ccGlow:SetUnit(unit) end
	self:Refresh()
	self:Show()
end

function Plate:ClearUnit()
	self.unit = nil
	self:UnregisterAllEvents()
	self:StopCast()
	self.power:Hide()
	if self.auras then self.auras:SetEnabled(false) end
	if self.cc then self.cc:SetEnabled(false) end
	if self.purge then self.purge:SetEnabled(false) end
	if self.ccGlow then self.ccGlow:SetEnabled(false) end
	self:Hide()
end

function Plate:Refresh()
	local unit = self.unit
	if not unit then return end
	self.isFriend = Plain(UnitIsFriend("player", unit)) and true or false
	self:ApplyOptions()
	if self.eventsModern ~= self.modern then self:RegisterEvents() end
	self:UpdatePower()
	self:UpdateStackBounds()
	self:UpdateHitArea()
	self:UpdateHealth()
	self:UpdateName()
	self:UpdateColor()
	self:UpdateAggro()
	self:UpdateTarget()
	self:UpdateLevel()
	self:UpdateClassification()
	self:UpdateRaidIcon()
	self:UpdateQuestIcon()
	self:UpdateCast()
end

function Plate:OnEvent(event)
	local castKind = CAST_EVENTS[event]
	if castKind then
		if castKind == "stop" then self:StopCast() else self:UpdateCast() end
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		self:UpdateHealth()
	elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
		-- a mob that gains or loses all its power shows or hides its bar
		if self.isPlayerUnit then self:UpdatePowerValue() else self:UpdatePower() end
	elseif event == "UNIT_DISPLAYPOWER" then
		-- a druid changing form: energy, rage or mana
		self:UpdatePower()
	elseif event == "UNIT_NAME_UPDATE" then
		self:UpdateName()
	elseif event == "UNIT_FACTION" then
		self:Refresh()
	elseif event == "UNIT_FLAGS" or event == "UNIT_THREAT_LIST_UPDATE" then
		self:UpdateColor()
		self:UpdateName()
		self:UpdateAggro()
	elseif event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
		self:UpdateLevel()
		self:UpdateClassification()
	end
end

------------------------------------------------------------------------------------------
-- Element updates
------------------------------------------------------------------------------------------
function Plate:UpdateHealth()
	local unit, health = self.unit, self.health
	health:SetMinMaxValues(0, UnitHealthMax(unit))
	health:SetValue(UnitHealth(unit))
	if self.executeCurve then
		SetExecuteColor(health, unit, self.executeCurve)
	end

	local text = health.text
	if not self.options.health.showTextFormat then
		text:Hide()
		return
	end
	local format = self.options.health.textFormat
	if Plain(UnitIsDeadOrGhost(unit)) then
		text:SetText(DEAD)
	elseif format == "health" then
		text:SetFormattedText("%s", AbbreviateNumbers(UnitHealth(unit)))
	elseif format == "health-full" then
		text:SetFormattedText("%s/%s", AbbreviateNumbers(UnitHealth(unit)), AbbreviateNumbers(UnitHealthMax(unit)))
	elseif format == "losthealth" then
		text:SetFormattedText("-%s", AbbreviateNumbers(UnitHealthMissing(unit, true)))
	elseif format == "perc-full" then
		text:SetFormattedText("%s/%s - %.0f%%", AbbreviateNumbers(UnitHealth(unit)),
			AbbreviateNumbers(UnitHealthMax(unit)), UnitHealthPercent(unit, true, percentCurve))
	else
		-- the Modern style shows one decimal, as in his picture: 87.2%
		text:SetFormattedText(self.modern and "%.1f%%" or "%.0f%%", UnitHealthPercent(unit, true, percentCurve))
	end
	text:Show()
end

function Plate:IsTapDenied()
	local unit = self.unit
	return not Plain(UnitPlayerControlled(unit)) and Plain(UnitIsTapDenied(unit)) and true or false
end

function Plate:IsOnThreatList()
	return Plain(UnitThreatSituation("player", self.unit)) ~= nil
end

local function ClassColor(unit)
	local _, class = UnitClass(unit)
	class = Plain(class)
	return class and RAID_CLASS_COLORS[class]
end

local function FriendlyPlayerColor(unit)
	if Plain(UnitIsPVP(unit)) then return 0, 1, 0 end
	return 0.667, 0.667, 1
end

function Plate:UpdateColor()
	local unit = self.unit
	local isPlayer = Plain(UnitIsPlayer(unit))
	local classColor = isPlayer and self.options.health.useClassColor and ClassColor(unit)
	local r, g, b
	if classColor then
		r, g, b = classColor.r, classColor.g, classColor.b
	elseif isPlayer and not self.isFriend and not self.options.health.useClassColor then
		-- class colour off: his own colour for enemy players (Enemy page, Enemy Player Color)
		local own = self.options.health.playerColor
		r, g, b = own[1], own[2], own[3]
	elseif self:IsTapDenied() then
		r, g, b = 0.5, 0.5, 0.5
	elseif self:IsOnThreatList() then
		r, g, b = 1, 0, 0
	elseif isPlayer and self.isFriend then
		r, g, b = FriendlyPlayerColor(unit)
	else
		r, g, b = UnitSelectionColor(unit, self.isFriend)
	end
	-- the target highlight takes the bar's colour on friendly plates and stays white on enemies
	if self.isFriend then
		self.health.selection:SetVertexColor(r, g, b)
	else
		self.health.selection:SetVertexColor(1, 1, 1)
	end
	local general = ns.db.general
	self.executeCurve = nil
	-- enemies only, and only when the normal colour is plain data a curve can be built from
	if general.executeColor and not self.isFriend and Plain(r) and Plain(g) and Plain(b) then
		self.executeCurve = ExecuteCurve(r, g, b, general.executePercent)
		SetExecuteColor(self.health, unit, self.executeCurve)
	else
		self.health:SetStatusBarColor(r, g, b)
	end
end

function Plate:UpdateName()
	local unit, name = self.unit, self.name
	if not self.options.name.displayName then return end
	name:SetText(UnitName(unit))
	local isPlayer = Plain(UnitIsPlayer(unit))
	local classColor = isPlayer and self.isFriend and self.options.health.useClassColor and ClassColor(unit)
	if self:IsTapDenied() or Plain(UnitIsDeadOrGhost(unit)) then
		name:SetTextColor(0.5, 0.5, 0.5)
	elseif self.modern then
		-- white, as in his picture; the bar carries the colour
		name:SetTextColor(1, 1, 1)
	elseif classColor then
		name:SetTextColor(classColor.r, classColor.g, classColor.b)
	elseif self:IsOnThreatList() then
		name:SetTextColor(1, 0, 0)
	elseif isPlayer and self.isFriend then
		name:SetTextColor(FriendlyPlayerColor(unit))
	else
		name:SetTextColor(UnitSelectionColor(unit, self.isFriend))
	end
end

function Plate:UpdateAggro()
	local aggro = self.health.aggro
	if self.isFriend then
		aggro:Hide()
		return
	end
	-- The unit's own threat state, as the original asks for it: a mob the player is fighting has
	-- none, so its bar keeps its plain colour. Asking for the player's threat on the mob (as this
	-- did until 1.2.1) laid the red glow over every enemy in a fight and washed the bar out.
	local status = Plain(UnitThreatSituation(self.unit))
	if status and status > 0 then
		aggro:SetVertexColor(GetThreatStatusColor(status))
		aggro:Show()
	else
		aggro:Hide()
	end
end

-- The frame round the bars: dark, or light on the target. Modern frames its power and cast bars
-- too, in solid black as in his picture.
function Plate:SetBorderColor(isTarget)
	local r, a
	if isTarget then
		r, a = 1, self.isFriend and 0.35 or 0.55
		if self.modern then r, a = 0.8, 1 end
	else
		r, a = 0, self.modern and 1 or 0.6
	end
	self.health.border:SetVertexColor(r, r, r, a)
	self.power.border:SetVertexColor(r, r, r, a)
	self.cast.border:SetVertexColor(r, r, r, a)
end

function Plate:UpdateTarget()
	local unit, health = self.unit, self.health
	if not unit then return end
	local isTarget = UnitIsUnit(unit, "target")
	if issecretvalue(isTarget) then
		-- Comparison is restricted: the client decides visibility, scale stays neutral.
		health.selection:Show()
		health.selection:SetAlphaFromBoolean(isTarget, 0.25, 0)
		self:SetBorderColor(false)
		self:SetScale(1)
		return
	end
	health.selection:SetAlpha(0.25)
	health.selection:SetShown(isTarget)
	if isTarget then
		self:SetBorderColor(true)
		self:SetScale(ns.db.general.clickable.targetScale)
	else
		self:SetBorderColor(false)
		self:SetScale(1)
	end
end

function Plate:UpdateLevel()
	local unit, frame = self.unit, self.level
	local indicator = self.options.levelIndicator
	local isPlayer = Plain(UnitIsPlayer(unit))
	local showPlayer = indicator.showPlayerLevel
	local showNPC = indicator.showNPCLevel
	local level = Plain(UnitLevel(unit))
	if self.nameOnly or level == nil or (isPlayer and not showPlayer) or (not isPlayer and not showNPC) then
		frame:Hide()
		return
	end
	if level <= 0 and Plain(UnitClassification(unit)) == "worldboss" then
		frame.skull:Show()
		frame.text:Hide()
	else
		frame.skull:Hide()
		frame.text:Show()
		if level <= 0 then
			frame.text:SetText("??")
			frame.text:SetTextColor(1, 0.1, 0.1)
		else
			local color = GetCreatureDifficultyColor(level)
			frame.text:SetText(level)
			if color then
				frame.text:SetTextColor(color.r, color.g, color.b)
			else
				frame.text:SetTextColor(1, 0.82, 0)
			end
		end
	end
	frame:Show()
end

function Plate:UpdateClassification()
	local icon = self.classification
	local classification = Plain(UnitClassification(self.unit))
	if self.nameOnly or self.isFriend then
		icon:Hide()
	elseif classification == "elite" or classification == "worldboss" then
		icon:SetAtlas("nameplates-icon-elite-gold")
		icon:Show()
	elseif classification == "rareelite" then
		icon:SetAtlas("nameplates-icon-elite-silver")
		icon:Show()
	else
		icon:Hide()
	end
end

function Plate:UpdateRaidIcon()
	if not self.unit then return end
	-- The index is always secret; type() tells present from absent without reading it.
	local index = GetRaidTargetIndex(self.unit)
	if type(index) == "nil" then
		self.raidIcon:Hide()
	else
		-- what SetRaidTargetIconTexture does, done here: Blizzard code working on our texture
		-- taints the event run (see SetExecuteColor)
		self.raidIcon:SetSpriteSheetCell(index, 4, 4)
		self.raidIcon:Show()
	end
end

function Plate:UpdateQuestIcon()
	if not self.unit then return end
	local show = self.options.objectiveIcons.showQuestObjectives
		and Plain(C_QuestLog.UnitIsRelatedToActiveQuest(self.unit))
	self.questIcon:SetShown(show and true or false)
end

-- Which power the unit shows now, and its colour. Hidden where the unit has none.
function Plate:UpdatePower()
	local unit, power = self.unit, self.power
	self.isPlayerUnit = unit and Plain(UnitIsPlayer(unit)) and true or false
	local wanted = self.modern and unit
		and (ns.db.general.modernPower ~= "players" or Plain(UnitIsPlayer(unit)))
	local shown = false
	if wanted then
		local _, token, r, g, b = UnitPowerType(unit)
		token, r, g, b = Plain(token), Plain(r), Plain(g), Plain(b)
		local color = token and POWER_COLORS[token]
		if color then
			power:SetStatusBarColor(color[1], color[2], color[3])
		elseif r and g and b then
			power:SetStatusBarColor(r, g, b)
		else
			power:SetStatusBarColor(0, 0, 1)
		end
		-- A player always has a bar, unless the maximum is plainly 0. A mob gets one only while it
		-- plainly holds some power: one with nothing in its second bar (his picture, a Young Wolf)
		-- shows no empty bar. A secret value (in combat) keeps the last decision.
		local max, current = UnitPowerMax(unit), UnitPower(unit)
		if Plain(UnitIsPlayer(unit)) then
			shown = Plain(max) ~= 0
		elseif issecretvalue(max) or issecretvalue(current) then
			shown = power:IsShown()
		else
			shown = max > 0 and current > 0
		end
	end
	if shown ~= power:IsShown() then
		power:SetShown(shown)
		self:LayoutBars()
	end
	if shown then self:UpdatePowerValue() end
end

function Plate:UpdatePowerValue()
	local unit, power = self.unit, self.power
	if not unit or not power:IsShown() then return end
	power:SetMinMaxValues(0, UnitPowerMax(unit))
	power:SetValue(UnitPower(unit))
end

function Plate:StopCast()
	local cast = self.cast
	cast:Hide()
	if cast.timeBinding then cast.timeBinding:SetEnabled(false) end
end

function Plate:UpdateCast()
	local unit, cast = self.unit, self.cast
	if not self.options.castBar.enabled or self.nameOnly then
		self:StopCast()
		return
	end
	local name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
	local duration, direction
	if type(name) ~= "nil" then
		duration = UnitCastingDuration(unit)
		direction = Enum.StatusBarTimerDirection.ElapsedTime
	else
		name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(unit)
		if type(name) ~= "nil" then
			duration = UnitChannelDuration(unit)
			direction = Enum.StatusBarTimerDirection.RemainingTime
		end
	end
	if type(name) == "nil" or type(duration) == "nil" then
		self:StopCast()
		return
	end
	cast:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
	if cast.timeBinding then
		if self.modern then
			cast.timeBinding:SetDuration(duration)
			cast.timeBinding:SetEnabled(true)
		else
			cast.timeBinding:SetEnabled(false)
		end
	end
	cast.time:SetShown(self.modern and cast.timeBinding ~= nil)
	cast.text:SetText(name)
	cast.icon:SetTexture(texture)
	if type(notInterruptible) == "nil" then
		cast.shield:SetAlpha(0)
	else
		cast.shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
	end
	cast:Show()
end
