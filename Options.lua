-- Options UI for Dan's Raid Frames (Esc > Options > AddOns > Dan's Raid Frames, opened via /drf).
-- Uses genuine Blizzard stock templates inside the native Options canvas:
--   * SettingsCheckboxTemplate (stock modern checkboxes with row hover highlight)
--   * WowStyle1DropdownTemplate (stock modern dropdown button; popup handled privately to avoid Blizzard_Menu pool taint)
--   * MinimalSliderWithSteppersTemplate (stock Edit Mode stepper sliders with < / > buttons)
--   * InsetFrameTemplate & UIPanelButtonTemplate (stock recessed preview box & buttons)

local _, ns = ...

local PANEL_NAME = "Dan's Raid Frames"

local ROW_HEIGHT = 23
local ROW_GAP = -2
local SECTION_GAP = -6
local LEFT_COL_WIDTH = 390
local CONTROL_WIDTH = 190
local VALUE_WIDTH = 44

local ORIENTATION_OPTIONS = {
    { value = false, label = "Vertical" },
    { value = true,  label = "Horizontal" },
}

-- Where the members sit inside the party frame's 5 slots (Top/Center/Bottom for vertical groups).
local ALIGNMENT_OPTIONS = {
    { value = 0, label = "Left / Top" },
    { value = 1, label = "Center" },
    { value = 2, label = "Right / Bottom" },
}

local SORT_OPTIONS = {
    { value = 0, label = "Role" },
    { value = 1, label = "Group" },
    { value = 2, label = "Alphabetical" },
}

local TEMPLATE_OPTIONS = {
    { value = 0, label = "Legacy" },
    { value = 1, label = "Buffs Top" },
    { value = 2, label = "Buffs Bottom" },
}

local function PlayClickSound(on)
    if PlaySound and SOUNDKIT then
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

-- Creates a Blizzard Settings-style row with a subtle hover highlight and gold left label.
local function CreateSettingRow(parent, labelText)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LEFT_COL_WIDTH, ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    highlight:SetVertexColor(1, 0.82, 0, 0.12)
    highlight:Hide()

    row:EnableMouse(true)
    row:SetScript("OnEnter", function() highlight:Show() end)
    row:SetScript("OnLeave", function() highlight:Hide() end)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(labelText)
    row.Label = label
    row.Highlight = highlight

    return row
end

-- Stock Blizzard section header with gold title and subtle divider line.
local function CreateSectionHeader(parent, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(LEFT_COL_WIDTH, 22)

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    label:SetPoint("BOTTOMLEFT", 6, 4)
    label:SetText(text)

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 6, 0)
    line:SetPoint("BOTTOMRIGHT", -6, 0)
    line:SetColorTexture(0.6, 0.52, 0.25, 0.45)

    return header
end

-- Stock Blizzard Checkbox row (Label on left in gold, SettingsCheckboxTemplate on right).
local function CreateStockCheckbox(parent, labelText, onClick)
    local row = CreateSettingRow(parent, labelText)

    local ok, cb = pcall(CreateFrame, "CheckButton", nil, row, "SettingsCheckboxTemplate")
    if not ok or not cb then
        cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
    end
    cb:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.Label:SetPoint("RIGHT", cb, "LEFT", -12, 0)

    if cb.Text then
        cb.Text:SetText("")
    end

    cb:HookScript("OnEnter", function() row.Highlight:Show() end)
    cb:HookScript("OnLeave", function() row.Highlight:Hide() end)
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        PlayClickSound(checked)
        onClick(checked)
    end)

    function row:SetChecked(val)
        cb:SetChecked(val and true or false)
    end

    return row
end

---------------------------------------------------------------------------
-- Stock WowStyle1DropdownTemplate Button + Private Taint-Free Radio Menu
-- (Uses genuine WowStyle1DropdownTemplate button appearance without touching
-- Blizzard_Menu's global shared frame pool, preventing 12.0 StatusText taint)
---------------------------------------------------------------------------
local dropdownPopup = CreateFrame("Frame", nil, UIParent, "TooltipBorderedFrameTemplate")
dropdownPopup:SetFrameStrata("TOOLTIP")
dropdownPopup:SetClampedToScreen(true)
dropdownPopup:EnableMouse(true)
dropdownPopup:Hide()

local popupItems = {}
local activeDropdownOwner = nil

local function CloseDropdownPopup()
    dropdownPopup:Hide()
    activeDropdownOwner = nil
end

local function OpenDropdownPopup(ownerBtn, options, getValue, onSelect, refreshOwner)
    if activeDropdownOwner == ownerBtn and dropdownPopup:IsShown() then
        CloseDropdownPopup()
        return
    end
    activeDropdownOwner = ownerBtn

    local curVal = getValue()
    local itemHeight = 22
    local pad = 6
    local width = ownerBtn:GetWidth()

    for i, opt in ipairs(options) do
        local item = popupItems[i]
        if not item then
            item = CreateFrame("Button", nil, dropdownPopup)
            item:SetHeight(itemHeight)

            local hl = item:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
            hl:SetVertexColor(1, 0.82, 0, 0.22)
            hl:Hide()
            item.Highlight = hl

            local radioBg = item:CreateTexture(nil, "BORDER")
            radioBg:SetSize(16, 16)
            radioBg:SetPoint("LEFT", 6, 0)
            if radioBg.SetAtlas then
                pcall(radioBg.SetAtlas, radioBg, "common-dropdown-icon-radial", false)
            end
            item.RadioBg = radioBg

            local check = item:CreateTexture(nil, "ARTWORK")
            check:SetSize(16, 16)
            check:SetPoint("CENTER", radioBg, "CENTER", 0, 0)
            local okAtlas = check.SetAtlas and pcall(check.SetAtlas, check, "common-dropdown-icon-checkmark-yellow", false)
            if not okAtlas then
                check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            end
            item.Check = check

            local text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", radioBg, "RIGHT", 6, 0)
            text:SetPoint("RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            item.Text = text

            item:SetScript("OnEnter", function(self) self.Highlight:Show() end)
            item:SetScript("OnLeave", function(self) self.Highlight:Hide() end)

            popupItems[i] = item
        end

        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", dropdownPopup, "TOPLEFT", pad, -pad - (i - 1) * itemHeight)
        item:SetPoint("TOPRIGHT", dropdownPopup, "TOPRIGHT", -pad, -pad - (i - 1) * itemHeight)
        item.Text:SetText(opt.label)
        local selected = (opt.value == curVal)
        item.Check:SetShown(selected)
        if selected then
            item.Text:SetTextColor(1, 0.82, 0)
        else
            item.Text:SetTextColor(1, 1, 1)
        end

        item:SetScript("OnClick", function()
            PlayClickSound(true)
            CloseDropdownPopup()
            onSelect(opt.value)
            refreshOwner()
        end)
        item:Show()
    end

    for i = #options + 1, #popupItems do
        popupItems[i]:Hide()
    end

    dropdownPopup:SetSize(width, pad * 2 + #options * itemHeight)
    dropdownPopup:ClearAllPoints()
    dropdownPopup:SetPoint("TOPLEFT", ownerBtn, "BOTTOMLEFT", 0, -2)
    dropdownPopup:Show()
end

-- Stock Blizzard Dropdown row using genuine WowStyle1DropdownTemplate button visual.
local function CreateStockDropdown(parent, labelText, options, getValue, onSelect)
    local row = CreateSettingRow(parent, labelText)
    row:SetHeight(ROW_HEIGHT + 2)

    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    if not ok or not dropdown then
        dropdown = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        dropdown:SetHeight(22)
    end
    dropdown:SetWidth(CONTROL_WIDTH)
    dropdown:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.Label:SetPoint("RIGHT", dropdown, "LEFT", -12, 0)

    local function SetDropdownLabel(text)
        if dropdown.Text and dropdown.Text.SetText then
            dropdown.Text:SetText(text)
        elseif dropdown.SetDefaultText then
            dropdown:SetDefaultText(text)
        elseif dropdown.SetText then
            dropdown:SetText(text)
        end
    end

    function row:Refresh()
        local cur = getValue()
        for _, opt in ipairs(options) do
            if opt.value == cur then
                SetDropdownLabel(opt.label)
                return
            end
        end
        if options[1] then
            SetDropdownLabel(options[1].label)
        end
    end

    -- Intercept mouse down so WowStyle1DropdownTemplate opens our taint-free menu
    -- instead of acquiring radio frames from Blizzard_Menu's global shared pool.
    dropdown:SetScript("OnMouseDown", function(self)
        PlayClickSound(true)
        OpenDropdownPopup(self, options, getValue, onSelect, function()
            row:Refresh()
        end)
    end)
    dropdown:SetScript("OnClick", nil)
    dropdown:HookScript("OnEnter", function() row.Highlight:Show() end)
    dropdown:HookScript("OnLeave", function() row.Highlight:Hide() end)

    row:Refresh()
    return row
end

-- Stock Blizzard Edit Mode Stepper Slider row (MinimalSliderWithSteppersTemplate).
local function CreateStockSlider(parent, labelText, suffix, onChanged, onCommit)
    local row = CreateSettingRow(parent, labelText)
    row:SetHeight(ROW_HEIGHT + 2)

    local valueText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetWidth(VALUE_WIDTH)
    valueText:SetJustifyH("RIGHT")
    valueText:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    local unitSuffix = suffix or ""
    local function FormatVal(v)
        return tostring(v) .. unitSuffix
    end

    row.min = 72
    row.max = 144
    row.step = 2
    row.lastValue = nil
    row.updating = false

    local function OnSliderValueChanged(value)
        local step = row.step or 2
        local min = row.min or 0
        local snapped = min + math.floor((value - min) / step + 0.5) * step
        valueText:SetText(FormatVal(snapped))
        if not row.updating and snapped ~= row.lastValue then
            row.lastValue = snapped
            onChanged(snapped)
        end
    end

    local function Commit()
        if not row.updating and onCommit and row.lastValue then
            onCommit(row.lastValue)
        end
    end

    local control -- the widget whose SetValue drives the row (stepper or fallback slider)

    local ok, stepper = pcall(CreateFrame, "Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    if ok and stepper and stepper.Init and MinimalSliderWithSteppersMixin then
        control = stepper
        stepper:SetSize(CONTROL_WIDTH - VALUE_WIDTH - 6, 20)
        stepper:SetPoint("RIGHT", valueText, "LEFT", -6, 0)
        row.Label:SetPoint("RIGHT", stepper, "LEFT", -12, 0)

        -- Layout inner slider between Back (<) and Forward (>) stepper buttons
        if stepper.Slider and stepper.Back and stepper.Forward then
            stepper.Slider:ClearAllPoints()
            stepper.Slider:SetPoint("LEFT", stepper, "LEFT", 18, 0)
            stepper.Slider:SetPoint("RIGHT", stepper, "RIGHT", -18, 0)
            stepper.Slider:SetHeight(16)

            stepper.Back:ClearAllPoints()
            stepper.Back:SetSize(14, 18)
            stepper.Back:SetPoint("RIGHT", stepper.Slider, "LEFT", -4, 0)

            stepper.Forward:ClearAllPoints()
            stepper.Forward:SetSize(14, 18)
            stepper.Forward:SetPoint("LEFT", stepper.Slider, "RIGHT", 4, 0)
        end

        stepper:Init(72, 72, 144, 36, {})

        stepper:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            OnSliderValueChanged(value)
        end)

        -- Persist to Edit Mode once the user releases the slider or clicks < / >.
        if stepper.Slider then
            stepper.Slider:HookScript("OnMouseUp", Commit)
        end
        if stepper.Back then
            stepper.Back:HookScript("OnClick", Commit)
        end
        if stepper.Forward then
            stepper.Forward:HookScript("OnClick", Commit)
        end

        function row:SetRange(min, max, step)
            self.min = min
            self.max = max
            self.step = step
            self.updating = true
            local cur = self.lastValue or min
            stepper:Init(cur, min, max, (max - min) / step, {})
            if stepper.Slider and stepper.Slider.SetValueStep then
                stepper.Slider:SetValueStep(step)
            end
            if stepper.Slider and stepper.Slider.SetObeyStepOnDrag then
                stepper.Slider:SetObeyStepOnDrag(true)
            end
            self.updating = false
        end
    else
        -- Fallback standard slider if MinimalSliderWithSteppersTemplate is unavailable
        if ok and stepper and stepper.Hide then
            stepper:Hide()
        end
        local slider = CreateFrame("Slider", nil, row)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(CONTROL_WIDTH - VALUE_WIDTH - 6, 16)
        slider:SetPoint("RIGHT", valueText, "LEFT", -6, 0)
        row.Label:SetPoint("RIGHT", slider, "LEFT", -12, 0)
        if slider.SetObeyStepOnDrag then
            slider:SetObeyStepOnDrag(true)
        end
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(0, 0, 0, 0.6)
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(6)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

        slider:SetScript("OnValueChanged", function(_, value)
            OnSliderValueChanged(value)
        end)
        slider:SetScript("OnMouseUp", Commit)
        control = slider

        function row:SetRange(min, max, step)
            self.min, self.max, self.step = min, max, step
            self.updating = true
            slider:SetMinMaxValues(min, max)
            slider:SetValueStep(step)
            self.updating = false
        end
    end

    function row:SetValueSilently(value)
        self.updating = true
        self.lastValue = value
        control:SetValue(value)
        valueText:SetText(FormatVal(value))
        self.updating = false
    end

    return row
end

-- Stock Blizzard InsetFrameTemplate box holding a 1:1 scale mock raid frame with stock Raid-Bar textures.
local function CreatePreviewBox(parent, fixedMode)
    local ok, box = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if not ok or not box then
        box = CreateFrame("Frame", nil, parent)
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.07, 0.85)
    end
    box:SetSize(210, 230)

    local caption = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    caption:SetPoint("TOP", 0, -14)
    caption:SetText("1:1 Frame Preview")

    local sizeLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLabel:SetPoint("BOTTOM", 0, 38)

    local orientLabel = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    orientLabel:SetPoint("TOP", sizeLabel, "BOTTOM", 0, -3)

    local unitFrame = CreateFrame("Frame", nil, box)
    unitFrame:SetPoint("CENTER", 0, 6)
    unitFrame:SetSize(72, 36)

    local border = unitFrame:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 0.95)

    local healthBar = unitFrame:CreateTexture(nil, "ARTWORK")
    healthBar:SetPoint("TOPLEFT", 1, -1)
    healthBar:SetPoint("BOTTOMRIGHT", -1, 9)
    healthBar:SetTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")

    local _, classFile = UnitClass("player")
    local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if classColor then
        healthBar:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
    else
        healthBar:SetVertexColor(0.2, 0.8, 0.2, 1)
    end

    local powerBar = unitFrame:CreateTexture(nil, "ARTWORK")
    powerBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, -1)
    powerBar:SetPoint("BOTTOMRIGHT", -1, 1)
    powerBar:SetTexture("Interface\\RaidFrame\\Raid-Bar-Resource-Fill")
    powerBar:SetVertexColor(0.1, 0.45, 0.95, 1)

    local roleIcon = unitFrame:CreateTexture(nil, "OVERLAY")
    roleIcon:SetSize(12, 12)
    roleIcon:SetPoint("TOPLEFT", 3, -3)
    roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    roleIcon:SetTexCoord(0.296875, 0.59375, 0.3125, 0.625)

    local nameText = unitFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", roleIcon, "RIGHT", 2, 0)
    nameText:SetPoint("RIGHT", unitFrame, "RIGHT", -3, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetText(UnitName("player") or "Player")

    -- Mock Big Defensive icon (center of frame)
    local bigDefIcon = unitFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    bigDefIcon:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    bigDefIcon:SetTexture("Interface\\Icons\\Spell_Holy_PowerWordShield")
    bigDefIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Mock Buff icons (2 small icons)
    local buff1 = unitFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    buff1:SetTexture("Interface\\Icons\\Spell_Holy_WordFortitude")
    buff1:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local buff2 = unitFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    buff2:SetTexture("Interface\\Icons\\Spell_Nature_Regeneration")
    buff2:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Mock Debuff / Status Icon
    local debuff1 = unitFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    debuff1:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowWordPain")
    debuff1:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    function box:UpdateSize(w, h)
        local mode = fixedMode or ns.GetActiveMode()
        local prof = ns.GetProfile(mode)
        caption:SetText(mode == "raid" and "Raid Frame Preview (1:1)" or "Party Frame Preview (1:1)")

        w = w or (prof and prof.frameWidth) or 72
        h = h or (prof and prof.frameHeight) or 36
        unitFrame:SetSize(w, h)

        local opacity = (prof and prof.opacity) or 100
        unitFrame:SetAlpha(ns.OpacityToAlpha(opacity))

        local bigDefScale = ((prof and prof.bigDefensiveSize) or 100) / 100
        local buffScale = ((prof and prof.buffSize) or 100) / 100
        local iconScale = ((prof and prof.iconSize) or 100) / 100
        local auraOrg = (prof and prof.auraOrganizationType) or 0

        bigDefIcon:SetSize(math.floor(18 * bigDefScale + 0.5), math.floor(18 * bigDefScale + 0.5))

        local bSize = math.floor(11 * buffScale + 0.5)
        buff1:SetSize(bSize, bSize)
        buff2:SetSize(bSize, bSize)

        local dSize = math.floor(11 * iconScale + 0.5)
        debuff1:SetSize(dSize, dSize)

        buff1:ClearAllPoints()
        buff2:ClearAllPoints()
        debuff1:ClearAllPoints()

        if auraOrg == 1 then
            -- Buffs Top: buffs at top-right, debuffs at bottom-left
            buff1:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", -2, -2)
            buff2:SetPoint("RIGHT", buff1, "LEFT", -1, 0)
            debuff1:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 2, 2)
        elseif auraOrg == 2 then
            -- Buffs Bottom: buffs at bottom-right, debuffs at top-right
            buff1:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -2, 2)
            buff2:SetPoint("RIGHT", buff1, "LEFT", -1, 0)
            debuff1:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", -2, -2)
        else
            -- Legacy: buffs at bottom-right, debuffs at bottom-left
            buff1:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -2, 2)
            buff2:SetPoint("RIGHT", buff1, "LEFT", -1, 0)
            debuff1:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 2, 2)
        end

        local templateLabel = "Legacy"
        for _, opt in ipairs(TEMPLATE_OPTIONS) do
            if opt.value == auraOrg then
                templateLabel = opt.label
                break
            end
        end

        sizeLabel:SetText(("%d x %d  •  %d%% Opacity"):format(w, h, opacity))
        local isHoriz = prof and prof.useHorizontalGroups
        orientLabel:SetText(("%s  •  %s"):format(isHoriz and "Horizontal" or "Vertical", templateLabel))
    end

    return box
end

-- Opens Blizzard's Options > Gameplay > Interface scrolled to its Raid Frames section, which holds
-- the display options this addon deliberately doesn't duplicate (power bars, debuffs, health text...).
local function OpenBlizzardRaidFrameOptions()
    if Settings and Settings.OpenToCategory and Settings.INTERFACE_CATEGORY_ID then
        Settings.OpenToCategory(Settings.INTERFACE_CATEGORY_ID, RAID_FRAMES_LABEL)
    else
        ns.Print("Open Options > Gameplay > Interface > Raid Frames.")
    end
end

local function CreateBlizzardOptionsButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(210, 24)
    button:SetText("Blizzard Raid Frame Options")
    button:SetScript("OnClick", function()
        PlayClickSound(true)
        OpenBlizzardRaidFrameOptions()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Blizzard Raid Frame Options")
        GameTooltip:AddLine("Opens Options > Gameplay > Interface > Raid Frames: power bars, class colors, pets, debuffs, dispel indicators and health text.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return button
end

local MOVE_HINT = "To move or resize frames, right-click a party or raid frame and choose |cffffd100Unlock Frames|r."
    .. " Right-click the outline to lock them again. Type |cffffd100/drf help|r for all commands."

-- Short explanation of how to move frames (unlocking happens from the frames' right-click menu).
local function CreateMoveHint(parent)
    local hint = CreateFrame("Frame", nil, parent)
    hint:SetSize(LEFT_COL_WIDTH, 44)

    local text = hint:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 10, -4)
    text:SetWidth(LEFT_COL_WIDTH - 20)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(MOVE_HINT)

    return hint
end

local panels = {}

-- Builds the Root overview panel shown when clicking "Dan's Raid Frames" directly in the left AddOn list.
local function BuildRootPanel(panel)
    local view = {}

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -14)
    title:SetText(PANEL_NAME)

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Click |cffffd100[+]|r next to Dan's Raid Frames on the left to configure |cffffd100Party Frames|r and |cffffd100Raid Frames|r separately.")

    local visHeader = CreateSectionHeader(panel, "General & Visibility")
    visHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)

    local cbRaidStyle = CreateStockCheckbox(panel, "Show Raid Frames in Groups", function(checked)
        ns.SetEnabled(checked)
    end)
    cbRaidStyle:SetPoint("TOPLEFT", visHeader, "BOTTOMLEFT", 0, -4)

    local moveHint = CreateMoveHint(panel)
    moveHint:SetPoint("TOPLEFT", cbRaidStyle, "BOTTOMLEFT", 0, ROW_GAP)

    local profilesHeader = CreateSectionHeader(panel, "Frame Profiles (Expand [+] on Left Sidebar to Edit)")
    profilesHeader:SetPoint("TOPLEFT", moveHint, "BOTTOMLEFT", 0, -8)

    local partyPreview = CreatePreviewBox(panel, "party")
    partyPreview:SetPoint("TOPLEFT", profilesHeader, "BOTTOMLEFT", 6, -10)

    local raidPreview = CreatePreviewBox(panel, "raid")
    raidPreview:SetPoint("TOPLEFT", partyPreview, "TOPRIGHT", 24, 0)

    local blizzardButton = CreateBlizzardOptionsButton(panel)
    blizzardButton:SetPoint("TOPLEFT", partyPreview, "BOTTOMLEFT", 0, -12)

    function view:Refresh()
        if not ns.db then
            return
        end
        cbRaidStyle:SetChecked(ns.db.showRaidFramesInGroups)
        self:UpdatePreview()
    end

    function view:UpdatePreview()
        partyPreview:UpdateSize(ns.GetSize("party"))
        raidPreview:UpdateSize(ns.GetSize("raid"))
    end

    panel:SetScript("OnShow", function()
        CloseDropdownPopup()
        view:Refresh()
    end)
    panel:SetScript("OnHide", CloseDropdownPopup)

    table.insert(panels, view)
end

-- Builds a dedicated subcategory panel for either "party" (Party Frames) or "raid" (Raid Frames).
local function BuildModePanel(panel, mode)
    local view = { mode = mode }
    local isRaid = (mode == "raid")
    local modeLabel = isRaid and "Raid Frames" or "Party Frames"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -14)
    title:SetText(PANEL_NAME .. " — " .. modeLabel)

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText(("Settings for %s."):format(modeLabel))

    local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    local function ShowSavedStatus()
        local w, h = ns.GetSize(mode)
        statusText:SetText(("|cff00ff00Applied to %s (%d x %d)|r"):format(modeLabel, w, h))
    end

    -- Saves a setting for this panel's mode straight to Edit Mode.
    local function SetModeOption(key, value)
        ns.SetActiveMode(mode)
        ns.SetOption(key, value)
        ShowSavedStatus()
    end

    -- Section 1: Visibility
    local visHeader = CreateSectionHeader(panel, "Visibility")
    visHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)

    local cbRaidStyle = CreateStockCheckbox(panel, "Show Raid Frames in Groups", function(checked)
        ns.SetActiveMode(mode)
        ns.SetEnabled(checked)
        ShowSavedStatus()
    end)
    cbRaidStyle:SetPoint("TOPLEFT", visHeader, "BOTTOMLEFT", 0, -4)

    local moveHint = CreateMoveHint(panel)
    moveHint:SetPoint("TOPLEFT", cbRaidStyle, "BOTTOMLEFT", 0, ROW_GAP)

    -- Section 2: Layout & Appearance
    local layoutHeader = CreateSectionHeader(panel, "Layout & Appearance — " .. modeLabel)
    layoutHeader:SetPoint("TOPLEFT", moveHint, "BOTTOMLEFT", 0, SECTION_GAP)

    local orientDropdown = CreateStockDropdown(panel, "Group Orientation", ORIENTATION_OPTIONS, function()
        local prof = ns.GetProfile(mode)
        return (prof and prof.useHorizontalGroups) and true or false
    end, function(isHorizontal)
        SetModeOption("useHorizontalGroups", isHorizontal)
    end)
    orientDropdown:SetPoint("TOPLEFT", layoutHeader, "BOTTOMLEFT", 0, -4)

    -- Party only: raid groups already lay out their own 5 slots.
    local alignDropdown
    local rowAboveSort = orientDropdown
    if not isRaid then
        alignDropdown = CreateStockDropdown(panel, "Alignment", ALIGNMENT_OPTIONS, function()
            local prof = ns.GetProfile(mode)
            return prof and prof.alignment or 0
        end, function(value)
            SetModeOption("alignment", value)
        end)
        alignDropdown:SetPoint("TOPLEFT", orientDropdown, "BOTTOMLEFT", 0, ROW_GAP)
        rowAboveSort = alignDropdown
    end

    local sortDropdown = CreateStockDropdown(panel, "Sort Players By", SORT_OPTIONS, function()
        local prof = ns.GetProfile(mode)
        return prof and prof.sortBy or 0
    end, function(value)
        SetModeOption("sortBy", value)
    end)
    sortDropdown:SetPoint("TOPLEFT", rowAboveSort, "BOTTOMLEFT", 0, ROW_GAP)

    local templateDropdown = CreateStockDropdown(panel, "Template", TEMPLATE_OPTIONS, function()
        local prof = ns.GetProfile(mode)
        return prof and prof.auraOrganizationType or 0
    end, function(value)
        SetModeOption("auraOrganizationType", value)
    end)
    templateDropdown:SetPoint("TOPLEFT", sortDropdown, "BOTTOMLEFT", 0, ROW_GAP)

    local cbBorder = CreateStockCheckbox(panel, "Display Border", function(checked)
        SetModeOption("displayBorder", checked)
    end)
    cbBorder:SetPoint("TOPLEFT", templateDropdown, "BOTTOMLEFT", 0, ROW_GAP)

    -- Section 3: Size & Opacity
    local sizeHeader = CreateSectionHeader(panel, "Size & Opacity — " .. modeLabel)
    sizeHeader:SetPoint("TOPLEFT", cbBorder, "BOTTOMLEFT", 0, SECTION_GAP)

    local function CommitSlider()
        ns.SetActiveMode(mode)
        ns.CommitChanges(true)
        ShowSavedStatus()
    end

    -- Width/height sliders resize live while dragging; Edit Mode is saved on release.
    local function CreateSizeSlider(labelText, isWidth)
        return CreateStockSlider(panel, labelText, "", function(value)
            ns.SetActiveMode(mode)
            if isWidth then
                ns.StageSize(value, nil)
            else
                ns.StageSize(nil, value)
            end
            local w, h = ns.GetSize(mode)
            statusText:SetText(("|cff00ff00%d x %d|r"):format(w, h))
        end, CommitSlider)
    end

    -- Percentage sliders for a profile key, staged live and saved on release.
    local function CreatePercentSlider(labelText, key, statusLabel)
        return CreateStockSlider(panel, labelText, "%", function(value)
            ns.SetActiveMode(mode)
            ns.StageOption(key, value)
            statusText:SetText(("|cff00ff00%s: %d%%|r"):format(statusLabel, value))
        end, CommitSlider)
    end

    local widthSlider = CreateSizeSlider("Frame Width", true)
    widthSlider:SetPoint("TOPLEFT", sizeHeader, "BOTTOMLEFT", 0, -4)

    local heightSlider = CreateSizeSlider("Frame Height", false)
    heightSlider:SetPoint("TOPLEFT", widthSlider, "BOTTOMLEFT", 0, ROW_GAP)

    local opacitySlider = CreatePercentSlider("Opacity", "opacity", "Opacity")
    opacitySlider:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", 0, ROW_GAP)

    local bigDefSlider = CreatePercentSlider("Big Defensive Size", "bigDefensiveSize", "Big Defensive")
    bigDefSlider:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", 0, ROW_GAP)

    local buffSizeSlider = CreatePercentSlider("Buff Size", "buffSize", "Buff Size")
    buffSizeSlider:SetPoint("TOPLEFT", bigDefSlider, "BOTTOMLEFT", 0, ROW_GAP)

    local iconSizeSlider = CreatePercentSlider("Icon Size", "iconSize", "Icon Size")
    iconSizeSlider:SetPoint("TOPLEFT", buffSizeSlider, "BOTTOMLEFT", 0, ROW_GAP)

    -- Right-side recessed 1:1 Preview Box + Action Buttons
    local previewBox = CreatePreviewBox(panel, mode)
    previewBox:SetPoint("TOPLEFT", visHeader, "TOPRIGHT", 20, -4)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(108, 24)
    resetButton:SetPoint("TOPLEFT", previewBox, "BOTTOMLEFT", 0, -10)
    resetButton:SetText("Reset Defaults")
    resetButton:SetScript("OnClick", function()
        ns.SetActiveMode(mode)
        ns.ResetSize()
        local w, h = ns.GetSize(mode)
        statusText:SetText(("|cff00ff00Reset (%d x %d)|r"):format(w, h))
    end)

    local applyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    applyButton:SetSize(94, 24)
    applyButton:SetPoint("TOPRIGHT", previewBox, "BOTTOMRIGHT", 0, -10)
    applyButton:SetText("Apply")
    applyButton:SetScript("OnClick", function()
        ns.SetActiveMode(mode)
        ns.CommitChanges(false)
        ShowSavedStatus()
    end)

    local blizzardButton = CreateBlizzardOptionsButton(panel)
    blizzardButton:SetPoint("TOPLEFT", previewBox, "BOTTOMLEFT", 0, -40)
    blizzardButton:SetPoint("TOPRIGHT", previewBox, "BOTTOMRIGHT", 0, -40)

    statusText:SetPoint("TOP", blizzardButton, "BOTTOM", 0, -8)
    statusText:SetText("")

    function view:Refresh()
        if not ns.db then
            return
        end
        local prof = ns.GetProfile(mode)
        local ranges = ns.GetSizeRanges()
        local width, height = ns.GetSize(mode)

        cbRaidStyle:SetChecked(ns.db.showRaidFramesInGroups)
        orientDropdown:Refresh()
        if alignDropdown then
            alignDropdown:Refresh()
        end
        sortDropdown:Refresh()
        templateDropdown:Refresh()
        cbBorder:SetChecked(prof.displayBorder)

        widthSlider:SetRange(unpack(ranges.width))
        heightSlider:SetRange(unpack(ranges.height))
        opacitySlider:SetRange(unpack(ranges.opacity))
        bigDefSlider:SetRange(unpack(ranges.bigDefensiveSize))
        buffSizeSlider:SetRange(unpack(ranges.buffSize))
        iconSizeSlider:SetRange(unpack(ranges.iconSize))

        widthSlider:SetValueSilently(width or ranges.width[1])
        heightSlider:SetValueSilently(height or ranges.height[1])
        opacitySlider:SetValueSilently(prof.opacity or ranges.opacity[2])
        bigDefSlider:SetValueSilently(prof.bigDefensiveSize or 100)
        buffSizeSlider:SetValueSilently(prof.buffSize or 100)
        iconSizeSlider:SetValueSilently(prof.iconSize or 100)

        self:UpdatePreview()
    end

    function view:UpdatePreview()
        local width, height = ns.GetSize(mode)
        previewBox:UpdateSize(width, height)
    end

    panel:SetScript("OnShow", function()
        CloseDropdownPopup()
        statusText:SetText("")
        ns.SetActiveMode(mode)
        view:Refresh()
    end)
    panel:SetScript("OnHide", CloseDropdownPopup)

    table.insert(panels, view)
end

function ns.CreateOptions()
    local rootPanel = CreateFrame("Frame")
    rootPanel.name = PANEL_NAME
    BuildRootPanel(rootPanel)
    ns.optionsPanel = rootPanel

    local partyPanel = CreateFrame("Frame")
    partyPanel.name = "Party Frames"
    partyPanel.parent = PANEL_NAME
    BuildModePanel(partyPanel, "party")
    ns.partyPanel = partyPanel

    local raidPanel = CreateFrame("Frame")
    raidPanel.name = "Raid Frames"
    raidPanel.parent = PANEL_NAME
    BuildModePanel(raidPanel, "raid")
    ns.raidPanel = raidPanel

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(rootPanel, PANEL_NAME)
        if Settings.RegisterCanvasLayoutSubcategory then
            ns.partyCategory = Settings.RegisterCanvasLayoutSubcategory(category, partyPanel, "Party Frames")
            ns.raidCategory = Settings.RegisterCanvasLayoutSubcategory(category, raidPanel, "Raid Frames")
        end
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(rootPanel)
        InterfaceOptions_AddCategory(partyPanel)
        InterfaceOptions_AddCategory(raidPanel)
    end
end

function ns.UpdatePreviewBoxes()
    for _, view in ipairs(panels) do
        if view.UpdatePreview then
            view:UpdatePreview()
        end
    end
end

function ns.RefreshOptions()
    if not ns.db then
        return
    end
    for _, view in ipairs(panels) do
        if view.Refresh then
            view:Refresh()
        end
    end
end

function ns.OpenOptions()
    if InCombatLockdown() then
        ns.Print("Cannot open the Options menu during combat.")
        return false
    end
    if Settings and Settings.OpenToCategory and ns.settingsCategory and ns.settingsCategory.GetID then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
        return true
    elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
        -- Called twice on purpose: on old clients the first call only opens the AddOns tab.
        InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        return true
    end
    return false
end

function DansRaidFrames_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.SetUnlocked(not ns.IsUnlocked())
    else
        ns.OpenOptions()
    end
end

function DansRaidFrames_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame or UIParent, menuButtonFrame and "ANCHOR_LEFT" or "ANCHOR_CURSOR")
    GameTooltip:SetText(PANEL_NAME)
    GameTooltip:AddLine("Left-click: open options", 1, 1, 1)
    GameTooltip:AddLine(ns.IsUnlocked() and "Right-click: lock frames" or "Right-click: unlock frames to move them", 1, 1, 1)
    GameTooltip:Show()
end

function DansRaidFrames_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
