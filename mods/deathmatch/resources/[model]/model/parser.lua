function cleanupLineContent(line) -- removed the special tumulators symbols
    local removeSymbols = {
        "\r","\n","\t"," "
    }
    for _,symbols in ipairs(removeSymbols) do 
        line = line:gsub(symbols,"")
    end 
    return line
end
function isExculudeSymbolHanding(data) 
    local exculudeSymbols = {
        ";","!","%","$","^"
    }
    for _,symbols in ipairs(exculudeSymbols) do 
        if string.sub(data, 1, 1) == symbols then return true end
    end 
    return false
end
function fetchHandingLineTokens(line) 
    local tokens  ={}
    for token in string.gmatch(line, "[^%s]+") do
        table.insert(tokens,token)
    end
    return tokens
end
function readIDESection(sectionFlag,data) 
    local result = {}
    local data = split(data,"\r")
    local isFlag = false
    for index,line in ipairs(data) do 
        line = cleanupLineContent(line)
        if string.len(line) > 0 and string.sub(line, 1, 1) ~= "#" then -- skip comment
            if line == "end" then 
                isFlag = false
            end
            if isFlag then 
                table.insert(result,split(line,","))
            end
            
            if line == sectionFlag then 
                isFlag = true
            end
        end
    end
    return result
end
function readHandingSection(data) 
    local result = {}
    local data = split(data,"\r")
    local isFlag = false
    for index,line in ipairs(data) do 
        line = line:gsub("\n","")
        if string.len(line) > 0 and not isExculudeSymbolHanding(line) then -- skip comment
            line = fetchHandingLineTokens(line)
            local name = line[1]
            local handingline = ""
            for i=2,#line do 
                handingline = handingline..string.format("%s,",line[i])
        
            end
            result[name] = handingline
        end
    end
    return result
end
function saveToFile(filename,data)
    local fileHandle = fileCreate(filename) 
    fileWrite(fileHandle,data) 
    fileClose(fileHandle)   
end