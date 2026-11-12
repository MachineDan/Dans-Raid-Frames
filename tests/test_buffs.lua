-- Offline check for Buffs.lua: who gets the red-bordered missing-buff marker.
-- Run from the repo root: luajit tests/test_buffs.lua
local failures, checks = 0, 0
local function Expect(cond, msg)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL " .. msg)
    end
end

-- Fake world -----------------------------------------------------------------------------------
local NAMES = { [21562] = "Power Word: Fortitude", [1243] = "Power Word: Fortitude",
    [21564] = "Prayer of Fortitude", [1459] = "Arcane Intellect" }
local units = {
    player = { buffs = { ["Power Word: Fortitude"] = true } },
    party1 = { buffs = {} },                                  -- missing
    party2 = { buffs = { ["Prayer of Fortitude"] = true } },  -- group version counts
    party3 = { buffs = {}, dead = true },                     -- dead: no marker
    party4 = { buffs = {}, offline = true },                  -- offline: no marker
}
local inCombat, secretAuras = false, false

local function NewRegion()
    local r = { shown = false }
    function r:SetAllPoints() end
    function r:SetPoint() end
    function r:ClearAllPoints() end
    function r:SetColorTexture() end
    function r:SetTexCoord() end
    function r:SetTexture(t) self.texture = t end
    return r
end
local function NewFrame()
    local f = NewRegion()
    function f:SetSize(w) self.size = w end
    function f:SetFrameLevel() end
    function f:GetFrameLevel() return 1 end
    function f:EnableMouse() end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:CreateTexture() return NewRegion() end
    function f:RegisterEvent() end
    function f:SetScript(_, fn) self.onEvent = fn end
    return f
end
local eventFrame
CreateFrame = function()
    local f = NewFrame()
    eventFrame = eventFrame or f
    return f
end
for i = 1, 5 do
    local f = NewFrame()
    f.shown = true
    local unit = (i == 1) and "player" or ("party" .. (i - 1))
    function f:GetAttribute(k) return k == "unit" and unit or nil end
    _G["CompactPartyFrameMember" .. i] = f
end

UnitClass = function() return "Priest", "PRIEST" end
C_Spell = { GetSpellName = function(id) return NAMES[id] end, GetSpellTexture = function(id) return 135987 end }
C_SpellBook = { IsSpellKnown = function(id) return id == 1243 end } -- only rank 1 learned
C_UnitAuras = { GetAuraDataBySpellName = function(unit, name)
    if secretAuras then error("secret") end
    return units[unit].buffs[name] and { name = name } or nil
end }
C_Secrets = { ShouldAurasBeSecret = function() return secretAuras end }
C_Timer = { NewTicker = function() return {} end }
InCombatLockdown = function() return inCombat end
IsInGroup = function() return true end
UnitExists = function(u) return units[u] ~= nil end
UnitIsConnected = function(u) return not units[u].offline end
UnitIsDeadOrGhost = function(u) return units[u].dead or false end
UnitPowerType = function() return 0 end

-- Buffs.lua keeps its markers private: remember which marker frame gets created on which unit frame.
local shownFor = {}
local realCreate = CreateFrame
eventFrame = nil
CreateFrame = function(_, _, parent)
    local f = realCreate()
    if parent then shownFor[parent] = f end
    return f
end
local ns = {
    db = { showMissingBuff = true },
    GetProfile = function() return { frameWidth = 144, frameHeight = 72, buffSize = 70 } end,
    GetAbsoluteIconSize = function() return 140 end,
}
assert(loadfile("Buffs.lua"))("DansRaidFrames", ns)
eventFrame.onEvent(eventFrame, "PLAYER_LOGIN")

local function Shown(i)
    local m = shownFor[_G["CompactPartyFrameMember" .. i]]
    return m and m.shown or false
end

Expect(not Shown(1), "player has Fortitude: no marker")
Expect(Shown(2), "party1 missing Fortitude: marker shown")
Expect(not Shown(3), "party2 has Prayer of Fortitude: no marker")
Expect(not Shown(4), "party3 dead: no marker")
Expect(not Shown(5), "party4 offline: no marker")
local m = shownFor[_G.CompactPartyFrameMember2]
Expect(m and m.size == math.floor(11 * 140 / 100 + 0.5) + 2, "marker matches the buff icon size plus border")
Expect(m and m.icon.texture == 135987, "marker shows the Fortitude icon")

-- Buffing party1 removes its marker on the next aura event.
units.party1.buffs["Power Word: Fortitude"] = true
eventFrame.onEvent(eventFrame, "UNIT_AURA", "party1")
Expect(not Shown(2), "party1 buffed: marker gone")

-- Combat: markers hide, nothing errors even though auras are secret.
units.party1.buffs = {}
ns.UpdateBuffMarkers()
Expect(Shown(2), "party1 debuffed again: marker back")
inCombat, secretAuras = true, true
eventFrame.onEvent(eventFrame, "PLAYER_REGEN_DISABLED")
Expect(not Shown(2), "entering combat hides markers")
local ok = pcall(ns.UpdateBuffMarkers)
Expect(ok and not Shown(2), "updates while auras are secret stay hidden, no error")
inCombat, secretAuras = false, false
eventFrame.onEvent(eventFrame, "PLAYER_REGEN_ENABLED")
Expect(Shown(2), "leaving combat brings the marker back")

-- Option off hides everything.
ns.db.showMissingBuff = false
ns.UpdateBuffMarkers()
Expect(not Shown(2), "option off: no markers")

-- A class without a buff (or a priest who hasn't learned it) never shows anything.
ns.db.showMissingBuff = true
C_SpellBook.IsSpellKnown = function() return false end
eventFrame.onEvent(eventFrame, "SPELLS_CHANGED")
Expect(not Shown(2), "spell not learned: no markers")

print(("%d/%d buff marker checks pass"):format(checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
