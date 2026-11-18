RadioPack = {
    rate = 32000,
    segmentFrames = 60 * 32000,
    overlap = 0.1,
}

local path = "audio/radio.bin"
local maxSegmentBytes = 2 * 1024 * 1024
local headerBytes, recordBytes = 24, 16

local function u16(data, i)
    local a, b = data:byte(i, i + 1)
    return a + b * 256
end

local function u32(data, i)
    return u16(data, i) + u16(data, i + 2) * 65536
end

local function record(data, i)
    return u32(data, i), u32(data, i + 4), u32(data, i + 8), u32(data, i + 12)
end

local function read(file, offset, length)
    if fileSetPos(file, offset) ~= offset then return nil end
    local data = fileRead(file, length)
    if type(data) == "string" and #data == length then return data end
end

local function parse(file)
    local size = fileGetSize(file)
    local header = read(file, 0, headerBytes)
    if not header or header:sub(1, 4) ~= "VCSR" or u16(header, 5) ~= 1 then
        return nil, "invalid header or unsupported version"
    end
    local stationCount = u16(header, 7)
    local segmentCount, effectOffset, effectBytes, packSize = record(header, 9)
    local indexBytes = (stationCount + segmentCount) * recordBytes
    if stationCount ~= 9 or segmentCount < stationCount or segmentCount > 4096
        or effectOffset ~= headerBytes + indexBytes or effectBytes < recordBytes
        or effectBytes > maxSegmentBytes or packSize ~= size or effectOffset + effectBytes >= size then
        return nil, "invalid index or pack size"
    end
    local index = read(file, headerBytes, indexBytes)
    local effectData = read(file, effectOffset, effectBytes)
    if not index or not effectData then return nil, "short index or effect read" end

    local clips, clipStart = {}, recordBytes + 1
    for i = 1, 4 do
        local clipBytes = u32(effectData, 1 + (i - 1) * 4)
        if clipBytes < 44 or clipStart + clipBytes - 1 > effectBytes
            or effectData:sub(clipStart, clipStart + 3) ~= "RIFF"
            or effectData:sub(clipStart + 8, clipStart + 11) ~= "WAVE" then
            return nil, "invalid retune effect"
        end
        clips[i] = effectData:sub(clipStart, clipStart + clipBytes - 1)
        clipStart = clipStart + clipBytes
    end
    if clipStart ~= effectBytes + 1 then return nil, "unexpected retune data" end

    local stations = {}
    local nextSegment, nextOffset = 0, effectOffset + effectBytes
    for i = 1, stationCount do
        local id, first, count, total = record(index, 1 + (i - 1) * recordBytes)
        if id ~= i or first ~= nextSegment or count < 1 or first + count > segmentCount
            or total <= (count - 1) * RadioPack.segmentFrames or total > count * RadioPack.segmentFrames then
            return nil, "invalid station " .. i
        end
        local station = {total = total, segments = {}}
        for seq = 1, count do
            local start, frames, offset, bytes = record(index, 1 + (stationCount + nextSegment) * recordBytes)
            if start ~= (seq - 1) * RadioPack.segmentFrames
                or frames ~= math.min(RadioPack.segmentFrames, total - start)
                or offset ~= nextOffset or bytes < 4 or bytes > maxSegmentBytes or offset + bytes > size then
                return nil, "invalid segment in station " .. id
            end
            station.segments[seq] = {seconds = frames / RadioPack.rate, offset = offset, bytes = bytes}
            nextSegment, nextOffset = nextSegment + 1, nextOffset + bytes
        end
        stations[id] = station
    end
    if nextSegment ~= segmentCount or nextOffset ~= size then return nil, "incomplete index coverage" end
    return {file = file, stations = stations, clips = clips}
end

function RadioPack.open()
    local file = fileOpen(path, true)
    if not file then return nil, "audio pack unavailable" end
    local pack, reason = parse(file)
    if not pack then fileClose(file) end
    return pack, reason
end

function RadioPack.readSegment(pack, segment)
    local data = read(pack.file, segment.offset, segment.bytes)
    if data and data:sub(1, 4) == "OggS" then return data end
end
