PedAIRules = {}

function PedAIRules.ranged(weapon)
    return weapon >= 22 and weapon <= 38
end

function PedAIRules.profile(model)
    local entry = PedAIModels[model]
    -- Models outside the VCS namespace use the ordinary street pedestrian.
    local pedType, statId = 4, 13
    if entry then pedType, statId = entry[1], entry[2] end
    return setmetatable({pedType = pedType, statId = statId}, {__index = PedAIStats[statId]})
end

local function hasFlag(mask, flag)
    return flag ~= 0 and math.floor(mask / flag) % 2 == 1
end

function PedAIRules.gunshot(listener, shooter, horizontalDistance, armed, wanted)
    local group = listener.pedType
    local enemy = PedAITypes[shooter.pedType]
    local threats = listener.threats or PedAITypes[group].threats
    if not hasFlag(threats, 0x100000) or group == shooter.pedType and group ~= 4 and group ~= 5 then return end

    if group == 16 and shooter.pedType == 0 then return "flee", "run", 6000 end
    if group == 6 then
        if shooter.pedType == 6 then return end
        if wanted then return "fight", "run", 20000 end
        return "look", "walk", 1000
    end
    if group >= 7 and group <= 15 then
        -- 0x001EFFB0 returns the shooter's type bit in place of the gun flag.
        if group ~= 11 and not hasFlag(threats, enemy.identity) then return end
        if enemy.identity == 0 then return end
        if listener.fear > 100 - shooter.temper or shooter.pedType == 6 then return "flee", "run", 10000 end
        if armed then return "fight", "run", 20000 end
        return
    end

    -- Civilian specific dispatch in 0x002D9D18.
    if listener.fear > listener.law then
        if horizontalDistance < 30 then return "flee", "sprint", 10000 end
        return "flee", "run", 5000
    elseif listener.temper > listener.fear then
        if armed then return "fight", "run", 20000 end
        return "flee", horizontalDistance < 20 and "run" or "walk", 5000
    elseif horizontalDistance < 30 then
        return "flee", "run", 10000
    end
    return "flee", "walk", 5000
end

function PedAIRules.evadeAnimation(profile)
    return hasFlag(profile.flags, 0x10) and "EV_step" or "EV_dive"
end

local protectedGroup = {[6]=true,[10]=true,[11]=true}

function PedAIRules.intent(kind, self, attacker, rangedAttack, rangedDefense)
    if kind == "carjack" then
        -- Driver branch 0x002FDCB0, objective 8 targets the jacker.
        return self.temper > self.fear and "fight" or "flee"
    elseif kind == "passenger" then
        -- 0x003EF018 schedules the seat exits. Continue away from the incident on the MTA path graph.
        return "flee"
    elseif kind == "witness" or kind == "ally" then
        -- 0x0030A520 tests the actual linked leader, excludes police aggressors,
        -- and puts willing followers on objective 8 for 30000 ms.
        if kind == "ally" and attacker.pedType ~= 6 and self.temper > self.fear then return "fight" end
        if self.pedType == 6 and attacker.pedType ~= 6 then return "fight" end
        if self.fear > 100 - attacker.temper or rangedAttack and not rangedDefense then return "flee" end
        return nil
    end
    -- Direct attack selector 0x002201A0. The strict inequality matters on a tie.
    if self.fear > 100 - attacker.temper then return "flee" end
    if self.statId == attacker.statId then return nil end
    if protectedGroup[self.pedType] and protectedGroup[attacker.pedType] then return "flee" end
    if rangedAttack and not rangedDefense then return "flee" end
    return "fight"
end

-- MTA inventory counterparts. Both Ingram variants and the PS2 heavy weapons
-- share host inventory slots, so use the ordinary model for that host weapon.
local vcsWeapon = {[22]=19,[23]=19,[24]=20,[25]=21,[26]=23,[27]=22,[28]=25,
    [29]=27,[30]=28,[31]=29,[32]=24,[33]=30,[34]=31,[35]=32,[36]=32,[37]=33,[38]=35}
function PedAIRules.attackRange(weapon)
    local id = vcsWeapon[weapon]
    return id and PedAIWeaponRange[id] or 1.7
end
