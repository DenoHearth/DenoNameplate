-- Diminishing returns of crowd control, left of the enemy plate (the mirror of the removable
-- buffs on its right). His ask, 2026-10-11: "we have dispell on the right side, could we have
-- CC DR on the left side of deno frames".
--
-- The tracking is Forever Simple DR by Tarolg (DR/Store, Catalog, Engine, Sources: MIT, see
-- DR/LICENSE-ForeverDR): it puts together what the game lets an addon see (the game's own DR
-- feed where it is on, readable auras, your and your pet's casts, miss and immune messages) and
-- marks what it could not confirm. This file only draws its answer on Deno Nameplate's plates.
--
-- One icon per category: the last crowd control used (or the category's picture), a frame in
-- yellow (the next one lasts half), orange (a quarter) or red (immune), the same in words under
-- it, and the seconds until the category resets. Grey icon: part of it is an estimate.

local _, addon = ...
local DR = addon.DR

local SIZE, GAP, MAX = 18, 2, 4
local STAGE = { { 1, 0.82, 0 }, { 1, 0.5, 0 }, { 1, 0.1, 0.1 } }
local WORD = { "50%", "25%", "IMM" }
local redColor = CreateColor(1, 0.1, 0.1, 1)
local stageColors = { CreateColor(1, 0.82, 0, 1), CreateColor(1, 0.5, 0, 1), CreateColor(1, 0.1, 0.1, 1) }
local started, queued, since = false, true, 0

local function stageOf(entry)
	if entry.immune or entry.count >= DR.IMMUNE_STACKS then return 3 end
	return math.max(1, math.min(2, entry.count))
end

local function newIcon(plate, index)
	local icon = CreateFrame("Frame", nil, plate)
	icon:SetSize(SIZE, SIZE)
	-- left of the bar, past the elite mark
	icon:SetPoint("RIGHT", plate.health, "LEFT", -16 - (index - 1) * (SIZE + GAP), 0)
	icon.border = icon:CreateTexture(nil, "BACKGROUND")
	icon.border:SetPoint("TOPLEFT", -1, 1)
	icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
	icon.border:SetColorTexture(1, 1, 1, 1)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints()
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.time = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	icon.time:SetPoint("CENTER", 0, 0)
	icon.word = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
	icon.word:SetPoint("TOP", icon, "BOTTOM", 0, -1)
	return icon
end

local function draw(plate, entries, guid)
	local icons = plate.drIcons
	local shown = 0
	if entries then
		for _, entry in ipairs(entries) do
			if shown >= MAX then break end
			if DR.ShouldShow(entry.category) then
				shown = shown + 1
				if not icons then
					icons = {}
					plate.drIcons = icons
				end
				local icon = icons[shown]
				if not icon then
					icon = newIcon(plate, shown)
					icons[shown] = icon
				end
				local stage = stageOf(entry)
				local color = STAGE[stage]
				icon.texture:SetTexture(entry.spellID and DR.SpellIcon(entry.spellID) or DR.CategoryIcon(entry.category))
				icon.texture:SetDesaturated(entry.estimated)
				-- where the game says "immune" in a value an addon may not read, the game picks the colour
				local secret = guid and not entry.immune and DR.secretImmune[guid .. ":" .. entry.category]
				if secret and secret.resetAt == entry.resetAt then
					icon.border:SetVertexColorFromBoolean(secret.box.value, redColor, stageColors[stage])
				else
					icon.border:SetVertexColor(color[1], color[2], color[3], 1)
				end
				icon.word:SetText(WORD[stage])
				icon.word:SetTextColor(color[1], color[2], color[3])
				icon.time:SetText(string.format("%d", math.max(0, math.ceil(entry.remaining))))
				icon:Show()
			end
		end
	end
	if icons then
		for index = shown + 1, #icons do icons[index]:Hide() end
	end
	return shown > 0
end

local function refresh()
	local on = started and DR.db and DR.db.enabled
	local now = GetTime()
	local live = false
	for unit, plate in pairs(addon.active) do
		local guid = on and not plate.isFriend and DR.ReadEnemy(unit) or nil
		if draw(plate, guid and DR.tracker:Snapshot(guid, now) or nil, guid) then live = true end
	end
	return live or (on and DR.tracker:HasLive(now))
end

function DR.RequestRefresh() queued = true end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
	since = since + elapsed
	if not queued or since < 0.1 then return end
	since, queued = 0, false
	if refresh() then queued = true end       -- the seconds on the icons keep counting
end)

-- Our two switches (Options: General) are the tracker's "enabled" and "also NPCs".
local function sync()
	if not started then return end
	local general = addon.db.general
	DR.Set("enabled", general.showDR and true or false)
	DR.Set("npcs", general.drNPCs and true or false)
	DR.RequestRefresh()
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	if not addon.db then return end
	local saved, problem = DR.LoadSettings(DenoNameplateDB.dr)
	if not saved then
		DR.Print("its saved settings could not be read (" .. tostring(problem) .. "); starting from the defaults.")
		saved = DR.LoadSettings(nil)
	end
	DenoNameplateDB.dr = saved
	DR.db = saved
	saved.chat = false                    -- no chat lines of its own; the switches are in our options
	DR.tracker = DR.NewTracker(function() return DR.db.resetTime end, DR.Learned)
	DR.OnSettingChanged(function(key)
		if key == "enabled" and not DR.db.enabled then DR.ClearTracking() end
	end)
	started = true
	local general = addon.db.general
	saved.enabled, saved.npcs = general.showDR and true or false, general.drNPCs and true or false
	DR.StartSources()
	hooksecurefunc(addon, "Refresh", sync)
end)
