-- ============================================================
-- Marksmanship Rotation Helper - Simulator.lua
-- Deterministic, non-combat scenarios for exercising the real
-- rotation evaluator without touching the player's live state.
-- Doubles as this addon's self-check suite, since the author
-- cannot playtest a level-70 Marksmanship Hunter directly.
-- ============================================================

local ADDON_NAME, ns = ...

local STEP_DURATION = 3.5

-- Arcane Shot and Steady Shot are trainer-taught early; Multi-Shot and
-- Aimed Shot come later, so a leveling loadout may not have them yet.
local BASE_KNOWN = {
    "SERPENT_STING",
    "ARCANE_SHOT",
    "STEADY_SHOT",
}

local FULL_KNOWN = {
    "SERPENT_STING",
    "ARCANE_SHOT",
    "MULTI_SHOT",
    "AIMED_SHOT",
    "STEADY_SHOT",
    "RAPID_FIRE",
}

local SCENARIO_ORDER = {
    "sting",
    "core",
    "moving",
    "aoe",
}

local SCENARIO_LABELS = {
    sting = "Serpent Sting maintenance",
    core = "Arcane / Aimed / Multi-Shot priority",
    moving = "Moving gates cast-time shots",
    aoe = "AoE / Multi-Shot priority",
    all = "Complete suite",
}

local scenarios = {
    sting = {
        {
            label = "No Serpent Sting on target: apply it first",
            state = { serpentStingExpiration = false },
            cooldowns = { SERPENT_STING = 0, ARCANE_SHOT = 0 },
            expectedMain = "SERPENT_STING",
        },
        {
            label = "Serpent Sting about to expire: refresh proactively",
            stingExpiresIn = 2,
            cooldowns = { SERPENT_STING = 0, ARCANE_SHOT = 0 },
            expectedMain = "SERPENT_STING",
        },
        {
            label = "Serpent Sting has plenty of time left: use Arcane Shot",
            stingExpiresIn = 15,
            cooldowns = { SERPENT_STING = 0, ARCANE_SHOT = 0 },
            expectedMain = "ARCANE_SHOT",
        },
        {
            label = "Skipped on a target about to die anyway",
            state = { targetTTD = 3, serpentStingExpiration = false },
            cooldowns = { SERPENT_STING = 0, ARCANE_SHOT = 4 },
            expectedMain = nil,
        },
        {
            label = "Disabled via settings: never recommended",
            state = { serpentStingExpiration = false },
            cooldowns = {
                SERPENT_STING = 0,
                ARCANE_SHOT = 4,
                AIMED_SHOT = 4,
                MULTI_SHOT = 4,
                STEADY_SHOT = 0,
            },
            maintainSerpentSting = false,
            expectedMain = "STEADY_SHOT",
        },
    },
    core = {
        {
            label = "Arcane Shot outranks Aimed Shot and Multi-Shot",
            cooldowns = { ARCANE_SHOT = 0, AIMED_SHOT = 0, MULTI_SHOT = 0 },
            expectedMain = "ARCANE_SHOT",
        },
        {
            label = "Aimed Shot fills when Arcane Shot is down",
            cooldowns = { ARCANE_SHOT = 4, AIMED_SHOT = 0, MULTI_SHOT = 0 },
            expectedMain = "AIMED_SHOT",
        },
        {
            label = "Multi-Shot fills when Arcane and Aimed are down",
            cooldowns = { ARCANE_SHOT = 4, AIMED_SHOT = 4, MULTI_SHOT = 0 },
            expectedMain = "MULTI_SHOT",
        },
        {
            label = "Steady Shot fills when nothing else is ready",
            cooldowns = { ARCANE_SHOT = 4, AIMED_SHOT = 4, MULTI_SHOT = 4, STEADY_SHOT = 0 },
            expectedMain = "STEADY_SHOT",
        },
        {
            label = "Insufficient mana for Arcane Shot falls through to Steady Shot",
            state = { mana = 120 },
            cooldowns = { ARCANE_SHOT = 0, AIMED_SHOT = 4, MULTI_SHOT = 4, STEADY_SHOT = 0 },
            expectedMain = "STEADY_SHOT",
        },
        {
            label = "Leveling loadout without Aimed/Multi-Shot still fills with Steady Shot",
            known = BASE_KNOWN,
            cooldowns = { ARCANE_SHOT = 4, STEADY_SHOT = 0 },
            expectedMain = "STEADY_SHOT",
        },
    },
    moving = {
        {
            label = "Moving still allows the instant Arcane Shot",
            state = { moving = true },
            cooldowns = { ARCANE_SHOT = 0, AIMED_SHOT = 0, STEADY_SHOT = 0 },
            expectedMain = "ARCANE_SHOT",
        },
        {
            label = "Moving still allows the instant Multi-Shot",
            state = { moving = true },
            cooldowns = { ARCANE_SHOT = 4, MULTI_SHOT = 0 },
            expectedMain = "MULTI_SHOT",
        },
        {
            label = "Moving with only cast-time shots ready: no action",
            state = { moving = true },
            cooldowns = { ARCANE_SHOT = 4, MULTI_SHOT = 4, AIMED_SHOT = 0, STEADY_SHOT = 0 },
            expectedMain = nil,
        },
    },
    aoe = {
        {
            label = "Two enemies stay in single-target mode",
            state = { enemyCount = 2 },
            cooldowns = { ARCANE_SHOT = 0, MULTI_SHOT = 0 },
            expectedMain = "ARCANE_SHOT",
            expectedAoe = false,
        },
        {
            label = "Three enemies switch to AoE and lead with Multi-Shot",
            state = { enemyCount = 3 },
            cooldowns = { ARCANE_SHOT = 0, MULTI_SHOT = 0 },
            expectedMain = "MULTI_SHOT",
            expectedAoe = true,
        },
        {
            label = "AoE still maintains Serpent Sting first",
            state = { enemyCount = 3, serpentStingExpiration = false },
            cooldowns = { SERPENT_STING = 0, MULTI_SHOT = 0 },
            expectedMain = "SERPENT_STING",
            expectedAoe = true,
        },
        {
            label = "Forced single-target mode ignores enemy count",
            mode = "single",
            state = { enemyCount = 5 },
            cooldowns = { ARCANE_SHOT = 0, MULTI_SHOT = 0 },
            expectedMain = "ARCANE_SHOT",
            expectedAoe = false,
        },
        {
            label = "Forced AoE mode engages even with one enemy",
            mode = "aoe",
            state = { enemyCount = 1 },
            cooldowns = { ARCANE_SHOT = 0, MULTI_SHOT = 0 },
            expectedMain = "MULTI_SHOT",
            expectedAoe = true,
        },
    },
}

local runtime = {
    active = false,
    name = nil,
    stepIndex = 1,
    stepStartedAt = 0,
}

local function CopyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function KnownSet(list)
    local result = {}
    for _, key in ipairs(list or FULL_KNOWN) do result[key] = true end
    return result
end

local function BuildContext(step)
    local now = GetTime()
    local known = KnownSet(step.known)
    local cooldowns = {}
    local inRange = {}
    local costs = {}

    for key in pairs(known) do
        cooldowns[key] = 99
        inRange[key] = true
        costs[key] = ns.CONFIG.COSTS[key] or 0
    end
    for key, value in pairs(step.cooldowns or {}) do cooldowns[key] = value end

    local state = {
        mana = 1000,
        maxMana = 2000,
        inCombat = true,
        moving = false,

        targetExists = true,
        targetAttackable = true,
        targetGUID = "MRH_SIM_TARGET",
        targetHPPercent = 80,
        targetHealth = 80000,
        targetHealthMax = 100000,
        targetTTD = 60,

        serpentStingExpiration = now + 15,

        enemyCount = 1,
    }

    for key, value in pairs(CopyTable(step.state)) do state[key] = value end

    -- Expiration timers are relative to `now`, which only exists once
    -- BuildContext runs, so scenarios request them via a delta instead
    -- of a raw state override.
    if step.stingExpiresIn ~= nil then
        state.serpentStingExpiration = now + step.stingExpiresIn
    end

    return {
        now = now,
        state = state,
        db = {
            mode = step.mode or "auto",
            maintainSerpentSting = step.maintainSerpentSting ~= false,
        },
        known = known,
        costs = costs,
        cooldowns = cooldowns,
        inRange = inRange,
        gcdRemaining = step.gcdRemaining or 0,
    }
end

local function GetScenarioSteps(name)
    if name ~= "all" then return scenarios[name] end

    local result = {}
    for _, scenarioName in ipairs(SCENARIO_ORDER) do
        for _, step in ipairs(scenarios[scenarioName]) do
            table.insert(result, step)
        end
    end
    return result
end

for scenarioName, steps in pairs(scenarios) do
    for index, step in ipairs(steps) do
        step.scenarioName = scenarioName
        step.scenarioIndex = index
        step.scenarioTotal = #steps
    end
end

local function ActualAbility(decision)
    return decision and decision.ability or nil
end

local function StepPassed(step, snapshot)
    local actualMain = ActualAbility(snapshot.main)
    if actualMain ~= step.expectedMain then return false end
    if step.expectedAoe ~= nil and snapshot.aoeActive ~= step.expectedAoe then
        return false
    end
    return true
end

local function DescribeResult(step, snapshot)
    local expectedMain = step.expectedMain or "WAIT"
    local actualMain = ActualAbility(snapshot.main) or "WAIT"
    return string.format(
        "%s: main %s/%s%s",
        step.label,
        actualMain,
        expectedMain,
        step.expectedAoe ~= nil
            and string.format(", aoe %s/%s", tostring(snapshot.aoeActive), tostring(step.expectedAoe))
            or ""
    )
end

function ns.Simulator_GetScenarioNames()
    local result = {}
    for _, name in ipairs(SCENARIO_ORDER) do table.insert(result, name) end
    return result
end

function ns.Simulator_GetScenarioLabel(name)
    return SCENARIO_LABELS[name] or name
end

function ns.Simulator_IsActive()
    return runtime.active
end

function ns.Simulator_Start(name)
    name = name or "all"
    if name ~= "all" and not scenarios[name] then
        return false, "Unknown scenario '" .. tostring(name) .. "'."
    end

    if ns.Diagnostics_IsActive and ns.Diagnostics_IsActive()
        and ns.Diagnostics_Stop then
        ns.Diagnostics_Stop("simulator")
    end

    runtime.active = true
    runtime.name = name
    runtime.stepIndex = 1
    runtime.stepStartedAt = GetTime()
    if ns.db and ns.db.testMode and ns.Display_SetTestMode then
        ns.Display_SetTestMode(false)
    end
    return true
end

function ns.Simulator_Stop()
    local wasActive = runtime.active
    runtime.active = false
    runtime.name = nil
    runtime.stepIndex = 1
    runtime.stepStartedAt = 0
    return wasActive
end

function ns.Simulator_Next()
    if not runtime.active then return false end
    local steps = GetScenarioSteps(runtime.name)
    runtime.stepIndex = runtime.stepIndex % #steps + 1
    runtime.stepStartedAt = GetTime()
    return true
end

function ns.Simulator_GetStatus()
    if not runtime.active then return nil end
    local steps = GetScenarioSteps(runtime.name)
    local step = steps[runtime.stepIndex]
    return {
        name = runtime.name,
        label = SCENARIO_LABELS[runtime.name],
        stepIndex = runtime.stepIndex,
        stepTotal = #steps,
        stepLabel = step and step.label,
    }
end

function ns.Simulator_GetSnapshot()
    if not runtime.active then return nil end

    local steps = GetScenarioSteps(runtime.name)
    local now = GetTime()
    local elapsed = now - runtime.stepStartedAt
    if elapsed >= STEP_DURATION then
        local advances = math.floor(elapsed / STEP_DURATION)
        runtime.stepIndex = (runtime.stepIndex - 1 + advances) % #steps + 1
        runtime.stepStartedAt = runtime.stepStartedAt + advances * STEP_DURATION
        elapsed = now - runtime.stepStartedAt
    end

    local step = steps[runtime.stepIndex]
    local context = BuildContext(step)
    local snapshot = ns.Rotation_GetSnapshot(context)
    local passed = StepPassed(step, snapshot)

    snapshot.simulation = {
        activeName = runtime.name,
        scenarioName = step.scenarioName,
        scenarioLabel = SCENARIO_LABELS[step.scenarioName],
        stepIndex = step.scenarioIndex,
        stepTotal = step.scenarioTotal,
        suiteIndex = runtime.stepIndex,
        suiteTotal = #steps,
        stepLabel = step.label,
        expectedMain = step.expectedMain,
        passed = passed,
        detail = DescribeResult(step, snapshot),
        state = context.state,
        stepProgress = math.min(1, elapsed / STEP_DURATION),
    }
    return snapshot
end

function ns.Simulator_RunSelfCheck()
    local passed = 0
    local total = 0
    local failures = {}

    for _, scenarioName in ipairs(SCENARIO_ORDER) do
        for _, step in ipairs(scenarios[scenarioName]) do
            total = total + 1
            local snapshot = ns.Rotation_GetSnapshot(BuildContext(step))
            if StepPassed(step, snapshot) then
                passed = passed + 1
            else
                table.insert(failures, DescribeResult(step, snapshot))
            end
        end
    end
    return passed, total, failures
end
