-- Test build only, not for release. Runs only if a spell button is still refused: then it names
-- every registered game setting whose fields were written under an addon's taint, and puts that
-- in the error window (Button Drawer's), which he copies. 1.5.1 gives the Friendly and Enemy
-- settings plain default values (Options.lua, GroupRegister); if the refusal is gone, this never
-- runs. issecurevariable is asked about the string field "variable" of each setting: an earlier
-- check asked with the setting itself as the key, which the client does not accept, and so it
-- reported nothing either way.
local ADDON, ns = ...

local reported = false

local function TaintedSettings()
	local settings = SettingsPanel and rawget(SettingsPanel, "settings")
	if type(settings) ~= "table" then return "no SettingsPanel.settings" end
	local count, tainted = 0, {}
	for setting in pairs(settings) do
		count = count + 1
		local ok, secure, by = pcall(issecurevariable, setting, "variable")
		if ok and not secure then
			local variable = rawget(setting, "variable")
			tainted[#tainted + 1] = tostring(variable) .. " (" .. tostring(by) .. ")"
		end
	end
	local list = #tainted > 0 and table.concat(tainted, ", ", 1, math.min(#tainted, 12)) or "none"
	return string.format("%d settings, %d with tainted fields: %s", count, #tainted, list)
end

local watch = CreateFrame("Frame")
watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watch:SetScript("OnEvent", function(_, _, addon, func)
	if reported then return end
	local stack = debugstack() or ""
	if not stack:find("UseAction") then return end
	reported = true
	local text = "Deno Nameplate 1.5.1 check (copy all of this)\n" .. tostring(addon) .. " / " .. tostring(func)
		.. (stack:find("TryUseActionButton") and ", key" or ", mouse") .. "\n" .. TaintedSettings()
	local handler = geterrorhandler()
	if handler then pcall(handler, text) end
end)
