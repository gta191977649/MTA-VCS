-- ObjectData +0x1f selects the effect in SLUS-21590 00132C50.
-- Mixer 001C3D70 maps effects 9/10 to event 0x50 and 2/3 to event 0x51.
local glassRates = {20000, 20000, 18000, 20000}
local glass = {distance=55, frequency=19000, variation=1999, volumeVariation=10}
local box = {distance=60, frequency=18600, variation=1499, volumeVariation=19}
local samples = {
    ebprop_freezer = glass,
    ebprop_freezerfloor = glass,
    ebprop_delicounter = glass,
    mar_a2tv = glass,
    ebprop_cashreg = box,
    ebprop_clothesrail = box,
    ebprop_speaker = box,
    ebprop_gblaster = box,
    mar_a2_stereo = box,
}
local lastPlayed = setmetatable({}, {__mode="k"})

addEventHandler("onClientEagleObjectDamageEffect", root, function(owner, model)
    local sample = owner == "vcs" and samples[model]
    if not sample then return end

    local interior, dimension = getElementInterior(source), getElementDimension(source)
    if interior ~= getElementInterior(localPlayer) or dimension ~= getElementDimension(localPlayer) then
        return
    end

    local now = getTickCount()
    if lastPlayed[source] == now then return end
    lastPlayed[source] = now

    local file, rate = "wooden_box_smash", 18600
    if sample == glass then
        local variant = math.random(#glassRates)
        file, rate = "glass_shard_" .. variant, glassRates[variant]
    end

    local x, y, z = getElementPosition(source)
    local sound = playSound3D("audio/" .. file .. ".wav", x, y, z)
    if not sound then return end
    setElementInterior(sound, interior)
    setElementDimension(sound, dimension)
    setSoundMinDistance(sound, sample.distance * 0.2)
    setSoundMaxDistance(sound, sample.distance)
    setSoundSpeed(sound, (sample.frequency + math.random(-sample.variation, sample.variation)) / rate)
    local volume = sample == glass and math.random(80 - sample.volumeVariation, 80 + sample.volumeVariation)
        or math.random(80, 80 + sample.volumeVariation)
    setSoundVolume(sound, volume / 127)
end)
