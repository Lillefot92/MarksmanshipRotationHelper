-- ============================================================
-- Marksmanship Rotation Helper - Rotation.lua
-- Shot-priority PvE rotation for Marksmanship Hunters.
--
-- TBC mechanics this priority relies on:
--   * Auto Shot fires on its own timer with no player action needed;
--     this addon never tries to model or avoid clipping it, since that
--     is not a well-established mechanic worth asserting without being
--     able to test it live.
--   * Serpent Sting is a real DoT with a live-readable expiration, so
--     maintenance works exactly like a duration-based debuff refresh.
--   * Steady Shot and Aimed Shot have a cast time and require standing
--     still; Arcane Shot and Multi-Shot are instant and usable while
--     moving. This addon downranks the two cast-time shots while moving.
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

-- ------------------------------------------------------------
-- Serpent Sting maintenance
-- ------------------------------------------------------------

local function ShouldMaintainSerpentSting()
    if not Settings().maintainSerpentSting then return nil end
    if not Knows("SERPENT_STING") then return nil end
    if not State().targetAttackable then return nil end
    if State().targetTTD < ns.CONFIG.SERPENT_STING_MIN_TTD then return nil end

    local expiration = State().serpentStingExpiration or 0
    if expiration > 0 and expiration - Now() > ns.CONFIG.SERPENT_STING_REFRESH_AT then
        return nil
    end

    if not TargetAbilityAvailable("SERPENT_STING") then return nil end
    return "SERPENT_STING"
end

-- ------------------------------------------------------------
-- Core shots
-- ------------------------------------------------------------

local function CanArcaneShot()
    return TargetAbilityAvailable("ARCANE_SHOT")
end

local function CanMultiShot()
    return TargetAbilityAvailable("MULTI_SHOT")
end

-- Aimed Shot and Steady Shot both have a cast time and require standing
-- still; casting one while moving simply fails, so they are skipped
-- entirely while moving rather than recommended and missed.
local function CanAimedShot()
    if State().moving then return false end
    return TargetAbilityAvailable("AIMED_SHOT")
end

local function CanSteadyShot()
    if State().moving then return false end
    return TargetAbilityAvailable("STEADY_SHOT")
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

local function SingleTargetDecision()
    local sting = ShouldMaintainSerpentSting()
    if sting then
        return Decision(sting, "Maintain your Serpent Sting")
    end

    if CanArcaneShot() then
        return Decision("ARCANE_SHOT", "Arcane Shot is ready")
    end

    if CanAimedShot() then
        return Decision("AIMED_SHOT", "Aimed Shot is ready")
    end

    if CanMultiShot() then
        return Decision("MULTI_SHOT", "Multi-Shot is ready")
    end

    if CanSteadyShot() then
        return Decision("STEADY_SHOT", "Filler between cooldowns")
    end

    return nil
end

local function AoeDecision()
    local sting = ShouldMaintainSerpentSting()
    if sting then
        return Decision(sting, "Maintain your Serpent Sting")
    end

    if CanMultiShot() then
        return Decision("MULTI_SHOT", "Core multi-target damage")
    end

    if CanArcaneShot() then
        return Decision("ARCANE_SHOT", "Arcane Shot is ready")
    end

    if CanAimedShot() then
        return Decision("AIMED_SHOT", "Aimed Shot is ready")
    end

    if CanSteadyShot() then
        return Decision("STEADY_SHOT", "Filler between cooldowns")
    end

    return nil
end

local function EvaluateSnapshot()
    local aoeActive, enemyCount = GetTargetMode()
    local decision

    if State().targetAttackable then
        if aoeActive then
            decision = AoeDecision()
        else
            decision = SingleTargetDecision()
        end
    end

    return {
        main = decision,
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
    if not main then return nil, "No action needed - auto shot continues", nil end
    return main.ability, main.reason, nil
end
