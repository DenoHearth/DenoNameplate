-- Puts a plate on every nameplate the client shows and keeps the client's own one invisible.
local ADDON, ns = ...

local plates = {}   -- nameplate frame -> our plate
local active = {}   -- unit token -> our plate

-- The client's UnitFrame has to stay where it is: the click area belongs to it. It is kept
-- at alpha 0 instead of hidden, and a hook holds it there when the client resets the alpha.
local suppressed = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

local function Suppress(unitFrame, on)
	if not hooked[unitFrame] then
		hooked[unitFrame] = true
		local locked = false
		hooksecurefunc(unitFrame, "SetAlpha", function(frame)
			if locked or not suppressed[frame] or frame:IsForbidden() then return end
			locked = true
			frame:SetAlpha(0)
			locked = false
		end)
	end
	suppressed[unitFrame] = on
	unitFrame:SetAlpha(on and 0 or 1)
end

local function IsTrue(value)
	return not issecretvalue(value) and value and true or false
end

local function OnAdded(unit)
	local base = C_NamePlate.GetNamePlateForUnit(unit)
	if not base or base:IsForbidden() then return end
	local unitFrame = base.UnitFrame
	local forbidden = unitFrame and unitFrame:IsForbidden()
	-- Left to the client: plates addons may not touch, the player's own plate, and plates
	-- that only carry a widget (quest progress bars and the like).
	if forbidden or IsTrue(UnitIsUnit(unit, "player")) or IsTrue(UnitNameplateShowsWidgetsOnly(unit)) then
		if plates[base] then plates[base]:ClearUnit() end
		if unitFrame and not forbidden then Suppress(unitFrame, false) end
		return
	end
	local plate = plates[base]
	if not plate then
		plate = ns.CreatePlate(base)
		plates[base] = plate
	end
	active[unit] = plate
	if unitFrame then Suppress(unitFrame, true) end
	plate:SetUnit(unit)
end

local function OnRemoved(unit)
	local plate = active[unit]
	if not plate then return end
	active[unit] = nil
	plate:ClearUnit()
end

-- Entry points for the offline test fixture.
ns.active, ns.OnUnitAdded, ns.OnUnitRemoved = active, OnAdded, OnRemoved

function ns.UpdateAllPlates()
	for _, plate in pairs(active) do plate:Refresh() end
end

-- Aura rows cannot be built in combat; plates first shown mid-fight get theirs here.
function ns.AfterCombat()
	for unit, plate in pairs(active) do
		if not plate.auras then
			plate:EnsureAuras()
			if plate.auras then
				plate.auras:SetUnit(unit)
				plate:ApplyOptions()
			end
		end
	end
end

function ns.StartDriver()
	local driver = CreateFrame("Frame")
	driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	driver:RegisterEvent("PLAYER_TARGET_CHANGED")
	driver:RegisterEvent("RAID_TARGET_UPDATE")
	driver:RegisterEvent("QUEST_LOG_UPDATE")
	driver:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	driver:SetScript("OnEvent", function(self, event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			OnAdded(unit)
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			OnRemoved(unit)
		elseif event == "PLAYER_TARGET_CHANGED" then
			for _, plate in pairs(active) do plate:UpdateTarget() end
		elseif event == "RAID_TARGET_UPDATE" then
			for _, plate in pairs(active) do plate:UpdateRaidIcon() end
		elseif event == "QUEST_LOG_UPDATE" then
			for _, plate in pairs(active) do plate:UpdateQuestIcon() end
		elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
			for _, plate in pairs(active) do
				plate:UpdateColor()
				plate:UpdateName()
				plate:UpdateAggro()
			end
		end
	end)

	-- Nameplates already on screen when the addon starts (after a /reload).
	for _, base in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = base.namePlateUnitToken or (base.UnitFrame and base.UnitFrame.unit)
		if type(unit) == "string" then OnAdded(unit) end
	end
end
