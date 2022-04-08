PED_GROUP = {
    ["PLAYER"] = {
        Respect = {},
        Hate = {},
        Decision = nil,
    },
    ["DEFAULT"] = {
        Respect = {},
        Hate = {},
        Decision = "excuteAIDecisionDefault",
    },
    ["CIVMALE"] = {
        Respect = {},
        Hate = {},
        Decision = "excuteAIDecisionWeak",
    },
    ["CIVFEMALE"] = {
        Respect = {},
        Hate = {},
        Decision = "excuteAIDecisionWeak",
    },
    ["COP"] = {
        Respect = {
            "MEDIC",
            "FIREMAN",
            "COP",
            "COP_2",
            "SWAT",
            "FBI",
            "ARMY",
            "TANK",
        },
        Hate = {
            "CRIMINAL",
            "DEALER",
        },
        WeaponRandom = {
            {3,1},
            {22,30},
        },
        Decision = "excuteAIDecisionCop",
    },
    ["COP_2"] = {
        Respect = {
            "MEDIC",
            "FIREMAN",
            "COP",
            "COP_2",
            "SWAT",
            "FBI",
            "ARMY",
            "TANK",
        },
        Hate = {
            "CRIMINAL",
            "DEALER",
        },
        Weapon = {
            {25,30},
        },
        Decision = "excuteAIDecisionCop",
    },
    ["SWAT"] = {
        Respect = {
            "MEDIC",
            "FIREMAN",
            "COP",
            "COP_2",
            "SWAT",
            "FBI",
            "ARMY",
            "TANK",
        },
        Hate = {
            "CRIMINAL",
            "DEALER",
        },
        Weapon = {
            {31,100},
        },
        --[[
        WeaponRandom = {
            {31,500},
        },
        ]]
        Decision = "excuteAIDecisionCop",
    },
    ["FBI"] = {
        Respect = {
            "MEDIC",
            "FIREMAN",
            "COP",
            "COP_2",
            "SWAT",
            "FBI",
            "ARMY",
            "TANK",
        },
        Hate = {
            "CRIMINAL",
            "DEALER",
        },
        Weapon = {
            {29,100},
        },
        --[[
        WeaponRandom = {
            {31,500},
        },
        ]]
        Decision = "excuteAIDecisionCop",
    },
    ["ARMY"] = {
        Respect = {
            "MEDIC",
            "FIREMAN",
            "COP",
            "COP_2",
            "SWAT",
            "FBI",
            "ARMY",
            "TANK",
        },
        Hate = {
            "CRIMINAL",
            "DEALER",
        },
        Weapon = {
            {31,100},
        },
        --[[
        WeaponRandom = {
            {31,500},
        },
        ]]
        Decision = "excuteAIDecisionCop",
    },
    ["TANK"] = {
        Respect = {
            "MEDIC",
            "FIREMAN",
            "COP",
            "COP_2",
            "SWAT",
            "FBI",
            "ARMY",
            "TANK",
        },
        Hate = {
            "CRIMINAL",
            "DEALER",
        },
        Weapon = {
            {31,100},
        },
        --[[
        WeaponRandom = {
            {31,500},
        },
        ]]
        Decision = "excuteAIDecisionCop",
    },
    ["MEDIC"] = {
        Respect = {
            "COP",
            "COP_2",
            "FIREMAN",
        },
        Hate = {},
        Decision = "excuteAIDecisionWeak",
    },
    ["FIREMAN"] = {
        Respect = {
            "MEDIC",
            "COP_2",
            "FIREMAN",
        },
        Hate = {},
        Decision = "excuteAIDecisionWeak",
    },
    ["CRIMINAL"] = {
        Respect = {},
        Hate = {
            "COP",
            "COP_2",
        },
        Weapon = {
            {22,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["PROSTITUTE"] = {
        Respect = {},
        Hate = {
            "COP",
        },
        Decision = "excuteAIDecisionWeak",
    },
    --Gange
    ["GANG1"] = {
        Respect = {
            "GANG1",
        },
        Hate = {
            "GANG2",
            "GANG3",
            "GANG4",
            "GANG5",
            "GANG6",
            "GANG7",
            "GANG8",
            "GANG9",
            "GANG10",
        },
        Weapon = {
            {32,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG2"] = {
        Respect = {
            "GANG2",
        },
        Hate = {
            "GANG1",
            "GANG3",
            "GANG4",
            "GANG5",
            "GANG6",
            "GANG7",
            "GANG8",
            "GANG9",
            "GANG10",
        },
        Weapon = {
            {32,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG3"] = {
        Respect = {
            "GANG3",
        },
        Hate = {
            "GANG2",
            "GANG1",
            "GANG4",
            "GANG5",
            "GANG6",
            "GANG7",
            "GANG8",
            "GANG9",
            "GANG10",
        },
        Weapon = {
            {28,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG4"] = {
        Respect = {
            "GANG4",
        },
        Weapon = {
            {28,30},
        },
        Hate = {
            "GANG2",
            "GANG3",
            "GANG1",
            "GANG5",
            "GANG6",
            "GANG7",
            "GANG8",
            "GANG9",
            "GANG10",
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG5"] = {
        Respect = {
            "GANG5",
        },
        Hate = {
            "GANG2",
            "GANG3",
            "GANG4",
            "GANG1",
            "GANG6",
            "GANG7",
            "GANG8",
            "GANG9",
            "GANG10",
        },
        Weapon = {
            {32,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG6"] = {
        Respect = {
            "GANG6",
        },
        Hate = {
            "GANG2",
            "GANG3",
            "GANG4",
            "GANG5",
            "GANG1",
            "GANG7",
            "GANG8",
            "GANG9",
            "GANG10",
        },
        Weapon = {
            {32,30},
            {22,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG7"] = {
        Respect = {
            "GANG7",
        },
        Hate = {
            "GANG2",
            "GANG3",
            "GANG4",
            "GANG5",
            "GANG6",
            "GANG1",
            "GANG8",
            "GANG9",
            "GANG10",
        },
        Weapon = {
            {32,30},
            {22,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG8"] = {
        Respect = {
            "GANG8",
        },
        Hate = {
            "GANG2",
            "GANG3",
            "GANG4",
            "GANG5",
            "GANG6",
            "GANG7",
            "GANG1",
            "GANG9",
            "GANG10",
        },
        Weapon = {
            {32,30},
            {22,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG9"] = {
        Respect = {
            "GANG9",
        },
        Hate = {
            "GANG2",
            "GANG3",
            "GANG4",
            "GANG5",
            "GANG6",
            "GANG7",
            "GANG8",
            "GANG1",
            "GANG10",
        },
        Weapon = {
            {32,30},
            {22,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
    ["GANG10"] = {
        Respect = {
            "GANG10",
        },
        Hate = {
            "GANG2",
            "GANG3",
            "GANG4",
            "GANG5",
            "GANG6",
            "GANG7",
            "GANG8",
            "GANG9",
            "GANG1",
        },
        Weapon = {
            {32,30},
            {22,30},
        },
        Decision = "excuteAIDecisionPsyco",
    },
}

PED_IDE = {}
local CIVIL_WEAPONS = {
    2,4,6,7,8,0,15
}


AI_ELEMENT_PRIORITY = {
    ["player"] = 10,
    ["ped"] = 5,
    ["vehicle"] = 1,
}


-- Generate Ped Group
local file = fileOpen("data/ped.dat",true)
if not file then
    return false -- stop function on failture
end
local FullText = fileRead(file, 100)

while not fileIsEOF(file) do
FullText = FullText .. fileRead(file, 100)
end
fileClose(file)

Lines = split(FullText,'\n' )
for i = 1, #Lines do
    --print(Lines[i])
    local params = split(Lines[i],",")
    local model = string.gsub(params[1], "\r", "")
    local group = string.gsub(params[2], "\r", "")
    PED_IDE[tonumber(model)] = group
end

function getPedGroupByModel(model_id) 
    local group = PED_IDE[model_id]
    if PED_GROUP[group] ~= nil then 
        return group
    else
        return "DEFAULT"
    end
end
function excutePedGroupDecisionFromModel(model_id) 
    local group = PED_IDE[model_id]
    if PED_GROUP[group] ~= nil then 
        return AI_DECISION[PED_GROUP[group].Decision]
    else
        return AI_DECISION[PED_GROUP["DEFAULT"].Decision]
    end
end
function excutePedGroupDecision(npc,group) 
    local temper = getElementData(npc,"npchlc:temper") == false and 0 or getElementData(npc,"npchlc:temper")
    

    if group == "DEFAULT" then 
        if temper > 80 then
            --print("excuteAIDecisionPsyco",group)
            return AI_DECISION["excuteAIDecisionPsyco"](npc)
        else
            --print("excuteAIDecisionWeak",group)
            return AI_DECISION["excuteAIDecisionWeak"](npc)
        end
    end

    return AI_DECISION[PED_GROUP[group].Decision](npc)
end
function givePedGroupWeapon(npc)
    --local model = getElementModel(npc)
    local group = getPedGroup(npc)
    local temper = getElementData(npc,"npchlc:temper") == false and 0 or getElementData(npc,"npchlc:temper")
    if group == "DEFAULT" and temper > 50 then -- give random weapon
        local weapon = math.random(1,#CIVIL_WEAPONS)
        giveWeapon(npc,CIVIL_WEAPONS[weapon],1,true)
    end
    if PED_GROUP[group] ~= nil then 
        -- check random weapon 
        if PED_GROUP[group].WeaponRandom ~= nil then
            local select = math.random(1,#PED_GROUP[group].WeaponRandom)
            giveWeapon(npc,PED_GROUP[group].WeaponRandom[select][1],PED_GROUP[group].WeaponRandom[select][2],true)
        
        end

        
        if PED_GROUP[group].Weapon ~= nil then
            for _,val in ipairs(PED_GROUP[group].Weapon) do
                --print("give weapon"..val[1])
                giveWeapon(npc,val[1],val[2],true)
            end
        
        end
    end
end
--[[
function getPedGang(npc) 
    --local gang = getElementData(ped,"npchlc:group") or false
    local gang = population.peds[npc].group or "DEFAULT"

    if gang == "GANG1" or gang == "GANG2" or gang == "GANG3" or gang == "GANG4" or gang == "GANG5" or gang == "GANG6" or gang == "GANG7" or gang == "GANG8" or gang == "GANG9" or gang == "GANG10" or gang == "COP" then
        return gang
    end

    return gang
end
]]
function getPedGroup(npc) 
    if not isElement(npc) then 
        return "DEFAULT"
    end
    return getElementData(npc,"npchlc:group") or "DEFAULT"
end

function isAttackerRespect(ped,attacker) 
    local ped_group = getPedGroup(ped) 
    local attacker_group = getPedGroup(attacker) 
    for _,respect in ipairs(PED_GROUP[ped_group].Respect) do 
        if respect == attacker_group then return true end
    end
    return false
end

function isEnforcementGroup(group) 
    return group == "COP" or group == "COP_2" or group == "FBI" or group == "ARMY" or group == "SWAT" or group == "TANK"
end
function isGangGroup(group) 
    return group == "GANG1" or group == "GANG2" or group == "GANG3" or group == "GANG4" or group == "GANG5" or group == "GANG6" or group == "GANG7" or group == "GANG8" or group == "GANG9" or group == "GANG10"
end
function hasElementHigherProperty(npc,new_attacker) 
    if not isElement(new_attacker) then return true end
    local current_attacker = getNPCAttacker(npc) or false
    if isElement(current_attacker) and current_attacker ~= false then 
        local current_priority = AI_ELEMENT_PRIORITY[getElementType(current_attacker)]
        local new_priority = AI_ELEMENT_PRIORITY[getElementType(new_attacker)]
        if new_priority > current_priority then return true end
    else 
        return true
    end
    return false
end