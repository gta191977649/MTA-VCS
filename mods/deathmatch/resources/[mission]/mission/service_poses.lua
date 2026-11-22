-- Replicate pose transitions. Clients evaluate the IFP locally and can recover
-- its phase when the ped streams in halfway through an action.
local key="mission:servicePose"

function Mission.servicePose(ped,clip)
    if clip then
        setElementData(ped,key,{clip,getTickCount()},"broadcast","deny")
    else
        removeElementData(ped,key)
    end
end

addEvent("mission:poseClock",true)
addEventHandler("mission:poseClock",resourceRoot,function(sent)
    if client and source==resourceRoot and type(sent)=="number" then
        triggerClientEvent(client,"mission:poseClockReply",resourceRoot,sent,getTickCount())
    end
end,false)
