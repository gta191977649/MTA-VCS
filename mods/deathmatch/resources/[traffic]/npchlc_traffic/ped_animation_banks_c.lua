-- MTA indexes custom IFP blocks by name across the whole client.
local prefix = getResourceName(getThisResource()):lower() .. "_" .. getTickCount() .. "_"
TrafficAnimationBanks = {street = prefix .. "street", activity = prefix .. "activity"}
local loaded = {}

function TrafficAnimationBanks.load(block, path)
    if isElement(loaded[block]) then return loaded[block] end
    local file = fileOpen(path, true)
    if not file then
        outputDebugString("[" .. getResourceName(getThisResource()) .. "] Cannot open " .. path, 1)
        return false
    end
    local size = fileGetSize(file)
    local data = size >= 36 and fileRead(file, size)
    fileClose(file)
    if not data or #data ~= size or data:sub(1,4) ~= "ANP3" then
        outputDebugString("Invalid ANP3 resource file: " .. path, 1)
        return false
    end
    local a,b,c,d = data:byte(5,8)
    if 8+a+256*b+65536*c+16777216*d ~= size then
        outputDebugString("Truncated or oversized ANP3 resource file: " .. path, 1)
        return false
    end
    loaded[block] = engineLoadIFP(data, block)
    if not loaded[block] then outputDebugString("Cannot load animation block " .. block .. " from " .. path, 1) end
    return loaded[block]
end
