-- Taken from Forever Simple DR 0.8.0 by Tarolg (CurseForge project 1724602), MIT License,
-- see DR/LICENSE-ForeverDR. Changed here: the file's table is Deno Nameplate's own `DR` table
-- instead of the addon table, and the chat prefix. The rules and sources are his.
local _, addon = ...
addon.DR = addon.DR or {}
local ns = addon.DR
-- Pure diminishing-returns state. Time is always passed in; no WoW API calls.
--
-- Model (modern DR): each application in a category shortens the next one
-- (100% -> 50% -> 25%) and the third leaves the target immune. The window
-- resets resetTime seconds after the last effect in the category ends.
-- Evidence of different quality feeds one state per (actor GUID, category):
--   native   Blizzard's own DR tracker (authoritative timing and immunity)
--   aura     a readable CC aura on the enemy (exact start/end)
--   cast     your or your pet's successful cast (landing unconfirmed)
--   group    a group member's cast on their target (landing unconfirmed)
ns.IMMUNE_STACKS = 3
ns.MERGE_WINDOW = 1.0      -- one application seen by several sources
local UNKNOWN_CC = 6       -- assumed full CC length when no end is observable
local MAX_ACTORS = 200
local IDLE_ACTOR = 120

local Tracker = {}
Tracker.__index = Tracker

function ns.NewTracker(resetTime, learned)
    return setmetatable({ actors = {}, size = 0, resetTime = resetTime,
        learned = learned or function() end }, Tracker)
end

local function StageFactor(count) return 0.5 ^ math.max(0, count - 1) end

function Tracker:EstimateEnd(st, now)
    local full = st.spellID and self.learned(st.spellID) or UNKNOWN_CC
    return now + full * StageFactor(st.count)
end

function Tracker:Evict()
    local oldestGUID, oldest
    for guid, actor in pairs(self.actors) do
        if not oldest or actor.seen < oldest then oldestGUID, oldest = guid, actor.seen end
    end
    if oldestGUID then self.actors[oldestGUID] = nil; self.size = self.size - 1 end
end

-- Returns the live state, discarding it first if its window has reset.
function Tracker:State(guid, category, now, create)
    if type(guid) ~= "string" then return end
    local actor = self.actors[guid]
    if not actor then
        if not create then return end
        if self.size >= MAX_ACTORS then self:Prune(now) end
        if self.size >= MAX_ACTORS then self:Evict() end
        actor = { cats = {}, seen = now }
        self.actors[guid], self.size = actor, self.size + 1
    end
    if create then actor.seen = math.max(actor.seen, now) end
    local st = actor.cats[category]
    if st and st.resetAt and now >= st.resetAt then st = nil; actor.cats[category] = nil end
    if not st and create then st = { count = 0 }; actor.cats[category] = st end
    return st, actor
end

local function Reschedule(self, st, now)
    if st.active and not st.endKnown then st.activeUntil = self:EstimateEnd(st, st.appliedAt or now) end
    if not st.nativeTimed then st.resetAt = (st.activeUntil or now) + self.resetTime() end
end

-- a = { source, confirmed, spellID, expires, stageHint, key }
-- Returns "applied", "merged", "immune" (unconfirmed attempt ignored) or nil.
function Tracker:Apply(guid, category, now, a)
    local st = self:State(guid, category, now, true)
    if not st then return end
    local recent = st.lastApply and math.abs(now - st.lastApply) <= ns.MERGE_WINDOW
    if recent then
        if a.confirmed and not st.confirmed then st.confirmed = true; st.source = a.source end
        if a.spellID and (a.confirmed or not st.spellID) then st.spellID = a.spellID end
        if a.expires then st.activeUntil, st.endKnown = a.expires, true end
        if a.stageHint and a.stageHint > st.count then st.count = a.stageHint end
        if a.key then st.lastKey = a.key end
        if st.count >= ns.IMMUNE_STACKS then st.immune = true end
        Reschedule(self, st, now)
        return "merged"
    end
    if st.immune and not a.confirmed then return "immune" end
    if st.immune then
        -- A confirmed landing contradicts the assumed immunity: restart the count.
        st.count, st.immune = 0, false
    end
    st.count = st.count + 1
    if a.stageHint and a.stageHint > st.count then st.count = a.stageHint end
    st.active, st.appliedAt, st.lastApply, st.lastKey = true, now, now, a.key
    st.spellID = a.spellID or st.spellID
    st.confirmed, st.source, st.nativeTimed = a.confirmed == true, a.source, false
    st.activeUntil, st.endKnown = a.expires, a.expires ~= nil
    if st.count >= ns.IMMUNE_STACKS then st.immune = true end
    Reschedule(self, st, now)
    return "applied"
end

-- The effect with key (aura instance) ended; nil key ends any active effect.
function Tracker:End(guid, category, now, key)
    local st = self:State(guid, category, now, false)
    if not st or not st.active then return false end
    if key and st.lastKey and key ~= st.lastKey then return false end
    st.active, st.activeUntil, st.endKnown = false, now, true
    Reschedule(self, st, now)
    return true
end

-- A readable Blizzard DR tracker update. n = { start, duration, countdown, immune }.
-- Blizzard reports a countdown once the category's reset timer is running and
-- a non-countdown state while an effect is still active. Either way, each new
-- non-countdown start time is one application.
function Tracker:Native(guid, category, now, n)
    local st = self:State(guid, category, now, true)
    if not st then return end
    if n.countdown and n.duration > 0 then
        if st.count == 0 then st.count, st.confirmed, st.source = 1, true, "native" end
        st.active, st.activeUntil, st.endKnown = false, n.start, true
        st.resetAt, st.nativeTimed, st.confirmed = n.start + n.duration, true, true
    elseif not st.nativeStart or math.abs(n.start - st.nativeStart) > 0.25 then
        local expires = n.duration > 0 and n.start + n.duration or nil
        self:Apply(guid, category, now, { source = "native", confirmed = true, expires = expires })
        st = self:State(guid, category, now, false)
        if not st then return end
    end
    st.nativeStart = n.start
    if n.immune then
        st.immune = true
        if st.count < ns.IMMUNE_STACKS then st.count = ns.IMMUNE_STACKS end
    end
    return st
end

-- An IMMUNE response to a CC attempt. Only accepted when the category was
-- already one application from immunity, so Divine Shield or Ice Block do not
-- masquerade as DR immunity.
function Tracker:ImmuneHit(guid, category, now)
    local st = self:State(guid, category, now, false)
    if not st or st.count < ns.IMMUNE_STACKS - 1 then return false end
    st.immune, st.count = true, math.max(st.count, ns.IMMUNE_STACKS)
    return true
end

-- Drop idle actors whose every category has reset.
function Tracker:Prune(now)
    for guid, actor in pairs(self.actors) do
        local live = false
        for category, st in pairs(actor.cats) do
            if st.resetAt and now >= st.resetAt then actor.cats[category] = nil else live = true end
        end
        if not live and now - actor.seen >= IDLE_ACTOR then
            self.actors[guid], self.size = nil, self.size - 1
        end
    end
end

function Tracker:Clear()
    self.actors, self.size = {}, 0
end

-- Read-only view for display. Entries are sorted by ns.CATEGORIES order.
function Tracker:Snapshot(guid, now)
    local actor = type(guid) == "string" and self.actors[guid]
    if not actor then return nil end
    local list
    for index, category in ipairs(ns.CATEGORIES) do
        local st = actor.cats[category]
        if st and st.count > 0 and st.resetAt and now < st.resetAt then
            list = list or {}
            local start = st.activeUntil or now
            list[#list + 1] = {
                category = category, order = index, count = st.count, immune = st.immune == true,
                active = st.active == true and (st.activeUntil == nil or now < st.activeUntil),
                resetAt = st.resetAt, remaining = st.resetAt - now,
                windowStart = start, windowLength = st.resetAt - start,
                estimated = not (st.confirmed and st.endKnown), confirmed = st.confirmed == true,
                spellID = st.spellID, source = st.source,
            }
        end
    end
    return list
end

function Tracker:HasLive(now)
    for _, actor in pairs(self.actors) do
        for _, st in pairs(actor.cats) do
            if st.resetAt and now < st.resetAt then return true end
        end
    end
    return false
end
