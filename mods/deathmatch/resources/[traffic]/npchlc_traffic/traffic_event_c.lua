-- this will fixed the heli falling down issue
local ClientHelis = {}
addEvent("traffic.vehicle.heli",true)
addEventHandler("traffic.vehicle.heli",root,function(npc,veh,speed)
	if veh ~= nil then 
		setHelicopterRotorSpeed (veh,1)
		setPedControlState(npc, "horn", true)
		setElementData(npc,"copheli.horn",true)
		--[[
		--setPedControlState(npc,"horn",true)
		local hx,hy,hz = getElementPosition(veh)
		local px,py,pz = getElementPosition(localPlayer)
		
		ClientHelis[veh] = {
			light = createSearchLight(hx,hy,hz, px,py,pz, 0, 15)
		}
		]]
	end
	--setSearchLightStartPosition(ClientHelis[veh].light, hx,hy,hz)
    --setSearchLightEndPosition(ClientHelis[veh].light, px,py,pz)
end)
--[[
addEventHandler("onClientPreRender", root, function() 
	
	local px,py,pz = getElementPosition(localPlayer)
	for heli,val in pairs(ClientHelis) do 
		if getElementHealth(heli) <=1 then 
			destroyElement(ClientHelis[heli].light)
			ClientHelis[heli] = nil
			return
		end
		local hx,hy,hz = getElementPosition(heli)
		if getDistanceBetweenPoints3D(px,py,pz,hx,hy,hz) < 50 and hz - pz > 3 then
		setSearchLightStartPosition(ClientHelis[heli].light, hx,hy,hz)
		setSearchLightEndPosition(ClientHelis[heli].light, px,py,pz)
		else
			setSearchLightStartPosition(ClientHelis[heli].light, hx,hy,hz)
			setSearchLightEndPosition(ClientHelis[heli].light,hx,hy,hz-20)
		end 
	end
end)
]]
addEventHandler( "onClientElementStreamOut", root,
    function ( )
        if getElementType( source ) == "vehicle" and ClientHelis[source] ~= nil then
         	destroyElement(ClientHelis[source].light)
         	ClientHelis[source] = nil
        end
    end
)
addEventHandler( "onClientElementStreamIn", root,
    function ( )
        if getElementType( source ) == "ped" and getElementData(source,"copheli.horn") then
			setPedControlState(source, "horn", true)
        end
    end
)

addEventHandler("onClientElementDestroy",root,function ( )
    if getElementType( source ) == "vehicle" and ClientHelis[source] ~= nil then
     	destroyElement(ClientHelis[source].light)
     	ClientHelis[source] = nil
    end
 end)