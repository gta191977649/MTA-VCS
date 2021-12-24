local PlayerModModel = {}
function initModels() 
    -- process vehicle handing
    for key,val in pairs(IMG_VEHICLE) do 
        if val.replace == true and val.handing ~= false then
            -- deal with replace vehicle handing
            local handing = split(val.handing,",")
            for i=1,#handing do 
                if tonumber(handing[i]) then
                    handing[i] = tonumber(handing[i])
                end
            end
            iprint(handing)
            applyVehicleCustomHanding(val.parent,handing) 

            print(string.format("vehicle %d is handing loaded.",val.parent))
        end
    end
end
function setElementModModel(player,name)
    triggerClientEvent(player,"mod.client.setSkin",player,name)
end

addEvent("mod.server.spawnVehicle",true)
addEventHandler("mod.server.spawnVehicle",root,function(model,parent,x,y,z) 
    local veh = createVehicle(parent,x,y,z)
    setElementData(veh,"mod.model",model)
    -- deal with handing 
    if IMG_VEHICLE[model].handing ~= nil then 
        print(#IMG_VEHICLE[model].handing)
        applyVehicleCustomHanding(veh,IMG_VEHICLE[model].handing) 
    end
end)

function applyVehicleCustomHanding(theVehicle,handing) 

    if tonumber(theVehicle) then -- dealwith replaced vehicle

        setModelHandling(theVehicle, "mass",handing[1])
        setModelHandling(theVehicle, "turnMass",handing[2])
        setModelHandling(theVehicle, "dragCoeff",handing[3])
        setModelHandling(theVehicle, "centerOfMass", {handing[4],handing[5],handing[6]} )
        setModelHandling(theVehicle, "percentSubmerged", handing[7])
        setModelHandling(theVehicle, "tractionMultiplier", handing[8])
        setModelHandling(theVehicle, "tractionLoss",handing[9])
        setModelHandling(theVehicle, "tractionBias",handing[10])
        setModelHandling(theVehicle, "numberOfGears",handing[11])
        setModelHandling(theVehicle, "maxVelocity",handing[12])
        setModelHandling(theVehicle, "engineAcceleration",handing[13])
        setModelHandling(theVehicle, "engineInertia",handing[14])
        setModelHandling(theVehicle, "driveType",handing[15])
        setModelHandling(theVehicle, "engineType",handing[16])
        setModelHandling(theVehicle, "brakeDeceleration",handing[17])
        setModelHandling(theVehicle, "brakeBias",handing[18])
        setModelHandling(theVehicle, "steeringLock",handing[19])
        setModelHandling(theVehicle, "suspensionForceLevel",handing[20])
        setModelHandling(theVehicle, "suspensionDamping",handing[21])
        setModelHandling(theVehicle, "suspensionHighSpeedDamping",handing[22])
        setModelHandling(theVehicle, "suspensionUpperLimit",handing[23])
        setModelHandling(theVehicle, "suspensionLowerLimit",handing[24])
        setModelHandling(theVehicle, "suspensionFrontRearBias",handing[25] )
        setModelHandling(theVehicle, "suspensionAntiDiveMultiplier",handing[26])
        setModelHandling(theVehicle, "seatOffsetDistance",handing[27])
        setModelHandling(theVehicle, "collisionDamageMultiplier",handing[28])
        setModelHandling(theVehicle, "monetary",handing[29]) 
        setModelHandling(theVehicle, "modelFlags",handing[30])
        setModelHandling(theVehicle, "handlingFlags", handing[31])
        setModelHandling(theVehicle, "headLight",handing[32]) 
        setModelHandling(theVehicle, "tailLight",handing[33]) 
        setModelHandling(theVehicle, "animGroup",handing[34]) 
  
    else -- deal with imported vehicle

        setVehicleHandling(theVehicle, "mass",handing[1])
        setVehicleHandling(theVehicle, "turnMass",handing[2])
        setVehicleHandling(theVehicle, "dragCoeff",handing[3])
        setVehicleHandling(theVehicle, "centerOfMass", {handing[4],handing[5],handing[6]} )
        setVehicleHandling(theVehicle, "percentSubmerged", handing[7])
        setVehicleHandling(theVehicle, "tractionMultiplier", handing[8])
        setVehicleHandling(theVehicle, "tractionLoss",handing[9])
        setVehicleHandling(theVehicle, "tractionBias",handing[10])
        setVehicleHandling(theVehicle, "numberOfGears",handing[11])
        setVehicleHandling(theVehicle, "maxVelocity",handing[12])
        setVehicleHandling(theVehicle, "engineAcceleration",handing[13])
        setVehicleHandling(theVehicle, "engineInertia",handing[14])
        setVehicleHandling(theVehicle, "driveType",handing[15])
        setVehicleHandling(theVehicle, "engineType",handing[16])
        setVehicleHandling(theVehicle, "brakeDeceleration",handing[17])
        setVehicleHandling(theVehicle, "brakeBias",handing[18])
        setVehicleHandling(theVehicle, "steeringLock",handing[19])
        setVehicleHandling(theVehicle, "suspensionForceLevel",handing[20])
        setVehicleHandling(theVehicle, "suspensionDamping",handing[21])
        setVehicleHandling(theVehicle, "suspensionHighSpeedDamping",handing[22])
        setVehicleHandling(theVehicle, "suspensionUpperLimit",handing[23])
        setVehicleHandling(theVehicle, "suspensionLowerLimit",handing[24])
        setVehicleHandling(theVehicle, "suspensionFrontRearBias",handing[25] )
        setVehicleHandling(theVehicle, "suspensionAntiDiveMultiplier",handing[26])
        setVehicleHandling(theVehicle, "seatOffsetDistance",handing[27])
        setVehicleHandling(theVehicle, "collisionDamageMultiplier",handing[28])
        --setVehicleHandling(theVehicle, "monetary",handing[29]) 
        setVehicleHandling(theVehicle, "modelFlags",handing[30])
        setVehicleHandling(theVehicle, "handlingFlags", handing[31])
        --setVehicleHandling(theVehicle, "headLight",handing[32]) 
        --setVehicleHandling(theVehicle, "tailLight",handing[33]) 
        --setVehicleHandling(theVehicle, "animGroup",handing[34]) 

    end
    print("model handing loaded.")
end
--addEventHandler ( "onResourceStart", resourceRoot,initModels) -- BUG NOT FIXED
