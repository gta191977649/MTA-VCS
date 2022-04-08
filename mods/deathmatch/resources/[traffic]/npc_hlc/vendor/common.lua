--
-- Created by IntelliJ IDEA.
-- User: Sparrow
-- Date: 2021/2/24
-- Time: 22:55
-- To change this template use File | Settings | File Templates.
--


function controlVehicleForward(npc,speed)
    local vehPtr = getPedOccupiedVehicle(npc)
    local vx,vy,vz = getElementVelocity(vehPtr)
    local m = getElementMatrix(vehPtr)
    local vrx,vry,vrz = vx*m[1][1]+vy*m[1][2]+vz*m[1][3], vx*m[2][1]+vy*m[2][2]+vz*m[2][3], vx*m[3][1]+vy*m[3][2]+vz*m[3][3]
    setPedControlState(npc,"accelerate",vry < speed)
    setPedControlState(npc,"brake_reverse",vry > speed*0.9)
    setPedControlState(npc,"handbrake",vry > speed*0.95)
end
function controlVehicleBackward(npc)
    setPedControlState(npc,"accelerate",false)
    setPedControlState(npc,"handbrake",false)
    setPedControlState(npc,"brake_reverse",true)
end
function controlVehicleBreak(npc)
    setPedControlState (npc,'accelerate', false)
    setPedControlState (npc,"handbrake", true )
end
function controlVehicleLeft(npc)
    setPedControlState (npc,"vehicle_left", true )
    setPedControlState (npc,"vehicle_right ", false )
end
function controlVehicleRight(npc)
    setPedControlState (npc,"vehicle_right", true )
    setPedControlState (npc,"vehicle_left", false )
end
function controlVehicleDirCancel(npc)
    setPedControlState (npc,"vehicle_right", false )
    setPedControlState (npc,"vehicle_left", false )
end

function controlPedRight(npc)
    setPedControlState (npc,"right", true )
    setPedControlState (npc,"left", false )
    setPedControlState (npc,"backwards", false )
end

function controlPedLeft(npc)
    setPedControlState (npc,"right", false )
    setPedControlState (npc,"left", true )
    setPedControlState (npc,"backwards", false )

end
function controlPedBack(npc)
    setPedControlState (npc,"backwards", true )
    setPedControlState (npc,"right", false )
    setPedControlState (npc,"left", false )
end

function setElementForwardVelocity( elem, vel ) 
    local ang = getElementRotation( elem ); 
    ang = math.rad(90 - ang); 
    local vx = math.cos( ang ) * vel; 
    local vy = math.sin( ang ) * vel; 
    return setElementVelocity( elem, vx, vy, 0 ); 
end 
