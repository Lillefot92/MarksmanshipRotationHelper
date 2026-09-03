-- ============================================================
-- Marksmanship Rotation Helper - Diagnostics.lua
-- Opt-in, privacy-safe live recorder and copyable report window.
--
-- Reports never read or store character, realm, account, target
-- names, chat text, unit GUIDs, or item links. Recording exists
-- only in memory and stops automatically after 60 seconds.
-- ============================================================

local ADDON_NAME, ns = ...

local RECORDING_SECONDS = 60
local HEARTBEAT_SECONDS = 0.50
local MAX_ENTRIES = 500

local runtime = {
    active = false,
    startedAt = 0,
    stoppedAt = 0,
    entries = {},
    metadata = nil,
    lastSampleAt = 0,
    lastSignature = nil,
}

local reportFrame
local reportEditBox

local EVENT_LABELS = {
    COMBAT_START = "combat-start",
    COMBAT_END = "combat-end",
    RECORDING_START = "recording-start",
    RECORDING_STOP = "recording-stop",
    RECORDING_COMPLETE = "recording-complete",
}

local STOP_LABELS = {
    manual = "recording-stop",
    simulator = "recording-stop-for-simulator",
    preview = "recording-stop-for-preview",
}

local ABILITY_PHASES = {
    cast = true,
}

local function BooleanText(value)
    return value and "yes" or "no"
end

local function Number(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    return value
end

local function CleanText(value)
    value = tostring(value or "")
    value = value:gsub("[\r\n\t]", " ")
    value = value:gsub("%s+", " ")
    return value:sub(1, 160)
end

local function Append(entry)
    table.insert(runtime.entries, entry)
    if #runtime.entries > MAX_ENTRIES then
        table.remove(runtime.entries, 1)
    end
end

local function Elapsed(now)
    if runtime.startedAt <= 0 then return 0 end
    return math.max(0, Number(now, GetTime()) - runtime.startedAt)
end

local function AppendEventLabel(label, value, now)
    Append({
        kind = "event",
        elapsed = math.min(RECORDING_SECONDS, Elapsed(now)),
        label = label,
        value = type(value) == "number" and value or nil,
    })
end

local function CaptureMetadata()
    local clientVersion, clientBuild, _, interfaceVersion
    if GetBuildInfo then
        clientVersion, clientBuild, _, interfaceVersion = GetBuildInfo()
    end

    local db = ns.db or {}
    return {
        addonVersion = ns.VERSION or "unknown",
        clientVersion = clientVersion or "unknown",
        clientBuild = clientBuild or "unknown",
        interfaceVersion = interfaceVersion or "unknown",
        level = UnitLevel and UnitLevel("player") or 0,
        mode = CleanText(db.mode or "auto"),
        maintainSerpentSting = db.maintainSerpentSting == true,
        showCooldowns = db.showCooldowns == true,
    }
end

local function RefreshSettings()
    if ns.Settings_Refresh then ns.Settings_Refresh() end
end

local function StopInternal(reason, now)
    if not runtime.active then return false end
    now = now or GetTime()
    AppendEventLabel(
        STOP_LABELS[reason] or STOP_LABELS.manual,
        nil,
        now
    )
    runtime.active = false
    runtime.stoppedAt = now
    RefreshSettings()
    return true
end

local function CompleteRecording(now)
    if not runtime.active then return false end
    AppendEventLabel(EVENT_LABELS.RECORDING_COMPLETE, nil, now)
    runtime.active = false
    runtime.stoppedAt = now
    RefreshSettings()
    print("|cff4477ffMarksmanship Rotation Helper|r: Diagnostic recording complete. "
        .. "Use /mrh report to copy it.")
    return true
end

function ns.Diagnostics_IsActive()
    return runtime.active
end

function ns.Diagnostics_Start()
    if runtime.active then
        return false, "A diagnostic recording is already active."
    end
    if ns.Simulator_IsActive and ns.Simulator_IsActive() then
        return false, "Stop the rotation simulator before recording live data."
    end
    if ns.db and ns.db.testMode then
        return false, "Stop display preview before recording live data."
    end

    runtime.active = true
    runtime.startedAt = GetTime()
    runtime.stoppedAt = 0
    runtime.entries = {}
    runtime.metadata = CaptureMetadata()
    runtime.lastSampleAt = 0
    runtime.lastSignature = nil
    AppendEventLabel(EVENT_LABELS.RECORDING_START, nil, runtime.startedAt)
    RefreshSettings()
    return true
end

function ns.Diagnostics_Stop(reason)
    return StopInternal(reason or "manual", GetTime())
end

function ns.Diagnostics_Clear()
    runtime.active = false
    runtime.startedAt = 0
    runtime.stoppedAt = 0
    runtime.entries = {}
    runtime.metadata = nil
    runtime.lastSampleAt = 0
    runtime.lastSignature = nil
    RefreshSettings()
end

function ns.Diagnostics_AddEvent(kind, numericValue)
    if not runtime.active then return false end
    local label = EVENT_LABELS[kind]
    if not label then return false end

    local now = GetTime()
    if Elapsed(now) >= RECORDING_SECONDS then
        CompleteRecording(now)
        return false
    end

    AppendEventLabel(label, tonumber(numericValue), now)
    return true
end

function ns.Diagnostics_AddAbilityUse(abilityKey, phase)
    if not runtime.active then return false end
    if type(abilityKey) ~= "string"
        or not ns.ABILITIES
        or not ns.ABILITIES[abilityKey] then
        return false
    end
    if not ABILITY_PHASES[phase] then return false end

    local now = GetTime()
    if Elapsed(now) >= RECORDING_SECONDS then
        CompleteRecording(now)
        return false
    end

    Append({
        kind = "ability",
        elapsed = Elapsed(now),
        ability = abilityKey,
        phase = phase,
    })
    return true
end

local function SnapshotSignature(snapshot, state)
    return table.concat({
        snapshot.main and snapshot.main.ability or "NONE",
        snapshot.main and snapshot.main.reason or "",
        state.inCombat and "1" or "0",
        state.targetAttackable and "1" or "0",
        snapshot.aoeActive and "1" or "0",
        state.moving and "1" or "0",
    }, "|")
end

function ns.Diagnostics_Sample(snapshot)
    if not runtime.active or not snapshot then return end

    local now = GetTime()
    if Elapsed(now) >= RECORDING_SECONDS then
        CompleteRecording(now)
        return
    end

    -- Simulated and preview data are intentionally excluded from live reports.
    if snapshot.simulation or (ns.db and ns.db.testMode) then return end

    local state = ns.state or {}
    local signature = SnapshotSignature(snapshot, state)

    if signature == runtime.lastSignature
        and now - runtime.lastSampleAt < HEARTBEAT_SECONDS then
        return
    end

    runtime.lastSignature = signature
    runtime.lastSampleAt = now
    Append({
        kind = "sample",
        elapsed = Elapsed(now),
        main = snapshot.main and snapshot.main.ability or "NONE",
        reason = snapshot.main and CleanText(snapshot.main.reason) or "",
        mana = Number(state.mana, 0),
        targetHP = Number(state.targetHPPercent, 100),
        targetTTD = math.min(999, Number(state.targetTTD, 999)),
        enemies = Number(snapshot.enemyCount or state.enemyCount, 0),
        stingRemaining = math.max(0, Number(state.serpentStingExpiration, 0) - now),
        combat = state.inCombat == true,
        moving = state.moving == true,
        aoe = snapshot.aoeActive == true,
    })
end

function ns.Diagnostics_GetStatus()
    local now = runtime.active and GetTime()
        or (runtime.stoppedAt > 0 and runtime.stoppedAt or runtime.startedAt)
    local duration = math.min(RECORDING_SECONDS, Elapsed(now))
    return {
        active = runtime.active,
        duration = duration,
        remaining = runtime.active
            and math.max(0, RECORDING_SECONDS - duration) or 0,
        entryCount = #runtime.entries,
        hasReport = runtime.metadata ~= nil and #runtime.entries > 0,
    }
end

local function SettingLine(label, value)
    return label .. ": " .. tostring(value)
end

function ns.Diagnostics_GetReport()
    local metadata = runtime.metadata
    if not metadata then
        return table.concat({
            "Marksmanship Rotation Helper diagnostic report",
            "No recording is available.",
            "",
            "Use /mrh record, fight normally for up to 60 seconds, then "
                .. "use /mrh report.",
        }, "\n")
    end

    local status = ns.Diagnostics_GetStatus()
    local lines = {
        "Marksmanship Rotation Helper diagnostic report",
        "Privacy: contains no player, realm, account, or target names; "
            .. "no chat, GUIDs, or item links.",
        SettingLine("Addon", metadata.addonVersion),
        SettingLine("Client", metadata.clientVersion
            .. " build " .. metadata.clientBuild
            .. " interface " .. metadata.interfaceVersion),
        SettingLine("Level", metadata.level),
        SettingLine("Recording duration", string.format("%.1fs", status.duration)),
        SettingLine("Entries", status.entryCount),
        SettingLine("Target mode", metadata.mode),
        SettingLine("Maintain Serpent Sting", BooleanText(metadata.maintainSerpentSting)),
        SettingLine("Cooldown row", BooleanText(metadata.showCooldowns)),
        "",
        "Row types: E=anonymous event, A=ability use, S=state sample.",
        "State columns:",
        "time S main mana hp% ttd enemies stingLeft gcd combat moving aoe reason",
    }

    for _, entry in ipairs(runtime.entries) do
        if entry.kind == "event" then
            table.insert(lines, string.format(
                "%.2f E %s %s",
                entry.elapsed,
                entry.label,
                entry.value and string.format("%.2f", entry.value) or "-"
            ))
        elseif entry.kind == "ability" then
            table.insert(lines, string.format(
                "%.2f A %s %s",
                entry.elapsed,
                entry.ability,
                entry.phase
            ))
        else
            table.insert(lines, string.format(
                "%.2f S %s %d %.1f %.1f %d %.1f %s %s %s %s",
                entry.elapsed,
                entry.main,
                entry.mana,
                entry.targetHP,
                entry.targetTTD,
                entry.enemies,
                entry.stingRemaining,
                BooleanText(entry.combat),
                BooleanText(entry.moving),
                BooleanText(entry.aoe),
                entry.reason ~= "" and entry.reason or "-"
            ))
        end
    end

    return table.concat(lines, "\n")
end

local function CreateReportWindow()
    if reportFrame then return end

    reportFrame = CreateFrame(
        "Frame",
        "MarksmanshipRotationHelperReportFrame",
        UIParent,
        "BackdropTemplate"
    )
    reportFrame:SetSize(700, 520)
    reportFrame:SetPoint("CENTER")
    reportFrame:SetFrameStrata("DIALOG")
    reportFrame:SetClampedToScreen(true)
    reportFrame:SetMovable(true)
    reportFrame:EnableMouse(true)
    reportFrame:RegisterForDrag("LeftButton")
    reportFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 },
    })
    reportFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    reportFrame:SetScript(
        "OnDragStop",
        function(self) self:StopMovingOrSizing() end
    )
    reportFrame:Hide()

    local close = CreateFrame(
        "Button",
        nil,
        reportFrame,
        "UIPanelCloseButton"
    )
    close:SetPoint("TOPRIGHT", reportFrame, "TOPRIGHT", -4, -4)

    local title = reportFrame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalLarge"
    )
    title:SetPoint("TOPLEFT", reportFrame, "TOPLEFT", 24, -22)
    title:SetText("Privacy-safe diagnostic report")

    local instructions = reportFrame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlightSmall"
    )
    instructions:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    instructions:SetWidth(650)
    instructions:SetJustifyH("LEFT")
    instructions:SetText(
        "The report is selected automatically. Press Ctrl+C to copy it, "
            .. "then paste it to your tester message or bug report."
    )

    local scroll = CreateFrame(
        "ScrollFrame",
        "MarksmanshipRotationHelperReportScrollFrame",
        reportFrame,
        "UIPanelScrollFrameTemplate"
    )
    scroll:SetPoint("TOPLEFT", reportFrame, "TOPLEFT", 24, -78)
    scroll:SetPoint("BOTTOMRIGHT", reportFrame, "BOTTOMRIGHT", -46, 24)

    reportEditBox = CreateFrame("EditBox", nil, scroll)
    reportEditBox:SetMultiLine(true)
    reportEditBox:SetAutoFocus(false)
    reportEditBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    reportEditBox:SetWidth(620)
    reportEditBox:SetMaxLetters(0)
    reportEditBox:SetScript(
        "OnEscapePressed",
        function(self) self:ClearFocus() end
    )
    scroll:SetScrollChild(reportEditBox)

    if UISpecialFrames then
        table.insert(UISpecialFrames, reportFrame:GetName())
    end
end

function ns.Diagnostics_OpenReport()
    CreateReportWindow()
    local report = ns.Diagnostics_GetReport()
    local _, lineCount = report:gsub("\n", "\n")
    reportEditBox:SetHeight(math.max(400, (lineCount + 2) * 14))
    reportEditBox:SetText(report)
    reportFrame:Show()
    reportEditBox:SetFocus()
    reportEditBox:HighlightText()
end
