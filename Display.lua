-- ============================================================
-- Marksmanship Rotation Helper - Display.lua
-- Compact icon-first recommendation display, adapted from the
-- matching Retribution Paladin helper for a shot-priority (not
-- swing-driven, not seal-driven) Marksmanship Hunter rotation.
-- ============================================================

local ADDON_NAME, ns = ...

-- ------------------------------------------------------------
-- Movable root: every visual element inherits its scale.
-- ------------------------------------------------------------

local COLORS = {
    background = { 0.018, 0.024, 0.036, 0.94 },
    ready = { 0.32, 0.78, 0.36, 1.00 },
    accent = { 0.35, 0.70, 1.00, 1.00 },
    inactive = { 0.22, 0.27, 0.34, 0.95 },
}

local root = CreateFrame("Frame", "MarksmanshipRotationHelperRoot", UIParent)
root:SetSize(180, 130)
root:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
root:SetFrameStrata("MEDIUM")
root:SetMovable(true)
root:SetClampedToScreen(true)
root:RegisterForDrag("LeftButton")
root:Show()

root:SetScript("OnDragStart", function(self)
    if ns.db and not ns.db.locked then self:StartMoving() end
end)

root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    ns.db.point, ns.db.x, ns.db.y = point, x, y
end)

ns.rootFrame = root

local function ApplyBackdrop(frame, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    frame:SetBackdropColor(
        COLORS.background[1],
        COLORS.background[2],
        COLORS.background[3],
        alpha or COLORS.background[4]
    )
    frame:SetBackdropBorderColor(
        COLORS.ready[1],
        COLORS.ready[2],
        COLORS.ready[3],
        COLORS.ready[4]
    )
end

local function SetBorder(frame, color)
    if not frame or not frame.SetBackdropBorderColor then return end
    frame:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
end

-- ------------------------------------------------------------
-- Main recommendation
-- ------------------------------------------------------------

local mainFrame = CreateFrame(
    "Frame",
    "MarksmanshipRotationHelperMainIcon",
    root,
    "BackdropTemplate"
)
mainFrame:SetSize(92, 92)
mainFrame:SetPoint("TOP", root, "TOP", 0, 0)
ApplyBackdrop(mainFrame, 0.94)
mainFrame:Hide()

local mainTexture = mainFrame:CreateTexture(nil, "ARTWORK")
mainTexture:SetPoint("TOPLEFT", 4, -4)
mainTexture:SetPoint("BOTTOMRIGHT", -4, 4)
mainTexture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local mainCooldown = CreateFrame(
    "Cooldown",
    nil,
    mainFrame,
    "CooldownFrameTemplate"
)
mainCooldown:SetAllPoints(mainTexture)
mainCooldown:SetDrawEdge(false)
mainCooldown:SetHideCountdownNumbers(false)

local testBanner = CreateFrame(
    "Frame",
    "MarksmanshipRotationHelperTestBanner",
    root,
    "BackdropTemplate"
)
testBanner:SetSize(180, 20)
testBanner:SetPoint("BOTTOM", mainFrame, "TOP", 0, 6)
ApplyBackdrop(testBanner, 0.92)
testBanner:SetBackdropBorderColor(1.00, 0.20, 0.16, 1)
testBanner:Hide()

local testBannerText = testBanner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
testBannerText:SetPoint("CENTER")
testBannerText:SetText("|cffff3b30TEST MODE|r")

local unlockedText = mainFrame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontNormalSmall"
)
unlockedText:SetPoint("BOTTOM", mainFrame, "TOP", 0, 4)
unlockedText:SetText("DRAG")
unlockedText:SetTextColor(
    COLORS.accent[1],
    COLORS.accent[2],
    COLORS.accent[3],
    COLORS.accent[4]
)
unlockedText:Hide()

-- ------------------------------------------------------------
-- Cooldown availability row
-- ------------------------------------------------------------

local cooldownRow = CreateFrame("Frame", "MarksmanshipRotationHelperCooldownRow", root)
cooldownRow:SetSize(190, 45)
cooldownRow:SetPoint("TOP", mainFrame, "BOTTOM", 0, -10)
cooldownRow:Hide()

local COOLDOWN_ICON_SIZE = 36
local COOLDOWN_ICON_GAP = 6

local function CreateCooldownIcon(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(COOLDOWN_ICON_SIZE, COOLDOWN_ICON_SIZE)
    ApplyBackdrop(frame, 0.94)
    frame:Hide()

    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", 3, -3)
    texture:SetPoint("BOTTOMRIGHT", -3, 3)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(texture)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(false)

    local entry = {
        frame = frame,
        texture = texture,
        cooldown = cooldown,
        name = nil,
        cachedIcon = nil,
    }

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if not entry.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.name, 1, 1, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return entry
end

local rapidFireIcon = CreateCooldownIcon(cooldownRow)
local trinketIcons = {
    CreateCooldownIcon(cooldownRow),
    CreateCooldownIcon(cooldownRow),
}

local trinket0Slot = GetInventorySlotInfo("Trinket0Slot")
local trinket1Slot = GetInventorySlotInfo("Trinket1Slot")
local TRINKET_SLOTS = { trinket0Slot, trinket1Slot }
local trinketCache = {}

local function SetReadyColor(texture, ready)
    if not ready then
        texture:SetDesaturated(true)
        texture:SetVertexColor(0.58, 0.58, 0.58)
    else
        texture:SetDesaturated(false)
        texture:SetVertexColor(1, 1, 1)
    end
end

local function UpdateAbilityCooldownIcon(entry, key)
    local identifier = ns.GetAbilityIdentifier(key)
    local start, duration = ns.GetCooldown(identifier)
    local remaining = ns.GetAbilityCooldownRemaining(key, true)
    local ready = remaining <= 0.15

    local icon = ns.GetAbilityIcon(key)
    if entry.cachedIcon ~= icon then
        entry.texture:SetTexture(icon)
        entry.cachedIcon = icon
    end
    entry.name = ns.GetAbilityName(key) or key
    entry.cooldown:SetCooldown(start or 0, duration or 0)

    SetReadyColor(entry.texture, ready)
    SetBorder(entry.frame, ready and COLORS.ready or COLORS.inactive)
end

local function UpdateTrinketIcon(entry, slot)
    local itemLink = GetInventoryItemLink("player", slot)
    if not itemLink then return false end

    local cached = trinketCache[itemLink]
    if not cached then
        local spellName = ns.GetItemSpellName(itemLink)
        if not spellName then
            -- Do not negatively cache: item data can arrive after login.
            return false
        end
        cached = {
            name = GetItemInfo(itemLink) or spellName,
            icon = GetInventoryItemTexture("player", slot),
        }
        trinketCache[itemLink] = cached
    end

    if entry.cachedIcon ~= cached.icon then
        entry.texture:SetTexture(cached.icon)
        entry.cachedIcon = cached.icon
    end
    entry.name = cached.name

    local ready, start, duration = ns.GetItemCooldownInfo(slot)
    entry.cooldown:SetCooldown(start or 0, duration or 0)
    SetReadyColor(entry.texture, ready)
    SetBorder(entry.frame, ready and COLORS.ready or COLORS.inactive)
    return true
end

local function LayoutCooldownRow(activeFrames)
    local count = #activeFrames
    if count == 0 then return end
    local width = count * COOLDOWN_ICON_SIZE + (count - 1) * COOLDOWN_ICON_GAP
    local startX = -width / 2 + COOLDOWN_ICON_SIZE / 2

    for index, frame in ipairs(activeFrames) do
        frame:ClearAllPoints()
        frame:SetPoint(
            "TOP",
            cooldownRow,
            "TOP",
            startX + (index - 1) * (COOLDOWN_ICON_SIZE + COOLDOWN_ICON_GAP),
            0
        )
    end
end

local function UpdateCooldownRow(snapshot)
    if not ns.db.showCooldowns or (snapshot and snapshot.simulation) then
        cooldownRow:Hide()
        return
    end

    local active = {}

    if ns.PlayerKnowsAbility("RAPID_FIRE") then
        UpdateAbilityCooldownIcon(rapidFireIcon, "RAPID_FIRE")
        table.insert(active, rapidFireIcon.frame)
    else
        rapidFireIcon.frame:Hide()
    end

    for index, slot in ipairs(TRINKET_SLOTS) do
        if slot and UpdateTrinketIcon(trinketIcons[index], slot) then
            table.insert(active, trinketIcons[index].frame)
        else
            trinketIcons[index].frame:Hide()
        end
    end

    if #active == 0 then
        cooldownRow:Hide()
        return
    end

    cooldownRow:Show()
    for _, frame in ipairs(active) do frame:Show() end
    LayoutCooldownRow(active)
end

-- ------------------------------------------------------------
-- Tooltip and interaction
-- ------------------------------------------------------------

local lastDisplaySnapshot
local tooltipVisible = false
local tooltipLastRefresh = 0

local function TooltipIsOwned(owner)
    if not owner or not GameTooltip then return false end
    if GameTooltip.IsOwned then return GameTooltip:IsOwned(owner) end
    if GameTooltip.GetOwner then return GameTooltip:GetOwner() == owner end
    return false
end

local function DisplayModeLabel(snapshot)
    local requested = ns.db and ns.db.mode or "auto"
    if requested == "auto" then
        return snapshot and snapshot.aoeActive and "Auto / AoE" or "Auto / Single"
    end
    return "Forced " .. requested
end

local function ShowMainTooltip()
    local snapshot = lastDisplaySnapshot
    local decision = snapshot and snapshot.main
    if not decision then return end

    GameTooltip:SetOwner(mainFrame, "ANCHOR_TOP")
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:AddLine("Marksmanship Rotation Helper", 0.32, 0.78, 0.36)
    GameTooltip:AddLine(ns.GetAbilityName(decision.ability) or decision.ability, 1, 1, 1)
    if decision.reason and decision.reason ~= "" then
        GameTooltip:AddLine(decision.reason, 0.72, 0.78, 0.86, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(
        "Mode / targets",
        DisplayModeLabel(snapshot) .. " / " .. tostring(snapshot.enemyCount or 1),
        0.65, 0.70, 0.78, 1, 1, 1
    )
    GameTooltip:AddDoubleLine(
        "Mana",
        tostring(ns.state.mana or 0) .. " / " .. tostring(ns.state.maxMana or 0),
        0.65, 0.70, 0.78, 1, 1, 1
    )
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click: cycle target mode", 0.82, 0.86, 0.92)
    GameTooltip:AddLine("/mrh opens settings", 0.62, 0.68, 0.76)
    GameTooltip:Show()
    tooltipLastRefresh = GetTime()
end

mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", function()
    if ns.db and not ns.db.locked then root:StartMoving() end
end)
mainFrame:SetScript("OnDragStop", function()
    root:StopMovingOrSizing()
    local point, _, _, x, y = root:GetPoint()
    ns.db.point, ns.db.x, ns.db.y = point, x, y
end)
mainFrame:SetScript("OnMouseUp", function(_, button)
    if button ~= "RightButton" or not ns.db then return end
    local nextMode = { auto = "single", single = "aoe", aoe = "auto" }
    ns.db.mode = nextMode[ns.db.mode] or "auto"
    if ns.Settings_Refresh then ns.Settings_Refresh() end
    if tooltipVisible then ShowMainTooltip() end
end)
mainFrame:SetScript("OnEnter", function()
    tooltipVisible = true
    ShowMainTooltip()
end)
mainFrame:SetScript("OnLeave", function()
    tooltipVisible = false
    if TooltipIsOwned(mainFrame) then GameTooltip:Hide() end
end)

-- ------------------------------------------------------------
-- Action-bar lookup and non-secure glow
-- ------------------------------------------------------------

local glow = CreateFrame(
    "Frame",
    "MarksmanshipRotationHelperGlow",
    UIParent,
    "BackdropTemplate"
)
glow:SetFrameStrata("HIGH")
glow:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
})
glow:SetBackdropBorderColor(1, 0.85, 0.1, 1)
glow:Hide()

local glowAnimation = glow:CreateAnimationGroup()
glowAnimation:SetLooping("REPEAT")

local fadeOut = glowAnimation:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0.28)
fadeOut:SetDuration(0.55)
fadeOut:SetOrder(1)

local fadeIn = glowAnimation:CreateAnimation("Alpha")
fadeIn:SetFromAlpha(0.28)
fadeIn:SetToAlpha(1)
fadeIn:SetDuration(0.55)
fadeIn:SetOrder(2)

local BAR_PREFIXES = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarLeftButton",
    "MultiBarRightButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
}

local actionSlotsByName = {}

local function AddActionSlot(name, slot)
    if not name then return end
    actionSlotsByName[name] = actionSlotsByName[name] or {}
    table.insert(actionSlotsByName[name], slot)
end

local function GetMacroActionSpell(macroIndex)
    if not GetMacroSpell then return nil end
    local name, _, spellID = GetMacroSpell(macroIndex)
    if name then return name end
    if spellID then return ns.GetSpellName(spellID) end
    return nil
end

local function RebuildActionCache()
    actionSlotsByName = {}
    for slot = 1, 120 do
        if HasAction(slot) then
            local actionType, id = GetActionInfo(slot)
            if actionType == "spell" and id then
                AddActionSlot(ns.GetSpellName(id), slot)
            elseif actionType == "macro" and id then
                AddActionSlot(GetMacroActionSpell(id), slot)
            end
        end
    end
end

local function FindThirdPartyButton(slot)
    local button = _G["BT4Button" .. slot]
    if button and button:IsVisible() then return button end
    button = _G["DominosActionButton" .. slot]
    if button and button:IsVisible() then return button end
    return nil
end

local function FindBlizzardButton(slot)
    for _, prefix in ipairs(BAR_PREFIXES) do
        for index = 1, 12 do
            local button = _G[prefix .. index]
            if button and button.action == slot and button:IsVisible() then
                return button
            end
        end
    end
    return nil
end

function ns.FindActionButtonForAbility(key)
    local name = ns.GetAbilityName(key)
    local slots = name and actionSlotsByName[name]
    if not slots then return nil end

    for _, slot in ipairs(slots) do
        local button = FindThirdPartyButton(slot) or FindBlizzardButton(slot)
        if button then return button end
    end
    return nil
end

local actionEventFrame = CreateFrame("Frame")
actionEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
actionEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
actionEventFrame:RegisterEvent("UPDATE_MACROS")
actionEventFrame:RegisterEvent("SPELLS_CHANGED")
actionEventFrame:SetScript("OnEvent", function()
    local ok, err = pcall(RebuildActionCache)
    if not ok then ns.ReportOnce("Action-bar cache", err) end
end)

local function HideGlow()
    glow:Hide()
    glowAnimation:Stop()
end

local function UpdateGlow(snapshot)
    if not ns.db.showGlow or not snapshot or not snapshot.main
        or snapshot.simulation then
        HideGlow()
        return
    end

    local button = ns.FindActionButtonForAbility(snapshot.main.ability)
    if not button then
        HideGlow()
        return
    end

    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", button, "TOPLEFT", -6, 6)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 6, -6)
    glow:Show()
    if not glowAnimation:IsPlaying() then glowAnimation:Play() end
end

-- ------------------------------------------------------------
-- Debug panel
-- ------------------------------------------------------------

local debugFrame = CreateFrame(
    "Frame",
    "MarksmanshipRotationHelperDebugFrame",
    UIParent,
    "BackdropTemplate"
)
debugFrame:SetSize(330, 20)
debugFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220)
debugFrame:SetFrameStrata("MEDIUM")
ApplyBackdrop(debugFrame, 0.80)
debugFrame:Hide()

local DEBUG_LINE_COUNT = 20
local debugLines = {}
for index = 1, DEBUG_LINE_COUNT do
    local line = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line:SetPoint("TOPLEFT", 8, -8 - (index - 1) * 12)
    line:SetJustifyH("LEFT")
    debugLines[index] = line
end

local function BuildDebugLines(snapshot)
    local s = ns.state
    local lines = {}

    table.insert(lines, "=== Marksmanship Rotation Helper " .. ns.VERSION .. " ===")
    if ns.db.testMode then
        table.insert(lines, "*** TEST MODE - SIMULATED RECOMMENDATIONS ***")
    end

    if snapshot.simulation then
        local sim = snapshot.simulation
        local simulatedState = sim.state
        local actualMain = snapshot.main and snapshot.main.ability

        table.insert(lines, "*** ROTATION SIMULATOR - NOT LIVE COMBAT ***")
        table.insert(lines, string.format(
            "Scenario: %s  Step: %d/%d",
            sim.scenarioLabel,
            sim.stepIndex,
            sim.stepTotal
        ))
        if sim.activeName == "all" then
            table.insert(lines, string.format(
                "Complete suite: %d/%d",
                sim.suiteIndex,
                sim.suiteTotal
            ))
        end
        table.insert(lines, sim.stepLabel)
        table.insert(lines, string.format(
            "Mana: %d  Targets: %d  Target HP: %.0f%%",
            simulatedState.mana,
            simulatedState.enemyCount,
            simulatedState.targetHPPercent
        ))
        table.insert(lines, "Main actual/expected: "
            .. (actualMain and (ns.GetAbilityName(actualMain) or actualMain) or "NONE")
            .. " / "
            .. (sim.expectedMain
                and (ns.GetAbilityName(sim.expectedMain) or sim.expectedMain)
                or "NONE"))
        table.insert(lines, sim.passed
            and "|cff40ff40RESULT: PASS|r"
            or "|cffff4040RESULT: FAIL - use /mrh sim check|r")
        table.insert(lines, "Use /mrh sim next or /mrh sim stop")
        return lines
    end

    table.insert(lines, string.format("Mana: %d/%d  Combat: %s  Moving: %s",
        s.mana, s.maxMana, s.inCombat and "yes" or "no", s.moving and "yes" or "no"))

    if s.targetAttackable then
        table.insert(lines, string.format("Target: %s  HP: %.0f%%  TTD: %.1fs",
            UnitName("target") or "?", s.targetHPPercent, s.targetTTD))
    else
        table.insert(lines, "Target: none/invalid")
    end

    table.insert(lines, string.format("Enemies: %d  Mode: %s  AOE: %s",
        s.enemyCount, ns.db.mode, snapshot.aoeActive and "yes" or "no"))
    table.insert(lines, string.format("Serpent Sting: %.0fs left",
        math.max(0, (s.serpentStingExpiration or 0) - GetTime())))
    table.insert(lines, string.format("GCD: %.2fs", ns.GetGCDRemaining()))

    if snapshot.main then
        table.insert(lines, "Main: " .. (ns.GetAbilityName(snapshot.main.ability) or "?"))
        table.insert(lines, "Reason: " .. (snapshot.main.reason or ""))
    else
        table.insert(lines, "Main: no action needed")
        table.insert(lines, "Reason: auto shot continues")
    end

    local coreKeys = { "SERPENT_STING", "ARCANE_SHOT", "AIMED_SHOT", "MULTI_SHOT", "STEADY_SHOT" }
    table.insert(lines, "--- Core cooldowns ---")
    for _, key in ipairs(coreKeys) do
        if ns.PlayerKnowsAbility(key) then
            table.insert(lines, string.format("%s: %.1fs",
                ns.GetAbilityName(key) or key,
                ns.GetAbilityCooldownRemaining(key, true)))
        else
            table.insert(lines, (ns.GetAbilityName(key) or key) .. ": not known")
        end
    end

    return lines
end

local function UpdateDebugPanel(snapshot)
    if not ns.db.debugMode and not snapshot.simulation then
        debugFrame:Hide()
        return
    end

    local lines = BuildDebugLines(snapshot)
    debugFrame:SetHeight(#lines * 12 + 16)
    debugFrame:Show()
    for index = 1, DEBUG_LINE_COUNT do
        debugLines[index]:SetText(lines[index] or "")
    end
end

-- ------------------------------------------------------------
-- Main UI updates and test preview
-- ------------------------------------------------------------

local testModeStartedAt = 0

local function BuildTestSnapshot()
    local keys = { "ARCANE_SHOT", "AIMED_SHOT", "MULTI_SHOT", "NONE" }
    local elapsed = GetTime() - testModeStartedAt
    local index = math.floor(elapsed / 1.5) % #keys + 1
    local key = keys[index]
    local snapshot = {
        aoeActive = false,
        enemyCount = 1,
    }

    if key ~= "NONE" then
        snapshot.main = {
            ability = key,
            reason = "Display test preview",
        }
    end
    return snapshot
end

function ns.Display_SetTestMode(enabled)
    if enabled
        and ns.Diagnostics_IsActive
        and ns.Diagnostics_IsActive()
        and ns.Diagnostics_Stop then
        ns.Diagnostics_Stop("preview")
    end
    ns.db.testMode = enabled == true
    testModeStartedAt = GetTime()
end

local function UpdateMainIcon(snapshot)
    local decision = snapshot and snapshot.main
    if not ns.db.showIcon or not decision then
        mainFrame:Hide()
        mainCooldown:SetCooldown(0, 0)
        if TooltipIsOwned(mainFrame) then GameTooltip:Hide() end
        tooltipVisible = false
        return
    end

    lastDisplaySnapshot = snapshot
    if mainTexture.SetDesaturated then mainTexture:SetDesaturated(false) end
    mainTexture:SetVertexColor(1, 1, 1, 1)
    mainTexture:SetTexture(ns.GetAbilityIcon(decision.ability))
    local identifier = ns.GetAbilityIdentifier(decision.ability)
    local start, duration = ns.GetCooldown(identifier)
    mainCooldown:SetCooldown(start or 0, duration or 0)

    if not ns.db.locked then
        SetBorder(mainFrame, COLORS.accent)
    else
        SetBorder(mainFrame, COLORS.ready)
    end
    mainFrame:Show()

    if tooltipVisible and GetTime() - tooltipLastRefresh >= 0.20 then
        if TooltipIsOwned(mainFrame) then
            ShowMainTooltip()
        else
            tooltipVisible = false
        end
    end
end

local function UpdateTestBanner(snapshot)
    local sim = snapshot and snapshot.simulation
    if sim then
        testBanner:SetBackdropBorderColor(0.20, 0.75, 1.00, 1)
        testBannerText:SetText(string.format(
            "|cff55ccffSIMULATION: %s %d/%d|r",
            sim.scenarioName:upper(),
            sim.stepIndex,
            sim.stepTotal
        ))
        testBanner:Show()
    elseif ns.db.testMode then
        testBanner:SetBackdropBorderColor(1.00, 0.20, 0.16, 1)
        testBannerText:SetText("|cffff3b30TEST MODE|r")
        testBanner:Show()
    else
        testBanner:Hide()
    end
end

local function SafeUpdate(context, func, ...)
    local ok, err = pcall(func, ...)
    if not ok then ns.ReportOnce(context, err) end
end

local function BuildSnapshot()
    if ns.Simulator_IsActive and ns.Simulator_IsActive() then
        local ok, result = pcall(ns.Simulator_GetSnapshot)
        if ok and result then return result end
        if not ok then ns.ReportOnce("Rotation simulator", result) end
    end
    if ns.db.testMode then return BuildTestSnapshot() end
    local ok, result = pcall(ns.Rotation_GetSnapshot)
    if not ok then
        ns.ReportOnce("Rotation logic", result)
        return { main = nil, aoeActive = false, enemyCount = 0 }
    end
    return result
end

function ns.Display_ApplySettings()
    if not ns.db then return end
    root:ClearAllPoints()
    root:SetPoint(
        ns.db.point or "CENTER",
        UIParent,
        ns.db.point or "CENTER",
        ns.db.x or 0,
        ns.db.y or 250
    )
    root:SetScale(ns.db.scale or 1)
    root:EnableMouse(not ns.db.locked)
    if ns.db.locked then
        unlockedText:Hide()
    else
        unlockedText:Show()
        SetBorder(mainFrame, COLORS.accent)
    end
end

-- ------------------------------------------------------------
-- Update loop
-- ------------------------------------------------------------

local elapsedUI = 0
local elapsedCooldown = 0
local ticker = CreateFrame("Frame")

ticker:SetScript("OnUpdate", function(_, elapsed)
    elapsedUI = elapsedUI + elapsed
    elapsedCooldown = elapsedCooldown + elapsed
    if elapsedUI < ns.CONFIG.UI_TICK then return end
    elapsedUI = 0

    if not ns.db then return end

    local ok, err = pcall(ns.RefreshState)
    if not ok then ns.ReportOnce("State refresh", err) end

    local snapshot = BuildSnapshot()
    SafeUpdate("Diagnostic recorder", ns.Diagnostics_Sample or function() end, snapshot)
    SafeUpdate("Main icon", UpdateMainIcon, snapshot)
    SafeUpdate("Test/simulation banner", UpdateTestBanner, snapshot)
    SafeUpdate("Action-bar glow", UpdateGlow, snapshot)
    SafeUpdate("Debug panel", UpdateDebugPanel, snapshot)

    if elapsedCooldown >= ns.CONFIG.COOLDOWN_ROW_TICK then
        elapsedCooldown = 0
        SafeUpdate("Cooldown row", UpdateCooldownRow, snapshot)
    end
end)
