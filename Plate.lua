-- One plate: health bar, name, cast bar, level, classification, raid and quest icons.
local ADDON, ns = ...

local CLASSIC_WIDTH, CLASSIC_HEIGHT = 110, 12

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

local UNIT_EVENTS = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS",
	"UNIT_THREAT_LIST_UPDATE", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED",
}

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

	-- Classic style: the old bordered plate art, which has a pocket for the level on its right.
	health.classicBorder = health:CreateTexture(nil, "OVERLAY")
	health.classicBorder:SetTexture("Interface\\Tooltips\\Nameplate-Border")
	health.classicBorder:SetTexCoord(0, 1, 0.5, 1)
	health.classicBorder:SetPoint("TOPLEFT", -4, 3)
	health.classicBorder:SetPoint("BOTTOMRIGHT", 18, -3)
	health.classicBorder:Hide()

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

	local cast = CreateFrame("StatusBar", nil, plate)
	plate.cast = cast
	cast:SetStatusBarTexture(ns.statusBars["Blizzard2"])
	cast:SetStatusBarColor(1, 0.7, 0)
	cast:Hide()
	cast.background = cast:CreateTexture(nil, "BACKGROUND")
	cast.background:SetAllPoints()
	cast.background:SetColorTexture(0.2, 0.2, 0.2, 0.85)
	cast.text = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cast.text:SetAllPoints()
	cast.text:SetWordWrap(false)
	cast.icon = cast:CreateTexture(nil, "OVERLAY")
	cast.icon:SetPoint("RIGHT", cast, "LEFT", 0, 0)
	cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
end

------------------------------------------------------------------------------------------
-- Options
------------------------------------------------------------------------------------------
function Plate:ApplyOptions()
	local general = ns.db.general
	local options = self.isFriend and ns.db.friendly or ns.db.enemy
	self.options = options
	local classic = general.useClassicStyle
	local health, cast = self.health, self.cast

	local width, height = options.health.width, options.health.height
	if classic then width, height = CLASSIC_WIDTH, CLASSIC_HEIGHT end
	self.nameOnly = self.isFriend and options.health.nameOnly

	health:SetSize(width, height)
	health:SetStatusBarTexture(ns.FetchStatusBar(options.health.statusBar))
	health:SetShown(not self.nameOnly)
	local bg = options.health.backgroundColor
	health.background:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
	health.border:SetShown(not classic)
	health.classicBorder:SetShown(classic)
	ns.SetFont(health.text, options.health.font, options.health.fontSize, options.health.fontFlags)

	self.name:ClearAllPoints()
	if self.nameOnly then
		self.name:SetPoint("BOTTOM", health, "BOTTOM", 0, 4)
	else
		self.name:SetPoint("BOTTOM", health, "TOP", 0, 4)
	end
	self.name:SetShown(options.name.displayName)
	ns.SetFont(self.name, options.name.font, options.name.fontSize, options.name.fontFlags)

	local castHeight = classic and CLASSIC_HEIGHT or options.castBar.height
	cast:ClearAllPoints()
	cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -2)
	cast:SetSize(math.max(width - castHeight, 10), castHeight)
	cast:SetStatusBarTexture(ns.FetchStatusBar(options.castBar.statusBar))
	cast.icon:SetSize(castHeight, castHeight)
	cast.shield:SetSize(castHeight, castHeight * 1.2)
	ns.SetFont(cast.text, options.castBar.font, options.castBar.fontSize, options.castBar.fontFlags)

	self.level.icon:SetShown(not classic)
	self.level.text:SetFontObject(classic and GameFontHighlightSmall or GameFontWhiteTiny2)

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
			self.clickBox:SetAllPoints(self.base)
		end
		self.clickBox:Show()
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
end

------------------------------------------------------------------------------------------
-- Unit assignment
------------------------------------------------------------------------------------------
function Plate:SetUnit(unit)
	self.unit = unit
	self:UnregisterAllEvents()
	for _, event in ipairs(UNIT_EVENTS) do self:RegisterUnitEvent(event, unit) end
	for event in pairs(CAST_EVENTS) do self:RegisterUnitEvent(event, unit) end
	self:EnsureAuras()
	if self.auras then self.auras:SetUnit(unit) end
	self:Refresh()
	self:Show()
end

function Plate:ClearUnit()
	self.unit = nil
	self:UnregisterAllEvents()
	self.cast:Hide()
	if self.auras then self.auras:SetEnabled(false) end
	self:Hide()
end

function Plate:Refresh()
	local unit = self.unit
	if not unit then return end
	self.isFriend = Plain(UnitIsFriend("player", unit)) and true or false
	self:ApplyOptions()
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
		if castKind == "stop" then self.cast:Hide() else self:UpdateCast() end
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		self:UpdateHealth()
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
		text:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, percentCurve))
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
	elseif self:IsTapDenied() then
		r, g, b = 0.9, 0.9, 0.9
	elseif self:IsOnThreatList() then
		r, g, b = 1, 0, 0
	elseif isPlayer and self.isFriend then
		r, g, b = FriendlyPlayerColor(unit)
	else
		r, g, b = UnitSelectionColor(unit, self.isFriend)
	end
	self.health:SetStatusBarColor(r, g, b)
end

function Plate:UpdateName()
	local unit, name = self.unit, self.name
	if not self.options.name.displayName then return end
	name:SetText(UnitName(unit))
	local isPlayer = Plain(UnitIsPlayer(unit))
	local classColor = isPlayer and self.isFriend and self.options.health.useClassColor and ClassColor(unit)
	if self:IsTapDenied() or Plain(UnitIsDeadOrGhost(unit)) then
		name:SetTextColor(0.5, 0.5, 0.5)
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
	local status = Plain(UnitThreatSituation("player", self.unit))
	if status and status > 0 then
		aggro:SetVertexColor(GetThreatStatusColor(status))
		aggro:Show()
	else
		aggro:Hide()
	end
end

function Plate:UpdateTarget()
	local unit, health = self.unit, self.health
	if not unit then return end
	local isTarget = UnitIsUnit(unit, "target")
	if issecretvalue(isTarget) then
		-- Comparison is restricted: the client decides visibility, scale stays neutral.
		health.selection:Show()
		health.selection:SetAlphaFromBoolean(isTarget, 0.25, 0)
		health.border:SetVertexColor(0, 0, 0, 0.6)
		self:SetScale(1)
		return
	end
	health.selection:SetAlpha(0.25)
	health.selection:SetShown(isTarget)
	if isTarget then
		health.border:SetVertexColor(1, 1, 1, self.isFriend and 0.35 or 0.55)
		self:SetScale(ns.db.general.clickable.targetScale)
	else
		health.border:SetVertexColor(0, 0, 0, 0.6)
		self:SetScale(1)
	end
end

function Plate:UpdateLevel()
	local unit, frame = self.unit, self.level
	local indicator = self.options.levelIndicator
	local classic = ns.db.general.useClassicStyle
	local isPlayer = Plain(UnitIsPlayer(unit))
	local showPlayer = classic or indicator.showPlayerLevel
	local showNPC = classic or indicator.showNPCLevel
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
		SetRaidTargetIconTexture(self.raidIcon, index)
		self.raidIcon:Show()
	end
end

function Plate:UpdateQuestIcon()
	if not self.unit then return end
	local show = self.options.objectiveIcons.showQuestObjectives
		and Plain(C_QuestLog.UnitIsRelatedToActiveQuest(self.unit))
	self.questIcon:SetShown(show and true or false)
end

function Plate:UpdateCast()
	local unit, cast = self.unit, self.cast
	if not self.options.castBar.enabled or self.nameOnly then
		cast:Hide()
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
		cast:Hide()
		return
	end
	cast:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
	cast.text:SetText(name)
	cast.icon:SetTexture(texture)
	if type(notInterruptible) == "nil" then
		cast.shield:SetAlpha(0)
	else
		cast.shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
	end
	cast:Show()
end
