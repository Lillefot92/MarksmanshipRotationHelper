-- ============================================================
-- Marksmanship Rotation Helper - Core.lua
-- Compatibility helpers, saved settings, combat state, localized
-- spell data, target tracking, Serpent Sting tracking, and mana.
--
-- This addon is an advisor. It never casts a spell or presses a
-- protected action for the player.
-- ============================================================

local ADDON_NAME, ns = ...

local BOOKTYPE_SPELL_VALUE = BOOKTYPE_SPELL or "spell"
local MANA_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

ns.MANA_POWER_TYPE = MANA_POWER_TYPE
ns.VERSION = "1.1.0"

-- Ability identity is resolved primarily by literal English spell name
-- (matched against the player's own spellbook at runtime), NOT by the
-- numeric id below. The id is only a best-effort fallback used before
-- the spellbook has been scanned once. This keeps the addon correct
-- even if a specific rank id is off, as long as the name is right.
ns.ABILITIES = {
    SERPENT_STING          = { name = "Serpent Sting",          id = 1978,  target = true },
    ARCANE_SHOT             = { name = "Arcane Shot",            id = 3044,  target = true },
    MULTI_SHOT               = { name = "Multi-Shot",              id = 2643,  target = true },
    AIMED_SHOT                = { name = "Aimed Shot",              id = 19434, target = true },
    STEADY_SHOT                = { name = "Steady Shot",             id = 34120, target = true },

    RAPID_FIRE                  = { name = "Rapid Fire",              id = 3045 },
}

ns.CONFIG = {
    -- Live game data (mana cost, cooldowns) is always preferred. These
    -- are fallbacks only, used before the game reports real numbers.
    COSTS = {
        SERPENT_STING   = 135,
        ARCANE_SHOT     = 145,
        MULTI_SHOT      = 190,
        AIMED_SHOT      = 190,
        STEADY_SHOT     = 110,
    },

    -- If Serpent Sting is not currently active, it is a safe instant
    -- filler; this only stops it being re-suggested on a target about to
    -- die anyway.
    SERPENT_STING_MIN_TTD    = 6,
    -- Tolerance for the Auto Shot clip-avoidance check below.
    STEADY_SHOT_CLIP_TOLERANCE = 0.25,
    AOE_ENEMY_THRESHOLD      = 3,
    ENEMY_MEMORY             = 3.5,
    GCD_DURATION             = 1.50,
    UI_TICK                  = 0.05,
    COOLDOWN_ROW_TICK        = 0.20,
}

ns.state = {
    playerGUID              = UnitGUID("player"),
    mana                    = 0,
    maxMana                 = 100,
    inCombat                = false,
    moving                  = false,

    targetExists             = false,
    targetAttackable         = false,
    targetGUID                = nil,
    targetHPPercent           = 100,
    targetHealth              = 0,
    targetHealthMax           = 0,
    targetTTD                 = 999,
    targetFirstSeenAt         = 0,
    targetLastSampleAt        = 0,
    targetLastHealth          = 0,
    targetSmoothedDPS         = 0,

    -- Serpent Sting is a real DoT with a live-readable expiration, applied
    -- by the player specifically (so a different Hunter's Serpent Sting on
    -- the same target is not mistaken for our own). It is a safe instant
    -- filler in this rotation, not a debuff to keep up at all costs.
    serpentStingExpiration    = 0,

    -- Auto Shot fires on its own timer, just like a melee swing. Steady
    -- Shot must be timed so it does not delay ("clip") the next Auto Shot -
    -- this is the single most important Hunter DPS mechanic, confirmed
    -- against Wowhead/Icy Veins/Warcraft Tavern before writing this addon.
    rangedSpeed                = 0,
    lastAutoShotAt             = 0,
    nextAutoShotAt             = 0,

    nearbyEnemies              = {},
    enemyCount                 = 0,
    knownSpells                 = nil,
}

-- ------------------------------------------------------------
-- Saved settings
-- ------------------------------------------------------------

local function InitDB()
    MarksmanshipRotationHelperDB = MarksmanshipRotationHelperDB or {}
    local db = MarksmanshipRotationHelperDB

    if db.schemaVersion  == nil then db.schemaVersion = 1 end
    if db.point          == nil then db.point = "CENTER" end
    if db.x              == nil then db.x = 0 end
    if db.y              == nil then db.y = 250 end
    if db.scale          == nil then db.scale = 1.0 end
    if db.showIcon       == nil then db.showIcon = true end
    if db.showGlow       == nil then db.showGlow = true end
    if db.showCooldowns  == nil then db.showCooldowns = true end
    if db.showSwingBar   == nil then db.showSwingBar = true end
    if db.showWaitIndicator == nil then db.showWaitIndicator = true end
    if db.locked         == nil then db.locked = true end
    if db.debugMode      == nil then db.debugMode = false end
    if db.testMode       == nil then db.testMode = false end
    if db.mode           == nil then db.mode = "auto" end
    if db.maintainSerpentSting == nil then db.maintainSerpentSting = true end

    if db.mode ~= "auto" and db.mode ~= "single" and db.mode ~= "aoe" then
        db.mode = "auto"
    end

    ns.db = db
end

-- ------------------------------------------------------------
-- Error reporting
-- ------------------------------------------------------------

local seenErrors = {}

function ns.ReportOnce(context, err)
    local key = tostring(context) .. ":" .. tostring(err)
    if seenErrors[key] then return end
    seenErrors[key] = true
    print("|cffff6640Marksmanship Rotation Helper|r: " .. tostring(context)
        .. " hit an error and was skipped (" .. tostring(err)
        .. "). Please report this message.")
end

-- ------------------------------------------------------------
-- WoW API compatibility helpers
-- ------------------------------------------------------------

function ns.GetSpellName(spellIdentifier)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellIdentifier)
        if ok and name then return name end
    end
    if GetSpellInfo then
        local name = GetSpellInfo(spellIdentifier)
        return name
    end
    return nil
end

function ns.GetSpellIcon(spellIdentifier)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellIdentifier)
        if ok and icon then return icon end
    end
    if GetSpellTexture then
        local icon = GetSpellTexture(spellIdentifier)
        if icon then return icon end
    end
    if GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellIdentifier)
        if icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function ns.GetSpellCastTimeMS(spellIdentifier)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellIdentifier)
        if ok and info then
            return info.castTime or 0
        end
    end
    if GetSpellInfo then
        local _, _, _, castTime = GetSpellInfo(spellIdentifier)
        return castTime or 0
    end
    return 0
end

function ns.GetCooldown(spellIdentifier)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellIdentifier)
        if ok and info then
            return info.startTime or 0, info.duration or 0, info.isEnabled
        end
    end
    if GetSpellCooldown then
        local start, duration, enabled = GetSpellCooldown(spellIdentifier)
        return start or 0, duration or 0, enabled
    end
    return 0, 0, nil
end

function ns.GetGCDInfo()
    -- 61304 is Blizzard's hidden global-cooldown spell. If it is not
    -- exposed by this client, the function safely returns no active GCD.
    return ns.GetCooldown(61304)
end

function ns.GetGCDRemaining()
    local start, duration = ns.GetGCDInfo()
    if not start or not duration or start == 0 or duration == 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

local function IsSameCooldown(startA, durationA, startB, durationB)
    if not startA or not startB or startA == 0 or startB == 0 then return false end
    return math.abs(startA - startB) <= 0.05
        and math.abs((durationA or 0) - (durationB or 0)) <= 0.05
end

function ns.GetCooldownRemaining(spellIdentifier, ignoreGCD)
    local start, duration = ns.GetCooldown(spellIdentifier)
    if start == 0 or duration == 0 then return 0 end
    if ignoreGCD then
        local gcdStart, gcdDuration = ns.GetGCDInfo()
        if IsSameCooldown(start, duration, gcdStart, gcdDuration) then
            return 0
        end
    end
    return math.max(0, start + duration - GetTime())
end

function ns.GetSpellManaCost(spellIdentifier, fallback)
    local getCosts = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    if getCosts then
        local ok, costs = pcall(getCosts, spellIdentifier)
        if ok and costs then
            for _, costInfo in ipairs(costs) do
                if costInfo.type == MANA_POWER_TYPE then
                    return costInfo.cost or fallback
                end
            end
        end
    end
    return fallback
end

function ns.GetItemSpellName(itemLink)
    if not itemLink then return nil end
    if C_Item and C_Item.GetItemSpell then
        local ok, name = pcall(C_Item.GetItemSpell, itemLink)
        if ok and name then return name end
    end
    if GetItemSpell then
        local ok, name = pcall(GetItemSpell, itemLink)
        if ok and name then return name end
    end
    return nil
end

function ns.GetItemCooldownInfo(slot)
    local start, duration, enabled = GetInventoryItemCooldown("player", slot)
    start, duration = start or 0, duration or 0
    local remaining = math.max(0, start + duration - GetTime())
    local ready = enabled ~= 0 and (start == 0 or duration == 0 or remaining <= 0.15)
    return ready, start, duration
end

-- ------------------------------------------------------------
-- Localized abilities and known ranks
-- ------------------------------------------------------------

function ns.RefreshAbilityMetadata()
    for _, ability in pairs(ns.ABILITIES) do
        -- ability.name is a literal, stable identifier set above. Only
        -- the icon needs a live lookup, and it is safe to fall back to
        -- the numeric id for that even if the id is not the current rank.
        ability.icon = ns.GetSpellIcon(ability.name) or ns.GetSpellIcon(ability.id)
    end
end

function ns.RefreshKnownSpells()
    local known = {}
    local ok = pcall(function()
        local tabCount = GetNumSpellTabs and GetNumSpellTabs() or 0
        for tab = 1, tabCount do
            local _, _, offset, spellCount = GetSpellTabInfo(tab)
            if offset and spellCount then
                for index = offset + 1, offset + spellCount do
                    local name = GetSpellBookItemName(index, BOOKTYPE_SPELL_VALUE)
                    if name then
                        local spellType, spellID
                        if GetSpellBookItemInfo then
                            spellType, spellID = GetSpellBookItemInfo(index, BOOKTYPE_SPELL_VALUE)
                        end
                        if spellType == "SPELL" or spellType == "spell" or spellType == nil then
                            known[name] = {
                                id = spellID,
                                bookIndex = index,
                            }
                        end
                    end
                end
            end
        end
    end)

    if ok and next(known) ~= nil then
        ns.state.knownSpells = known
    end
end

function ns.GetAbilityName(key)
    local ability = ns.ABILITIES[key]
    return ability and (ability.name or ns.GetSpellName(ability.id)) or nil
end

function ns.GetAbilityIcon(key)
    local ability = ns.ABILITIES[key]
    if not ability then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    return ability.icon or ns.GetSpellIcon(ability.name or ability.id)
end

function ns.GetAbilityIdentifier(key)
    local ability = ns.ABILITIES[key]
    if not ability then return nil end
    local name = ns.GetAbilityName(key)
    local known = name and ns.state.knownSpells and ns.state.knownSpells[name]
    return (known and known.id) or name or ability.id
end

function ns.PlayerKnowsAbility(key)
    local ability = ns.ABILITIES[key]
    if not ability then return false end
    local name = ns.GetAbilityName(key)
    if not ns.state.knownSpells then
        if IsPlayerSpell then
            local ok, result = pcall(IsPlayerSpell, ability.id)
            if ok and result ~= nil then return result == true end
        end
        return false
    end
    return name ~= nil and ns.state.knownSpells[name] ~= nil
end

function ns.GetAbilityCost(key)
    local identifier = ns.GetAbilityIdentifier(key)
    return ns.GetSpellManaCost(identifier, ns.CONFIG.COSTS[key] or 0)
end

function ns.GetAbilityCastTimeMS(key)
    return ns.GetSpellCastTimeMS(ns.GetAbilityIdentifier(key))
end

function ns.GetAbilityCooldownRemaining(key, ignoreGCD)
    return ns.GetCooldownRemaining(ns.GetAbilityIdentifier(key), ignoreGCD)
end

function ns.IsAbilityReady(key, tolerance)
    return ns.GetAbilityCooldownRemaining(key, true) <= (tolerance or 0.15)
end

function ns.IsAbilityInRange(key, unit)
    local ability = ns.ABILITIES[key]
    if not ability or not ability.target then return true end
    unit = unit or "target"
    local name = ns.GetAbilityName(key)
    if not name or not IsSpellInRange then return true end
    local result = IsSpellInRange(name, unit)
    return result == nil or result == 1
end

function ns.IsAbilityUsable(key)
    local identifier = ns.GetAbilityIdentifier(key)
    if not identifier or not IsUsableSpell then return true, false end
    local usable, insufficientPower = IsUsableSpell(identifier)
    return usable == true, insufficientPower == true
end

-- ------------------------------------------------------------
-- Aura helpers
-- ------------------------------------------------------------

local function CasterMatches(sourceUnit, requiredCaster)
    if not requiredCaster then return true end
    if not sourceUnit then return false end
    if UnitIsUnit then
        local ok, same = pcall(UnitIsUnit, sourceUnit, requiredCaster)
        if ok then return same == true end
    end
    return sourceUnit == requiredCaster
end

function ns.FindAura(unit, abilityOrName, harmful, requiredCaster)
    if not UnitExists(unit) then return nil end

    local name = ns.ABILITIES[abilityOrName] and ns.GetAbilityName(abilityOrName) or abilityOrName
    if not name then return nil end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local filter = harmful and "HARMFUL" or "HELPFUL"
        local index = 1
        while true do
            local data = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
            if not data then return nil end
            if data.name == name and CasterMatches(data.sourceUnit, requiredCaster) then
                return {
                    expirationTime = data.expirationTime or 0,
                    duration = data.duration or 0,
                    applications = data.applications or 0,
                    sourceUnit = data.sourceUnit,
                    spellId = data.spellId,
                }
            end
            index = index + 1
        end
    end

    local index = 1
    while true do
        local auraName, _, count, _, duration, expirationTime, sourceUnit, _, _, spellId
        if harmful then
            auraName, _, count, _, duration, expirationTime, sourceUnit, _, _, spellId = UnitDebuff(unit, index)
        else
            auraName, _, count, _, duration, expirationTime, sourceUnit, _, _, spellId = UnitBuff(unit, index)
        end
        if not auraName then return nil end
        if auraName == name and CasterMatches(sourceUnit, requiredCaster) then
            return {
                expirationTime = expirationTime or 0,
                duration = duration or 0,
                applications = count or 0,
                sourceUnit = sourceUnit,
                spellId = spellId,
            }
        end
        index = index + 1
    end
end

-- ------------------------------------------------------------
-- Enemy tracking
-- ------------------------------------------------------------

local function HasFlag(flags, flag)
    if not flags or not flag then return true end
    local bitLibrary = bit or bit32
    if not bitLibrary or not bitLibrary.band then return true end
    return bitLibrary.band(flags, flag) ~= 0
end

local function IsHostileCombatLogObject(flags)
    return HasFlag(flags, COMBATLOG_OBJECT_REACTION_HOSTILE)
end

function ns.MarkEnemy(guid, flags)
    if not guid or guid == ns.state.playerGUID then return end
    if flags and not IsHostileCombatLogObject(flags) then return end
    ns.state.nearbyEnemies[guid] = GetTime()
end

function ns.CountNearbyEnemies()
    local now = GetTime()
    local count = 0
    for guid, seenAt in pairs(ns.state.nearbyEnemies) do
        if now - seenAt > ns.CONFIG.ENEMY_MEMORY then
            ns.state.nearbyEnemies[guid] = nil
        else
            count = count + 1
        end
    end

    if ns.state.targetAttackable and ns.state.targetGUID
        and not ns.state.nearbyEnemies[ns.state.targetGUID] then
        count = math.max(1, count)
    end
    return count
end

-- ------------------------------------------------------------
-- Auto Shot swing tracking
--
-- Auto Shot fires on its own timer, exactly like a melee weapon swing.
-- Steady Shot has a real cast time, so casting it carelessly can delay
-- ("clip") the next Auto Shot and cost real DPS - this is the single
-- most-cited Hunter mechanic in TBC guides. Tracking it here lets
-- Rotation.lua check "would Steady Shot finish before the next Auto Shot
-- is due" before ever recommending it, the same way the companion
-- Warrior addon protects its post-swing Slam window.
-- ------------------------------------------------------------

local AUTO_SHOT_NAME = "Auto Shot"

function ns.GetRangedSpeed()
    if not UnitRangedDamage then return 0 end
    local speed = select(8, UnitRangedDamage("player"))
    return speed or 0
end

-- Shared with the main-hand swing math a melee rotation addon would use:
-- rescale the remaining time on a timer proportionally when the
-- underlying speed changes (e.g. Rapid Fire, a haste trinket proc).
function ns.RescaleSwingRemaining(remaining, oldSpeed, newSpeed)
    remaining = math.max(0, tonumber(remaining) or 0)
    oldSpeed = tonumber(oldSpeed) or 0
    newSpeed = tonumber(newSpeed) or 0

    if remaining <= 0 or oldSpeed <= 0 or newSpeed <= 0 then
        return remaining
    end

    local fractionRemaining = remaining / oldSpeed
    fractionRemaining = math.max(0, math.min(1, fractionRemaining))
    return fractionRemaining * newSpeed
end

function ns.UpdateRangedSpeed()
    local now = GetTime()
    local oldSpeed = ns.state.rangedSpeed or 0
    local newSpeed = ns.GetRangedSpeed()

    if newSpeed <= 0 then return end
    if oldSpeed > 0 and ns.state.nextAutoShotAt > now then
        local remaining = ns.state.nextAutoShotAt - now
        ns.state.nextAutoShotAt = now
            + ns.RescaleSwingRemaining(remaining, oldSpeed, newSpeed)
    end
    ns.state.rangedSpeed = newSpeed
end

function ns.ResetRangedTracking()
    ns.state.rangedSpeed = ns.GetRangedSpeed()
    ns.state.lastAutoShotAt = 0
    ns.state.nextAutoShotAt = 0
end

function ns.RecordAutoShot(now)
    now = now or GetTime()
    ns.UpdateRangedSpeed()
    ns.state.lastAutoShotAt = now
    ns.state.nextAutoShotAt = now + math.max(0.1, ns.state.rangedSpeed)
end

function ns.GetRangedSwingRemaining()
    if ns.state.nextAutoShotAt <= 0 then return 0 end
    return math.max(0, ns.state.nextAutoShotAt - GetTime())
end

function ns.GetRangedSwingProgress()
    local speed = ns.state.rangedSpeed or 0
    if speed <= 0 or ns.state.nextAutoShotAt <= 0 then return 0 end
    return math.max(0, math.min(1, 1 - ns.GetRangedSwingRemaining() / speed))
end

-- ------------------------------------------------------------
-- Live state refresh
-- ------------------------------------------------------------

local function ResetTargetSampling(guid, health, now)
    ns.state.targetGUID = guid
    ns.state.targetFirstSeenAt = now
    ns.state.targetLastSampleAt = now
    ns.state.targetLastHealth = health or 0
    ns.state.targetSmoothedDPS = 0
    ns.state.targetTTD = 999
end

local function UpdateTargetSampling(health, now)
    local elapsed = now - (ns.state.targetLastSampleAt or now)
    if elapsed < 0.25 then return end

    local previous = ns.state.targetLastHealth or health
    local lost = previous - health
    if lost > 0 then
        local currentDPS = lost / elapsed
        if ns.state.targetSmoothedDPS <= 0 then
            ns.state.targetSmoothedDPS = currentDPS
        else
            ns.state.targetSmoothedDPS =
                ns.state.targetSmoothedDPS * 0.65 + currentDPS * 0.35
        end
    elseif lost < 0 then
        ns.state.targetSmoothedDPS = ns.state.targetSmoothedDPS * 0.75
    end

    ns.state.targetLastHealth = health
    ns.state.targetLastSampleAt = now
    if ns.state.targetSmoothedDPS > 0 then
        ns.state.targetTTD = health / ns.state.targetSmoothedDPS
    else
        ns.state.targetTTD = 999
    end
end

local function UpdateTargetState(now)
    local exists = UnitExists("target")
        and not UnitIsDeadOrGhost("target")
        and UnitCanAttack("player", "target")

    if not exists then
        ns.state.targetExists = false
        ns.state.targetAttackable = false
        ns.state.targetGUID = nil
        ns.state.targetHPPercent = 100
        ns.state.targetHealth = 0
        ns.state.targetHealthMax = 0
        ns.state.targetTTD = 999
        ns.state.serpentStingExpiration = 0
        return
    end

    local guid = UnitGUID("target")
    local health = UnitHealth("target") or 0
    local healthMax = UnitHealthMax("target") or 0

    ns.state.targetExists = true
    ns.state.targetAttackable = true
    ns.state.targetHealth = health
    ns.state.targetHealthMax = healthMax
    ns.state.targetHPPercent = healthMax > 0 and (health / healthMax * 100) or 100

    if guid ~= ns.state.targetGUID then
        ResetTargetSampling(guid, health, now)
    else
        UpdateTargetSampling(health, now)
    end

    local serpentSting = ns.FindAura("target", "SERPENT_STING", true, "player")
    ns.state.serpentStingExpiration = serpentSting and serpentSting.expirationTime or 0

    if ns.state.inCombat and guid then
        ns.state.nearbyEnemies[guid] = now
    end
end

function ns.RefreshState()
    local now = GetTime()
    ns.state.mana = UnitPower("player", MANA_POWER_TYPE) or 0
    ns.state.maxMana = UnitPowerMax("player", MANA_POWER_TYPE) or 100
    ns.state.inCombat = not not UnitAffectingCombat("player")
    ns.state.moving = GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0 or false
    ns.UpdateRangedSpeed()
    UpdateTargetState(now)
    ns.state.enemyCount = ns.CountNearbyEnemies()
end

-- ------------------------------------------------------------
-- Combat log
-- ------------------------------------------------------------

local function EventIsPlayerAttack(subevent)
    return subevent == "SWING_DAMAGE"
        or subevent == "SWING_MISSED"
        or subevent == "SPELL_DAMAGE"
        or subevent == "SPELL_MISSED"
        or subevent == "RANGE_DAMAGE"
        or subevent == "RANGE_MISSED"
end

local function GetCombatLogAbilityKey(eventSpellName)
    if not eventSpellName then return nil end
    for key in pairs(ns.ABILITIES) do
        if eventSpellName == ns.GetAbilityName(key) then
            return key
        end
    end
    return nil
end

local function HandleCombatLogEvent()
    local cle = { CombatLogGetCurrentEventInfo() }
    local subevent = cle[2]
    local sourceGUID = cle[4]
    local sourceFlags = cle[6]
    local destGUID = cle[8]
    local destFlags = cle[10]

    if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        ns.state.nearbyEnemies[destGUID] = nil
        return
    end

    if sourceGUID == ns.state.playerGUID then
        if EventIsPlayerAttack(subevent) and destGUID then
            ns.MarkEnemy(destGUID, destFlags)
        end
        if (subevent == "RANGE_DAMAGE" or subevent == "RANGE_MISSED")
            and cle[13] == AUTO_SHOT_NAME then
            ns.RecordAutoShot(GetTime())
        end
        if subevent == "SPELL_CAST_SUCCESS" and ns.Diagnostics_AddAbilityUse then
            local abilityKey = GetCombatLogAbilityKey(cle[13])
            if abilityKey then
                ns.Diagnostics_AddAbilityUse(abilityKey, "cast")
            end
        end
    elseif destGUID == ns.state.playerGUID and EventIsPlayerAttack(subevent) then
        ns.MarkEnemy(sourceGUID, sourceFlags)
    end
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UNIT_RANGEDDAMAGE")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= ADDON_NAME then return end
        InitDB()
        ns.RefreshAbilityMetadata()
        ns.RefreshKnownSpells()
        ns.state.playerGUID = UnitGUID("player")
        ns.ResetRangedTracking()
        ns.RefreshState()
        if ns.Display_ApplySettings then ns.Display_ApplySettings() end
        print("|cff4477ffMarksmanship Rotation Helper|r " .. ns.VERSION
            .. " loaded. Type /mrh for settings.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.state.playerGUID = UnitGUID("player")
        ns.RefreshAbilityMetadata()
        ns.RefreshKnownSpells()
        ns.ResetRangedTracking()
        ns.RefreshState()
    elseif event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        ns.RefreshKnownSpells()
        ns.RefreshAbilityMetadata()
        if ns.Settings_Refresh then ns.Settings_Refresh() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.ResetRangedTracking()
    elseif event == "UNIT_RANGEDDAMAGE" then
        local unit = ...
        if unit == "player" then ns.UpdateRangedSpeed() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.Diagnostics_AddEvent then ns.Diagnostics_AddEvent("COMBAT_END") end
        ns.state.nearbyEnemies = {}
        ns.state.enemyCount = ns.state.targetAttackable and 1 or 0
        ns.ResetRangedTracking()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ns.Diagnostics_AddEvent then ns.Diagnostics_AddEvent("COMBAT_START") end
        ns.RefreshState()
    elseif event == "PLAYER_TARGET_CHANGED" then
        ns.RefreshState()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local ok, err = pcall(HandleCombatLogEvent)
        if not ok then ns.ReportOnce("Combat log handling", err) end
    end
end)

-- ------------------------------------------------------------
-- Slash commands
-- ------------------------------------------------------------

local function Trim(text)
    return (text:match("^%s*(.-)%s*$"))
end

local function RefreshSettingsPanel()
    if ns.Settings_Refresh then ns.Settings_Refresh() end
end

local function ToggleSetting(key)
    ns.db[key] = not ns.db[key]
    if ns.Display_ApplySettings then ns.Display_ApplySettings() end
    RefreshSettingsPanel()
    return ns.db[key]
end

local function OnOff(value)
    return value and "ON" or "OFF"
end

local function PrintSimulatorCheck(prefix)
    if not ns.Simulator_RunSelfCheck then
        print(prefix .. "Simulator is not available.")
        return
    end

    local passed, total, failures = ns.Simulator_RunSelfCheck()
    local color = passed == total and "|cff40ff40" or "|cffff4040"
    print(prefix .. color .. passed .. "/" .. total
        .. " simulator checks passed.|r")
    for _, failure in ipairs(failures) do
        print("  |cffff6640FAIL|r " .. failure)
    end
end

local function StartSimulator(prefix, name)
    if not ns.Simulator_Start then
        print(prefix .. "Simulator is not available.")
        return
    end

    if ns.Diagnostics_IsActive and ns.Diagnostics_IsActive()
        and ns.Diagnostics_Stop then
        ns.Diagnostics_Stop("simulator")
        print(prefix .. "Diagnostic recording stopped before simulation.")
    end

    local ok, err = ns.Simulator_Start(name)
    if not ok then
        print(prefix .. err)
        print(prefix .. "Use /mrh sim list to see available scenarios.")
        return
    end

    print(prefix .. "Simulator started: "
        .. ns.Simulator_GetScenarioLabel(name) .. ".")
    print(prefix .. "Each step lasts 3.5 seconds. Use /mrh sim next or /mrh sim stop.")
    PrintSimulatorCheck(prefix)
    RefreshSettingsPanel()
end

SLASH_MARKSMANSHIPROTATIONHELPER1 = "/mrh"
SLASH_MARKSMANSHIPROTATIONHELPER2 = "/mmhelper"

SlashCmdList["MARKSMANSHIPROTATIONHELPER"] = function(message)
    message = Trim(message or ""):lower()
    local prefix = "|cff4477ffMarksmanship Rotation Helper|r: "

    if message == "" or message == "config" or message == "options" then
        if ns.Settings_Toggle then
            ns.Settings_Toggle()
        else
            print(prefix .. "Settings panel is not available.")
        end
    elseif message == "lock" then
        ns.db.locked = true
        if ns.Display_ApplySettings then ns.Display_ApplySettings() end
        RefreshSettingsPanel()
        print(prefix .. "Locked.")
    elseif message == "unlock" then
        ns.db.locked = false
        if ns.Display_ApplySettings then ns.Display_ApplySettings() end
        RefreshSettingsPanel()
        print(prefix .. "Unlocked. Drag the main display, then use /mrh lock.")
    elseif message == "icon" then
        print(prefix .. "Main icon: " .. OnOff(ToggleSetting("showIcon")))
    elseif message == "glow" then
        print(prefix .. "Action-bar glow: " .. OnOff(ToggleSetting("showGlow")))
    elseif message == "cooldowns" then
        print(prefix .. "Cooldown and trinket row: " .. OnOff(ToggleSetting("showCooldowns")))
    elseif message == "swing" then
        print(prefix .. "Auto Shot swing bar: " .. OnOff(ToggleSetting("showSwingBar")))
    elseif message == "wait" then
        print(prefix .. "Intentional wait indicator: "
            .. OnOff(ToggleSetting("showWaitIndicator")))
    elseif message == "sting" then
        print(prefix .. "Maintain Serpent Sting: " .. OnOff(ToggleSetting("maintainSerpentSting")))
    elseif message == "debug" then
        print(prefix .. "Debug panel: " .. OnOff(ToggleSetting("debugMode")))
    elseif message == "test" then
        if ns.Simulator_IsActive and ns.Simulator_IsActive() then
            ns.Simulator_Stop()
        end
        ns.db.testMode = not ns.db.testMode
        if ns.Display_SetTestMode then ns.Display_SetTestMode(ns.db.testMode) end
        RefreshSettingsPanel()
        print(prefix .. "Display test mode: " .. OnOff(ns.db.testMode))
    elseif message == "sim" or message == "sim all" then
        StartSimulator(prefix, "all")
    elseif message == "sim stop" then
        if ns.Simulator_Stop and ns.Simulator_Stop() then
            RefreshSettingsPanel()
            print(prefix .. "Simulator stopped. Live recommendations restored.")
        else
            print(prefix .. "Simulator is already stopped.")
        end
    elseif message == "sim next" then
        if ns.Simulator_Next and ns.Simulator_Next() then
            RefreshSettingsPanel()
            print(prefix .. "Advanced to the next simulator step.")
        else
            print(prefix .. "Start it first with /mrh sim.")
        end
    elseif message == "sim check" then
        PrintSimulatorCheck(prefix)
    elseif message == "sim list" then
        local names = ns.Simulator_GetScenarioNames
            and ns.Simulator_GetScenarioNames() or {}
        print(prefix .. "Simulator scenarios:")
        print("  all - complete suite")
        for _, name in ipairs(names) do
            print("  " .. name .. " - " .. ns.Simulator_GetScenarioLabel(name))
        end
    elseif message:match("^sim%s+") then
        local name = message:match("^sim%s+(%a+)")
        StartSimulator(prefix, name)
    elseif message == "mode" then
        local order = { auto = "single", single = "aoe", aoe = "auto" }
        ns.db.mode = order[ns.db.mode] or "auto"
        RefreshSettingsPanel()
        print(prefix .. "Target mode: " .. ns.db.mode)
    elseif message:match("^mode%s+") then
        local value = message:match("^mode%s+(%a+)")
        if value == "auto" or value == "single" or value == "aoe" then
            ns.db.mode = value
            RefreshSettingsPanel()
            print(prefix .. "Target mode set to " .. value .. ".")
        else
            print(prefix .. "Use /mrh mode auto, /mrh mode single, or /mrh mode aoe.")
        end
    elseif message:match("^scale%s+") then
        local value = tonumber(message:match("^scale%s+([%d%.]+)"))
        if value and value >= 0.3 and value <= 3 then
            ns.db.scale = value
            if ns.Display_ApplySettings then ns.Display_ApplySettings() end
            RefreshSettingsPanel()
            print(prefix .. "Scale set to " .. value .. ".")
        else
            print(prefix .. "Give a number from 0.3 to 3, for example /mrh scale 1.2.")
        end
    elseif message == "reset" then
        ns.db.point, ns.db.x, ns.db.y, ns.db.scale = "CENTER", 0, 250, 1.0
        if ns.Display_ApplySettings then ns.Display_ApplySettings() end
        RefreshSettingsPanel()
        print(prefix .. "Position and scale reset.")
    elseif message == "record" or message == "record start" then
        if not ns.Diagnostics_Start then
            print(prefix .. "Diagnostic recorder is not available.")
        elseif message == "record"
            and ns.Diagnostics_IsActive
            and ns.Diagnostics_IsActive() then
            ns.Diagnostics_Stop()
            print(prefix .. "Diagnostic recording stopped. Use /mrh report.")
        else
            local ok, err = ns.Diagnostics_Start()
            if ok then
                print(prefix .. "Recording live decisions for up to 60 seconds. "
                    .. "Use /mrh record stop when finished.")
            else
                print(prefix .. tostring(err))
            end
        end
    elseif message == "record stop" then
        if ns.Diagnostics_Stop and ns.Diagnostics_Stop() then
            print(prefix .. "Diagnostic recording stopped. Use /mrh report.")
        else
            print(prefix .. "No diagnostic recording is active.")
        end
    elseif message == "record clear" then
        if ns.Diagnostics_Clear then ns.Diagnostics_Clear() end
        print(prefix .. "Diagnostic report cleared.")
    elseif message == "report" then
        if ns.Diagnostics_OpenReport then
            ns.Diagnostics_OpenReport()
        else
            print(prefix .. "Diagnostic report window is not available.")
        end
    elseif message == "debug spells" then
        local list = {}
        for name in pairs(ns.state.knownSpells or {}) do
            table.insert(list, name)
        end
        table.sort(list)
        print(prefix .. #list .. " known spellbook entries:")
        if #list > 0 then print("  " .. table.concat(list, ", ")) end
    else
        print(prefix .. "commands:")
        print("  /mrh                        - open the settings panel")
        print("  /mrh help                   - show this command list")
        print("  /mrh lock | unlock         - lock or move the display")
        print("  /mrh mode auto|single|aoe   - target-count behavior")
        print("  /mrh sting                  - toggle Serpent Sting maintenance")
        print("  /mrh icon | glow            - toggle main icon/action-bar glow")
        print("  /mrh cooldowns              - toggle cooldown and trinket row")
        print("  /mrh swing                  - toggle the Auto Shot swing bar")
        print("  /mrh wait                   - toggle intentional wait advice")
        print("  /mrh scale 1.2              - resize the complete display")
        print("  /mrh debug                  - toggle live diagnostic information")
        print("  /mrh test                   - preview the high-level display")
        print("  /mrh sim [scenario]         - run deterministic rotation scenarios")
        print("  /mrh sim next|stop|check    - control or verify the simulator")
        print("  /mrh record [start|stop]    - capture up to 60s of live decisions")
        print("  /mrh report                 - open the copyable private report")
        print("  /mrh record clear           - erase the in-memory report")
        print("  /mrh reset                  - reset display position and scale")
    end
end
