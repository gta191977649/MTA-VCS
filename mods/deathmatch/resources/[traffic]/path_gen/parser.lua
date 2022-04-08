local PATH = {
    node_block = {
        ped = {},
        car = {},
        boat = {},
    },
}

function readNodeSection(sectionFlag,data) 
    local section_data = {}

    local isFlag = false
    local isSection = false

    local currentGroupType = 1
    for index,line in ipairs(data) do 
        
        if string.len(line) > 0 and string.sub(line, 1, 1) ~= "//" then -- skip comment
            line = removedSpecialChar(line)
            if line == "end" then 
                isFlag = false
            end
            if isFlag then 
                line = split(line,",")
                if #line == 2 then -- when a new section
                    currentGroupType = getGroupTypeName(line[1])
                end
                if #line == 12 then -- it's the section data
                    local NodeType, NextNode, IsCrossRoad, XAbs, YAbs, ZAbs, Median, LeftLanes, RightLanes, SpeedLimit, Flags, SpawnRate = unpack(line)
                    if NodeType ~= "0" then
                        table.insert(PATH.node_block[currentGroupType],{XAbs / 16, YAbs/ 16, ZAbs / 16,1,1})
                    end
                end
           
            end
            if line == sectionFlag then 
                isFlag = true
            end
        end
    end
end


function writeFile(filename) 

    local node_block = PATH.node_block
    --write header
    local f = fileCreate(filename)
    --[[
    -- write nodes (only vehicles)
    for node_index,node in ipairs(node_block.car) do 
        local x,y,z,rx,ry = unpack(node)
        x,y,z = math.floor(x*1000),math.floor(y*1000),math.floor(z*1000)
		rx,ry = math.floor(rx*1000),math.floor(ry*1000)
        fileWrite(f,dataToBytes("3i2s",x,y,z,rx,ry))
    end
    --]]
    -- this will write all type of nodes
    fileWrite(f,dataToBytes("3i",(#node_block.car + #node_block.ped + #node_block.boat),0,0))

    for key,blocks in pairs(node_block) do 
        for node_index,node in ipairs(blocks) do 
            local x,y,z,rx,ry = unpack(node)
            x,y,z = math.floor(x*1000),math.floor(y*1000),math.floor(z*1000)
            rx,ry = math.floor(rx*1000),math.floor(ry*1000)
            fileWrite(f,dataToBytes("3i2s",x,y,z,rx,ry))
        end
        print(key.." Processed, total "..#blocks)
    end

    fileClose(f)
    print(string.format("path write!, Total %d peds, %d cars, %d boats",#node_block.ped,#node_block.car,#node_block.boat))
end

function convert(path) 
    local file = openFile(path) 
    readNodeSection("path",file)
    writeFile("vcs")
end



convert("paths.ipl")