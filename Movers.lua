-- Unlock / Lock mode for moving and resizing the Party or Raid frames.
--
-- Unlocking targets one frame group ("party" or "raid"). A thin outline ("mover") is drawn around
-- its full footprint, as if every slot were filled (5 party members / 40 raid members):
-- dragging the outline moves the real frames with pure C++ widget calls (ClearAllPoints / SetPoint),
-- dragging the corner grip resizes the unit frames through the same StageSize / CommitChanges path
-- as the sliders, and right-clicking the outline locks again. With Edit Mode, the dropped position is
-- written into the Edit Mode layout (ns.SaveFramePosition), so Edit Mode can still move the frames.
-- Right-clicking a party/raid frame offers "Unlock Frames" (added with Menu.ModifyMenu, Blizzard's
-- taint-safe way to extend menus).
-- The mover is our own frame: nothing here calls Blizzard Lua methods on the unit frames.
-- It sits below the options window (HIGH strata) so its sliders stay usable while unlocked.
-- Frames can't be moved in combat, so entering combat locks them automatically.

local _, ns = ...

local MOVER_FRAME_LEVEL = 500

local STRATA_ORDER = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
    DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local unlockedMode = nil -- "party", "raid" or nil when locked
local movers = {}

function ns.IsUnlocked()
    return unlockedMode ~= nil
end

function ns.GetUnlockedMode()
    return unlockedMode
end

-- The group you're currently looking at: raid frames in a raid (or when party frames aren't raid-style).
local function GetDefaultMode()
    if IsInRaid() or not (ns.db and ns.db.showRaidFramesInGroups) then
        return "raid"
    end
    return "party"
end

-- The frame that actually gets moved. With Edit Mode that's the frame Edit Mode itself drags
-- (PartyFrame holds CompactPartyFrame), so both ways of moving stay in sync.
local function GetTarget(mode)
    if mode == "raid" then
        return _G["CompactRaidFrameContainer"]
    end
    if ns.UsesEditModePositions() and _G["PartyFrame"] then
        return _G["PartyFrame"]
    end
    return _G["CompactPartyFrame"]
end

-- The container the unit frames are laid out in: the outline starts at its top-left corner.
local function GetContainer(mode)
    return (mode == "raid") and _G["CompactRaidFrameContainer"] or _G["CompactPartyFrame"]
end

-- The group's full footprint (as if all 5 party / 40 raid slots were filled, see
-- ns.GetFullGroupSize), in unscaled screen pixels: left, top, width, height.
local function GetMoverBounds(mover)
    local container = GetContainer(mover.mode)
    local scale = container and container:GetEffectiveScale() or UIParent:GetEffectiveScale()
    local w, h = ns.GetFullGroupSize(mover.mode)
    w, h = w * scale, h * scale

    local left, top
    if mover.isMoving and mover.dropX and GetTarget(mover.mode) == container then
        -- Dragging the container itself, which may be hidden (raid frames outside a raid).
        left, top = mover.dropX, mover.dropY
    elseif container then
        left, top = container:GetLeft(), container:GetTop()
    end
    if not (left and top) then
        local pos = ns.db and ns.db[mover.posKey]
        if pos and pos.x and pos.y then
            left, top = pos.x, pos.y
        end
    end
    if left and top then
        return left * scale, top * scale, w, h
    end
    local cx, cy = UIParent:GetCenter()
    local uiScale = UIParent:GetEffectiveScale()
    return cx * uiScale - w / 2, cy * uiScale + h / 2, w, h
end

-- The outline is always rebuilt from where the real frames are, so it can't drift away from them.
local function PositionMover(mover)
    local left, top, width, height = GetMoverBounds(mover)
    local s = mover:GetEffectiveScale()
    mover:ClearAllPoints()
    mover:SetSize(width / s, height / s)
    mover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / s, top / s)
end

---------------------------------------------------------------------------
-- Moving: plain cursor-delta dragging of the real frames
---------------------------------------------------------------------------

local function StopDragging(mover)
    if not mover.isMoving then
        return
    end
    mover:SetScript("OnUpdate", nil)
    mover.isMoving = false
    if mover.dropX and mover.dropY and not InCombatLockdown() then
        ns.SaveFramePosition(mover.mode, mover.dropX, mover.dropY)
    end
    mover.dropX, mover.dropY = nil, nil
    if unlockedMode == mover.mode then
        PositionMover(mover)
    end
end

local function OnDragUpdate(mover)
    local target = GetTarget(mover.mode)
    if not target or InCombatLockdown() or not IsMouseButtonDown("LeftButton") then
        StopDragging(mover)
        return
    end
    local scale = target:GetEffectiveScale()
    local x, y = GetCursorPosition()
    mover.dropX = mover.startLeft + (x - mover.startCursorX) / scale
    mover.dropY = mover.startTop + (y - mover.startCursorY) / scale

    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mover.dropX, mover.dropY)
    if not ns.UsesEditModePositions() and ns.db then
        -- Keep ns.db current so a layout pass mid-drag re-applies this spot, not the old one.
        ns.db[mover.posKey] = { x = mover.dropX, y = mover.dropY }
    end
    PositionMover(mover)
end

local function StartDragging(mover)
    if InCombatLockdown() or mover.isMoving or mover.isResizing then
        return
    end
    local target = GetTarget(mover.mode)
    if not target then
        return
    end
    local scale = target:GetEffectiveScale()
    local left, top = target:GetLeft(), target:GetTop()
    if not left or not top then
        -- Hidden container (e.g. raid frames outside a raid): start from the placeholder outline.
        local ratio = mover:GetEffectiveScale() / scale
        left, top = mover:GetLeft() * ratio, mover:GetTop() * ratio
    end
    mover.startLeft, mover.startTop = left, top
    mover.startCursorX, mover.startCursorY = GetCursorPosition()
    mover.dropX, mover.dropY = nil, nil
    mover.isMoving = true
    mover:SetScript("OnUpdate", OnDragUpdate)
end

---------------------------------------------------------------------------
-- Resizing
---------------------------------------------------------------------------

local function StopResizing(mover)
    if not mover.isResizing then
        return
    end
    mover.isResizing = false
    mover:SetScript("OnUpdate", nil)
    if not InCombatLockdown() then
        ns.CommitChanges(true)
    end
end

local function OnResizeUpdate(mover)
    if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then
        StopResizing(mover)
        return
    end
    local x, y = GetCursorPosition()
    if x == mover.lastCursorX and y == mover.lastCursorY then
        return
    end
    mover.lastCursorX, mover.lastCursorY = x, y

    -- Spread the cursor movement over the frames in each direction so the corner tracks the cursor.
    local ts = mover.targetScale
    local width = mover.startW + (x - mover.startCursorX) / ts / mover.countX
    local height = mover.startH + (mover.startCursorY - y) / ts / mover.countY
    ns.StageSize(width, height)
end

local function StartResizing(mover)
    if InCombatLockdown() or mover.isMoving or mover.isResizing then
        return
    end
    local w, h = ns.GetSize(mover.mode)
    local target = GetTarget(mover.mode)
    local ts = target and target:GetEffectiveScale() or mover:GetEffectiveScale()

    -- How many frames the full outline holds side by side and on top of each other:
    -- 5 per group along the group's direction, and 8 groups for a full raid.
    local groups = (mover.mode == "raid") and 8 or 1
    if ns.GetProfile(mover.mode).useHorizontalGroups then
        mover.countX, mover.countY = 5, groups
    else
        mover.countX, mover.countY = groups, 5
    end
    mover.startW, mover.startH = w, h
    mover.startCursorX, mover.startCursorY = GetCursorPosition()
    mover.lastCursorX, mover.lastCursorY = nil, nil
    mover.targetScale = ts
    mover.isResizing = true

    ns.SetActiveMode(mover.mode)
    mover:SetScript("OnUpdate", OnResizeUpdate)
end

---------------------------------------------------------------------------
-- Mover frames
---------------------------------------------------------------------------

local function CreateMover(mode)
    local mover = CreateFrame("Frame", nil, UIParent)
    mover.mode = mode
    mover.posKey = (mode == "raid") and "raidPos" or "partyPos"

    -- Above the unit frames so it catches the mouse, below the options window (HIGH).
    local strata = "MEDIUM"
    local target = GetTarget(mode)
    if target and (STRATA_ORDER[target:GetFrameStrata()] or 0) > STRATA_ORDER.MEDIUM then
        strata = target:GetFrameStrata()
    end
    mover:SetFrameStrata(strata)
    mover:SetFrameLevel(MOVER_FRAME_LEVEL)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    -- Faint fill only while hovered, so the frames stay readable.
    local fill = mover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.1, 0.55, 1, 0.12)
    fill:Hide()

    -- 1px outline: top, bottom, left, right
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", true },
        { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false },
        { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local tex = mover:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(0.35, 0.75, 1, 0.9)
        tex:SetPoint(edge[1], 0, 0)
        tex:SetPoint(edge[2], 0, 0)
        if edge[3] then
            tex:SetHeight(1)
        else
            tex:SetWidth(1)
        end
    end

    -- Corner grip: drag to resize the unit frames.
    local grip = CreateFrame("Button", nil, mover)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", 6, -6)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            StartResizing(mover)
        end
    end)
    grip:SetScript("OnMouseUp", function()
        StopResizing(mover)
    end)

    mover:SetScript("OnDragStart", function()
        StartDragging(mover)
    end)
    mover:SetScript("OnDragStop", function()
        StopDragging(mover)
    end)
    -- Right-click the outline (it covers the frames while unlocked) to lock again.
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ns.SetUnlocked(false)
        end
    end)
    mover:SetScript("OnEnter", function()
        fill:Show()
    end)
    mover:SetScript("OnLeave", function()
        fill:Hide()
    end)

    return mover
end

-- Called after every ApplyLiveVisuals so the outline follows frames that resize, move or reappear.
function ns.UpdateMovers()
    for mode, mover in pairs(movers) do
        local show = (unlockedMode == mode)
        if show and mode == "party" then
            -- Party outline only for raid-style party frames outside a raid.
            show = ns.db and ns.db.showRaidFramesInGroups and not IsInRaid()
        end
        if show then
            if not mover.isMoving then
                PositionMover(mover)
            end
            mover:Show()
        else
            StopDragging(mover)
            StopResizing(mover)
            mover:Hide()
        end
    end
end

-- Unlocks one frame group (mode "party" / "raid", or nil for the group you're in), or locks.
function ns.SetUnlocked(value, mode, quiet)
    local newMode = nil
    if value then
        if InCombatLockdown() then
            ns.Print("Frames can't be moved in combat.")
            return
        end
        newMode = (mode == "party" or mode == "raid") and mode or GetDefaultMode()
    end
    if newMode == unlockedMode then
        return
    end
    unlockedMode = newMode

    if unlockedMode and not movers[unlockedMode] then
        movers[unlockedMode] = CreateMover(unlockedMode)
    end

    -- Shows (or hides again) the party frame while solo, then repositions the outline.
    ns.ApplyLiveVisuals()
    if unlockedMode and C_Timer and C_Timer.After then
        -- A frame that was just shown may not report its position until the next frame.
        C_Timer.After(0, ns.UpdateMovers)
    end

    if not quiet then
        if unlockedMode then
            ns.Print(("%s unlocked: drag to move, drag the corner to resize, right-click to lock."):format(
                unlockedMode == "raid" and "Raid frames" or "Party frames"))
        else
            ns.Print("Frames locked.")
        end
    end
end

---------------------------------------------------------------------------
-- "Unlock Frames" entry in the party / raid frames' right-click menu
---------------------------------------------------------------------------

-- Menu types Blizzard's compact unit frames open on right-click (CompactUnitFrame_OpenMenu).
local UNIT_MENU_TYPES = { "SELF", "VEHICLE", "PET", "RAID_PLAYER", "PARTY", "PLAYER", "TARGET" }
local FRAME_PREFIX_MODES = {
    { "CompactPartyFrameMember", "party" },
    { "CompactRaidGroup", "raid" },
    { "CompactRaidFrame", "raid" },
}

-- The same menus also open from the player, target and party portraits: only add our entry when
-- the menu was opened from a compact party/raid frame. Returns that frame's group.
local function GetCompactFrameMode(frame)
    local name = frame and frame.GetName and frame:GetName()
    if type(name) ~= "string" then
        return nil
    end
    for _, entry in ipairs(FRAME_PREFIX_MODES) do
        if name:sub(1, #entry[1]) == entry[1] then
            return entry[2]
        end
    end
    return nil
end

local function AddUnlockMenuEntry(owner, rootDescription, contextData)
    local frame = (type(contextData) == "table" and contextData.ownerFrame) or owner
    local mode = GetCompactFrameMode(frame)
    if not mode or InCombatLockdown() then
        return
    end
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("Simple Raid Frames")
    if unlockedMode then
        rootDescription:CreateButton("Lock Frames", function()
            ns.SetUnlocked(false)
        end)
    else
        rootDescription:CreateButton("Unlock Frames", function()
            ns.SetUnlocked(true, mode)
        end)
    end
end

local menuEntriesAdded = false
local function AddUnitMenuEntries()
    if menuEntriesAdded or not (Menu and Menu.ModifyMenu) then
        return
    end
    menuEntriesAdded = true
    for _, which in ipairs(UNIT_MENU_TYPES) do
        Menu.ModifyMenu("MENU_UNIT_" .. which, AddUnlockMenuEntry)
    end
end
AddUnitMenuEntries()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- In case Blizzard_Menu wasn't loaded yet when this file ran.
        AddUnitMenuEntries()
    elseif unlockedMode then
        ns.SetUnlocked(false, nil, true)
        ns.Print("Frames locked for combat.")
    end
end)
