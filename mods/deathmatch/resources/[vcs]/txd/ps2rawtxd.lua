function initImg()
    local path = "data/rawindex.txt"
    local img = engineLoadIMGContainer("./data/raw.img")
    local file = fileOpen(path,true) 
    if not file then
        return false 
    end
    local FullText = fileRead(file, 100)
    
    while not fileIsEOF(file) do
        FullText = FullText .. fileRead(file, 100)
    end
    fileClose(file)

    Lines = split(FullText,'\n' )
    Async:setPriority("high")
    Async:iterate(1, #Lines, function(i) 
        local filename = Lines[i]..".tga"
        filename = string.gsub(filename, "\r", "")
        local txdName =  string.gsub(Lines[i], "\r", "")
        local raw = img:getFile(filename)
        if raw then
            print("RAW:",#raw)
            local txd = dxCreateTexture(raw)
            if txd then 
                local shader = dxCreateShader("replace.fx")
                dxSetShaderValue(shader,"Tex0",txd)
                engineApplyShaderToWorldTexture(shader,txdName)
                print("Replaced: "..txdName)
            end
        end
    end,function() 
        print("Replace finish")
    end); 
end
local ps2Shaders = {}
function init()
    local path = "data/rawindex.txt"
    local file = fileOpen(path,true) 
    if not file then
        return false 
    end
    local FullText = fileRead(file, 100)
    
    while not fileIsEOF(file) do
        FullText = FullText .. fileRead(file, 100)
    end
    fileClose(file)

    Lines = split(FullText,'\n' )
    Async:setPriority("high")
    Async:iterate(1, #Lines, function(i) 
        local filename = "data/raw/"..Lines[i]..".tga"
        filename = string.gsub(filename, "\r", "")
        local txdName =  string.gsub(Lines[i], "\r", "")
        local txd = dxCreateTexture(filename)
        local shader = dxCreateShader("replace.fx")
        dxSetShaderValue(shader,"Tex0",txd)
        engineApplyShaderToWorldTexture(shader,txdName)
        table.insert(ps2Shaders,shader)
        print("Replaced: "..txdName)

    end,function() 
        print("Replace finish")
    end); 
end
init()
--[[
addCommandHandler( "ps2",enablePS2Txd)
addCommandHandler( "nops2",disablePS2Txd)
]]