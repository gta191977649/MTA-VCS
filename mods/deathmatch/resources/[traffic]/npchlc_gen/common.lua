function openFile(path) 
    local f = fileOpen(path)
    local line = fileRead(f,fileGetSize(f))
    line = split(line,"\r")
    
    return line
end
function removedSpecialChar(str) 
    local specialChar = {
        "\r","\n","\t"," "
    }
    for _,char in ipairs(specialChar) do 
        str = string.gsub(str,char,"")
    end
    return str
end
function getGroupTypeName(type) 
    local typeMapping = {
        ["0"] = "ped",
        ["1"] = "car",
        ["2"] = "boat",
    }
    return typeMapping[type]
end