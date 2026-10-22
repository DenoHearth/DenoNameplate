-- Demon frame: the pet frame in Blizzard's own art with a wider health bar (name and health on it,
-- stance above), a thin mana line and a cast bar under it. His design, 2026-10-23 (simulator
-- mock-ups _mock_db_tw / _mock_db_cb / _mock_db_move). Holding Ctrl out of combat shows a blue box
-- over the demon frame and over Blizzard's pet action bar; dragging a box moves that piece.
--
-- Patterns taken from shipping Forever addons:
--   * Blizzard's pet frame is switched off the way oUF does it in ShestakUI_Forever
--     (Libs/oUF/Blizzard.lua, handleFrame): UnregisterAllEvents and the "alwaysBlocked" roleset.
--   * Moving a Blizzard bar: a mover box over it and SetPoint out of combat, re-applied when the
--     game places the bar again, as AnyMoveForever does (AnyMoveForever.lua, Apply / Register).
--     The pet bar is only touched once he has moved it; until then it is Blizzard's, untouched.
--   * Health, power and the cast bar follow the Forever display rules (foreverman recipes 1-3,
--     and Plate:UpdateCast): every secret goes straight into a widget, a formatter or SetText.
local ADDON, ns = ...

local UNIT = "pet"
local BAR_WIDTH = 150
local PORTRAIT = 37

-- Time left on a cast, one decimal, counted by the client (as on the plates).
local castTimeFormat
if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
	castTimeFormat = C_StringUtil.CreateNumericRuleFormatter()
	castTimeFormat:SetBreakpoints({
		{ threshold = 0, format = "%.1f", step = 0.1, rounding = Enum.NumericRuleFormatRounding.Up },
	})
end

local PET_MODES = { PET_MODE_AGGRESSIVE = true, PET_MODE_DEFENSIVE = true, PET_MODE_PASSIVE = true, PET_MODE_ASSIST = true }

local frame              -- the demon frame (a secure unit button: click targets the pet)
local movers = {}        -- name -> blue box shown while Ctrl is held
local barHooked = false

local function Plain(value)
	if issecretvalue(value) then return nil end
	return value
end

local function Edge(parent, target, level)
	local edge = CreateFrame("Frame", nil, parent)
	edge:SetPoint("TOPLEFT", target, "TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 1, -1)
	edge:SetFrameLevel(level)
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local line = edge:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(0.55, 0.55, 0.58, 1)
		line:SetPoint(side[1])
		line:SetPoint(side[2])
		if side[3] then line:SetHeight(1) else line:SetWidth(1) end
	end
	return edge
end

local function Text(parent, size, point, x)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetFont(ns.FetchFont("Friz Quadrata TT"), size, "OUTLINE")
	fs:SetPoint(point, x, 0)
	fs:SetWordWrap(false)
	return fs
end

-- Bar fills and ring are retail's art, as Deno Retail Frames draws the player frame: Forever answers
-- the frame atlases from its own bronze "-c60" sheet, and his frames wear retail's. The fills are the
-- player frame's retail fills (Media/, cut by Deno Retail Frames from interface/hud/uiunitframe2x.blp).
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local RETAIL_SHEET, SHEET_W, SHEET_H = 4642466, 2048, 1024
local TOT_RING = { 1113, 1353, 315, 413 }   -- ui-hud-unitframe-targetoftarget-portraiton on that sheet (2x)

local function Bar(parent, file)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(file)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.75)
	return bar
end

------------------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------------------
local function Build()
	frame = CreateFrame("Button", "DenoNameplatePetFrame", UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(PORTRAIT + 7 + BAR_WIDTH + 2, 62)
	frame:SetAttribute("unit", UNIT)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	-- portrait in a circle, and the left (round) part of the pet frame's ring
	local portrait = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	portrait:SetSize(PORTRAIT, PORTRAIT)
	portrait:SetPoint("TOPLEFT", 5, -5)
	local mask = frame:CreateMaskTexture()
	mask:SetAtlas("CircleMaskScalable")
	mask:SetAllPoints(portrait)
	portrait:AddMaskTexture(mask)
	frame.portrait = portrait

	-- the round left part of the pet frame's ring; the rest of that art is the small frame's bar slots
	local ring = frame:CreateTexture(nil, "ARTWORK")
	local part = 0.36
	local left, right, top, bottom = TOT_RING[1], TOT_RING[2], TOT_RING[3], TOT_RING[4]
	local cut = left + (right - left) * part
	ring:SetTexture(RETAIL_SHEET)
	ring:SetTexCoord(left / SHEET_W, cut / SHEET_W, top / SHEET_H, bottom / SHEET_H)
	ring:SetSize((cut - left) / 2, (bottom - top) / 2)
	ring:SetPoint("TOPLEFT", 0, 0)

	local health = Bar(frame, MEDIA .. "pet-health.tga")
	health:SetSize(BAR_WIDTH, 12)
	health:SetPoint("BOTTOMLEFT", portrait, "RIGHT", 2, -4)
	frame.health = health
	local power = Bar(frame, MEDIA .. "pet-mana.tga")
	power:SetSize(BAR_WIDTH, 5)
	power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -1)
	frame.power = power
	local edge = CreateFrame("Frame", nil, frame)
	edge:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
	edge:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
	Edge(frame, edge, health:GetFrameLevel() + 3)

	local over = CreateFrame("Frame", nil, health)
	over:SetAllPoints()
	over:SetFrameLevel(health:GetFrameLevel() + 5)
	frame.name = Text(over, 9, "LEFT", 4)
	frame.name:SetPoint("RIGHT", health, "RIGHT", -40, 0)
	frame.name:SetJustifyH("LEFT")
	frame.healthText = Text(over, 9, "RIGHT", -4)
	frame.stance = Text(frame, 8, "BOTTOMLEFT", 0)
	frame.stance:ClearAllPoints()
	frame.stance:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 1, 1)
	frame.stance:SetTextColor(0.6, 0.62, 0.68)

	-- cast bar under the mana line, Blizzard's cast fill, icon to its left
	local cast = Bar(frame, ns.WHITE)
	if C_Texture.GetAtlasInfo("ui-castingbar-filling-standard") then
		cast:GetStatusBarTexture():SetAtlas("ui-castingbar-filling-standard")
	else
		cast:SetStatusBarColor(1, 0.7, 0)
	end
	cast:SetSize(BAR_WIDTH - 12, 9)
	cast:SetPoint("TOPRIGHT", power, "BOTTOMRIGHT", 0, -3)
	cast:Hide()
	Edge(cast, cast, cast:GetFrameLevel() + 3)
	cast.icon = cast:CreateTexture(nil, "ARTWORK")
	cast.icon:SetSize(10, 10)
	cast.icon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
	cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local castOver = CreateFrame("Frame", nil, cast)
	castOver:SetAllPoints()
	castOver:SetFrameLevel(cast:GetFrameLevel() + 5)
	cast.text = Text(castOver, 8, "LEFT", 3)
	cast.text:SetPoint("RIGHT", cast, "RIGHT", -24, 0)
	cast.text:SetJustifyH("LEFT")
	cast.time = Text(castOver, 8, "RIGHT", -3)
	if castTimeFormat then
		cast.timeBinding = C_DurationUtil.CreateDurationTextBinding()
		cast.timeBinding:SetFormatter(castTimeFormat)
		cast.timeBinding:SetFontString(cast.time)
		cast.timeBinding:SetUpdateInterval(0.1)
		cast.timeBinding:SetEnabled(false)
	end
	frame.cast = cast
end

------------------------------------------------------------------------------------------
-- Updating
------------------------------------------------------------------------------------------
local function UpdateHealth()
	local health = frame.health
	health:SetMinMaxValues(0, UnitHealthMax(UNIT))
	health:SetValue(UnitHealth(UNIT))
	frame.healthText:SetText(AbbreviateNumbers(UnitHealth(UNIT)))
end

local function UpdatePower()
	frame.power:SetMinMaxValues(0, UnitPowerMax(UNIT))
	frame.power:SetValue(UnitPower(UNIT))
end

local function UpdateStance()
	local stance
	for i = 1, NUM_PET_ACTION_SLOTS or 10 do
		local name, _, isToken, isActive = GetPetActionInfo(i)
		name, isToken, isActive = Plain(name), Plain(isToken), Plain(isActive)
		if isToken and isActive and name and PET_MODES[name] then
			stance = _G[name]
			break
		end
	end
	frame.stance:SetText(stance or "")
end

local function StopCast()
	local cast = frame.cast
	cast:Hide()
	if cast.timeBinding then cast.timeBinding:SetEnabled(false) end
end

local function UpdateCast()
	local cast = frame.cast
	local name, _, texture = UnitCastingInfo(UNIT)
	local duration, direction
	if type(name) ~= "nil" then
		duration = UnitCastingDuration(UNIT)
		direction = Enum.StatusBarTimerDirection.ElapsedTime
	else
		name, _, texture = UnitChannelInfo(UNIT)
		if type(name) ~= "nil" then
			duration = UnitChannelDuration(UNIT)
			direction = Enum.StatusBarTimerDirection.RemainingTime
		end
	end
	if type(name) == "nil" or type(duration) == "nil" then
		StopCast()
		return
	end
	cast:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
	if cast.timeBinding then
		cast.timeBinding:SetDuration(duration)
		cast.timeBinding:SetEnabled(true)
	end
	cast.text:SetText(name)
	cast.icon:SetTexture(texture)
	cast:Show()
end

local function UpdateAll()
	if not frame then return end
	SetPortraitTexture(frame.portrait, UNIT)
	frame.name:SetText(UnitName(UNIT))
	UpdateHealth()
	UpdatePower()
	UpdateStance()
	UpdateCast()
end

local CAST_EVENTS = {
	UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_DELAYED = true,
	UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_FAILED = true,
}

local function OnEvent(_, event)
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		UpdateHealth()
	elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
		UpdatePower()
	elseif CAST_EVENTS[event] then
		UpdateCast()
	elseif event == "PET_BAR_UPDATE" then
		UpdateStance()
	else
		UpdateAll()
	end
end

------------------------------------------------------------------------------------------
-- Positions. Saved as the frame's centre in UIParent units (as AnyMoveForever does).
------------------------------------------------------------------------------------------
local function PlaceAt(target, position)
	local ratio = UIParent:GetEffectiveScale() / target:GetEffectiveScale()
	target:ClearAllPoints()
	target:SetPoint("CENTER", UIParent, "BOTTOMLEFT", position.x * ratio, position.y * ratio)
end

local function PlaceFrame()
	if InCombatLockdown() then return end
	local position = ns.db.general.pet.framePosition
	if position then
		PlaceAt(frame, position)
	else
		-- Blizzard's spot for the pet frame: under the player frame, a little in
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 15, 3)
	end
end

local applyingBar = false
local function PlaceBar()
	local position = ns.db.general.pet.barPosition
	if not position or not PetActionBar or InCombatLockdown() then return end
	applyingBar = true
	PlaceAt(PetActionBar, position)
	applyingBar = false
end

-- Only once he has moved the pet bar: the game places it again on layout changes, so put it back.
local function HookBar()
	if barHooked or not PetActionBar then return end
	barHooked = true
	hooksecurefunc(PetActionBar, "SetPoint", function()
		if not applyingBar and ns.db.general.pet.barPosition then
			if InCombatLockdown() then ns.petBarPending = true else PlaceBar() end
		end
	end)
end

------------------------------------------------------------------------------------------
-- Ctrl + drag
------------------------------------------------------------------------------------------
local function Mover(name, label, target, onDrop)
	local mover = CreateFrame("Button", nil, UIParent)
	mover:SetFrameStrata("DIALOG")
	mover:SetMovable(true)
	mover:SetClampedToScreen(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()
	local fill = mover:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.52, 0.80, 1.00, 0.15)
	Edge(mover, mover, mover:GetFrameLevel() + 1)
	local text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetFont(ns.FetchFont("Friz Quadrata TT"), 9, "OUTLINE")
	text:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 2, 2)
	text:SetText(label .. "  -  Ctrl + drag to move")
	text:SetTextColor(0.52, 0.80, 1.00)
	mover:SetScript("OnDragStart", function(self)
		if not InCombatLockdown() then self:StartMoving() end
	end)
	mover:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if InCombatLockdown() then return end
		local cx, cy = self:GetCenter()
		if not cx then return end
		local ratio = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
		onDrop({ x = cx * ratio, y = cy * ratio })
		self.place()
	end)
	mover.place = function()
		local t = target()
		if not t then return end
		local cx, cy = t:GetCenter()
		local width, height = t:GetSize()
		if not cx then return end
		local ratio = t:GetEffectiveScale() / mover:GetEffectiveScale()
		mover:ClearAllPoints()
		mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * ratio, cy * ratio)
		mover:SetSize(math.max(width * ratio, 40), math.max(height * ratio, 20))
	end
	movers[name] = mover
	return mover
end

local function ShowMovers(show)
	show = show and not InCombatLockdown() and ns.db.general.pet.ctrlMove
	for name, mover in pairs(movers) do
		local target = name == "frame" and frame or PetActionBar
		if show and target and target:IsVisible() then
			mover.place()
			mover:Show()
		else
			mover:Hide()
		end
	end
end

local function BuildMovers()
	Mover("frame", "Demon frame", function() return frame end, function(position)
		ns.db.general.pet.framePosition = position
		PlaceFrame()
	end)
	Mover("bar", "Pet buttons", function() return PetActionBar end, function(position)
		ns.db.general.pet.barPosition = position
		HookBar()
		PlaceBar()
	end)
end

------------------------------------------------------------------------------------------
-- Blizzard's pet frame, switched off while ours is on (ShestakUI_Forever's oUF way)
------------------------------------------------------------------------------------------
local function DisableBlizzardPetFrame()
	if not PetFrame then return end
	PetFrame:UnregisterAllEvents()
	if PetFrame.SetRolesets then PetFrame:SetRolesets("alwaysBlocked") end
	for _, bar in ipairs({ PetFrameHealthBar, PetFrameManaBar }) do
		if bar then bar:UnregisterAllEvents() end
	end
end

------------------------------------------------------------------------------------------
-- Start: called from Core a frame after login, out of combat.
------------------------------------------------------------------------------------------
local watcher = CreateFrame("Frame")

function ns.StartPetFrame()
	local pet = ns.db.general.pet
	if InCombatLockdown() then
		ns.petStartPending = true
		return
	end
	ns.petStartPending = false
	BuildMovers()
	if pet.barPosition then
		HookBar()
		PlaceBar()
	end
	watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function(_, event, key, down)
		if event == "MODIFIER_STATE_CHANGED" then
			if key == "LCTRL" or key == "RCTRL" then ShowMovers(down == 1) end
		elseif event == "PLAYER_REGEN_DISABLED" then
			ShowMovers(false)
		elseif event == "PLAYER_REGEN_ENABLED" then
			if ns.petBarPending then
				ns.petBarPending = false
				PlaceBar()
			end
		end
	end)

	if not pet.enabled then return end
	Build()
	DisableBlizzardPetFrame()
	PlaceFrame()
	RegisterUnitWatch(frame)
	frame:SetScript("OnEvent", OnEvent)
	frame:SetScript("OnShow", UpdateAll)
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }) do
		frame:RegisterUnitEvent(event, UNIT)
	end
	for event in pairs(CAST_EVENTS) do frame:RegisterUnitEvent(event, UNIT) end
	frame:RegisterUnitEvent("UNIT_PET", "player")
	frame:RegisterEvent("PET_BAR_UPDATE")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	UpdateAll()
end

-- Options: put both pieces back where the game had them.
function ns.ResetPetPositions()
	if InCombatLockdown() then
		print("|cffffcc59Deno Nameplate:|r Leave combat first, then reset the demon frame and pet buttons.")
		return
	end
	local pet = ns.db.general.pet
	pet.framePosition = nil
	local hadBar = pet.barPosition ~= nil
	pet.barPosition = nil
	if frame then PlaceFrame() end
	if hadBar then
		print("|cffffcc59Deno Nameplate:|r Pet buttons go back to the game's spot after |cffffffff/reload|r.")
	end
end
