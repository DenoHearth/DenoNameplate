-- Step test (test build only, not for release). His error, 2026-10-21: a MOUSE click on a spell
-- button gives "DenoNameplate was forbidden from calling UNKNOWN()" inside UseAction; the spell's key
-- does not. His runs measured: at every refusal nothing the click reads was tainted (the button's
-- action slot, the click functions, the secure templates, all 627 registered settings), no handler of
-- ours ran inside UseAction, and Forever wrote no taint.log. The first step test (22:59) was refused
-- in its first step already, with our nameplates, diminishing returns and every-frame code all off.
--
-- So this build starts with nothing of the addon switched on, only its files loaded, and adds every
-- part back one step at a time while he plays, the load-time parts too. A step lasts until he has
-- clicked spell buttons with the mouse a few times (counted here by looking at the mouse buttons and
-- which spell button the mouse is over; nothing is hooked, and the game is not asked for its mouse
-- focus) and some seconds have passed, out of combat. The first refusal is reported at once, in the
-- error window (Button Drawer's) that he copies anyway: that step's part is the cause. Everything is
-- also kept in the saved variables (DenoNameplateDB.stepTest).
local ADDON, ns = ...

local STEPS = {
	{ key = "nothing", text = "only the addon's files loaded, nothing switched on" },
	{ key = "objects", text = "+ the number formats and colour curves for cast times and crowd control" },
	{ key = "client", text = "+ the game settings it applies (view distance, clickable size)" },
	{ key = "options", text = "+ its pages in the game's Options" },
	{ key = "minimap", text = "+ the minimap button" },
	{ key = "slash", text = "+ the /dnp command" },
	{ key = "purge", text = "+ watching your spells and pet (for removable buffs)" },
	{ key = "driver", text = "+ our nameplates (no auras, click area, stacking or every-frame code)" },
	{ key = "dr", text = "+ diminishing returns" },
	{ key = "holder", text = "+ the every-frame code that keeps the game's plates hidden" },
	{ key = "reregister", text = "+ target events put back on the game's hidden plates" },
	{ key = "hitarea", text = "+ click area and stacking" },
	{ key = "auras", text = "+ aura rows (debuffs, crowd control, removable buffs)" },
}
local STEP_OF = {}
for index, step in ipairs(STEPS) do STEP_OF[step.key] = index end

local CLICKS_PER_STEP, SECONDS_PER_STEP = 5, 10

local current = 0          -- 0 until the player is in the world
local stepStart = 0
local results = {}
local lastLabel, lastAt
local finished = false
local refusedStep          -- the first step that was refused
local log = { build = "1.5.0-steps2", client = select(2, GetBuildInfo()), steps = results }

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
	if r.lastOurs then line = line .. "; last of ours before it: " .. r.lastOurs end
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
	objects = function() ns.MakePlateObjects() end,
	client = function() ns.ApplyClientSettings() end,
	options = function() ns.BuildOptions() end,
	minimap = function() ns.CreateMinimapButton() end,
	slash = function() ns.RegisterSlash() end,
	purge = function() ns.StartPurgeWatch() end,
	driver = function() ns.StartDriver() end,
	dr = function() ns.StartDR() end,
	holder = function() ns.StartHolder() end,
	reregister = function() ns.ReregisterSilenced() end,
	hitarea = function() ns.ApplyHitAreas() end,
	auras = function() ns.AfterCombat() end,
}

local function Begin(index)
	current = index
	stepStart = GetTime()
	results[index] = { clicks = 0, mouse = 0, key = 0 }
	local step = STEPS[index]
	if START[step.key] then
		local ok, problem = pcall(START[step.key])
		if not ok then results[index].startError = tostring(problem) end
	end
	Say(string.format("step %d of %d: %s. Keep clicking spells with the mouse, out of combat.", index, #STEPS, step.text))
	Save()
end

local function Advance()
	if finished or current == 0 then return end
	local r = results[current]
	if r.clicks < CLICKS_PER_STEP or GetTime() - stepStart < SECONDS_PER_STEP or InCombatLockdown() then return end
	if current < #STEPS then
		Begin(current + 1)
	else
		finished = true
		if refusedStep then
			Report("Deno Nameplate step test FINISHED, first refused in step " .. refusedStep .. " (copy all of this)")
		else
			Report("Deno Nameplate step test FINISHED, no step was refused (copy all of this)")
		end
		Say("finished. Open the error window, copy all, and paste it to Claude.")
	end
end

-- A mouse click on a spell button: a mouse button let go while the mouse is over one of the action
-- buttons Blizzard lists in ActionBarButtonEventsFrame.frames.
local function OverSpellButton()
	local frames = ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames
	if type(frames) ~= "table" then return false end
	for _, button in pairs(frames) do
		if button:IsVisible() and button:IsMouseOver() then return true end
	end
	return false
end

local wasDown = false
C_Timer.NewTicker(0.03, function()
	if current == 0 or finished then return end
	local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
	if wasDown and not down and OverSpellButton() then
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
		if not refusedStep then
			refusedStep = current
			Report(string.format("Deno Nameplate step test: REFUSED in step %d of %d (copy all of this)", current, #STEPS))
			Say(string.format("refused in step %d. You can stop: open the error window, copy all, and paste it to Claude.", current))
		end
		Save()
	end
end)
