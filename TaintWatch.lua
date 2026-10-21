-- Taint watch (test build only, not for release; it also switches the game's taint log on). His error, 2026-10-21: a MOUSE click on a spell
-- button gives "DenoNameplate was forbidden from calling UNKNOWN()" inside UseAction; the spell's key
-- does not. In Blizzard's code (forever branch, ActionButton.lua) only the mouse path reads the
-- button's own state before UseAction: OnClick reads self.action, and self.action is written anew on
-- every hover (OnEnter -> UpdateAction(true)) after reading ActionBarButtonRangeCheckFrame.actions[n]
-- and ActionBarButtonUsableWatcherFrame.actions[n]. Those per-action tables are made once and kept for
-- the session, so one tainted write to them leaves every later hover, and so every mouse click,
-- tainted until the game restarts. Nothing of ours is on the stack by then.
--
-- This file only reads (issecurevariable) and writes nothing of Blizzard's. Every handler of ours is
-- wrapped by ns.Watched: right after it returns, the slots are looked at again, so the first slot that
-- turns tainted is pinned to the handler (and event) it turned in. Slots that turn outside our
-- handlers are caught by a check four times a second. The findings go to chat and to the saved
-- variables (DenoNameplateDB.taintWatch), written when the game is closed.
local ADDON, ns = ...

local MAX_RECORDS = 25
local log = { build = "1.5.0-watch", client = select(2, GetBuildInfo()), records = {}, refusals = {} }
local recorded = {}        -- slot name -> true once its first turn is written down
local lastLabel, lastAt
local done = false
local started = GetTime()

local function Since() return math.floor((GetTime() - started) * 100 + 0.5) / 100 end

local function Save()
	if type(DenoNameplateDB) == "table" then DenoNameplateDB.taintWatch = log end
end

local function Say(text)
	print("|cffff8800Deno Nameplate watch:|r " .. text)
end

-- issecurevariable takes string keys; other keys are tried and skipped when the client refuses them.
local function Secure(tbl, key)
	local ok, secure, taintedBy
	if tbl == nil then
		ok, secure, taintedBy = pcall(issecurevariable, key)
	else
		ok, secure, taintedBy = pcall(issecurevariable, tbl, key)
	end
	if not ok then return true end
	return secure, taintedBy
end

local function Record(name, taintedBy, label)
	recorded[name] = true
	local entry = {
		slot = name,
		by = tostring(taintedBy),
		at = Since(),
		combat = InCombatLockdown() and true or false,
	}
	if label then
		entry.during = label
		entry.stack = debugstack(4, 6, 0)
	else
		entry.during = "outside our handlers"
		entry.lastOurs = lastLabel and (lastLabel .. " @" .. tostring(lastAt)) or "none yet"
	end
	local records = log.records
	records[#records + 1] = entry
	if #records == 1 then
		Say("first tainted slot: " .. name .. " (" .. entry.during .. ", " .. entry.at .. " s after load)")
	end
	if #records >= MAX_RECORDS then done = true end
	Save()
end

local function Check(tbl, key, name, label)
	if recorded[name] then return end
	local secure, taintedBy = Secure(tbl, key)
	if not secure then Record(name, taintedBy, label) end
end

local function ButtonName(button)
	local name = type(button.GetName) == "function" and button:GetName()
	return name or tostring(button)
end

-- What the mouse path of an action button reads before UseAction, and what decides how it is written.
local function Scan(label)
	if done then return end
	Check(nil, "ACTION_HIGHLIGHT_MARKS", "ACTION_HIGHLIGHT_MARKS", label)
	Check(nil, "QuickKeybindFrame", "QuickKeybindFrame", label)
	Check(nil, "SettingsPanel", "SettingsPanel", label)
	if SettingsPanel then Check(SettingsPanel, "settings", "SettingsPanel.settings", label) end
	if C_ActionBar then Check(C_ActionBar, "IsAutoCastPetAction", "C_ActionBar.IsAutoCastPetAction", label) end
	local range = ActionBarButtonRangeCheckFrame and ActionBarButtonRangeCheckFrame.actions
	local usable = ActionBarButtonUsableWatcherFrame and ActionBarButtonUsableWatcherFrame.actions
	if ActionBarButtonRangeCheckFrame then
		Check(ActionBarButtonRangeCheckFrame, "actions", "ActionBarButtonRangeCheckFrame.actions", label)
	end
	if ActionBarButtonUsableWatcherFrame then
		Check(ActionBarButtonUsableWatcherFrame, "actions", "ActionBarButtonUsableWatcherFrame.actions", label)
	end
	local frames = ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames
	if type(frames) ~= "table" then return end
	for _, button in pairs(frames) do
		local name = ButtonName(button)
		Check(button, "action", name .. ".action", label)
		Check(button, "bar", name .. ".bar", label)
		local action = button.action
		if type(action) == "number" then
			if type(range) == "table" then Check(range, action, "RangeCheck.actions[" .. action .. "]", label) end
			if type(usable) == "table" then Check(usable, action, "UsableWatcher.actions[" .. action .. "]", label) end
		end
	end
end

-- Wraps a handler of ours: the slots are looked at again as soon as it returns.
local function After(label, ...)
	lastLabel, lastAt = label, Since()
	pcall(Scan, label)
	return ...
end

function ns.Watched(label, fn)
	return function(...)
		if done then return fn(...) end
		local event = select(2, ...)
		local full = label
		if type(event) == "string" and not issecretvalue(event) then full = label .. " " .. event end
		return After(full, fn(...))
	end
end

-- Test build only: the game's own taint log (Logs\taint.log) names the exact line where Blizzard's code
-- first read something of ours. Switched on here so he has nothing to type; a normal build never
-- writes a game setting.
if C_CVar and C_CVar.GetCVar("taintLog") ~= "2" then pcall(C_CVar.SetCVar, "taintLog", "2") end
log.taintLog = C_CVar and C_CVar.GetCVar("taintLog")

local watch = CreateFrame("Frame")
local elapsedSince = 0
watch:SetScript("OnUpdate", function(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.25 then return end
	elapsedSince = 0
	Scan(nil)
end)

-- His second run (2026-10-21 22:34): the button's action slot and its two per-action entries were
-- clean at the refusal. So everything else the mouse path reads before UseAction is looked at, at
-- the refusal itself: the functions and tables on that path, and the "lockActionBars" setting it
-- asks for (Settings.GetValue walks every registered setting, ours too). Returns the tainted ones.
local function Wider()
	local found = {}
	local function Look(tbl, key, name)
		if tbl == nil and key == nil then return end
		local secure, by = Secure(tbl, key)
		if not secure then found[#found + 1] = name .. " (" .. tostring(by) .. ")" end
	end
	for _, name in ipairs({ "Settings", "SettingsPanel", "SECURE_ACTIONS", "SpellFlyout", "C_ActionBar", "C_CVar",
		"GetCVarBool", "IsModifiedClick", "GetCursorInfo", "UseAction", "GetActionInfo", "SaveMacro",
		"securecallfunction", "SecureActionButton_OnClick", "SecureButton_GetModifiedAttribute",
		"SecureButton_GetAttribute", "SecureButton_GetModifiedUnit", "SecureButton_GetModifierPrefix",
		"SecureButton_GetButtonSuffix", "SpellCanTargetItem", "SpellCanTargetItemID", "KeybindFrames_InQuickKeybindMode",
		"QuickKeybindFrame", "QuickKeybindButtonTemplateMixin", "ActionBarActionButtonMixin",
		"ActionBarActionButtonDerivedMixin", "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
		"UnitExists", "UnitCanAttack", "UnitCanAssist", "UnitHasVehicleUI", "GetModifiedClick",
		"ATTRIBUTE_NOOP", "NUM_ACTIONBAR_BUTTONS" }) do
		Look(nil, name, name)
	end
	if Settings then
		Look(Settings, "GetValue", "Settings.GetValue")
		Look(Settings, "GetSetting", "Settings.GetSetting")
	end
	if C_ActionBar then
		for _, key in ipairs({ "IsAutoCastPetAction", "GetActionBarPage", "GetExtraBarIndex" }) do
			Look(C_ActionBar, key, "C_ActionBar." .. key)
		end
	end
	if C_CVar then Look(C_CVar, "GetCVarBool", "C_CVar.GetCVarBool") Look(C_CVar, "GetCVar", "C_CVar.GetCVar") end
	if SECURE_ACTIONS then Look(SECURE_ACTIONS, "action", "SECURE_ACTIONS.action") end
	if ActionBarActionButtonMixin then
		for _, key in ipairs({ "OnClick", "TriggerSecureClick", "CalculateAction" }) do
			Look(ActionBarActionButtonMixin, key, "ActionBarActionButtonMixin." .. key)
		end
	end
	if ActionBarActionButtonDerivedMixin then
		Look(ActionBarActionButtonDerivedMixin, "ActionBarActionButtonDerivedMixin_OnClick", "Derived_OnClick")
	end
	if QuickKeybindButtonTemplateMixin then
		Look(QuickKeybindButtonTemplateMixin, "QuickKeybindButtonOnClick", "QuickKeybindButtonOnClick")
	end
	local button = ActionButton3 or ActionButton1
	if button then
		for _, key in ipairs({ "TriggerSecureClick", "CalculateAction", "popup", "isExtra", "buttonType", "bar",
			"ActionBarActionButtonDerivedMixin_OnClick", "OnClick" }) do
			Look(button, key, "ActionButton." .. key)
		end
	end
	local settings = SettingsPanel and rawget(SettingsPanel, "settings")
	if type(settings) == "table" then
		Look(SettingsPanel, "GetSetting", "SettingsPanel.GetSetting")
		local count, bad = 0, 0
		for setting in pairs(settings) do
			count = count + 1
			local secure, by = Secure(settings, setting)
			local ok, variable = pcall(setting.GetVariable, setting)
			variable = ok and tostring(variable) or "?"
			if not secure then
				bad = bad + 1
				if bad <= 10 then found[#found + 1] = "SettingsPanel.settings[" .. variable .. "] (" .. tostring(by) .. ")" end
			end
			if variable == "lockActionBars" then
				for _, key in ipairs({ "pendingValue", "GetValueDerived", "TransformValue", "GetValue", "variable" }) do
					Look(setting, key, "lockActionBars setting." .. key)
				end
			end
		end
		found[#found + 1] = "(settings walked: " .. count .. ", tainted keys: " .. bad .. ")"
	end
	return found
end

-- The whole finding as one entry in the error window (Button Drawer's, or the game's own), which
-- he copies anyway: the saved file only comes when the game closes normally, and it did not
-- (his upload, 2026-10-21: the file stopped at 21:51, the refusals were at 22:08 and 22:22).
local function Report(entry)
	local lines = { "Deno Nameplate watch report (copy all of this)",
		"client " .. tostring(log.client) .. ", number keys checkable: " .. tostring(log.numberKeys) }
	local refusal = {}
	for _, key in ipairs({ "func", "at", "button", "action", "actionSecure", "actionBy",
		"rangeSecure", "rangeBy", "usableSecure", "usableBy", "lastOurs" }) do
		refusal[#refusal + 1] = key .. "=" .. tostring(entry[key])
	end
	lines[#lines + 1] = "refusal: " .. table.concat(refusal, ", ")
	local tainted = entry.tainted or {}
	lines[#lines + 1] = "tainted at the refusal: " .. (#tainted > 0 and table.concat(tainted, "; ") or "none")
	lines[#lines + 1] = "taintLog now: " .. tostring(log.taintLog)
	if #log.records == 0 then
		lines[#lines + 1] = "tainted slots: none of the watched slots turned tainted"
	end
	for i, record in ipairs(log.records) do
		lines[#lines + 1] = string.format("%d. %s by %s at %s s, during %s%s", i, record.slot, record.by,
			tostring(record.at), record.during, record.lastOurs and (", last of ours " .. record.lastOurs) or "")
		if record.stack then lines[#lines + 1] = "   " .. record.stack:gsub("\n", "\n   ") end
	end
	local handler = geterrorhandler()
	if handler then pcall(handler, table.concat(lines, "\n")) end
end

-- At the refusal: the button under the mouse and what its click read.
local function Refusal(event, addon, func)
	local entry = { event = event, addon = tostring(addon), func = tostring(func), at = Since(),
		lastOurs = lastLabel and (lastLabel .. " @" .. tostring(lastAt)) or "none yet" }
	local foci = GetMouseFoci and GetMouseFoci()
	local button = type(foci) == "table" and foci[1] or nil
	if button and type(button) == "table" then
		entry.button = ButtonName(button)
		local secure, by = Secure(button, "action")
		entry.actionSecure, entry.actionBy = secure and true or false, tostring(by)
		local action = button.action
		if type(action) == "number" then
			entry.action = action
			local range = ActionBarButtonRangeCheckFrame and ActionBarButtonRangeCheckFrame.actions
			local usable = ActionBarButtonUsableWatcherFrame and ActionBarButtonUsableWatcherFrame.actions
			if type(range) == "table" then
				secure, by = Secure(range, action)
				entry.rangeSecure, entry.rangeBy = secure and true or false, tostring(by)
			end
			if type(usable) == "table" then
				secure, by = Secure(usable, action)
				entry.usableSecure, entry.usableBy = secure and true or false, tostring(by)
			end
		end
	end
	entry.tainted = Wider()
	local refusals = log.refusals
	if #refusals < 10 then refusals[#refusals + 1] = entry end
	if #refusals == 1 then
		Say("refusal recorded on " .. tostring(entry.button) .. ": its action slot is "
			.. (entry.actionSecure and "clean" or ("tainted by " .. tostring(entry.actionBy))))
		Report(entry)
	end
	Save()
end

watch:RegisterEvent("ADDON_LOADED")
watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watch:RegisterEvent("ADDON_ACTION_BLOCKED")
watch:RegisterEvent("PLAYER_LOGOUT")
watch:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		-- whether this client lets issecurevariable look at number keys (the per-action tables)
		log.numberKeys = pcall(issecurevariable, {}, 1)
		-- only the file-level code of ours has run so far: is anything tainted already?
		Scan("our files loading")
		Save()
	elseif event == "PLAYER_LOGOUT" then
		Save()
	else
		Refusal(event, arg1, arg2)
	end
end)
