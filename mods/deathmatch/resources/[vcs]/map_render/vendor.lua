function readFile(path) 
    local file = fileOpen(path)
    if not file then
        return false
    end
    local count = fileGetSize(file)
    local data = fileRead(file, count)
    fileClose(file)
    return data
end
function readDataInLines(data)
    data = split(data,"\n")
    return data
end

function isComment(line) 
    return line:sub(1,1) == "#" or line:sub(1,1) == "\r"
end
 