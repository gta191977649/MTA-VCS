local Config = {
    ModelFolder = "models/"
}
local Generator = {
    MetaSections = "",
}
local Reader = {
    Section = nil
}
local DatTable = {
    ide = {},
    ipl = {},
    img = {},
    data = {
        dff = {},
        txd = {},
    }
}
local SectionsHandler = {
    ["objs"] = function(line) 
        line = line:gsub(" ",""):gsub("\r","")
        local data = split(line,",")
        local id = data[1]
        local dff = data[2]
        local txd = data[3]
        
        DatTable.data.dff[dff] = true
        DatTable.data.txd[txd] = true
    end
}


function getFileSection(line) 
    return SectionsHandler[line] ~= nil and line or nil
end
function loadGTADAT(path) 
    local data = readFile(path) 
    data = readDataInLines(data)
    for _,line in ipairs(data) do 
        if not isComment(line) then 
            local tag = split(line," ")[1]
            if tag == "IDE" then 
                local ide = split(line," ")[2]:gsub('\r',"")
                table.insert(DatTable.ide,ide)
            end
        end
    end
    --iprint(DatTable.ide)
end

function loadSections(ide) 
    local ide_content = readFile(ide) 
    local data = readDataInLines(ide_content)
    for _,line in ipairs(data) do 
        if not isComment(line) then
            if line:gsub('\r',"") == "end" then 
                Reader.Section = nil
            end
            
            if Reader.Section then 
                SectionsHandler[Reader.Section](line)
            end

         
            if Reader.Section == nil then 
                Reader.Section = getFileSection(line:gsub('\r',""))
            end
            
        end
    end
end

function loadAllSections() 
    for _,ide in ipairs(DatTable.ide) do 
        loadSections(ide)
    end
end

function generateMeta() 
    -- append dff
    for dff,_ in pairs(DatTable.data.dff) do 
        Generator.MetaSections = Generator.MetaSections .. string.format("<file src=\"%s%s.dff\" type=\"client\"/>\n",Config.ModelFolder,dff)
    end
    -- append txd
    for txd,_ in pairs(DatTable.data.txd) do 
        Generator.MetaSections = Generator.MetaSections .. string.format("<file src=\"%s%s.txd\" type=\"client\"/>\n",Config.ModelFolder,txd)
    end
    -- write out file
    local fileHandle = fileCreate("meta.txt") 
    if fileHandle then 
        fileWrite(fileHandle,Generator.MetaSections)
        fileClose(fileHandle)
    end
end
function generate()
    loadGTADAT("data/gta.dat")
    loadAllSections() 
    generateMeta()
end

generate()