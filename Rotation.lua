-- ============================================================
-- Marksmanship Rotation Helper - Rotation.lua
-- Shot-priority PvE rotation for Marksmanship Hunters.
--
-- TBC mechanics this priority relies on, verified against Wowhead,
-- Icy Veins, and Warcraft Tavern's TBC Hunter guides before writing
-- this file:
--   * Auto Shot fires on its own timer, exactly like a melee swing.
--     Steady Shot has a real cast time, so it must be timed to finish
--     before the next Auto Shot is due, or it delays ("clips") that
--     Auto Shot and costs real damage. This is described as the single
--     most important Hunter DPS skill in TBC, so this addon tracks the
--     Auto Shot timer (see Core.lua) and checks it before recommending
--     Steady Shot, the same way the companion Warrior addon protects
--     its post-swing Slam window.
--   * Multi-Shot deals slightly more damage per cast than Steady Shot,
--     so it takes priority whenever it is off cooldown - in both
--     single-target and AoE, per every guide checked. Arcane Shot is
--     the next-best "replace a Steady Shot" option.
--   * Aimed Shot's long cast time makes it a pre-pull-only tool in the
--     standard rotation, not something to weave in mid-fight - doing so
--     would badly disrupt the Auto Shot timing above.
--   * Serpent Sting is not a debuff worth interrupting the shot
--     priority to maintain; it is simply a safe instant to use (while
--     moving, or when nothing else is ready) if it currently is not
--     already active.
--   * Steady Shot and Aimed Shot both require standing still; Arcane
--     Shot, Multi-Shot, and Serpent Sting are instant and usable while
--     moving.
--   * Kill Command is intentionally out of scope: it comes from the
--     Beast Mastery talent tree and needs an active pet, neither of
--     which fit a Marksmanship-focused advisor.
-- ============================================================

local ADDON_NAME, ns = ...

-- Rotation evaluation normally reads the live game APIs. The simulator
-- supplies an isolated context so the exact same priority functions can
-- be exercised without replacing or mutating ns.state.
local evaluationContext

local function State()
    return (evaluationContext and evaluationContext.state) or ns.state
end

local function Settings()
    return (evaluationContext and evaluationContext.db) or ns.db
end

local function Now()
    return (evaluationContext and evaluationContext.now) or GetTime()
end

local function AbilityCost(key)
    if evaluationContext and evaluationContext.costs
        and evaluationContext.costs[key] ~= nil then
        return evaluationContext.costs[key]
    end
    return ns.GetAbilityCost(key)
end

local function CooldownRemaining(key)
    if evaluationContext and evaluationContext.cooldowns
        and evaluationContext.cooldowns[key] ~= nil then
        return evaluationContext.cooldowns[key]
    end
    return ns.GetAbilityCooldownRemaining(key, true)
end

local function GCDRemaining()
    if evaluationContext and evaluationContext.gcdRemaining ~= nil then
        return evaluationContext.gcdRemaining
    end
    return ns.GetGCDRemaining()
end

local function SwingRemaining()
    if evaluationContext and evaluationContext.swingRemaining ~= nil then
        return evaluationContext.swingRemaining
    end
    return ns.GetRangedSwingRemaining()
end

local function Knows(key)
    if evaluationContext and evaluationContext.known then
        return evaluationContext.known[key] == true
    end
    return ns.PlayerKnowsAbility(key)
end

local function HasMana(key)
    return State().mana >= AbilityCost(key)
end

local function Ready(key, tolerance)
    return Knows(key)
        and CooldownRemaining(key) <= (tolerance or 0.15)
end

local function TargetAbilityAvailable(key, tolerance)
    if not State().targetAttackable then return false end
    if not Ready(key, tolerance) then return false end
    if not HasMana(key) then return false end
    if evaluationContext and evaluationContext.inRange
        and evaluationContext.inRange[key] ~= nil then
        return evaluationContext.inRange[key]
    end
    return ns.IsAbilityInRange(key, "target")
end

local function Decision(key, reason)
    if not key then return nil end
    return { ability = key, reason = reason or "" }
end

local function WaitDecision(reason)
    return { kind = "autoshot", reason = reason or "Wait for the next Auto Shot" }
end

-- ------------------------------------------------------------
-- Core shots
-- ------------------------------------------------------------

local function CanMultiShot()
    return TargetAbilityAvailable("MULTI_SHOT")
end

local function CanArcaneShot()
    return TargetAbilityAvailable("ARCANE_SHOT")
end

-- Steady Shot's cast time, in seconds. The simulator (and the headless
-- self-check, which never loads Core.lua at all) supplies this directly;
-- live play reads it from the actual game so haste is always accounted
-- for automatically.
local function SteadyShotCastTime()
    if evaluationContext and evaluationContext.steadyShotCastTime ~= nil then
        return evaluationContext.steadyShotCastTime
    end
    return (ns.GetAbilityCastTimeMS("STEADY_SHOT") or 0) / 1000
end

-- Steady Shot has a real cast time. Starting it only makes sense if it
-- will finish at or before the next Auto Shot is due - otherwise it
-- delays that Auto Shot and costs more damage than it gains.
local function SteadyShotWouldClip()
    local castTime = SteadyShotCastTime()
    if castTime <= 0 then return false end
    if (State().rangedSpeed or 0) <= 0 or (State().nextAutoShotAt or 0) <= 0 then
        -- No Auto Shot timer established yet (e.g. very start of the
        -- pull) - nothing to clip, so Steady Shot is always safe.
        return false
    end
    local finishesIn = GCDRemaining() + castTime
    return finishesIn - SwingRemaining() > ns.CONFIG.STEADY_SHOT_CLIP_TOLERANCE
end

-- Steady Shot and Aimed Shot both have a cast time and require standing
-- still; casting one while moving simply fails, so they are skipped
-- entirely while moving rather than recommended and missed.
local function CanSteadyShot()
    if State().moving then return false end
    if not TargetAbilityAvailable("STEADY_SHOT") then return false end
    return not SteadyShotWouldClip()
end

-- Serpent Sting is a safe instant filler, not a debuff to interrupt the
-- shot priority for. Only offer it while it is not already active.
local function CanUseSerpentSting()
    if not Settings().maintainSerpentSting then return false end
    if State().targetTTD < ns.CONFIG.SERPENT_STING_MIN_TTD then return false end
    local expiration = State().serpentStingExpiration or 0
    if expiration > Now() then return false end
    return TargetAbilityAvailable("SERPENT_STING")
end

-- Aimed Shot's cast time is too long to weave into the Auto Shot timing
-- mid-fight; the standard rotation only uses it before the pull.
local function CanPrecombatAimedShot()
    return TargetAbilityAvailable("AIMED_SHOT")
end

local function GetTargetMode()
    local count = State().enemyCount or 0
    if Settings().mode == "single" then
        return false, math.max(1, count)
    elseif Settings().mode == "aoe" then
        return true, math.max(ns.CONFIG.AOE_ENEMY_THRESHOLD, count)
    end
    return count >= ns.CONFIG.AOE_ENEMY_THRESHOLD, count
end

-- Multi-Shot and Arcane Shot outrank Steady Shot whenever they are
-- ready, in both single-target and AoE alike - every guide checked
-- agrees Multi-Shot's per-cast damage beats Steady Shot's regardless of
-- target count, so there is no separate AoE-only reordering needed.
local function CoreShotDecision()
    if CanMultiShot() then
        return Decision("MULTI_SHOT", "Replace a Steady Shot - it hits harder")
    end

    if CanArcaneShot() then
        return Decision("ARCANE_SHOT", "Replace a Steady Shot while it's on cooldown")
    end

    if CanSteadyShot() then
        return Decision("STEADY_SHOT", "Weave in after your last Auto Shot")
    end

    if CanUseSerpentSting() then
        return Decision("SERPENT_STING", "Safe instant filler")
    end

    return nil
end

local function PrecombatDecision()
    if CanPrecombatAimedShot() then
        return Decision("AIMED_SHOT", "Pre-cast before the pull - too slow to weave in combat")
    end
    return nil
end

local function EvaluateSnapshot()
    local aoeActive, enemyCount = GetTargetMode()
    local decision
    local wait

    if not State().inCombat then
        decision = PrecombatDecision()
    end

    if not decision and State().targetAttackable then
        decision = CoreShotDecision()
        if not decision then
            -- Nothing safe to cast without risking the next Auto Shot.
            wait = WaitDecision("Protecting your next Auto Shot from being clipped")
        end
    end

    return {
        main = decision,
        wait = wait,
        aoeActive = aoeActive,
        enemyCount = enemyCount,
    }
end

function ns.Rotation_GetSnapshot(context)
    local previousContext = evaluationContext
    evaluationContext = context
    local ok, result = pcall(EvaluateSnapshot)
    evaluationContext = previousContext

    if not ok then error(result, 0) end
    return result
end

-- Compatibility wrapper for older display/debug integrations.
function ns.Rotation_GetNextAbility()
    local snapshot = ns.Rotation_GetSnapshot()
    local main = snapshot.main
    if not main then
        return nil,
            snapshot.wait and snapshot.wait.reason or "No action needed - auto shot continues",
            nil
    end
    return main.ability, main.reason, nil
end
