-- Puts a plate on every nameplate the client shows and keeps the client's own one invisible.
local ADDON, ns = ...

local plates = {}   -- nameplate frame -> our plate
local active = {}   -- unit token -> our plate

-- The client's UnitFrame has to stay where it is: the click area belongs to it. It is kept
-- at alpha 0 instead of hidden. No SetAlpha hook (until 2026-10-19 there was one): our code
-- running inside Blizzard's own SetAlpha call tainted that run, and the stance bar after it was
-- blocked (probe 2026-10-19). The client also raises the alpha from its own code, which no hook
-- sees (his picture: the client's plate under ours in a fight). So every frame, a held plate
-- that is not at 0 goes back to 0.
local suppressed = setmetatable({}, { __mode = "k" })

-- A held plate's own code is switched off too, as EllesmereUI and Tempus do: the client's plate
-- keeps about 27 unit and 20 other events and runs its Lua all fight long under alpha 0, and
-- those runs shared their event batch with the stance bar, which was blocked (2026-10-19; gone
-- without Deno Nameplate). Only the target and soft-target events stay, for the soft-target
-- icon. The client registers the plate's events again when it hands the plate a new unit.
local function Silence(unitFrame)
	if unitFrame:IsProtected() then return end
	unitFrame:UnregisterAllEvents()
	unitFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
	unitFrame:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
	unitFrame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
	local castBar = unitFrame.castBar or (unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar)
	if castBar and not castBar:IsForbidden() then castBar:UnregisterAllEvents() end
end

local function Suppress(unitFrame, on)
	suppressed[unitFrame] = on
	unitFrame:SetAlpha(on and 0 or 1)
	if on then Silence(unitFrame) end
end

local holder = CreateFrame("Frame")
-- Under combat restrictions the client takes the methods off its plates (his error, 2026-10-19:
-- "attempt to call a nil value" every frame), so each one is looked up before it is called.
local function Usable(frame)
	if type(frame.CanBeAccessedInContext) ~= "function" then return false end
	local canAccess = frame:CanBeAccessedInContext()
	if issecretvalue(canAccess) or not canAccess then return false end
	return type(frame.IsForbidden) == "function" and not frame:IsForbidden()
		and type(frame.GetAlpha) == "function" and type(frame.SetAlpha) == "function"
end

holder:SetScript("OnUpdate", function()
	for frame, on in pairs(suppressed) do
		if on and Usable(frame) then
			local alpha = frame:GetAlpha()
			if issecretvalue(alpha) or alpha > 0 then frame:SetAlpha(0) end
		end
	end
end)

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
		plate:UpdateStackBounds()
		plate:UpdateHitArea()
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
