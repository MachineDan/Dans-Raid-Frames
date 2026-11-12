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
    [21564] = "Prayer of Fortitude", [1459] = "Arcane Intellect",
    [14752] = "Divine Spirit", [27681] = "Prayer of Spirit",
    [19740] = "Blessing of Might", [25782] = "Greater Blessing of Might",
    [19742] = "Blessing of Wisdom", [20217] = "Blessing of Kings" }
local ICONS = { [21562] = "fort", [14752] = "spirit", [19740] = "might", [19742] = "wisdom", [20217] = "kings" }
-- buffs[name] = who cast it ("player" = you)
local units = {
    player = { buffs = { ["Power Word: Fortitude"] = "other" } },
    party1 = { buffs = {} },                                     -- missing
    party2 = { buffs = { ["Prayer of Fortitude"] = "other" } },  -- group version counts
    party3 = { buffs = {}, dead = true },                        -- dead: no marker
    party4 = { buffs = {}, offline = true },                     -- offline: no marker
}
local class, known = "PRIEST", { [1243] = true }
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

UnitClass = function() return class, class end
C_Spell = { GetSpellName = function(id) return NAMES[id] end,
    GetSpellTexture = function(id) return ICONS[id] or (id == 1243 and "fort") or "other" end }
C_SpellBook = { IsSpellKnown = function(id) return known[id] or false end }
C_UnitAuras = { GetAuraDataBySpellName = function(unit, name, filter)
    if secretAuras then error("secret") end
    local source = units[unit].buffs[name]
    if not source or (filter:find("PLAYER") and source ~= "player") then
        return nil
    end
    return { name = name }
end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local powerTypes = {}
C_Secrets = { ShouldAurasBeSecret = function() return secretAuras end }
C_Timer = { NewTicker = function() return {} end }
InCombatLockdown = function() return inCombat end
IsInGroup = function() return true end
UnitExists = function(u) return units[u] ~= nil end
UnitIsConnected = function(u) return not units[u].offline end
UnitIsDeadOrGhost = function(u) return units[u].dead or false end
UnitPowerType = function(u) return powerTypes[u] or 0 end

-- Buffs.lua keeps its markers private: remember which marker frame gets created on which unit frame.
local shownFor = {}
local realCreate = CreateFrame
eventFrame = nil
CreateFrame = function(_, _, parent)
    local f = realCreate()
    if parent then
        shownFor[parent] = shownFor[parent] or {}
        table.insert(shownFor[parent], f)
    end
    return f
end
local ns = {
    db = { showMissingBuff = true },
    GetProfile = function() return { frameWidth = 144, frameHeight = 72, buffSize = 70 } end,
    GetAbsoluteIconSize = function() return 140 end,
}
assert(loadfile("Buffs.lua"))("DansRaidFrames", ns)
eventFrame.onEvent(eventFrame, "PLAYER_LOGIN")

-- Icons currently shown on party frame i, right to left.
local function Icons(i)
    local out = {}
    for _, m in ipairs(shownFor[_G["CompactPartyFrameMember" .. i]] or {}) do
        if m.shown then out[#out + 1] = m.icon.texture end
    end
    return table.concat(out, ",")
end
local function Shown(i)
    return Icons(i) ~= ""
end

Expect(not Shown(1), "player has Fortitude: no marker")
Expect(Shown(2), "party1 missing Fortitude: marker shown")
Expect(not Shown(3), "party2 has Prayer of Fortitude: no marker")
Expect(not Shown(4), "party3 dead: no marker")
Expect(not Shown(5), "party4 offline: no marker")
local m = shownFor[_G.CompactPartyFrameMember2][1]
Expect(m and m.size == math.floor(11 * 140 / 100 + 0.5) + 2, "marker matches the buff icon size plus border")
Expect(Icons(2) == "fort", "marker shows the Fortitude icon")

-- Buffing party1 removes its marker on the next aura event.
units.party1.buffs["Power Word: Fortitude"] = "player"
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

-- Priest with Divine Spirit talented: two icons for someone missing both, Spirit only on mana users.
known = { [1243] = true, [14752] = true }
C_SpellBook.IsSpellKnown = function(id) return known[id] or false end
units.party1.buffs = {}
units.party2.buffs = { ["Prayer of Fortitude"] = "other" }
powerTypes.party2 = 1 -- rage: a warrior doesn't need Spirit
eventFrame.onEvent(eventFrame, "SPELLS_CHANGED")
Expect(Icons(2) == "fort,spirit", "party1 missing both: two icons, got " .. Icons(2))
Expect(not Shown(3), "warrior with Fortitude: no Spirit marker")
units.party1.buffs = { ["Prayer of Spirit"] = "other" }
ns.UpdateBuffMarkers()
Expect(Icons(2) == "fort", "party1 got Spirit: only Fortitude left, got " .. Icons(2))

-- Paladin: only your own blessing counts, and the icon follows your last cast.
class, known = "PALADIN", { [19740] = true, [19742] = true }
for _, u in pairs(units) do u.buffs = {} end
units.party1.buffs = { ["Blessing of Kings"] = "other" }      -- another paladin's blessing
units.party2.buffs = { ["Greater Blessing of Might"] = "player" }
powerTypes.party2 = nil
eventFrame.onEvent(eventFrame, "SPELLS_CHANGED")
Expect(Icons(2) == "might", "other paladin's Kings doesn't count: marked with Might, got " .. Icons(2))
Expect(not Shown(3), "your Greater Blessing counts")
eventFrame.onEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 19742)
ns.UpdateBuffMarkers()
Expect(Icons(2) == "wisdom", "after casting Wisdom the marker suggests Wisdom, got " .. Icons(2))
eventFrame.onEvent(eventFrame, "SPELLS_CHANGED")
Expect(Icons(2) == "wisdom", "last cast survives a spell list update, got " .. Icons(2))

-- Classes without a long buff do nothing.
class, known = "WARRIOR", {}
eventFrame.onEvent(eventFrame, "SPELLS_CHANGED")
Expect(not Shown(2) and not Shown(3), "warrior: no markers")

print(("%d/%d buff marker checks pass"):format(checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
