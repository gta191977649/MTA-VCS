addCommandHandler("tpmap",function(cmd,mapname) 
    if mapdata[mapname] then 
        local x,y,z = unpack(mapdata[mapname].ipls[1].pos)
        setElementPosition(localPlayer,x,y,z)
    end
end)