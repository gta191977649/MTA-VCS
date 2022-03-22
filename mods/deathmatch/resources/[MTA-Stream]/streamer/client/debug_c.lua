addCommandHandler("tpmap",function(cmd,mapname) 
    if mapdata[mapname] then 
        local x,y,z = unpack(mapdata[mapname].ipls[1].pos)
        local ox,oy,oz = unpack(mapdata[mapname].offset)
        setElementPosition(localPlayer,x+ox,y+oy,z+oz)
    end
end)