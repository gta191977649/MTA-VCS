function setPedWalkingSAStyle(ped)
    local model = getElementModel(ped)
    if peds[model].walkingstyle ~= nil then 
        setPedWalkingStyle (ped,peds[model].walkingstyle )
    end
end
--[[
addEventHandler("onElementModelChange", root, function(old_model,new_model) 
    if getElementType(source) == "player" then
        if oldModel ~= new_model then 
            setPedWalkingSAStyle(source)
        end
    end
end) 
]]
