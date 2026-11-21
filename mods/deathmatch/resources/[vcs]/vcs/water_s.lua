-- The US PS2 water grid is exported as horizontal, axis-aligned quads.
local quads = {}

addEventHandler("onResourceStart",resourceRoot,function()
    local file=fileOpen("water.dat",true)
    if not file then return end
    local data=fileRead(file,fileGetSize(file))
    fileClose(file)
    for line in data:gmatch("[^\r\n]+") do
        if line:match("^%s*%-?%d") then
            local values={}
            for value in line:gmatch("%S+") do values[#values+1]=tonumber(value) end
            if #values==29 then
                quads[#quads+1]={math.min(values[1],values[22]),math.max(values[1],values[22]),
                    math.min(values[2],values[23]),math.max(values[2],values[23]),values[3]}
            end
        end
    end
end,false)

function getVcsWaterQuadLevel(x,y)
    if type(x)~="number" or type(y)~="number" then return false end
    for _,q in ipairs(quads) do
        if x>=q[1] and x<=q[2] and y>=q[3] and y<=q[4] then return q[5] end
    end
    return false
end
