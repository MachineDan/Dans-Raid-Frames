-- SimpleRaidFrames: Quick-access "/srf" window for all the Raid & Party Frame
-- options buried inside Blizzard's Edit Mode, with live 60 FPS resizing and zero 12.0 taint.
--
-- Settings always apply to BOTH Party Frames and Raid Frames.
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
    showWhenSolo = false,
}

local GLOBAL_KEYS = {
    selectedMode = true,
    showRaidFramesInGroups = true,
    showWhenSolo = true,
    partyPos = true,
    raidPos = true,
}

local LAYOUT_NAME = "SimpleRaidFramesModern"
local OLD_LAYOUT_NAME = "SimpleRaidFrames"
local PREFIX = "|cff33ff99Simple Raid Frames|r: "

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

local GetCVarValue = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVarValue = (C_CVar and C_CVar.SetCVar) or SetCVar

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
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

---------------------------------------------------------------------------
-- Ctrl + Left-Click Hold Dragging (Pure C++ widget methods, zero taint)
---------------------------------------------------------------------------
local activeDragTarget = nil
local activeDragPosKey = nil
local dragStartCursorX, dragStartCursorY = 0, 0
local dragStartLeft, dragStartTop = 0, 0
local dragLastLeft, dragLastTop = nil, nil
local wasLeftButtonDown = false

local dragHintTooltip = CreateFrame("Frame", nil, UIParent)
dragHintTooltip:SetFrameStrata("TOOLTIP")
dragHintTooltip:SetSize(136, 22)
dragHintTooltip:EnableMouse(false)
if dragHintTooltip.SetMouseClickEnabled then
    dragHintTooltip:SetMouseClickEnabled(false)
end
if dragHintTooltip.SetMouseMotionEnabled then
    dragHintTooltip:SetMouseMotionEnabled(false)
end
dragHintTooltip:Hide()

do
    local bg = dragHintTooltip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)

    local bTop = dragHintTooltip:CreateTexture(nil, "BORDER")
    bTop:SetColorTexture(0.45, 0.45, 0.5, 0.85)
    bTop:SetPoint("TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", 0, 0)
    bTop:SetHeight(1)

    local bBot = dragHintTooltip:CreateTexture(nil, "BORDER")
    bBot:SetColorTexture(0.45, 0.45, 0.5, 0.85)
    bBot:SetPoint("BOTTOMLEFT", 0, 0)
    bBot:SetPoint("BOTTOMRIGHT", 0, 0)
    bBot:SetHeight(1)

    local bLeft = dragHintTooltip:CreateTexture(nil, "BORDER")
    bLeft:SetColorTexture(0.45, 0.45, 0.5, 0.85)
    bLeft:SetPoint("TOPLEFT", 0, 0)
    bLeft:SetPoint("BOTTOMLEFT", 0, 0)
    bLeft:SetWidth(1)

    local bRight = dragHintTooltip:CreateTexture(nil, "BORDER")
    bRight:SetColorTexture(0.45, 0.45, 0.5, 0.85)
    bRight:SetPoint("TOPRIGHT", 0, 0)
    bRight:SetPoint("BOTTOMRIGHT", 0, 0)
    bRight:SetWidth(1)
end

local dragHintText = dragHintTooltip:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
dragHintText:SetPoint("CENTER", 0, 0)
dragHintText:SetText("|cff88ddffCtrl + Drag to move|r")

local function GetHoveredUnitFrameDragTarget()
    local cpf = _G["CompactPartyFrame"]
    if cpf and cpf:IsShown() then
        for i = 1, 5 do
            local mf = _G["CompactPartyFrameMember" .. i]
            if mf and mf:IsShown() and mf:IsMouseOver() then
                return cpf, "partyPos"
            end
        end
    end

    local container = _G["CompactRaidFrameContainer"]
    if container and container:IsShown() then
        for g = 1, 8 do
            local gf = _G["CompactRaidGroup" .. g]
            if gf and gf:IsShown() then
                for m = 1, 5 do
                    local mf = _G["CompactRaidGroup" .. g .. "Member" .. m]
                    if mf and mf:IsShown() and mf:IsMouseOver() then
                        return container, "raidPos"
                    end
                end
            end
        end
        for i = 1, 40 do
            local rf = _G["CompactRaidFrame" .. i]
            if rf and rf:IsShown() and rf:IsMouseOver() then
                return container, "raidPos"
            end
        end
    end

    return nil, nil
end

local dragWatcher = CreateFrame("Frame")
dragWatcher:SetScript("OnUpdate", function()
    local inCombat = InCombatLockdown()
    local leftDown = IsMouseButtonDown("LeftButton")

    if activeDragTarget then
        if inCombat or not leftDown then
            local posKey = activeDragPosKey
            local finalX, finalY = dragLastLeft, dragLastTop
            activeDragTarget = nil
            activeDragPosKey = nil
            dragLastLeft, dragLastTop = nil, nil
            wasLeftButtonDown = leftDown
            if posKey and finalX and finalY and ns.db then
                ns.db[posKey] = { x = finalX, y = finalY }
            end
            return
        end

        local scale = activeDragTarget:GetEffectiveScale()
        if not scale or scale <= 0 then
            scale = 1
        end
        local curX, curY = GetCursorPosition()
        local dx = (curX - dragStartCursorX) / scale
        local dy = (curY - dragStartCursorY) / scale
        dragLastLeft = dragStartLeft + dx
        dragLastTop = dragStartTop + dy

        activeDragTarget:ClearAllPoints()
        activeDragTarget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", dragLastLeft, dragLastTop)
        dragHintTooltip:Hide()
        wasLeftButtonDown = leftDown
        return
    end

    if inCombat then
        dragHintTooltip:Hide()
        wasLeftButtonDown = leftDown
        return
    end

    local hoveredTarget, hoveredPosKey = GetHoveredUnitFrameDragTarget()
    if hoveredTarget then
        if leftDown and not wasLeftButtonDown and IsControlKeyDown() then
            local left = hoveredTarget.GetLeft and hoveredTarget:GetLeft()
            local top = hoveredTarget.GetTop and hoveredTarget:GetTop()
            if left and top then
                dragHintTooltip:Hide()
                activeDragTarget = hoveredTarget
                activeDragPosKey = hoveredPosKey
                dragStartCursorX, dragStartCursorY = GetCursorPosition()
                dragStartLeft, dragStartTop = left, top
                dragLastLeft, dragLastTop = left, top
                wasLeftButtonDown = leftDown
                return
            end
        end

        if GameTooltip and GameTooltip:IsShown() and GameTooltip.GetLeft and GameTooltip.GetBottom then
            local gLeft, gBottom = GameTooltip:GetLeft(), GameTooltip:GetBottom()
            if gLeft and gBottom then
                local w = (dragHintText:GetStringWidth() or 110) + 18
                dragHintTooltip:SetSize(math.max(120, w), 22)
                dragHintTooltip:ClearAllPoints()
                dragHintTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", gLeft, gBottom - 2)
                dragHintTooltip:Show()
            else
                dragHintTooltip:Hide()
            end
        else
            dragHintTooltip:Hide()
        end
    else
        dragHintTooltip:Hide()
    end

    wasLeftButtonDown = leftDown
end)

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

local function ApplyLiveToRaidFrames(w, h, horiz, border, alpha)
    local container = _G["CompactRaidFrameContainer"]

    -- 1. Grouped raid frames (CompactRaidGroup1..8 and their Member1..5)
    local shownGroups = {}
    for g = 1, 8 do
        local groupFrame = _G["CompactRaidGroup" .. g]
        if groupFrame then
            DisableMouseOnDecoration(groupFrame)
            local title = groupFrame.title or _G["CompactRaidGroup" .. g .. "Title"]
            local titleH = (title and title.GetHeight and title:GetHeight()) or 14
            local padX = border and 7 or 0
            local padY = border and 5 or 0

            local prevMember = nil
            local shownInGroup = 0
            for m = 1, 5 do
                local mf = _G["CompactRaidGroup" .. g .. "Member" .. m]
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
                    if mf:IsShown() then
                        shownInGroup = m
                    end
                end
            end
            if shownInGroup == 0 then
                shownInGroup = 5
            end

            local groupW = (horiz and (w * 5) or w) + (border and 14 or 0)
            local groupH = (horiz and h or (h * 5)) + titleH + (border and 12 or 2)
            groupFrame:SetSize(groupW, groupH)

            local bf = groupFrame.borderFrame or _G["CompactRaidGroup" .. g .. "BorderFrame"]
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
                    groupFrame:SetPoint("TOPLEFT", prevGroup, "BOTTOMLEFT", 0, -RAID_GROUP_GAP)
                else
                    groupFrame:SetPoint("TOPLEFT", prevGroup, "TOPRIGHT", RAID_GROUP_GAP, 0)
                end
            end
        end
    end

    -- 2. Single-container / combined raid frames (CompactRaidFrame1..40)
    local shownCombined = {}
    for i = 1, 40 do
        local rf = _G["CompactRaidFrame" .. i]
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
                    rf:SetPoint("TOPLEFT", firstInPrevGroup, "BOTTOMLEFT", 0, -RAID_GROUP_GAP)
                else
                    rf:SetPoint("TOPLEFT", firstInPrevGroup, "TOPRIGHT", RAID_GROUP_GAP, 0)
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
        if activeDragTarget ~= container and ns.db and ns.db.raidPos and ns.db.raidPos.x and ns.db.raidPos.y then
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
    local key = (mode == "raid") and "raid" or (mode == "party" and "party" or ns.GetActiveMode())
    return ns.db[key] or PROFILE_DEFAULTS
end

function ns.SetActiveMode(mode)
    if not ns.db then
        return
    end
    ns.db.selectedMode = (mode == "raid") and "raid" or "party"
    if ns.RefreshOptions then
        ns.RefreshOptions()
    end
end

function ns.ApplyLiveVisuals()
    if InCombatLockdown() or not ns.db then
        return
    end

    local enabled = ns.db.showRaidFramesInGroups and true or false
    local solo = ns.db.showWhenSolo and true or false
    local inParty = IsInGroup() and not IsInRaid()
    local inRaid = IsInRaid()

    local partyProf = ns.GetProfile("party")
    local raidProf = ns.GetProfile("raid")

    local rw = Snap(raidProf.frameWidth or RANGES.width[1], RANGES.width)
    local rh = Snap(raidProf.frameHeight or RANGES.height[1], RANGES.height)
    local rHoriz = raidProf.useHorizontalGroups and true or false
    local rBorder = raidProf.displayBorder and true or false
    local rOpacity = Snap(raidProf.opacity or RANGES.opacity[2], RANGES.opacity)
    local rAlpha = math.max(0.5, math.min(1.0, rOpacity / 100))

    -- Apply Raid profile size, orientation, border & opacity to Raid Frames
    ApplyLiveToRaidFrames(rw, rh, rHoriz, rBorder, rAlpha)

    -- 1. Visibility of CompactPartyFrame vs standard portrait PartyFrame
    if inRaid then
        UpdateStandardPartyFramesShown(false)
    elseif inParty then
        UpdateStandardPartyFramesShown(not enabled)
    else
        UpdateStandardPartyFramesShown(false)
    end

    local w = Snap(partyProf.frameWidth or RANGES.width[1], RANGES.width)
    local h = Snap(partyProf.frameHeight or RANGES.height[1], RANGES.height)
    local horiz = partyProf.useHorizontalGroups and true or false
    local border = partyProf.displayBorder and true or false
    local sortBy = partyProf.sortBy or 0
    local opacity = Snap(partyProf.opacity or RANGES.opacity[2], RANGES.opacity)
    local alpha = math.max(0.5, math.min(1.0, opacity / 100))

    local cpf = _G["CompactPartyFrame"]
    if not cpf then
        return
    end

    DisableMouseOnDecoration(cpf)
    if activeDragTarget ~= cpf and ns.db.partyPos and ns.db.partyPos.x and ns.db.partyPos.y then
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
        cpf:SetShown(solo and enabled)
    end

    -- 2. Collect and sort CompactPartyFrameMember1..5 using C++ GetAttribute("unit")
    local entries = {}
    for i = 1, 5 do
        local member = _G["CompactPartyFrameMember" .. i]
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
    local padW = border and 14 or 0
    local padH = border and 12 or 0
    if horiz then
        cpf:SetSize(w * numShown + padW, h + titleH + 4 + padH)
    else
        cpf:SetSize(w + padW, h * numShown + titleH + 4 + padH)
    end

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

---------------------------------------------------------------------------
-- Edit Mode C++ Persistence (Saves to BOTH Party and Raid systems)
---------------------------------------------------------------------------
local function IsEditModeAvailable()
    return C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
        and EditModePresetLayoutManager
        and Enum and Enum.EditModeUnitFrameSetting
        and Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames ~= nil
end

local function IsEditModeReady()
    return IsEditModeAvailable() and EditModeManagerFrame and EditModeManagerFrame.accountSettings ~= nil
end

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
    local S = Enum.EditModeUnitFrameSetting
    if settingID == S.FrameWidth then
        local min, max = RANGES.width[1], RANGES.width[2]
        displayValue = math.max(min, math.min(max, displayValue))
        return displayValue - min
    elseif settingID == S.FrameHeight then
        local min, max = RANGES.height[1], RANGES.height[2]
        displayValue = math.max(min, math.min(max, displayValue))
        return displayValue - min
    elseif settingID == S.Opacity then
        local min, max = RANGES.opacity[1], RANGES.opacity[2]
        displayValue = math.max(min, math.min(max, displayValue))
        return displayValue - min
    end
    return displayValue
end

local function ToDisplayValue(settingID, rawValue)
    if settingID == nil or rawValue == nil then
        return rawValue
    end
    local setup = GetSettingDisplayInfo(settingID)
    if setup and type(setup.minValue) == "number" and type(setup.maxValue) == "number" then
        local min, max = setup.minValue, setup.maxValue
        local display = IsConvertibleSetting(setup) and (rawValue + min) or rawValue
        return math.max(min, math.min(max, math.floor(display + 0.5)))
    end
    local S = Enum.EditModeUnitFrameSetting
    if settingID == S.FrameWidth then
        local min, max = RANGES.width[1], RANGES.width[2]
        return math.max(min, math.min(max, rawValue + min))
    elseif settingID == S.FrameHeight then
        local min, max = RANGES.height[1], RANGES.height[2]
        return math.max(min, math.min(max, rawValue + min))
    elseif settingID == S.Opacity then
        local min, max = RANGES.opacity[1], RANGES.opacity[2]
        return math.max(min, math.min(max, rawValue + min))
    end
    return rawValue
end

local function WrapPresetEntry(entry, defaultName)
    if type(entry) ~= "table" then
        return nil
    end
    local presetType = (Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Preset) or 0
    if type(entry.systems) == "table" then
        return {
            layoutName = (type(entry.layoutName) == "string" and entry.layoutName ~= "" and entry.layoutName) or defaultName,
            layoutType = presetType,
            systems = DeepCopy(entry.systems),
        }
    end
    return {
        layoutName = defaultName,
        layoutType = presetType,
        systems = DeepCopy(entry),
    }
end

local function LoadLayouts()
    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or not layoutInfo.layouts then
        return nil
    end
    local all = {}
    local presetType = (Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Preset) or 0

    local presets = EditModePresetLayoutManager and EditModePresetLayoutManager.presetLayoutMap
    if type(presets) == "table" then
        if presets[0] ~= nil then
            local p0 = WrapPresetEntry(presets[0], HUD_EDIT_MODE_MODERN_PRESET or "Modern")
            if p0 then all[#all + 1] = p0 end
        end
        for i = 1, #presets do
            local p = WrapPresetEntry(presets[i], (i == 1 and (HUD_EDIT_MODE_CLASSIC_PRESET or "Classic")) or ("Preset " .. i))
            if p then all[#all + 1] = p end
        end
    end

    for i = 1, #layoutInfo.layouts do
        local layout = layoutInfo.layouts[i]
        if type(layout) == "table" and type(layout.systems) == "table"
            and type(layout.layoutName) == "string" and layout.layoutName ~= ""
            and layout.layoutName ~= OLD_LAYOUT_NAME
            and layout.layoutType ~= presetType then
            all[#all + 1] = {
                layoutName = layout.layoutName,
                layoutType = layout.layoutType,
                systems = DeepCopy(layout.systems),
            }
        end
    end

    layoutInfo.layouts = all
    if not all[layoutInfo.activeLayout] and #all > 0 then
        -- Default to Modern Preset (index 1), never Classic Preset (index 2)
        layoutInfo.activeLayout = 1
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

-- Reads current Party and Raid Frame settings from the active Edit Mode layout into ns.db.party and ns.db.raid.
function ns.ReadFromEditMode()
    if not IsEditModeReady() or not ns.db then
        return false
    end
    local layoutInfo = LoadLayouts()
    local active = layoutInfo and layoutInfo.layouts[layoutInfo.activeLayout]
    if not active then
        return false
    end

    local S = Enum.EditModeUnitFrameSetting

    local function ReadProfileFromSystem(sys, prof)
        if not sys or not prof then
            return
        end
        local border = GetRawSystemSetting(sys, S.DisplayBorder)
        local sortBy = GetRawSystemSetting(sys, S.SortPlayersBy)
        local auraOrg = GetRawSystemSetting(sys, S.AuraOrganizationType)
        local rawW = GetRawSystemSetting(sys, S.FrameWidth)
        local rawH = GetRawSystemSetting(sys, S.FrameHeight)
        local rawOpacity = GetRawSystemSetting(sys, S.Opacity)
        local rawBigDef = GetRawSystemSetting(sys, S.BigDefensiveIconSize)
        local rawBuff = GetRawSystemSetting(sys, S.BuffIconSize)
        local rawIcon = GetRawSystemSetting(sys, S.DebuffIconSize)

        if border ~= nil then prof.displayBorder = (border == 1) end
        if sortBy ~= nil then prof.sortBy = sortBy end
        if auraOrg ~= nil then prof.auraOrganizationType = auraOrg end
        if rawW ~= nil then prof.frameWidth = ToDisplayValue(S.FrameWidth, rawW) end
        if rawH ~= nil then prof.frameHeight = ToDisplayValue(S.FrameHeight, rawH) end
        if rawOpacity ~= nil then prof.opacity = ToDisplayValue(S.Opacity, rawOpacity) end
        if rawBigDef ~= nil then prof.bigDefensiveSize = ToDisplayValue(S.BigDefensiveIconSize, rawBigDef) end
        if rawBuff ~= nil then prof.buffSize = ToDisplayValue(S.BuffIconSize, rawBuff) end
        if rawIcon ~= nil then prof.iconSize = ToDisplayValue(S.DebuffIconSize, rawIcon) end
    end

    local partySys = FindUnitFrameSystem(active, Enum.EditModeUnitFrameSystemIndices.Party)
    if partySys then
        local partyProf = ns.GetProfile("party")
        local raidStyle = GetRawSystemSetting(partySys, S.UseRaidStylePartyFrames)
        local horiz = GetRawSystemSetting(partySys, S.UseHorizontalGroups)
        if raidStyle == 1 then ns.db.showRaidFramesInGroups = true end
        if horiz ~= nil then partyProf.useHorizontalGroups = (horiz == 1) end
        ReadProfileFromSystem(partySys, partyProf)
    end

    if Enum.EditModeUnitFrameSystemIndices.Raid then
        local raidSys = FindUnitFrameSystem(active, Enum.EditModeUnitFrameSystemIndices.Raid)
        if raidSys then
            local raidProf = ns.GetProfile("raid")
            if S.RaidGroupDisplayType then
                local dispType = GetRawSystemSetting(raidSys, S.RaidGroupDisplayType)
                if dispType ~= nil then
                    raidProf.useHorizontalGroups = (dispType == 1 or dispType == 3)
                end
            end
            ReadProfileFromSystem(raidSys, raidProf)
        end
    end

    return true
end

-- Saves separate Party (ns.db.party) and Raid (ns.db.raid) settings into the active Edit Mode layout.
function ns.SaveToEditMode()
    if not IsEditModeReady() or not ns.db then
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

    local function ApplyProfileToSystem(sys, prof)
        SetRawSystemSetting(sys, S.DisplayBorder, prof.displayBorder and 1 or 0)
        SetRawSystemSetting(sys, S.SortPlayersBy, prof.sortBy or 0)
        SetRawSystemSetting(sys, S.AuraOrganizationType, prof.auraOrganizationType or 0)
        SetRawSystemSetting(sys, S.FrameWidth, ToRawValue(S.FrameWidth, prof.frameWidth or 72))
        SetRawSystemSetting(sys, S.FrameHeight, ToRawValue(S.FrameHeight, prof.frameHeight or 36))
        SetRawSystemSetting(sys, S.Opacity, ToRawValue(S.Opacity, prof.opacity or 100))
        SetRawSystemSetting(sys, S.BigDefensiveIconSize, ToRawValue(S.BigDefensiveIconSize, prof.bigDefensiveSize or 100))
        SetRawSystemSetting(sys, S.BuffIconSize, ToRawValue(S.BuffIconSize, prof.buffSize or 100))
        SetRawSystemSetting(sys, S.DebuffIconSize, ToRawValue(S.DebuffIconSize, prof.iconSize or 100))
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
    end

    -- 1. Party Frames system (uses ns.db.party)
    local partyProf = ns.GetProfile("party")
    local partySys = FindUnitFrameSystem(active, Enum.EditModeUnitFrameSystemIndices.Party)
    if partySys then
        SetRawSystemSetting(partySys, S.UseRaidStylePartyFrames, ns.db.showRaidFramesInGroups and 1 or 0)
        SetRawSystemSetting(partySys, S.ShowPartyFrameBackground, 0) -- Always off for raid-style frames
        SetRawSystemSetting(partySys, S.UseHorizontalGroups, partyProf.useHorizontalGroups and 1 or 0)
        ApplyProfileToSystem(partySys, partyProf)
        ApplyCustomAnchor(partySys, ns.db.partyPos)
    end

    -- 2. Raid Frames system (uses ns.db.raid)
    if Enum.EditModeUnitFrameSystemIndices.Raid then
        local raidProf = ns.GetProfile("raid")
        local raidSys = FindUnitFrameSystem(active, Enum.EditModeUnitFrameSystemIndices.Raid)
        if raidSys then
            ApplyProfileToSystem(raidSys, raidProf)
            ApplyCustomAnchor(raidSys, ns.db.raidPos)
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
function ns.SupportsSize()
    return true
end

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
            prof.frameWidth or 72,
            prof.frameHeight or 36,
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
    ns.Print("Show raid frames in groups: " .. (ns.db.showRaidFramesInGroups and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
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

function ns.ResetPosition(mode)
    mode = mode or ns.GetActiveMode()
    local posKey = (mode == "raid") and "raidPos" or "partyPos"
    if ns.db then
        ns.db[posKey] = nil
    end
    local target = (mode == "raid") and _G["CompactRaidFrameContainer"] or _G["CompactPartyFrame"]
    if target then
        target:ClearAllPoints()
    end
    ns.ApplyLiveVisuals()
    ns.Print("Position reset to default.")
end

function ns.ResetSize()
    local prof = ns.GetProfile()
    for key, value in pairs(PROFILE_DEFAULTS) do
        prof[key] = value
    end
    local mode = ns.GetActiveMode()
    local posKey = (mode == "raid") and "raidPos" or "partyPos"
    if ns.db then
        ns.db[posKey] = nil
    end
    local target = (mode == "raid") and _G["CompactRaidFrameContainer"] or _G["CompactPartyFrame"]
    if target then
        target:ClearAllPoints()
    end
    ns.CommitChanges(false)
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
    SimpleRaidFramesDB = SimpleRaidFramesDB or {}
    for key, value in pairs(DEFAULTS) do
        if SimpleRaidFramesDB[key] == nil then
            SimpleRaidFramesDB[key] = value
        end
    end
    -- Raid-style frames must stay active by default
    if SimpleRaidFramesDB.showRaidFramesInGroups == false then
        SimpleRaidFramesDB.showRaidFramesInGroups = true
    end
    for _, mode in ipairs({ "party", "raid" }) do
        if type(SimpleRaidFramesDB[mode]) ~= "table" then
            SimpleRaidFramesDB[mode] = {}
        end
        local prof = SimpleRaidFramesDB[mode]
        for key, defaultVal in pairs(PROFILE_DEFAULTS) do
            if prof[key] == nil then
                if SimpleRaidFramesDB[key] ~= nil then
                    prof[key] = SimpleRaidFramesDB[key]
                else
                    prof[key] = defaultVal
                end
            end
        end
    end
    ns.db = SimpleRaidFramesDB

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
        InstallSafeHooks()
        ScheduleLiveVisuals()
        ns.Print("loaded. Type |cffffff00/srf|r to configure your raid & party frames.")
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
local HELP = "/srf - open config window | on | off | solo | width <n> | height <n> | size <w> <h> | reset | resetpos"

local function HandleSlash(msg)
    msg = strlower(strtrim(msg or ""))
    local cmd, arg1, arg2 = strsplit(" ", msg)
    if cmd == "on" then
        ns.SetEnabled(true)
    elseif cmd == "off" then
        ns.SetEnabled(false)
    elseif cmd == "toggle" then
        ns.SetEnabled(not ns.db.showRaidFramesInGroups)
    elseif cmd == "solo" then
        ns.SetOption("showWhenSolo", not ns.db.showWhenSolo)
        ns.Print("Show frames when solo: " .. (ns.db.showWhenSolo and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
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
    else
        ns.Print(HELP)
    end
end

SLASH_SIMPLERAIDFRAMES1 = "/srf"
SLASH_SIMPLERAIDFRAMES2 = "/simpleraidframes"
SlashCmdList["SIMPLERAIDFRAMES"] = HandleSlash
