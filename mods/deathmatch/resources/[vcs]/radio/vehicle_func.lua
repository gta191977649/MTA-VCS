addEventHandler("onClientVehicleEnter", getRootElement(),
    function(thePlayer, seat)
        if thePlayer == getLocalPlayer() then
            local station = getElementData(source,"radio_station")
            if not station then station = math.random(1,#STATIONS) end
            turnToRadio(station)
        end
    end
)
addEventHandler("onClientVehicleStartExit", getRootElement(),
    function(thePlayer, seat)
        if thePlayer == getLocalPlayer() then
            stopRadio()
        end
    end
)

setTimer(function() -- stop the radio when vehicle is removed or bugged
    if RADIO_PLAYING and not isPedInVehicle(localPlayer) then 
        stopRadio()
    end
end,1000,0)