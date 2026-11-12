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

-- Class buffs worth checking: the 1-hour ones in Forever (same spell IDs as Classic). Short or
-- range-based buffs (Battle Shout, totems, auras) would flicker on and off, so they're left out.
-- Any spell in a family counts as having the buff (all ranks and group versions).
--   needsMana: only checked on units that use mana.
--   mine: only your own casts count (Paladins split blessings between them, one per target each).
--   The icon is the family's first ID, or for "mine" families the one you last cast.
local CLASS_BUFFS = {
    PRIEST = {
        { ids = { 21562, 1243, 1244, 1245, 2791, 10937, 10938, 21564 } },        -- Power Word / Prayer of Fortitude
        { ids = { 14752, 14818, 14819, 27841, 27681 }, needsMana = true },         -- Divine Spirit / Prayer of Spirit
    },
    MAGE = {
        { ids = { 1459, 1460, 1461, 10156, 10157, 23028 }, needsMana = true },   -- Arcane Intellect / Brilliance
    },
    DRUID = {
        { ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 } },    -- Mark / Gift of the Wild
    },
    PALADIN = {
        { mine = true, ids = {
            19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916,       -- (Greater) Blessing of Might
            19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918,              -- (Greater) Blessing of Wisdom
            20217, 25898,                                                        -- (Greater) Blessing of Kings
            19977, 19978, 19979, 25890,                                          -- (Greater) Blessing of Light
        } },
    },
}

local UPDATE_INTERVAL = 1 -- seconds, out of combat only
local BORDER = 1          -- red border thickness, in the marker's units
local SPACING = 1         -- gap between icons when several buffs are missing

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

local lastMineCast -- spell ID of your last "mine" buff cast (survives re-resolving on SPELLS_CHANGED)
local markers = {} -- [unit frame] = { our marker frames, one per missing buff }
local myBuffs      -- the player's known class buffs: { names, icon, needsMana, mine, ids = set }

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
            local names, seen, idSet = {}, {}, {}
            for _, id in ipairs(family.ids) do
                idSet[id] = true
                local name = SpellName(id)
                if name and not seen[name] then
                    seen[name] = true
                    names[#names + 1] = name
                end
            end
            local iconID = family.ids[1]
            if family.mine and lastMineCast and idSet[lastMineCast] then
                iconID = lastMineCast
            elseif family.mine then
                -- Start with a blessing you actually know; casting another one switches the icon.
                for _, id in ipairs(family.ids) do
                    if KnowsSpell(id) then
                        iconID = id
                        break
                    end
                end
            end
            myBuffs[#myBuffs + 1] = { names = names, icon = SpellIcon(iconID), needsMana = family.needsMana,
                mine = family.mine, ids = idSet }
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
        local filter = buff.mine and "HELPFUL|PLAYER" or "HELPFUL"
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
        if not ok or IsSecret(aura) then
            return nil
        end
        if aura then
            return true
        end
    end
    return false
end

-- Returns the list of your class buffs this unit is missing (empty if none, or if we can't tell).
local missing = {}
local function MissingBuffs(unit)
    wipe(missing)
    if not unit or not UnitExists(unit) or not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then
        return missing
    end
    for _, buff in ipairs(myBuffs) do
        local relevant = true
        if buff.needsMana then
            local powerType = UnitPowerType(unit)
            relevant = (not IsSecret(powerType)) and powerType == 0 -- Enum.PowerType.Mana
        end
        if relevant and UnitHasBuff(unit, buff) == false then
            missing[#missing + 1] = buff
        end
    end
    return missing
end

local function GetMarker(unitFrame, index)
    local list = markers[unitFrame]
    if not list then
        list = {}
        markers[unitFrame] = list
    end
    local marker = list[index]
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
    list[index] = marker
    return marker
end

local function HideFrom(unitFrame, first)
    local list = markers[unitFrame]
    if list then
        for i = first, #list do
            list[i]:Hide()
        end
    end
end

local function HideAll()
    for unitFrame in pairs(markers) do
        HideFrom(unitFrame, 1)
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
            -- Top-right corner, extra icons going left.
            local list = MissingBuffs(unitFrame:GetAttribute("unit"))
            for i, buff in ipairs(list) do
                local marker = GetMarker(unitFrame, i)
                marker:SetSize(size, size)
                marker:ClearAllPoints()
                marker:SetPoint("TOPRIGHT", unitFrame, "TOPRIGHT", -3 - (i - 1) * (size + SPACING), -3)
                marker.icon:SetTexture(buff.icon)
                marker:Show()
            end
            HideFrom(unitFrame, #list + 1)
        elseif unitFrame then
            HideFrom(unitFrame, 1)
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
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")

-- Paladins: the marker shows the blessing you cast last, so it suggests what to rebuff with.
local function NoteCast(spellID)
    if not myBuffs or not spellID or IsSecret(spellID) then
        return
    end
    for _, buff in ipairs(myBuffs) do
        if buff.mine and buff.ids[spellID] then
            lastMineCast = spellID
            buff.icon = SpellIcon(spellID) or buff.icon
        end
    end
end

local ticker
eventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        NoteCast(spellID)
        return
    elseif event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" then
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
