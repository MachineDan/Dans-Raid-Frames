-- Offline check: what SaveToEditMode writes must decode, with Blizzard's own Forever
-- conversion (EditModeSettingDisplayInfo.lua), back to the value picked in /drf.
-- Run from the repo root: luajit tests/test_iconsize.lua
local S = {
    UseRaidStylePartyFrames = 4, ShowPartyFrameBackground = 5, UseHorizontalGroups = 6,
    FrameWidth = 10, FrameHeight = 11, DisplayBorder = 12, RaidGroupDisplayType = 13,
    SortPlayersBy = 14, AuraOrganizationType = 18, DebuffIconSize = 19, Opacity = 20,
    BigDefensiveIconSize = 21, BuffIconSize = 22,
}

-- Blizzard's two converters, copied from Forever's EditModeSettingDisplayInfo.lua.
local function ClampValue(self, v) return math.max(self.minValue, math.min(self.maxValue, v)) end
local function ConvertValueDefault(self, value, forDisplay)
    if forDisplay then return ClampValue(self, value * self.stepSize + self.minValue) end
    return (value - self.minValue) / self.stepSize
end
local function ConvertValueDiffFromMin(self, value, forDisplay)
    if forDisplay then return ClampValue(self, value + self.minValue) end
    return value - self.minValue
end
local function Info(setting, min, max, step, conv)
    return { setting = setting, minValue = min, maxValue = max, stepSize = step, ConvertValue = conv }
end
local INFO = {
    Info(S.FrameWidth, 72, 144, 2, ConvertValueDiffFromMin),
    Info(S.FrameHeight, 36, 72, 2, ConvertValueDiffFromMin),
    Info(S.Opacity, 50, 100, 1, ConvertValueDefault),
    Info(S.BigDefensiveIconSize, 50, 100, 5, ConvertValueDefault),
    Info(S.BuffIconSize, 50, 200, 10, ConvertValueDefault),
    Info(S.DebuffIconSize, 50, 200, 10, ConvertValueDefault),
}

-- Minimal WoW API stubs.
Enum = {
    EditModeSystem = { UnitFrame = 3 },
    EditModeUnitFrameSetting = S,
    EditModeUnitFrameSystemIndices = { Party = 3, Raid = 4 },
    EditModeLayoutType = { Preset = 0, Account = 1 },
}
EditModeSettingDisplayInfoManager = { systemSettingDisplayInfo = { [3] = INFO } }
EditModeSettingDisplayInfoMixin = {}
EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return { { layoutType = 0, layoutName = "Modern", systems = {} } } end }
EditModeManagerFrame = { accountSettings = {} }
local saved
C_EditMode = {
    GetLayouts = function()
        return { activeLayout = 2, layouts = { { layoutType = 1, layoutName = "Mine", systems = {
            { system = 3, systemIndex = 3, settings = {} },
            { system = 3, systemIndex = 4, settings = {} },
        } } } }
    end,
    SaveLayouts = function(info) saved = info end,
    SetActiveLayout = function() end,
}
local function noop() end
local frameStub = setmetatable({}, { __index = function() return noop end })
CreateFrame = function() return frameStub end
UIParent = { GetTop = function() return 768 end }
DEFAULT_CHAT_FRAME = { AddMessage = noop }
SlashCmdList = {}
hooksecurefunc = noop
InCombatLockdown = function() return true end -- skips live frame layout, not under test
C_CVar = { GetCVar = noop, SetCVar = noop }
strlower, strtrim, strsplit = string.lower, function(s) return s end, noop
unpack = unpack or table.unpack

local ns = {}
ns.CreateOptions = noop
assert(loadfile("Core.lua"))("DansRaidFrames", ns)
DansRaidFramesDB = {}

local PROFILE_KEY = { [S.Opacity] = "opacity", [S.BigDefensiveIconSize] = "bigDefensiveSize",
    [S.BuffIconSize] = "buffSize", [S.DebuffIconSize] = "iconSize",
    [S.FrameWidth] = "frameWidth", [S.FrameHeight] = "frameHeight" }

local failures, checks = 0, 0
local function Check(prof)
    ns.db = { showRaidFramesInGroups = true, party = prof, raid = prof }
    saved = nil
    assert(ns.SaveToEditMode(), "SaveToEditMode failed")
    local sys = saved.layouts[saved.activeLayout].systems[1]
    for _, setup in ipairs(INFO) do
        local raw
        for _, s in ipairs(sys.settings) do
            if s.setting == setup.setting then raw = s.value end
        end
        local want = prof[PROFILE_KEY[setup.setting]]
        local got = setup.ConvertValue(setup, raw, true)
        checks = checks + 1
        if got ~= want or raw ~= math.floor(raw) then
            failures = failures + 1
            print(("FAIL %-18s picked %d -> raw %s -> Blizzard shows %s"):format(
                PROFILE_KEY[setup.setting], want, tostring(raw), tostring(got)))
        end
    end
end

for v = 50, 200, 10 do
    Check({ frameWidth = 144, frameHeight = 72, opacity = 100, bigDefensiveSize = math.min(v, 100) - (math.min(v, 100) % 5),
        buffSize = v, iconSize = v, sortBy = 0, auraOrganizationType = 0 })
end
for v = 50, 100, 5 do
    Check({ frameWidth = 72, frameHeight = 36, opacity = v, bigDefensiveSize = v,
        buffSize = 100, iconSize = 100, sortBy = 0, auraOrganizationType = 0 })
end
-- The user's own saved profile.
Check({ frameWidth = 144, frameHeight = 72, opacity = 100, bigDefensiveSize = 95, buffSize = 70, iconSize = 70,
    sortBy = 0, auraOrganizationType = 0 })

print(("%d/%d settings round-trip correctly"):format(checks - failures, checks))
os.exit(failures == 0 and 0 or 1)
