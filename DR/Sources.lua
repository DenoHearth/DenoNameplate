-- Taken from Forever Simple DR 0.8.0 by Tarolg (CurseForge project 1724602), MIT License,
-- see DR/LICENSE-ForeverDR. Changed here: the file's table is Deno Nameplate's own `DR` table
-- instead of the addon table, and the chat prefix. The rules and sources are his.
local _, addon = ...
addon.DR = addon.DR or {}
local ns = addon.DR
-- Runtime evidence adapters. Everything that touches WoW events or APIs and
-- feeds ns.tracker lives here; ns.tracker itself stays pure.
--
-- Secret-value policy: every payload field is checked with ns.Public before
-- logic uses it. Secret native DR fields are never compared, indexed, stored as
-- keys or converted. A secret isImmune may only be handed to a documented
-- AllowedWhenTainted display sink (SetVertexColorFromBoolean) by Display.lua.
local DR_EVENT = "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED"
local PENDING_DELAY = 0.5   -- time for aura/native evidence to confirm a cast
local CONFIRM_WINDOW = 1.5
local MAX_PENDING = 32
local AURA_THROTTLE = 0.2
local READABLE_TTL = 1
local MISSES = { MISS = true, RESIST = true, DODGE = true, PARRY = true, EVADE = true, DEFLECT = true, REFLECT = true }

ns.stats = { native = 0, nativePublic = 0, nativePartial = 0, nativeSecret = 0, nativeOpaque = 0,
    nativeUnknownCategory = 0, auraApplied = 0, auraEnded = 0, casts = 0, groupCasts = 0,
    confirmed = 0, assumed = 0, notLanded = 0, immuneHits = 0, signals = 0 }
ns.nativeStatus = "not started"
ns.nativeMode = "none seen"
ns.samples = {}
ns.secretImmune = {}

local nativeValid = false
local categoryByValue = {}
local nativeGuids = {}      -- GUIDs that produced a readable native update
local watchers, spareWatchers = {}, {}
local pending, sent, seenCasts = {}, {}, {}
local auraUnits, dirty, lastScan = {}, {}, {}
local scanScheduled = false
local readable, readableAt = nil, 0
local frame

local function Now() return GetTime() end

-- Unit identity ------------------------------------------------------------

-- Inside battlegrounds Forever hides enemy players' GUIDs from addons
-- (UnitGUID takes a UnitTokenPvPRestrictedForAddOns; secret on 1.60.1.70245)
-- while UnitName, under a separate name-identity rule, stays readable. A
-- player's full name is unique there, so it keys the same per-enemy state.
-- NPC names are not unique and never stand in for a GUID.
local function NameKey(unit)
    local name, realm = UnitName(unit)
    -- "Unknown" (the GlobalStrings UNKNOWNOBJECT) means not loaded yet; it is not a name.
    if not canaccessvalue(name) or not ns.Text(name) or name == _G.UNKNOWNOBJECT then return end
    if not ns.Public(realm) then return end
    if ns.Text(realm) then name = name .. "-" .. realm end
    return "Name:" .. name
end

-- Returns a key for a readable, attackable unit (players unless NPCs are
-- enabled): its GUID, or for a player whose GUID is secret, its full name.
-- Any secret or missing flag rejects the unit.
function ns.ReadEnemy(unit)
    if not ns.Text(unit) then return end
    local exists = UnitExists(unit)
    if not ns.Bool(exists) or not exists then return end
    local hostile = UnitCanAttack("player", unit)
    if not ns.Bool(hostile) or not hostile then return end
    local isPlayer = UnitIsPlayer(unit)
    if not ns.Bool(isPlayer) or (not isPlayer and not ns.db.npcs) then return end
    local guid = UnitGUID(unit)
    if ns.Text(guid) then return guid, isPlayer end
    if isPlayer and not ns.Public(guid) then return NameKey(unit), isPlayer end
end

local function UnitForGUID(guid)
    for unit in pairs(watchers) do
        if ns.ReadEnemy(unit) == guid then return unit end
    end
end

-- Pending casts --------------------------------------------------------------

local function RemovePending(p)
    for index, item in ipairs(pending) do
        if item == p then table.remove(pending, index); return end
    end
end

-- Marks casts that the given evidence explains as landed.
local function ConfirmPending(guid, category, now)
    for _, p in ipairs(pending) do
        if not p.done and p.category == category and (p.guid == guid or p.guid == nil)
            and now - p.at <= CONFIRM_WINDOW then
            p.done = true
            ns.stats.confirmed = ns.stats.confirmed + 1
            -- Attach the known spell to a native update that had no spell identity.
            ns.tracker:Apply(guid, category, now, { source = p.source, confirmed = true, spellID = p.id })
        end
    end
end

local function AuraReadable(id)
    local secret = C_Secrets.ShouldSpellAuraBeSecret(id)
    return ns.Bool(secret) and not secret
end

-- If a source that would certainly have reported the landing is available
-- for this target and stayed silent, the cast missed, was resisted or broke.
local function Observable(p)
    if not UnitForGUID(p.guid) then return false end
    if ns.GetSource("native") and nativeGuids[p.guid] then return true end
    return ns.GetSource("auras") and AuraReadable(p.id)
end

local function Resolve(p)
    -- Casts confirmed by other evidence are done but still queued; drop them
    -- here so the queue holds only live attempts.
    if p.done then RemovePending(p); return end
    p.done = true
    RemovePending(p)
    if p.failed then ns.stats.notLanded = ns.stats.notLanded + 1; return end
    if not p.guid or not ns.GetSource("assume") then return end
    local now = Now()
    local st = ns.tracker:State(p.guid, p.category, now, false)
    if st and st.lastApply and math.abs(st.lastApply - p.at) <= ns.MERGE_WINDOW then return end
    if Observable(p) then ns.stats.notLanded = ns.stats.notLanded + 1; return end
    if ns.tracker:Apply(p.guid, p.category, p.at, { source = p.source, confirmed = false, spellID = p.id }) == "applied" then
        ns.stats.assumed = ns.stats.assumed + 1
    end
    ns.RequestRefresh()
end

local function AddPending(p)
    if #pending >= MAX_PENDING then
        local oldest = table.remove(pending, 1)
        oldest.done = true
    end
    pending[#pending + 1] = p
    C_Timer.After(PENDING_DELAY, addon.Watched("DR pending timer", function() Resolve(p) end))
end

-- A native update whose fields are secret still proves that a DR state
-- changed on this unit now. It can confirm a cast we observed publicly; the
-- category comes from our own cast, never from the secret payload.
-- immuneBox is nil or { value = <secret boolean> }. The boxed value is never
-- tested here; Display passes it straight to SetVertexColorFromBoolean.
local function KeepSecretImmune(guid, category, now, immuneBox)
    local st = ns.tracker:State(guid, category, now, false)
    if not st or not immuneBox then return end
    -- Boxes are keyed by GUID; drop those whose window has already reset so
    -- the table stays bounded by the live states.
    for key, entry in pairs(ns.secretImmune) do
        if not entry.resetAt or now >= entry.resetAt then ns.secretImmune[key] = nil end
    end
    ns.secretImmune[guid .. ":" .. category] = { box = immuneBox, resetAt = st.resetAt }
end
local function Signal(guid, now, immuneBox)
    ns.stats.signals = ns.stats.signals + 1
    for _, p in ipairs(pending) do
        if not p.done and p.own and (p.guid == guid or p.guid == nil) and now - p.at <= CONFIRM_WINDOW then
            p.done = true
            ns.stats.confirmed = ns.stats.confirmed + 1
            ns.tracker:Apply(guid, p.category, p.at, { source = p.source .. "+native", confirmed = true, spellID = p.id })
            KeepSecretImmune(guid, p.category, now, immuneBox)
        end
    end
    ns.RequestRefresh()
end

-- Native Blizzard DR feed ----------------------------------------------------------

local function Sample(unit, category, start, duration, countdown, immune)
    table.insert(ns.samples, 1, string.format("%.1f %s %s start=%.2f dur=%.2f countdown=%s immune=%s",
        Now(), unit, category, start, duration, tostring(countdown), tostring(immune)))
    if #ns.samples > 20 then table.remove(ns.samples) end
end

local nativeSeen = {}
local function OnNative(unit, info)
    if not ns.GetSource("native") then return end
    local stats, now = ns.stats, Now()
    stats.native = stats.native + 1
    local guid = ns.ReadEnemy(unit)
    -- ReadEnemy only hands out readable keys; said again here in the client's own terms,
    -- because the key is used as a table key below.
    if not canaccessvalue(guid) then guid = nil end
    if not ns.Public(info) or type(info) ~= "table" then
        stats.nativeOpaque = stats.nativeOpaque + 1
        if ns.nativeMode ~= "public" then ns.nativeMode = "opaque (event only)" end
        if guid then Signal(guid, now) end
        return
    end
    local category, start, duration = info.category, info.startTime, info.duration
    local countdown, immune = info.showCountdown, info.isImmune
    local name = ns.Number(category) and categoryByValue[category]
    if ns.Number(category) and not name then
        stats.nativeUnknownCategory = stats.nativeUnknownCategory + 1
        return
    end
    -- Only an assignment: a secret immune flag is boxed, never tested.
    local immuneBox
    if not ns.Bool(immune) then immuneBox = { value = immune } end
    if not name then
        stats.nativeSecret = stats.nativeSecret + 1
        if ns.nativeMode ~= "public" then ns.nativeMode = "secret (display-only)" end
        if guid then Signal(guid, now, immuneBox) end
        return
    end
    if not guid then return end
    local timed = ns.Number(start, 0) and ns.Number(duration, 0)
    if not timed or not ns.Bool(countdown) or not ns.Bool(immune) then
        -- Category readable, timing not: count applications and ends by the
        -- public countdown flag when available, estimating times ourselves.
        stats.nativePartial = stats.nativePartial + 1
        if ns.nativeMode ~= "public" then ns.nativeMode = "partial (category only)" end
        nativeGuids[guid] = true
        if ns.Bool(countdown) and countdown then ns.tracker:End(guid, name, now)
        elseif ns.Bool(countdown) then ns.tracker:Apply(guid, name, now, { source = "native", confirmed = true }) end
        if ns.Bool(immune) and immune then ns.tracker:Native(guid, name, now, { start = now, duration = 0, countdown = false, immune = true })
        else KeepSecretImmune(guid, name, now, immuneBox) end
        ConfirmPending(guid, name, now)
        ns.RequestRefresh()
        return
    end
    stats.nativePublic = stats.nativePublic + 1
    ns.nativeMode = "public"
    nativeGuids[guid] = true
    Sample(unit, name, start, duration, countdown, immune)
    -- The same update arrives once per token (target and nameplate).
    local key = string.format("%s:%s:%.3f:%.3f:%s:%s", guid, name, start, duration, tostring(countdown), tostring(immune))
    if nativeSeen[key] and now - nativeSeen[key] < 1 then return end
    nativeSeen[key] = now
    for seenKey, at in pairs(nativeSeen) do if now - at > 5 then nativeSeen[seenKey] = nil end end
    ns.tracker:Native(guid, name, now, { start = start, duration = duration, countdown = countdown, immune = immune })
    ConfirmPending(guid, name, now)
    ns.RequestRefresh()
end

local function LoadNativeCategories()
    local enum = Enum and Enum.SpellDiminishCategory
    if type(enum) ~= "table" then return false end
    for _, name in ipairs(ns.CATEGORIES) do
        if type(enum[name]) == "number" then categoryByValue[enum[name]] = name end
    end
    local ruleset = Enum.SpellDiminishRuleset and Enum.SpellDiminishRuleset.PvP
    if ruleset == nil then return true end
    local list = C_SpellDiminish.GetAllSpellDiminishCategories(ruleset)
    if ns.Public(list) and type(list) == "table" then
        for _, entry in ipairs(list) do
            if ns.Public(entry) and type(entry) == "table" and ns.Number(entry.category) then
                local name = categoryByValue[entry.category]
                if name then ns.SetNativeCategoryIcon(name, entry.icon) end
            end
        end
    end
    return true
end

local function StartNative()
    if not C_SpellDiminish or type(C_SpellDiminish.IsSystemSupported) ~= "function" then
        ns.nativeStatus = "unavailable: C_SpellDiminish is missing from this client"; return
    end
    local supported = C_SpellDiminish.IsSystemSupported()
    if not ns.Bool(supported) or not supported then
        ns.nativeStatus = "unavailable: the client reports the DR system as unsupported"; return
    end
    if not C_EventUtils.IsEventValid(DR_EVENT) then
        ns.nativeStatus = "unavailable: " .. DR_EVENT .. " is not a valid event"; return
    end
    if not LoadNativeCategories() then
        ns.nativeStatus = "unavailable: Enum.SpellDiminishCategory is missing"; return
    end
    nativeValid = true
    ns.nativeStatus = "listening"
end

-- Blizzard only sends DR updates while its own enemy DR option is enabled.
ns.CVAR_ENABLED = "spellDiminishPVPEnemiesEnabled"
ns.CVAR_ONLY_MINE = "spellDiminishPVPOnlyTriggerableByMe"
function ns.GetBlizzardOption(name)
    local value = C_CVar.GetCVar(name)
    if not ns.Text(value) then return nil end
    return value ~= "0"
end
function ns.SetBlizzardOption(name, enabled)
    if InCombatLockdown() then ns.Print("Change Blizzard's DR options outside combat."); return false end
    if ns.GetBlizzardOption(name) == nil then ns.Print("This client has no " .. name .. " setting."); return false end
    local ok = C_CVar.SetCVar(name, enabled and "1" or "0")
    return ns.Bool(ok) and ok
end

-- While the Blizzard DR feed source is on, Forever DR needs Blizzard's enemy DR option on:
-- without it the feed that confirms your CC never arrives. Until 2026-10-19 it switched the
-- option on by itself in every session; that write is gone: a game setting written by addon
-- code made the game's own code run tainted (the stance bar was blocked, probe 2026-10-19),
-- and his rule is that addons never change game settings by themselves. Now it only says
-- where to turn it on, once per session, out of combat.
local keepQueued, keepTold = false, false
local function KeepBlizzardOn()
    keepQueued = false
    if not (ns.db and ns.db.enabled and ns.GetSource("native")) then return end
    -- On already, or a client without the option.
    if ns.GetBlizzardOption(ns.CVAR_ENABLED) ~= false then return end
    if InCombatLockdown() or keepTold then return end
    keepTold = true
    ns.Print("Blizzard's 'diminishing returns on PvP enemies' option is off, so Forever DR cannot confirm "
        .. "your CC. Turn it on in Options -> Gameplay -> Advanced, or turn off Blizzard DR feed under Tracking sources.")
end
function ns.KeepBlizzardOn()
    if keepQueued then return end
    keepQueued = true
    C_Timer.After(0.2, addon.Watched("DR keep timer", KeepBlizzardOn))
end

-- Aura evidence ---------------------------------------------------------------

-- Tracked IDs whose auras are currently readable. Spells Blizzard flags as
-- never secret stay readable in combat; others only while auras are public.
local function ReadableIDs(now)
    if readable and now - readableAt < READABLE_TTL then return readable end
    local list, set = {}, {}
    for id in pairs(ns.TrackedIDs()) do
        if AuraReadable(id) then list[#list + 1] = id; set[id] = true end
    end
    readable, readableAt = { list = list, set = set }, now
    return readable
end
function ns.InvalidateReadable() readable = nil end

local function ScanUnit(unit, now, ids)
    local guid, isPlayer = ns.ReadEnemy(unit)
    if not guid then auraUnits[unit] = nil; return end
    local state = auraUnits[unit]
    local baseline = false
    if not state or state.guid ~= guid then
        state, baseline = { guid = guid, instances = {} }, true
        auraUnits[unit] = state
    end
    local current = {}
    for _, id in ipairs(ids.list) do
        local aura = C_UnitAuras.GetUnitAuraBySpellID(unit, id)
        local category = ns.CategoryOf(id)
        -- Public check first: no comparison ever touches a secret value.
        if category and ns.Public(aura) and type(aura) == "table" then
            local instance = aura.auraInstanceID
            local key = guid .. (ns.Number(instance, 1) and (":i" .. instance) or (":s" .. id))
            if not current[key] then
                local duration, expires
                if ns.Number(aura.duration, 0.01, 3600) then duration = aura.duration end
                if duration and ns.Number(aura.expirationTime, 0) then expires = aura.expirationTime end
                local source
                if ns.Text(aura.sourceUnit) then source = aura.sourceUnit end
                current[key] = { id = id, category = category, duration = duration, expires = expires, source = source }
            end
        end
    end
    for key, old in pairs(state.instances) do
        -- Only a still-readable spell's disappearance is evidence of its end.
        if not current[key] and ids.set[old.id] then
            state.instances[key] = nil
            if ns.tracker:End(guid, old.category, now, key) then ns.stats.auraEnded = ns.stats.auraEnded + 1 end
        end
    end
    for key, a in pairs(current) do
        if not state.instances[key] then
            state.instances[key] = a
            local foreign = canaccessvalue(a.source) and ns.Text(a.source) and a.source ~= "player" and a.source ~= "pet"
            local existing = ns.tracker:State(guid, a.category, now, false)
            if baseline and existing and existing.active then
                -- Already tracked through another token of the same enemy.
                existing.lastKey = existing.lastKey or key
            elseif not (foreign and not ns.GetSource("group")) then
                local applied = now
                if canaccessvalue(a.expires) and canaccessvalue(a.duration) and a.expires and a.duration then
                    local start = a.expires - a.duration
                    if start <= now + 0.1 and start >= now - 120 then applied = math.min(start, now) end
                end
                local hint
                if a.duration and isPlayer then
                    local full = ns.Learned(a.id)
                    if full then
                        local ratio = a.duration / full
                        if ratio <= 0.35 then hint = 3 elseif ratio <= 0.62 then hint = 2 end
                    end
                    ns.Learn(a.id, a.duration)
                end
                ns.tracker:Apply(guid, a.category, applied, { source = "aura", confirmed = true,
                    spellID = a.id, expires = a.expires, stageHint = hint, key = key })
                ns.stats.auraApplied = ns.stats.auraApplied + 1
                ConfirmPending(guid, a.category, now)
            end
        end
    end
    ns.RequestRefresh()
end

local RunScans
RunScans = function()
    scanScheduled = false
    if not ns.db.enabled or not ns.GetSource("auras") then dirty = {}; return end
    local now = Now()
    local ids = ReadableIDs(now)
    local again = false
    for unit in pairs(dirty) do
        if lastScan[unit] and now - lastScan[unit] < AURA_THROTTLE then again = true
        else
            dirty[unit], lastScan[unit] = nil, now
            if watchers[unit] then ScanUnit(unit, now, ids) end
        end
    end
    if again and not scanScheduled then
        scanScheduled = true
        C_Timer.After(AURA_THROTTLE, addon.Watched("DR scan timer", RunScans))
    end
end
local function QueueScan(unit)
    if not ns.GetSource("auras") then return end
    dirty[unit] = true
    if scanScheduled then return end
    scanScheduled = true
    C_Timer.After(0.05, addon.Watched("DR scan timer", RunScans))
end

-- Combat feedback ------------------------------------------------------------

local function OnCombatFeedback(unit, action)
    if not ns.GetSource("feedback") or not ns.Text(action) then return end
    local immune = action == "IMMUNE"
    if not immune and not MISSES[action] then return end
    local guid = ns.ReadEnemy(unit)
    if not guid then return end
    local now = Now()
    for _, p in ipairs(pending) do
        if not p.done and p.own and p.guid == guid and now - p.at <= 1 then
            p.failed = true
            if immune and ns.tracker:ImmuneHit(guid, p.category, now) then
                ns.stats.immuneHits = ns.stats.immuneHits + 1
                ns.RequestRefresh()
            end
        end
    end
end

-- Per-unit watchers --------------------------------------------------------

local function OnUnitEvent(self, event, _, arg2)
    local unit = self.unit
    if not unit or not ns.db.enabled then return end
    if event == DR_EVENT then OnNative(unit, arg2)
    elseif event == "UNIT_AURA" then QueueScan(unit)
    elseif event == "UNIT_COMBAT" then OnCombatFeedback(unit, arg2)
    end
end

-- Unit filters live in the client: the unit comes from the registration,
-- never from a possibly secret payload.
local function Watch(unit)
    if watchers[unit] then return end
    local watcher = table.remove(spareWatchers) or CreateFrame("Frame")
    watcher.unit = unit
    watcher:SetScript("OnEvent", addon.Watched("DR unit", OnUnitEvent))
    if nativeValid then watcher:RegisterUnitEvent(DR_EVENT, unit) end
    watcher:RegisterUnitEvent("UNIT_AURA", unit)
    watcher:RegisterUnitEvent("UNIT_COMBAT", unit)
    watchers[unit] = watcher
    QueueScan(unit)
end
local function Unwatch(unit)
    local watcher = watchers[unit]
    if not watcher then return end
    watcher:UnregisterAllEvents()
    watcher.unit = nil
    watchers[unit], auraUnits[unit], dirty[unit], lastScan[unit] = nil, nil, nil, nil
    spareWatchers[#spareWatchers + 1] = watcher
end
function ns.WatchedUnits() return watchers end

-- Casts --------------------------------------------------------------------

local function OnSent(unit, castGUID)
    if unit ~= "player" or not ns.Text(castGUID) then return end
    local count = 0
    for key, entry in pairs(sent) do
        if Now() - entry.at > 10 then sent[key] = nil else count = count + 1 end
    end
    if count >= 16 then return end
    sent[castGUID] = { guid = ns.ReadEnemy("target"), at = Now() }
end

local function OnSucceeded(unit, castGUID, id)
    if not ns.Text(unit) or not ns.Number(id, 1) then return end
    local entry = ns.SpellEntry(id)
    if not entry then return end
    local own = unit == "player" or unit == "pet"
    if own and not ns.GetSource("casts") then return end
    if not own then
        if not ns.GetSource("group") or not (unit:match("^party%d") or unit:match("^raid%d")) then return end
        if entry.aoe then return end
    end
    local now = Now()
    -- party1 and raid3 can be the same caster; count each cast once.
    if ns.Text(castGUID) then
        if seenCasts[castGUID] then return end
        seenCasts[castGUID] = now
        for key, at in pairs(seenCasts) do if now - at > 5 then seenCasts[key] = nil end end
    end
    local guid
    if not entry.aoe then
        if unit == "player" then
            local record = ns.Text(castGUID) and sent[castGUID]
            guid = record and record.guid or ns.ReadEnemy("target")
        else
            guid = ns.ReadEnemy(unit .. "target")
        end
        if not guid then return end
    end
    if own then ns.stats.casts = ns.stats.casts + 1 else ns.stats.groupCasts = ns.stats.groupCasts + 1 end
    AddPending({ guid = guid, category = entry.category, id = id, at = now,
        source = own and (unit == "pet" and "pet" or "cast") or "group", own = own })
end

-- Lifecycle ------------------------------------------------------------------

local mineQueued = false
function ns.QueueMine()
    if mineQueued then return end
    mineQueued = true
    C_Timer.After(0.5, addon.Watched("DR mine timer", function()
        mineQueued = false
        ns.RefreshMine()
        ns.RequestRefresh()
        if ns.RefreshSettings then ns.RefreshSettings() end
    end))
end

local mineEvents = { SPELLS_CHANGED = true, BAG_UPDATE_DELAYED = true, PLAYER_TALENT_UPDATE = true,
    CHARACTER_POINTS_CHANGED = true }
local restrictionEvents = { ADDON_RESTRICTION_STATE_CHANGED = true, PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true }

local function Register(target, event, unit)
    if not C_EventUtils.IsEventValid(event) then return false end
    if unit then return target:RegisterUnitEvent(event, unit) end
    return target:RegisterEvent(event)
end

function ns.ClearTracking()
    ns.tracker:Clear()
    for _, p in ipairs(pending) do p.done = true end
    pending, sent, auraUnits, nativeGuids, ns.secretImmune = {}, {}, {}, {}, {}
    for unit in pairs(watchers) do QueueScan(unit) end
    ns.RequestRefresh()
end

function ns.RescanAll()
    readable = nil
    for unit in pairs(watchers) do QueueScan(unit) end
end

function ns.StartSources()
    StartNative()
    frame = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_SPELLCAST_SUCCEEDED" }) do
        Register(frame, event)
    end
    Register(frame, "UNIT_SPELLCAST_SENT", "player")
    Register(frame, "UNIT_PET", "player")
    for event in pairs(mineEvents) do Register(frame, event) end
    for event in pairs(restrictionEvents) do Register(frame, event) end
    Register(frame, "CVAR_UPDATE")
    frame:SetScript("OnEvent", addon.Watched("DR", function(_, event, arg1, arg2, arg3)
        if event == "CVAR_UPDATE" then
            if ns.Text(arg1) and arg1:lower() == ns.CVAR_ENABLED:lower() then ns.KeepBlizzardOn() end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if ns.db.enabled then OnSucceeded(arg1, arg2, arg3) end
        elseif event == "UNIT_SPELLCAST_SENT" then
            if ns.db.enabled then OnSent(arg1, arg3) end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if ns.Text(arg1) then Watch(arg1) end
            ns.RequestRefresh()
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if ns.Text(arg1) then Unwatch(arg1) end
            ns.RequestRefresh()
        elseif event == "PLAYER_TARGET_CHANGED" then
            auraUnits.target = nil
            QueueScan("target")
            ns.RequestRefresh()
        elseif event == "PLAYER_FOCUS_CHANGED" then
            auraUnits.focus = nil
            QueueScan("focus")
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Enemies from the previous world are gone; their feed history
            -- would otherwise accumulate per GUID for the whole session.
            nativeGuids = {}
            for unit in pairs(watchers) do
                if unit ~= "target" and unit ~= "focus" then Unwatch(unit) end
            end
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                if not plate:IsForbidden() and ns.Text(plate.unitToken) then Watch(plate.unitToken) end
            end
            ns.QueueMine()
            ns.RescanAll()
        elseif event == "UNIT_PET" or mineEvents[event] then
            ns.QueueMine()
        elseif restrictionEvents[event] then
            ns.RescanAll()
            if event == "PLAYER_REGEN_ENABLED" then ns.KeepBlizzardOn() end
        end
    end))
    Watch("target")
    Watch("focus")
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if not plate:IsForbidden() and ns.Text(plate.unitToken) then Watch(plate.unitToken) end
    end
    ns.RefreshMine()
    ns.KeepBlizzardOn()
end

-- Settings that change catalog membership or secrecy invalidate scan data.
ns.OnSettingChanged(function(key)
    if key == "custom" or key == "sources" or key == "npcs" then
        readable = nil
        ns.RescanAll()
    end
    if key == "sources" or key == "enabled" then ns.KeepBlizzardOn() end
    if key == "custom" or key == "items" then ns.QueueMine() end
end)

-- Test hooks: expose internal entry points without adding globals.
ns._test = { OnNative = OnNative, OnSucceeded = OnSucceeded, OnSent = OnSent, Resolve = Resolve,
    OnCombatFeedback = OnCombatFeedback, RunScans = RunScans, Watch = Watch, Unwatch = Unwatch,
    Pending = function() return pending end }
