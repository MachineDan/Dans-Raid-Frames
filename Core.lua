-- Dan's Raid Frames: Quick-access "/drf" window for all the Raid & Party Frame
-- options buried inside Blizzard's Edit Mode, with live 60 FPS resizing and zero 12.0 taint.
--
-- Party Frames and Raid Frames each have their own profile (ns.db.party / ns.db.raid).
--
-- IMPORTANT (WoW 12.0 / Forever secret-value rules):
-- 1. NEVER call Blizzard Lua methods on PartyFrame, CompactPartyFrame, CompactUnitFrame,
--    or EditModeManagerFrame. Doing so writes addon-tainted values into PartyFrame.settingMap /
--    frame.optionTable / frame.unit, causing secret-value errors in combat.
-- 2. To persist settings: we only read/write a fresh table from C_EditMode.GetLayouts()
--    and pass it to C_EditMode.SaveLayouts(layoutInfo) (a pure C++ call).
-- 3. To update frames LIVE on screen at 60 FPS: we only call pure C++ widget methods
--    (GetAttribute, SetSize, ClearAllPoints, SetPoint, SetShown) on the frames.

local ADDON_NAME, ns = ...

local PROFILE_DEFAULTS = {
    useHorizontalGroups = false,
    displayBorder = false,
    sortBy = 0, -- 0 = Role, 1 = Group, 2 = Alphabetical
    alignment = 0, -- party only: 0 = Left/Top, 1 = Center, 2 = Right/Bottom within the 5 slots
    auraOrganizationType = 0, -- 0 = Legacy, 1 = Buffs Top, 2 = Buffs Bottom
    frameWidth = 72,
    frameHeight = 36,
    opacity = 100,
    bigDefensiveSize = 100,
    buffSize = 100,
    iconSize = 100,
}

local DEFAULTS = {
    selectedMode = "party", -- "party" or "raid"
    showRaidFramesInGroups = true,
}

local GLOBAL_KEYS = {
    selectedMode = true,
    showRaidFramesInGroups = true,
    partyPos = true,
    raidPos = true,
}

local LAYOUT_NAME = "DansRaidFrames"
local PREFIX = "|cff33ff99Dan's Raid Frames|r: "

-- Blizzard's Edit Mode slider limits for raid-style party/raid frames: { min, max, step }.
local RANGES = {
    width = { 72, 144, 2 },
    height = { 36, 72, 2 },
    opacity = { 50, 100, 1 },
    bigDefensiveSize = { 50, 200, 10 },
    buffSize = { 50, 200, 10 },
    iconSize = { 50, 200, 10 },
}

local ROLE_WEIGHT = {
    TANK = 1,
    HEALER = 2,
    DAMAGER = 3,
    NONE = 4,
}

-- Global names of Blizzard's compact unit frames, built once instead of
-- concatenating strings on every layout pass.
local PARTY_SLOTS = 5
local PARTY_MEMBER_NAMES = {}
for i = 1, PARTY_SLOTS do
    PARTY_MEMBER_NAMES[i] = "CompactPartyFrameMember" .. i
end

local RAID_GROUP_NAMES, RAID_GROUP_MEMBER_NAMES = {}, {}
for g = 1, 8 do
    RAID_GROUP_NAMES[g] = "CompactRaidGroup" .. g
    RAID_GROUP_MEMBER_NAMES[g] = {}
    for m = 1, 5 do
        RAID_GROUP_MEMBER_NAMES[g][m] = "CompactRaidGroup" .. g .. "Member" .. m
    end
end

local RAID_FRAME_NAMES = {}
for i = 1, 40 do
    RAID_FRAME_NAMES[i] = "CompactRaidFrame" .. i
end

local GetCVarValue = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVarValue = (C_CVar and C_CVar.SetCVar) or SetCVar

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

local function OnOff(value)
    return value and "|cff00ff00ON|r" or "|cffff0000OFF|r"
end

local function GetSettingDisplayInfo(settingID)
    if not settingID or not EditModeSettingDisplayInfoManager
        or not EditModeSettingDisplayInfoManager.systemSettingDisplayInfo
        or not Enum or not Enum.EditModeSystem then
        return nil
    end
    local list = EditModeSettingDisplayInfoManager.systemSettingDisplayInfo[Enum.EditModeSystem.UnitFrame]
    if not list then
        return nil
    end
    for _, setup in ipairs(list) do
        if setup.setting == settingID then
            return setup
        end
    end
    return nil
end

local function GetDynamicRange(settingID, fallback)
    local setup = GetSettingDisplayInfo(settingID)
    if setup and type(setup.minValue) == "number" and type(setup.maxValue) == "number" then
        return { setup.minValue, setup.maxValue, setup.stepSize or fallback[3] or 1 }
    end
    return { unpack(fallback) }
end

function ns.GetSizeRanges()
    local S = Enum and Enum.EditModeUnitFrameSetting or {}
    return {
        width = GetDynamicRange(S.FrameWidth, RANGES.width),
        height = GetDynamicRange(S.FrameHeight, RANGES.height),
        opacity = GetDynamicRange(S.Opacity, RANGES.opacity),
        bigDefensiveSize = GetDynamicRange(S.BigDefensiveIconSize, RANGES.bigDefensiveSize),
        buffSize = GetDynamicRange(S.BuffIconSize, RANGES.buffSize),
        iconSize = GetDynamicRange(S.DebuffIconSize, RANGES.iconSize),
    }
end

local function Snap(value, range)
    local min, max, step = range[1], range[2], range[3]
    value = math.max(min, math.min(max, value))
    return min + math.floor((value - min) / step + 0.5) * step
end

function ns.OpacityToAlpha(opacity)
    return math.max(0.5, math.min(1.0, opacity / 100))
end

---------------------------------------------------------------------------
-- Pure C++ Live Visual Updater (Party & Raid Frames, zero taint)
---------------------------------------------------------------------------
local function PassThroughUnitSubframes(unitFrame)
    if not unitFrame then
        return
    end
    local function DisableClicksOnList(list)
        if type(list) ~= "table" then
            return
        end
        for i = 1, #list do
            local sub = list[i]
            if sub and sub.SetMouseClickEnabled then
                sub:SetMouseClickEnabled(false)
            end
        end
    end
    DisableClicksOnList(unitFrame.buffFrames)
    DisableClicksOnList(unitFrame.debuffFrames)
    DisableClicksOnList(unitFrame.dispelDebuffFrames)
    if unitFrame.CenterDefensiveBuff and unitFrame.CenterDefensiveBuff.SetMouseClickEnabled then
        unitFrame.CenterDefensiveBuff:SetMouseClickEnabled(false)
    end
end

local function DisableMouseOnDecoration(frame)
    if not frame then
        return
    end
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
end

local function UpdateStandardPartyFramesShown(showStandard)
    if not PartyFrame then
        return
    end
    -- Keep PartyFrame shown because CompactPartyFrame is parented to it
    PartyFrame:SetShown(true)
    if PartyFrame.Background then
        PartyFrame.Background:SetShown(false)
    end
    for i = 1, 4 do
        local mf = PartyFrame["MemberFrame" .. i]
        if mf then
            if showStandard then
                local unit = "party" .. i
                mf:SetShown(UnitExists(unit) and true or false)
                if mf.EnableMouse then mf:EnableMouse(true) end
            else
                mf:SetShown(false)
                if mf.EnableMouse then mf:EnableMouse(false) end
            end
        end
    end
end

local RAID_GROUP_GAP = 6

-- Rounds a size in a frame's UI units to a whole number of screen pixels. At UI scales that don't
-- map units to whole pixels (e.g. 0.64 at 1440p: 1 unit = 1.2 px), a 72-unit frame is 86.4 px, and
-- identical frames get drawn 86 or 87 px wide depending on where their edges fall. With whole-pixel
-- sizes every edge shares the same sub-pixel offset, so all frames round the same way.
local function SnapToPixels(size, frame)
    local _, physH = GetPhysicalScreenSize()
    if not frame or not physH or physH <= 0 then
        return size
    end
    local pixelsPerUnit = frame:GetEffectiveScale() * physH / 768
    if pixelsPerUnit <= 0 then
        return size
    end
    return math.max(1, math.floor(size * pixelsPerUnit + 0.5)) / pixelsPerUnit
end

-- Frame-group sizes, shared by the layout code below and by the unlock-mode outline
-- (ns.GetFullGroupSize) so the outline always matches what a full group would look like.
local function GetRaidGroupTitleHeight(groupFrame, groupName)
    local title = groupFrame and (groupFrame.title or _G[groupName .. "Title"])
    return (title and title.GetHeight and title:GetHeight()) or 14
end

-- One raid group: 5 members plus its title and border padding.
local function GetRaidGroupSize(w, h, horiz, border, titleH)
    return (horiz and (w * 5) or w) + (border and 14 or 0),
        (horiz and h or (h * 5)) + titleH + (border and 12 or 2)
end

-- The party container always has room for PARTY_SLOTS members.
local function GetPartyContainerSize(w, h, horiz, border, titleH)
    local padW = border and 14 or 0
    local padH = border and 12 or 0
    if horiz then
        return w * PARTY_SLOTS + padW, h + titleH + 4 + padH
    end
    return w + padW, h * PARTY_SLOTS + titleH + 4 + padH
end

local function ApplyLiveToRaidFrames(w, h, horiz, border, alpha)
    local container = _G["CompactRaidFrameContainer"]
    w, h = SnapToPixels(w, container), SnapToPixels(h, container)
    local gap = SnapToPixels(RAID_GROUP_GAP, container)

    -- 1. Grouped raid frames (CompactRaidGroup1..8 and their Member1..5)
    local shownGroups = {}
    for g, groupName in ipairs(RAID_GROUP_NAMES) do
        local groupFrame = _G[groupName]
        if groupFrame then
            DisableMouseOnDecoration(groupFrame)
            local titleH = GetRaidGroupTitleHeight(groupFrame, groupName)
            local padX = border and 7 or 0
            local padY = border and 5 or 0

            local prevMember = nil
            for _, memberName in ipairs(RAID_GROUP_MEMBER_NAMES[g]) do
                local mf = _G[memberName]
                if mf then
                    mf:SetSize(w, h)
                    PassThroughUnitSubframes(mf)
                    mf:ClearAllPoints()
                    if not prevMember then
                        mf:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", padX, -(titleH + padY))
                    elseif horiz then
                        mf:SetPoint("LEFT", prevMember, "RIGHT", 0, 0)
                    else
                        mf:SetPoint("TOP", prevMember, "BOTTOM", 0, 0)
                    end
                    prevMember = mf
                end
            end

            groupFrame:SetSize(GetRaidGroupSize(w, h, horiz, border, titleH))

            local bf = groupFrame.borderFrame or _G[groupName .. "BorderFrame"]
            if bf then
                DisableMouseOnDecoration(bf)
                if border then
                    bf:ClearAllPoints()
                    bf:SetPoint("TOPLEFT", groupFrame, "TOPLEFT", 0, -titleH + 2)
                    bf:SetPoint("BOTTOMRIGHT", groupFrame, "BOTTOMRIGHT", 0, 0)
                    bf:SetShown(true)
                else
                    bf:SetShown(false)
                end
            end

            if groupFrame:IsShown() then
                shownGroups[#shownGroups + 1] = groupFrame
            end
        end
    end

    -- Anchor visible raid groups with RAID_GROUP_GAP padding so groups never overlap
    if container and #shownGroups > 0 then
        for idx, groupFrame in ipairs(shownGroups) do
            groupFrame:ClearAllPoints()
            if idx == 1 then
                groupFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            else
                local prevGroup = shownGroups[idx - 1]
                if horiz then
                    groupFrame:SetPoint("TOPLEFT", prevGroup, "BOTTOMLEFT", 0, -gap)
                else
                    groupFrame:SetPoint("TOPLEFT", prevGroup, "TOPRIGHT", gap, 0)
                end
            end
        end
    end

    -- 2. Single-container / combined raid frames (CompactRaidFrame1..40)
    local shownCombined = {}
    for _, name in ipairs(RAID_FRAME_NAMES) do
        local rf = _G[name]
        if rf then
            rf:SetSize(w, h)
            PassThroughUnitSubframes(rf)
            if #shownGroups == 0 and rf:IsShown() then
                shownCombined[#shownCombined + 1] = rf
            end
        end
    end

    if container and #shownGroups == 0 and #shownCombined > 0 then
        local startX = border and 7 or 0
        local startY = border and -5 or 0
        for idx, rf in ipairs(shownCombined) do
            rf:ClearAllPoints()
            if idx == 1 then
                rf:SetPoint("TOPLEFT", container, "TOPLEFT", startX, startY)
            elseif (idx - 1) % 5 == 0 then
                local firstInPrevGroup = shownCombined[idx - 5]
                if horiz then
                    rf:SetPoint("TOPLEFT", firstInPrevGroup, "BOTTOMLEFT", 0, -gap)
                else
                    rf:SetPoint("TOPLEFT", firstInPrevGroup, "TOPRIGHT", gap, 0)
                end
            else
                local prev = shownCombined[idx - 1]
                if horiz then
                    rf:SetPoint("LEFT", prev, "RIGHT", 0, 0)
                else
                    rf:SetPoint("TOP", prev, "BOTTOM", 0, 0)
                end
            end
        end
    end

    if container then
        DisableMouseOnDecoration(container)
        if container.SetAlpha then
            container:SetAlpha(alpha)
        end
        if container.borderFrame then
            DisableMouseOnDecoration(container.borderFrame)
            container.borderFrame:SetShown(border)
        end
        if ns.db and ns.db.raidPos and ns.db.raidPos.x and ns.db.raidPos.y and not ns.UsesEditModePositions() then
            container:ClearAllPoints()
            container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.raidPos.x, ns.db.raidPos.y)
        end
    end
end

function ns.GetActiveMode()
    if ns.db and ns.db.selectedMode == "raid" then
        return "raid"
    end
    return "party"
end

function ns.GetProfile(mode)
    if not ns.db then
        return PROFILE_DEFAULTS
    end
    if mode ~= "party" and mode ~= "raid" then
        mode = ns.GetActiveMode()
    end
    return ns.db[mode] or PROFILE_DEFAULTS
end

function ns.SetActiveMode(mode)
    if not ns.db then
        return
    end
    mode = (mode == "raid") and "raid" or "party"
    if ns.db.selectedMode == mode then
        return
    end
    ns.db.selectedMode = mode
    if ns.RefreshOptions then
        ns.RefreshOptions()
    end
end

-- Returns width, height, horizontal, border, alpha for a profile, snapped to the
-- same slider ranges the options panel uses.
local function ResolveLiveProfile(prof, ranges)
    local opacity = Snap(prof.opacity or ranges.opacity[2], ranges.opacity)
    return Snap(prof.frameWidth or ranges.width[1], ranges.width),
        Snap(prof.frameHeight or ranges.height[1], ranges.height),
        prof.useHorizontalGroups and true or false,
        prof.displayBorder and true or false,
        ns.OpacityToAlpha(opacity)
end

local function ApplyLiveToAllFrames()
    if InCombatLockdown() or not ns.db then
        return
    end

    local enabled = ns.db.showRaidFramesInGroups and true or false
    -- While the party frames are unlocked, they stay visible when solo so they can be positioned.
    local partyUnlocked = ns.GetUnlockedMode and ns.GetUnlockedMode() == "party"
    local inRaid = IsInRaid()
    local inParty = IsInGroup() and not inRaid
    local ranges = ns.GetSizeRanges()

    -- Apply Raid profile size, orientation, border & opacity to Raid Frames
    ApplyLiveToRaidFrames(ResolveLiveProfile(ns.GetProfile("raid"), ranges))

    -- 1. Visibility of CompactPartyFrame vs standard portrait PartyFrame
    UpdateStandardPartyFramesShown(inParty and not enabled)

    local partyProf = ns.GetProfile("party")
    local w, h, horiz, border, alpha = ResolveLiveProfile(partyProf, ranges)
    local sortBy = partyProf.sortBy or 0

    local cpf = _G["CompactPartyFrame"]
    if not cpf then
        return
    end
    w, h = SnapToPixels(w, cpf), SnapToPixels(h, cpf)

    DisableMouseOnDecoration(cpf)
    if ns.db.partyPos and ns.db.partyPos.x and ns.db.partyPos.y and not ns.UsesEditModePositions() then
        cpf:ClearAllPoints()
        cpf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.partyPos.x, ns.db.partyPos.y)
    end

    if cpf.SetAlpha then
        cpf:SetAlpha(alpha)
    end

    if inRaid then
        cpf:SetShown(false)
    elseif inParty then
        cpf:SetShown(enabled)
    else
        cpf:SetShown(partyUnlocked and enabled)
    end

    -- 2. Collect and sort CompactPartyFrameMember1..5 using C++ GetAttribute("unit")
    local entries = {}
    for i, memberName in ipairs(PARTY_MEMBER_NAMES) do
        local member = _G[memberName]
        if member then
            PassThroughUnitSubframes(member)
            local unit = member.GetAttribute and member:GetAttribute("unit") or nil
            local exists = (unit and UnitExists(unit)) and true or false
            local role = (exists and UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or "NONE"
            local name = (exists and UnitName(unit)) or ""
            entries[#entries + 1] = {
                frame = member,
                index = i,
                exists = exists,
                roleWeight = ROLE_WEIGHT[role] or 4,
                name = name,
            }
        end
    end

    table.sort(entries, function(a, b)
        if a.exists ~= b.exists then
            return a.exists
        end
        if sortBy == 0 then -- Role
            if a.roleWeight ~= b.roleWeight then
                return a.roleWeight < b.roleWeight
            end
        elseif sortBy == 2 then -- Alphabetical
            if a.name ~= b.name then
                return a.name < b.name
            end
        end
        return a.index < b.index
    end)

    -- 3. Resize and anchor the sorted member frames using pure C++ widget methods.
    local numShown = 0
    for pos, item in ipairs(entries) do
        if item.exists or item.frame:IsShown() then
            numShown = pos
        end
    end
    if numShown == 0 then
        numShown = 1
    end

    local titleH = (cpf.title and cpf.title:IsShown() and cpf.title:GetHeight()) or 0
    local firstX = border and 7 or 0
    local firstY = -(titleH + (border and 5 or 0))

    -- The container always has room for a full group of 5, so it keeps the same size (and stays
    -- where Edit Mode centered it) whoever is in the group; alignment places the members inside.
    local emptySlots = PARTY_SLOTS - numShown
    local alignment = partyProf.alignment or 0
    local shift = (alignment == 1 and emptySlots / 2) or (alignment == 2 and emptySlots) or 0
    if horiz then
        firstX = firstX + shift * w
    else
        firstY = firstY - shift * h
    end

    for pos, item in ipairs(entries) do
        local member = item.frame
        member:SetSize(w, h)
        member:ClearAllPoints()
        if pos == 1 then
            member:SetPoint("TOPLEFT", cpf, "TOPLEFT", firstX, firstY)
        else
            local prev = entries[pos - 1].frame
            if horiz then
                member:SetPoint("LEFT", prev, "RIGHT", 0, 0)
            else
                member:SetPoint("TOP", prev, "BOTTOM", 0, 0)
            end
        end
    end

    -- 4. Update CompactPartyFrame container size & border frame
    cpf:SetSize(GetPartyContainerSize(w, h, horiz, border, titleH))

    local borderFrame = cpf.borderFrame or _G["CompactPartyFrameBorderFrame"]
    if borderFrame then
        DisableMouseOnDecoration(borderFrame)
        if border and entries[1] and entries[numShown] then
            borderFrame:ClearAllPoints()
            borderFrame:SetPoint("TOPLEFT", entries[1].frame, "TOPLEFT", -7, 5)
            borderFrame:SetPoint("BOTTOMRIGHT", entries[numShown].frame, "BOTTOMRIGHT", 7, -7)
            borderFrame:SetShown(true)
        else
            borderFrame:SetShown(false)
        end
    end
end

local RAID_GROUPS = 8

-- Raid frames are either split into group frames or "combined" into one flow of CompactRaidFrameN.
-- Outside a raid nothing is shown, so assume groups (Blizzard's default).
local function RaidUsesCombinedFrames()
    for _, groupName in ipairs(RAID_GROUP_NAMES) do
        local groupFrame = _G[groupName]
        if groupFrame and groupFrame:IsShown() then
            return false
        end
    end
    for _, name in ipairs(RAID_FRAME_NAMES) do
        local rf = _G[name]
        if rf and rf:IsShown() then
            return true
        end
    end
    return false
end

-- Width and height of a full group (5 party members, or 8 raid groups of 5) laid out the way
-- ApplyLiveVisuals would, measured from the container's top-left corner, in the frames' own units.
-- Unlock mode outlines this so you see the whole footprint, not just who's in the group right now.
function ns.GetFullGroupSize(mode)
    local w, h, horiz, border = ResolveLiveProfile(ns.GetProfile(mode), ns.GetSizeRanges())
    -- Same whole-pixel rounding as the layout code, so the outline matches the drawn frames.
    local container = (mode == "raid") and _G["CompactRaidFrameContainer"] or _G["CompactPartyFrame"]
    w, h = SnapToPixels(w, container), SnapToPixels(h, container)
    local gaps = SnapToPixels(RAID_GROUP_GAP, container) * (RAID_GROUPS - 1)

    if mode ~= "raid" then
        local cpf = container
        local titleH = (cpf and cpf.title and cpf.title:IsShown() and cpf.title:GetHeight()) or 0
        return GetPartyContainerSize(w, h, horiz, border, titleH)
    end

    if RaidUsesCombinedFrames() then
        -- Rows (horizontal) or columns (vertical) of 5, RAID_GROUP_GAP between each block of 5.
        local startX, startY = border and 7 or 0, border and 5 or 0
        if horiz then
            return startX + w * 5, startY + h * RAID_GROUPS + gaps
        end
        return startX + w * RAID_GROUPS + gaps, startY + h * 5
    end

    local groupName = RAID_GROUP_NAMES[1]
    local groupW, groupH = GetRaidGroupSize(w, h, horiz, border, GetRaidGroupTitleHeight(_G[groupName], groupName))
    if horiz then
        return groupW, groupH * RAID_GROUPS + gaps
    end
    return groupW * RAID_GROUPS + gaps, groupH
end

function ns.ApplyLiveVisuals()
    ApplyLiveToAllFrames()
    -- Keep the unlock-mode boxes (Movers.lua) on top of the frames after every layout change.
    if ns.UpdateMovers then
        ns.UpdateMovers()
    end
end

---------------------------------------------------------------------------
-- Edit Mode C++ Persistence (Saves to BOTH Party and Raid systems)
---------------------------------------------------------------------------
local function IsEditModeAvailable()
    return C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
        and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts
        and Enum and Enum.EditModeUnitFrameSetting
        and Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames ~= nil
end

local function IsEditModeReady()
    return IsEditModeAvailable() and EditModeManagerFrame and EditModeManagerFrame.accountSettings ~= nil
end

-- In clients with Edit Mode, the Edit Mode layout owns where the frames sit. We never pin them to a
-- position of our own there, otherwise Blizzard's Edit Mode could no longer drag them.
-- Clients without Edit Mode keep the position in ns.db.partyPos / ns.db.raidPos instead.
function ns.UsesEditModePositions()
    return IsEditModeAvailable() and true or false
end

-- Positions from unlock mode waiting to be written into the Edit Mode layout by SaveToEditMode.
local pendingAnchors = {}

local function DeepCopy(src, seen)
    if type(src) ~= "table" then
        return src
    end
    seen = seen or {}
    if seen[src] then
        return seen[src]
    end
    local dst = {}
    seen[src] = dst
    for k, v in pairs(src) do
        if type(k) ~= "function" and type(k) ~= "userdata" and type(v) ~= "function" and type(v) ~= "userdata" then
            dst[DeepCopy(k, seen)] = DeepCopy(v, seen)
        end
    end
    return dst
end

-- Converts between human-readable display values and raw Edit Mode stored integers
-- without calling any Blizzard Lua methods on EditModeSettingDisplayInfoMixin.
local function IsConvertibleSetting(setup)
    if not setup or type(setup.minValue) ~= "number" or type(setup.maxValue) ~= "number" then
        return false
    end
    if EditModeSettingDisplayInfoMixin and setup.ConvertValue == EditModeSettingDisplayInfoMixin.ConvertValueDefault then
        return false
    end
    return true
end

local function ToRawValue(settingID, displayValue)
    if settingID == nil or displayValue == nil then
        return displayValue
    end
    local setup = GetSettingDisplayInfo(settingID)
    if setup and type(setup.minValue) == "number" and type(setup.maxValue) == "number" then
        local min, max = setup.minValue, setup.maxValue
        local clamped = math.max(min, math.min(max, displayValue))
        if IsConvertibleSetting(setup) then
            return math.floor(clamped - min + 0.5)
        end
        return math.floor(clamped + 0.5)
    end
    -- No display info available: width, height and opacity are stored as offsets from their minimum.
    local S = Enum.EditModeUnitFrameSetting
    local range = (settingID == S.FrameWidth and RANGES.width)
        or (settingID == S.FrameHeight and RANGES.height)
        or (settingID == S.Opacity and RANGES.opacity)
    if range then
        return math.max(range[1], math.min(range[2], displayValue)) - range[1]
    end
    return displayValue
end

-- Builds the same combined list EditModeManagerFrameMixin:UpdateLayoutInfo uses (and passes to
-- C_EditMode.SaveLayouts): Blizzard's presets first, then every saved layout. activeLayout is an
-- index into that list, so saved layouts are deep-copied but never dropped or reordered: any shift
-- would point activeLayout at another layout and switch the player off theirs (e.g. to "Modern").
local function LoadLayouts()
    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or type(layoutInfo.layouts) ~= "table" then
        return nil
    end
    -- Read-only on Blizzard's side: returns a fresh CopyTable of the preset layouts.
    local all = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    if type(all) ~= "table" then
        return nil
    end
    for i = 1, #layoutInfo.layouts do
        all[#all + 1] = DeepCopy(layoutInfo.layouts[i])
    end
    layoutInfo.layouts = all
    if not all[layoutInfo.activeLayout] then
        return nil
    end
    return layoutInfo
end

local function FindUnitFrameSystem(layout, systemIndex)
    local systemID = Enum.EditModeSystem.UnitFrame
    for _, system in ipairs(layout.systems or {}) do
        if system.system == systemID and system.systemIndex == systemIndex then
            return system
        end
    end
end

local function GetRawSystemSetting(system, settingID)
    if settingID == nil then
        return nil
    end
    for _, setting in ipairs(system.settings or {}) do
        if setting.setting == settingID then
            return setting.value
        end
    end
end

local function SetRawSystemSetting(system, settingID, rawValue)
    if settingID == nil or rawValue == nil then
        return
    end
    for _, setting in ipairs(system.settings) do
        if setting.setting == settingID then
            setting.value = rawValue
            return
        end
    end
    table.insert(system.settings, { setting = settingID, value = rawValue })
end

local function FindLayoutIndex(layoutInfo, name)
    for index, layout in ipairs(layoutInfo.layouts) do
        if layout.layoutName == name and layout.layoutType ~= Enum.EditModeLayoutType.Preset then
            return index
        end
    end
end

local function CreateOwnLayout(layoutInfo)
    local presetType = Enum.EditModeLayoutType.Preset
    local accountType = Enum.EditModeLayoutType.Account

    local numPresets, lastAccountIndex, numAccount = 0, nil, 0
    for index, layout in ipairs(layoutInfo.layouts) do
        if layout.layoutType == presetType then
            numPresets = numPresets + 1
        elseif layout.layoutType == accountType then
            lastAccountIndex = index
            numAccount = numAccount + 1
        end
    end

    local maxLayouts = (Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType) or 5
    if numAccount >= maxLayouts then
        return nil
    end

    -- Always clone from Modern Preset (index 1) when creating our custom layout from a preset
    local baseLayout = layoutInfo.layouts[1] or layoutInfo.layouts[layoutInfo.activeLayout]
    local newLayout = DeepCopy(baseLayout)
    newLayout.layoutType = accountType
    newLayout.layoutName = LAYOUT_NAME

    local newIndex = (lastAccountIndex or numPresets) + 1
    table.insert(layoutInfo.layouts, newIndex, newLayout)
    layoutInfo.activeLayout = newIndex
    return newIndex
end

-- Saves separate Party (ns.db.party) and Raid (ns.db.raid) settings into the active Edit Mode layout.
function ns.SaveToEditMode()
    if not ns.db then
        return false
    end
    if not IsEditModeReady() then
        if GetCVarValue and GetCVarValue("useCompactPartyFrames") ~= nil then
            SetCVarValue("useCompactPartyFrames", ns.db.showRaidFramesInGroups and "1" or "0")
            return true
        end
        return false
    end

    local layoutInfo = LoadLayouts()
    local active = layoutInfo and layoutInfo.layouts[layoutInfo.activeLayout]
    if not active then
        return false, "Could not find active Edit Mode layout."
    end

    local switchedLayout = false
    if active.layoutType == Enum.EditModeLayoutType.Preset then
        local existing = FindLayoutIndex(layoutInfo, LAYOUT_NAME)
        if existing then
            layoutInfo.activeLayout = existing
        elseif not CreateOwnLayout(layoutInfo) then
            return false, "Active layout is a preset and max custom layouts reached."
        end
        switchedLayout = true
        active = layoutInfo.layouts[layoutInfo.activeLayout]
    end

    local S = Enum.EditModeUnitFrameSetting

    local D = PROFILE_DEFAULTS
    local function ApplyProfileToSystem(sys, prof)
        SetRawSystemSetting(sys, S.DisplayBorder, prof.displayBorder and 1 or 0)
        SetRawSystemSetting(sys, S.SortPlayersBy, prof.sortBy or D.sortBy)
        SetRawSystemSetting(sys, S.AuraOrganizationType, prof.auraOrganizationType or D.auraOrganizationType)
        SetRawSystemSetting(sys, S.FrameWidth, ToRawValue(S.FrameWidth, prof.frameWidth or D.frameWidth))
        SetRawSystemSetting(sys, S.FrameHeight, ToRawValue(S.FrameHeight, prof.frameHeight or D.frameHeight))
        SetRawSystemSetting(sys, S.Opacity, ToRawValue(S.Opacity, prof.opacity or D.opacity))
        SetRawSystemSetting(sys, S.BigDefensiveIconSize, ToRawValue(S.BigDefensiveIconSize, prof.bigDefensiveSize or D.bigDefensiveSize))
        SetRawSystemSetting(sys, S.BuffIconSize, ToRawValue(S.BuffIconSize, prof.buffSize or D.buffSize))
        SetRawSystemSetting(sys, S.DebuffIconSize, ToRawValue(S.DebuffIconSize, prof.iconSize or D.iconSize))
    end

    local uiTop = UIParent and UIParent.GetTop and UIParent:GetTop() or nil
    local function ApplyCustomAnchor(sys, pos)
        if not sys or not pos or not pos.x or not pos.y or not uiTop then
            return
        end
        sys.isInDefaultPosition = false
        sys.anchorInfo = sys.anchorInfo or {}
        sys.anchorInfo.point = "TOPLEFT"
        sys.anchorInfo.relativeTo = "UIParent"
        sys.anchorInfo.relativePoint = "TOPLEFT"
        sys.anchorInfo.offsetX = pos.x
        sys.anchorInfo.offsetY = pos.y - uiTop
        -- A leftover second anchor point would pull the frame away from the one written above.
        sys.anchorInfo2 = nil
    end

    -- 1. Party Frames system (uses ns.db.party)
    local partyProf = ns.GetProfile("party")
    local partySys = FindUnitFrameSystem(active, Enum.EditModeUnitFrameSystemIndices.Party)
    if partySys then
        SetRawSystemSetting(partySys, S.UseRaidStylePartyFrames, ns.db.showRaidFramesInGroups and 1 or 0)
        SetRawSystemSetting(partySys, S.ShowPartyFrameBackground, 0) -- Always off for raid-style frames
        SetRawSystemSetting(partySys, S.UseHorizontalGroups, partyProf.useHorizontalGroups and 1 or 0)
        ApplyProfileToSystem(partySys, partyProf)
        ApplyCustomAnchor(partySys, pendingAnchors.partyPos or ns.db.partyPos)
    end

    -- 2. Raid Frames system (uses ns.db.raid)
    if Enum.EditModeUnitFrameSystemIndices.Raid then
        local raidProf = ns.GetProfile("raid")
        local raidSys = FindUnitFrameSystem(active, Enum.EditModeUnitFrameSystemIndices.Raid)
        if raidSys then
            ApplyProfileToSystem(raidSys, raidProf)
            ApplyCustomAnchor(raidSys, pendingAnchors.raidPos or ns.db.raidPos)
            if S.RaidGroupDisplayType then
                -- RaidGroupDisplayType: 0=SeparateVert, 1=SeparateHoriz, 2=CombineVert, 3=CombineHoriz
                local horiz = raidProf.useHorizontalGroups and 1 or 0
                local curType = GetRawSystemSetting(raidSys, S.RaidGroupDisplayType) or 0
                local isCombined = (curType == 2 or curType == 3)
                local newType = isCombined and (horiz == 1 and 3 or 2) or (horiz == 1 and 1 or 0)
                SetRawSystemSetting(raidSys, S.RaidGroupDisplayType, newType)
            end
        end
    end

    C_EditMode.SaveLayouts(layoutInfo)
    -- Same index the player had selected, unless we just moved off a preset onto our own layout.
    if C_EditMode.SetActiveLayout then
        C_EditMode.SetActiveLayout(layoutInfo.activeLayout)
    end
    if switchedLayout then
        ns.Print(("Switched from preset to custom Edit Mode layout '%s'."):format(active.layoutName))
    end
    return true
end

---------------------------------------------------------------------------
-- Public API for Options UI & Slash Commands
---------------------------------------------------------------------------
function ns.GetSize(mode)
    local prof = ns.GetProfile(mode)
    return prof and prof.frameWidth or RANGES.width[1],
           prof and prof.frameHeight or RANGES.height[1]
end

-- Called on every slider tick while dragging: resizes the real frames on screen at 60 FPS
-- and updates the 1:1 preview box without calling C_EditMode.SaveLayouts on every pixel.
function ns.StageSize(width, height)
    local prof = ns.GetProfile()
    local ranges = ns.GetSizeRanges()
    if width then
        prof.frameWidth = Snap(width, ranges.width)
    end
    if height then
        prof.frameHeight = Snap(height, ranges.height)
    end
    ns.ApplyLiveVisuals()
    if ns.UpdatePreviewBoxes then
        ns.UpdatePreviewBoxes()
    end
end

function ns.StageOption(key, value)
    if not ns.db then
        return
    end
    local ranges = ns.GetSizeRanges()
    if ranges[key] and type(value) == "number" then
        value = Snap(value, ranges[key])
    end
    if GLOBAL_KEYS[key] then
        ns.db[key] = value
    else
        local prof = ns.GetProfile()
        prof[key] = value
    end
    ns.ApplyLiveVisuals()
    if ns.UpdatePreviewBoxes then
        ns.UpdatePreviewBoxes()
    end
end

function ns.CommitChanges(quiet)
    ns.ApplyLiveVisuals()
    local ok, err = ns.SaveToEditMode()
    if not ok and err then
        ns.Print(err)
    elseif not quiet then
        local mode = ns.GetActiveMode()
        local prof = ns.GetProfile(mode)
        local label = (mode == "raid") and "Raid Frames" or "Party Frames"
        ns.Print(("Applied to %s (%d x %d, %s)"):format(
            label,
            prof.frameWidth or PROFILE_DEFAULTS.frameWidth,
            prof.frameHeight or PROFILE_DEFAULTS.frameHeight,
            prof.useHorizontalGroups and "Horizontal" or "Vertical"))
    end
    if ns.RefreshOptions then
        ns.RefreshOptions()
    end
    return ok
end

function ns.SetSize(width, height, quiet)
    ns.StageSize(width, height)
    ns.CommitChanges(quiet)
end

function ns.SetEnabled(value)
    ns.db.showRaidFramesInGroups = value and true or false
    ns.CommitChanges(true)
    ns.Print("Show raid frames in groups: " .. OnOff(ns.db.showRaidFramesInGroups))
end

function ns.SetOption(key, value)
    if GLOBAL_KEYS[key] then
        ns.db[key] = value
    else
        local prof = ns.GetProfile()
        prof[key] = value
    end
    ns.CommitChanges(true)
end

-- Stores where unlock mode dropped a frame group (x, y = TOPLEFT in UIParent BOTTOMLEFT space, in the
-- moved frame's own units). With Edit Mode it goes straight into the Edit Mode layout.
function ns.SaveFramePosition(mode, x, y)
    local posKey = (mode == "raid") and "raidPos" or "partyPos"
    if ns.UsesEditModePositions() then
        pendingAnchors[posKey] = { x = x, y = y }
        ns.CommitChanges(true)
        pendingAnchors[posKey] = nil
    elseif ns.db then
        ns.db[posKey] = { x = x, y = y }
    end
end

-- Forgets the dragged position for a mode so Blizzard's default anchor applies again.
-- Returns false with Edit Mode, where the position lives in the Edit Mode layout instead.
local function ClearSavedPosition(mode)
    if ns.UsesEditModePositions() then
        return false
    end
    if ns.db then
        ns.db[(mode == "raid") and "raidPos" or "partyPos"] = nil
    end
    local target = (mode == "raid") and _G["CompactRaidFrameContainer"] or _G["CompactPartyFrame"]
    if target then
        target:ClearAllPoints()
    end
    return true
end

function ns.ResetPosition(mode)
    if not ClearSavedPosition(mode or ns.GetActiveMode()) then
        ns.Print("Use Edit Mode's \"Reset Position\" to put these frames back in their default spot.")
        return
    end
    ns.ApplyLiveVisuals()
    ns.Print("Position reset to default.")
end

function ns.ResetSize()
    local prof = ns.GetProfile()
    for key, value in pairs(PROFILE_DEFAULTS) do
        prof[key] = value
    end
    ClearSavedPosition(ns.GetActiveMode())
    ns.CommitChanges(false)
end

-- Positions saved before Edit Mode owned them would keep snapping the frames back; drop them.
local function DropPositionsOwnedByEditMode()
    if ns.db and ns.UsesEditModePositions() then
        ns.db.partyPos, ns.db.raidPos = nil, nil
    end
end

---------------------------------------------------------------------------
-- Events & Safe Post-Hooks
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "EDIT_MODE_LAYOUTS_UPDATED",
    "PLAYER_REGEN_ENABLED",
    "GROUP_ROSTER_UPDATE",
    "UNIT_OTHER_PARTY_CHANGED",
    "PARTY_MEMBER_ENABLE",
    "ROLE_CHANGED_INFORM",
}) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end

local function ScheduleLiveVisuals()
    ns.ApplyLiveVisuals()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, ns.ApplyLiveVisuals)
    end
end

local hooksInstalled = false
local function InstallSafeHooks()
    if hooksInstalled then
        return
    end
    hooksInstalled = true
    if CompactPartyFrame then
        if CompactPartyFrame.UpdateVisibility then
            hooksecurefunc(CompactPartyFrame, "UpdateVisibility", ScheduleLiveVisuals)
        end
        if CompactPartyFrame.RefreshMembers then
            hooksecurefunc(CompactPartyFrame, "RefreshMembers", ScheduleLiveVisuals)
        end
        if CompactPartyFrame.UpdateLayout then
            hooksecurefunc(CompactPartyFrame, "UpdateLayout", ScheduleLiveVisuals)
        end
    end
    if PartyFrame and PartyFrame.UpdateVisibility then
        hooksecurefunc(PartyFrame, "UpdateVisibility", ScheduleLiveVisuals)
    end
    if CompactRaidFrameContainer then
        if CompactRaidFrameContainer.TryUpdate then
            hooksecurefunc(CompactRaidFrameContainer, "TryUpdate", ScheduleLiveVisuals)
        end
        if CompactRaidFrameContainer.LayoutFrames then
            hooksecurefunc(CompactRaidFrameContainer, "LayoutFrames", ScheduleLiveVisuals)
        end
    end
end

local function Initialize()
    DansRaidFramesDB = DansRaidFramesDB or {}
    for key, value in pairs(DEFAULTS) do
        if DansRaidFramesDB[key] == nil then
            DansRaidFramesDB[key] = value
        end
    end
    -- Raid-style frames must stay active by default
    if DansRaidFramesDB.showRaidFramesInGroups == false then
        DansRaidFramesDB.showRaidFramesInGroups = true
    end
    -- Replaced by unlock mode, which shows the frames while solo only while you position them.
    DansRaidFramesDB.showWhenSolo = nil
    for _, mode in ipairs({ "party", "raid" }) do
        if type(DansRaidFramesDB[mode]) ~= "table" then
            DansRaidFramesDB[mode] = {}
        end
        local prof = DansRaidFramesDB[mode]
        for key, defaultVal in pairs(PROFILE_DEFAULTS) do
            if prof[key] == nil then
                if DansRaidFramesDB[key] ~= nil then
                    prof[key] = DansRaidFramesDB[key]
                else
                    prof[key] = defaultVal
                end
            end
        end
    end
    ns.db = DansRaidFramesDB

    local ok, err = pcall(ns.CreateOptions)
    if not ok then
        ns.Print("Could not create the options window: " .. tostring(err))
    end
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then
            Initialize()
        end
        DropPositionsOwnedByEditMode()
        InstallSafeHooks()
        ScheduleLiveVisuals()
        ns.Print("loaded. Type |cffffff00/drf|r to configure your raid & party frames, |cffffff00/drf help|r for commands.")
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ScheduleLiveVisuals()
        if ns.RefreshOptions then
            ns.RefreshOptions()
        end
    elseif event == "PLAYER_REGEN_ENABLED"
        or event == "GROUP_ROSTER_UPDATE"
        or event == "UNIT_OTHER_PARTY_CHANGED"
        or event == "PARTY_MEMBER_ENABLE"
        or event == "ROLE_CHANGED_INFORM" then
        ScheduleLiveVisuals()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP_LINES = {
    "|cffffd100Moving frames:|r right-click a party or raid frame and choose |cffffd100Unlock Frames|r."
        .. " Drag the outline to move, drag its corner to resize, right-click it to lock.",
    "|cffffd100/drf|r - open the options",
    "|cffffd100/drf unlock|r [party|raid] - unlock frames to move them (same as the right-click menu)",
    "|cffffd100/drf lock|r - lock the frames again",
    "|cffffd100/drf on|r | |cffffd100off|r | |cffffd100toggle|r - show raid-style frames in groups",
    "|cffffd100/drf width|r <n> | |cffffd100height|r <n> | |cffffd100size|r <w> <h>"
        .. " - frame size, for the Party or Raid page you used last",
    "|cffffd100/drf reset|r - reset that page's settings to defaults",
    "|cffffd100/drf resetpos|r - put the frames back in their default spot",
    "|cffffd100/drf help|r - show this list",
}

local function PrintHelp()
    ns.Print("commands")
    for _, line in ipairs(HELP_LINES) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
    end
end

-- /drf debug (not listed in help): the party frames' real sizes and positions, in UI units and in
-- screen pixels, to tell pixel rounding apart from frames that really have different sizes.
local function PrintDebugInfo()
    local _, physH = GetPhysicalScreenSize()
    physH = (physH and physH > 0) and physH or 768
    ns.Print(("UI scale %.4f, screen height %d px"):format(UIParent:GetEffectiveScale(), physH))
    local prof = ns.GetProfile("party")
    DEFAULT_CHAT_FRAME:AddMessage(("  party profile: %s x %s"):format(tostring(prof.frameWidth), tostring(prof.frameHeight)))

    local shown = 0
    for i, name in ipairs(PARTY_MEMBER_NAMES) do
        local f = _G[name]
        if f and f:IsShown() then
            shown = shown + 1
            -- UI units -> screen pixels: units * effective scale * (screen height / 768)
            local toPixels = f:GetEffectiveScale() * physH / 768
            local w, h = f:GetWidth(), f:GetHeight()
            DEFAULT_CHAT_FRAME:AddMessage(("  member %d: %.2f x %.2f units = %.2f x %.2f px, left %.2f px, top %.2f px"):format(
                i, w, h, w * toPixels, h * toPixels, (f:GetLeft() or 0) * toPixels, (f:GetTop() or 0) * toPixels))
        end
    end
    if shown == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("  no party frames shown (join a group, or right-click > Unlock Frames while solo)")
    end
end

local function HandleSlash(msg)
    msg = strlower(strtrim(msg or ""))
    local cmd, arg1, arg2 = strsplit(" ", msg)
    if cmd == "on" then
        ns.SetEnabled(true)
    elseif cmd == "off" then
        ns.SetEnabled(false)
    elseif cmd == "toggle" then
        ns.SetEnabled(not ns.db.showRaidFramesInGroups)
    elseif cmd == "unlock" or cmd == "move" then
        ns.SetUnlocked(true, arg1)
    elseif cmd == "lock" then
        ns.SetUnlocked(false)
    elseif cmd == "resetpos" then
        ns.ResetPosition()
    elseif cmd == "width" and tonumber(arg1) then
        ns.SetSize(tonumber(arg1), nil, false)
    elseif cmd == "height" and tonumber(arg1) then
        ns.SetSize(nil, tonumber(arg1), false)
    elseif cmd == "size" and tonumber(arg1) and tonumber(arg2) then
        ns.SetSize(tonumber(arg1), tonumber(arg2), false)
    elseif cmd == "reset" then
        ns.ResetSize()
    elseif cmd == "" then
        ns.OpenOptions()
    elseif cmd == "help" or cmd == "?" then
        PrintHelp()
    elseif cmd == "debug" then
        PrintDebugInfo()
    else
        ns.Print("Unknown command. Type |cffffff00/drf help|r for the list.")
    end
end

SLASH_DANSRAIDFRAMES1 = "/drf"
SLASH_DANSRAIDFRAMES2 = "/dansraidframes"
SlashCmdList["DANSRAIDFRAMES"] = HandleSlash
