HUD = exports.hud

addEventHandler("onClientVehicleEnter", getRootElement(),
    function(thePlayer, seat)
        if thePlayer == getLocalPlayer() then
            local vehicle_name = getVehicleName(source)
            HUD:showGameText(vehicle_name,"VEHICLE_NAME",3000)
        end
    end
)
