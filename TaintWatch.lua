-- Step test (test build only, not for release). His error, 2026-10-21: a MOUSE click on a spell
-- button gives "DenoNameplate was forbidden from calling UNKNOWN()" inside UseAction; the spell's key
-- does not. What his runs measured: at every refusal nothing the click reads was tainted (the button's
-- action slot, the click functions, the secure templates, all 627 registered settings), no handler
-- of ours ran inside UseAction, and Forever wrote no taint.log. So the refusal is decided inside the
-- client, from something it keeps outside Lua.
--
-- This build finds the part of the addon that causes it in one session: the addon starts with only
-- its options and minimap button, and switches its parts on one step at a time while he plays. Each
-- step lasts until he has clicked spell buttons with the mouse a few times (counted here) and some
-- seconds have passed, out of combat. Refusals are counted per step, mouse or key, so the first step
-- that brings them names the part. The result goes to the error window (Button Drawer's), which he
-- copies anyway, and to the saved variables (DenoNameplateDB.stepTest).
local ADDON, ns = ...

local STEPS = {
	{ key = "base", text = "options and minimap button only" },
	{ key = "driver", text = "+ our nameplates (no auras, click area, stacking or every-frame code)" },
	{ key = "dr", text = "+ diminishing returns" },
	{ key = "holder", text = "+ the every-frame code that keeps the game's plates hidden" },
	{ key = "reregister", text = "+ target events put back on the game's hidden plates" },
	{ key = "hitarea", text = "+ click area and stacking" },
	{ key = "auras", text = "+ aura rows (debuffs, crowd control, removable buffs)" },
}
local STEP_OF = {}
for index, step in ipairs(STEPS) do STEP_OF[step.key] = index end

local CLICKS_PER_STEP, SECONDS_PER_STEP = 6, 15

local current = 0          -- 0 until the player is in the world
local stepStart = 0
local results = {}
local lastLabel, lastAt
local finished = false

local log = { build = "1.5.0-steps", client = select(2, GetBuildInfo()), steps = results }

local function Save()
	if type(DenoNameplateDB) == "table" then DenoNameplateDB.stepTest = log end
end

local function Say(text)
	print("|cffff8800Deno Nameplate test:|r " .. text)
end

-- Whether a part may run yet. Parts not named in STEPS always may.
function ns.TestAllows(key)
	local index = STEP_OF[key]
	return not index or index <= current
end

-- Wraps a handler of ours: remembers the last one that ran, for the refusal record.
function ns.Watched(label, fn)
	return function(...)
		lastLabel, lastAt = label, GetTime()
		return fn(...)
	end
end

local function Line(index)
	local r = results[index]
	local line = string.format("step %d (%s): %d mouse clicks on spell buttons, %d refused (%d mouse, %d key)",
		index, STEPS[index].text, r.clicks, r.mouse + r.key, r.mouse, r.key)
	if r.lastOurs then line = line .. "; last of ours before a refusal: " .. r.lastOurs end
	return line
end

local function Report(title)
	local lines = { title }
	for index = 1, #results do lines[#lines + 1] = Line(index) end
	local handler = geterrorhandler()
	if handler then pcall(handler, table.concat(lines, "\n")) end
	Save()
end

-- What each step switches on. The parts' own code waits for TestAllows.
local START = {
	driver = function() if ns.StartDriver then ns.StartDriver() end end,
	dr = function() if ns.StartDR then ns.StartDR() end end,
	holder = function() if ns.StartHolder then ns.StartHolder() end end,
	reregister = function() if ns.ReregisterSilenced then ns.ReregisterSilenced() end end,
	hitarea = function() if ns.ApplyHitAreas then ns.ApplyHitAreas() end end,
	auras = function() if ns.AfterCombat then ns.AfterCombat() end end,
}

local function Begin(index)
	current = index
	stepStart = GetTime()
	results[index] = { clicks = 0, mouse = 0, key = 0 }
	local step = STEPS[index]
	if START[step.key] then pcall(START[step.key]) end
	Say(string.format("step %d of %d: %s. Keep clicking spells with the mouse, out of combat.", index, #STEPS, step.text))
	Save()
end

local function Advance()
	if finished or current == 0 then return end
	local r = results[current]
	if r.clicks < CLICKS_PER_STEP or GetTime() - stepStart < SECONDS_PER_STEP or InCombatLockdown() then return end
	if current < #STEPS then
		Report("Deno Nameplate step test, after step " .. current .. " (copy all of this)")
		Begin(current + 1)
	else
		finished = true
		Report("Deno Nameplate step test FINISHED (copy all of this)")
		Say("finished. Open the error window, copy all, and paste it to Claude.")
	end
end

-- Mouse clicks on spell buttons, counted by looking at the mouse 30 times a second: a button
-- released while the mouse is on an action button. Nothing is hooked.
local wasDown = false
local function OnSpellButton()
	local foci = GetMouseFoci and GetMouseFoci()
	local focus = type(foci) == "table" and foci[1] or nil
	if type(focus) ~= "table" then return false end
	local ok, action = pcall(function() return focus.action end)
	return ok and type(action) == "number"
end

C_Timer.NewTicker(0.03, function()
	if current == 0 or finished then return end
	local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
	if wasDown and not down and OnSpellButton() then
		results[current].clicks = results[current].clicks + 1
	end
	wasDown = down and true or false
	Advance()
end)

local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_ENTERING_WORLD")
watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watch:RegisterEvent("ADDON_ACTION_BLOCKED")
watch:RegisterEvent("PLAYER_LOGOUT")
watch:SetScript("OnEvent", function(_, event, addon, func)
	if event == "PLAYER_ENTERING_WORLD" then
		watch:UnregisterEvent("PLAYER_ENTERING_WORLD")
		-- a moment after the world shows, so the login setup of every addon is done
		C_Timer.After(2, function() if current == 0 then Begin(1) end end)
	elseif event == "PLAYER_LOGOUT" then
		Save()
	elseif current > 0 and not finished then
		local stack = debugstack() or ""
		if not stack:find("UseAction") then return end
		local r = results[current]
		if stack:find("TryUseActionButton") then r.key = r.key + 1 else r.mouse = r.mouse + 1 end
		r.lastOurs = lastLabel and string.format("%s %.2f s before", lastLabel, GetTime() - lastAt) or "none"
		r.what = tostring(addon) .. " / " .. tostring(func)
		Save()
	end
end)
