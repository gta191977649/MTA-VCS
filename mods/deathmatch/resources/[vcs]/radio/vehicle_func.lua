local RADIO_PLAYING = false
addEventHandler("onClientVehicleEnter", getRootElement(),
    function(thePlayer, seat)
        if thePlayer == getLocalPlayer() then
            local station = getElementData(source,"radio_station")
            if not station then station = math.random(1,#STATIONS) end
            turnToRadio(station)
            RADIO_PLAYING = true
        end
    end
)
addEventHandler("onClientVehicleStartExit", getRootElement(),
    function(thePlayer, seat)
        if thePlayer == getLocalPlayer() then
            stopRadio()
            RADIO_PLAYING = false
        end
    end
)

setTimer(function() -- stop the radio when vehicle is removed or bugged
    if RADIO_PLAYING and not isPedInVehicle(localPlayer) then 
        stopRadio()
        RADIO_PLAYING = false
    end
end,1000,0)