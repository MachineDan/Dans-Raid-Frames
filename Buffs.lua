-- Dan's Raid Frames: missing class buff marker.
--
-- Blizzard's raid frames never show long class buffs like Power Word: Fortitude: the game's spell
-- visibility data hides them (AuraUtil.ShouldDisplayBuff), inside protected code addons can't change.
-- Instead, this puts your class buff's icon with a red border on every group member who lacks it.
--
-- Rules (see Core.lua): we never call Blizzard Lua methods on the unit frames. We only read
-- GetAttribute("unit") and create our own small frame anchored on top of each unit frame.
-- Aura data is secret while C_Secrets.ShouldAurasBeSecret() is true (in combat), so the markers
-- hide then and come back once the auras can be read again.

local ADDON_NAME, ns = ...

-- Class buffs. Any spell in a family counts as having the buff (single-target ranks and group
-- versions). The first ID is the icon. needsMana: only checked on units that use mana.
local CLASS_BUFFS = {
    PRIEST = {
        { ids = { 21562, 1243, 1244, 1245, 2791, 10937, 10938, 21564 } }, -- Power Word / Prayer of Fortitude
    },
    MAGE = {
        { ids = { 1459, 1460, 1461, 10156, 10157, 23028 }, needsMana = true }, -- Arcane Intellect / Brilliance
    },
    DRUID = {
        { ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 } }, -- Mark / Gift of the Wild
    },
}

local UPDATE_INTERVAL = 1 -- seconds, out of combat only
local BORDER = 1          -- red border thickness, in the marker's units

local PARTY_FRAMES, RAID_FRAMES = {}, {}
for i = 1, 5 do
    PARTY_FRAMES[#PARTY_FRAMES + 1] = "CompactPartyFrameMember" .. i
end
for g = 1, 8 do
    for m = 1, 5 do
        RAID_FRAMES[#RAID_FRAMES + 1] = "CompactRaidGroup" .. g .. "Member" .. m
    end
end
for i = 1, 40 do
    RAID_FRAMES[#RAID_FRAMES + 1] = "CompactRaidFrame" .. i
end

local markers = {} -- [unit frame] = our marker frame
local myBuffs      -- resolved list for the player's class: { names = {..}, icon = fileID, needsMana = bool }

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id)
    end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end

local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(id)
    end
    return GetSpellTexture and GetSpellTexture(id) or nil
end

local function KnowsSpell(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and known then
            return true
        end
    end
    if IsPlayerSpell and IsPlayerSpell(id) then
        return true
    end
    return IsSpellKnown and IsSpellKnown(id) or false
end

-- Works out which class buffs this character can cast. Re-run when spells are learned.
local function ResolveMyBuffs()
    myBuffs = {}
    local _, class = UnitClass("player")
    for _, family in ipairs(CLASS_BUFFS[class] or {}) do
        local known = false
        for _, id in ipairs(family.ids) do
            if KnowsSpell(id) then
                known = true
                break
            end
        end
        if known then
            local names, seen = {}, {}
            for _, id in ipairs(family.ids) do
                local name = SpellName(id)
                if name and not seen[name] then
                    seen[name] = true
                    names[#names + 1] = name
                end
            end
            myBuffs[#myBuffs + 1] = { names = names, icon = SpellIcon(family.ids[1]), needsMana = family.needsMana }
        end
    end
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function AurasReadable()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or secret then
            return false
        end
    end
    return not InCombatLockdown()
end

-- true = has it, false = missing, nil = can't tell (secret, or API missing).
local function UnitHasBuff(unit, buff)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        return nil
    end
    for _, name in ipairs(buff.names) do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
        if not ok or IsSecret(aura) then
            return nil
        end
        if aura then
            return true
        end
    end
    return false
end

-- Returns the first buff from your class this unit is missing, or nil.
local function MissingBuff(unit)
    if not unit or not UnitExists(unit) or not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then
        return nil
    end
    for _, buff in ipairs(myBuffs) do
        local relevant = true
        if buff.needsMana then
            local powerType = UnitPowerType(unit)
            relevant = (not IsSecret(powerType)) and powerType == 0 -- Enum.PowerType.Mana
        end
        if relevant and UnitHasBuff(unit, buff) == false then
            return buff
        end
    end
    return nil
end

local function GetMarker(unitFrame)
    local marker = markers[unitFrame]
    if marker then
        return marker
    end
    marker = CreateFrame("Frame", nil, unitFrame)
    marker:SetFrameLevel(unitFrame:GetFrameLevel() + 10)
    marker:EnableMouse(false)
    marker.border = marker:CreateTexture(nil, "OVERLAY", nil, 6)
    marker.border:SetAllPoints()
    marker.border:SetColorTexture(0.9, 0.05, 0.05, 1)
    marker.icon = marker:CreateTexture(nil, "OVERLAY", nil, 7)
    marker.icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    marker.icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    marker.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    marker:Hide()
    markers[unitFrame] = marker
    return marker
end

local function HideAll()
    for _, marker in pairs(markers) do
        marker:Hide()
    end
end

-- Same size as Blizzard's buff icons on that frame, plus the border.
local function MarkerSize(mode)
    local prof = ns.GetProfile(mode)
    local absolute = ns.GetAbsoluteIconSize and ns.GetAbsoluteIconSize(prof, "buffSize") or 100
    return math.floor(11 * absolute / 100 + 0.5) + BORDER * 2
end

local function UpdateList(names, mode)
    local size = MarkerSize(mode)
    for _, name in ipairs(names) do
        local unitFrame = _G[name]
        if unitFrame and unitFrame:IsShown() then
            local buff = MissingBuff(unitFrame:GetAttribute("unit"))
            if buff then
                local marker = GetMarker(unitFrame)
                marker:SetSize(size, size)
                marker:ClearAllPoints()
                marker:SetPoint("TOPRIGHT", unitFrame, "TOPRIGHT", -3, -3)
                marker.icon:SetTexture(buff.icon)
                marker:Show()
            elseif markers[unitFrame] then
                markers[unitFrame]:Hide()
            end
        elseif unitFrame and markers[unitFrame] then
            markers[unitFrame]:Hide()
        end
    end
end

function ns.UpdateBuffMarkers()
    if not ns.db or not ns.db.showMissingBuff or not myBuffs or #myBuffs == 0 or not IsInGroup() then
        HideAll()
        return
    end
    if not AurasReadable() then
        HideAll()
        return
    end
    UpdateList(PARTY_FRAMES, "party")
    UpdateList(RAID_FRAMES, "raid")
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_LOGIN", "SPELLS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_AURA",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
}) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end

local ticker
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" then
        ResolveMyBuffs()
        if not ticker and C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(UPDATE_INTERVAL, ns.UpdateBuffMarkers)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideAll()
        return
    elseif event == "UNIT_AURA" and not (unit and (unit == "player" or unit:find("^party") or unit:find("^raid"))) then
        return
    end
    ns.UpdateBuffMarkers()
end)
