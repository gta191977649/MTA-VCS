local key = "npchlc_traffic:stinger"
local strips, unfolding = {}, {}
local model, modelFailed, watching

local function loadModel()
    if model then return model end
    if modelFailed then return false end
    local id = engineRequestModel("object", 1593)
    if not id then return false end
    local txd = engineLoadTXD("stinger/plc_stinger.txd")
    local dff = engineLoadDFF("stinger/plc_stinger.dff")
    if txd and dff and engineImportTXD(txd, id) and engineReplaceModel(dff, id) then
        model = id
        return id
    end
    if dff then destroyElement(dff) end
    if txd then destroyElement(txd) end
    engineFreeModel(id)
    modelFailed = true
    outputDebugString("[npchlc_traffic] Could not load the police stinger slat", 2)
    return false
end

local function pose(ped, strip, age)
    if age <= 390 then return end
    local id = loadModel()
    if not id then return end
    local spacing, angle = TrafficStinger.geometry(age)
    local x, y, z, dx, dy = unpack(strip.data)
    local heading = math.deg(math.atan2(-dx, dy)) + 90
    for pair = 1, 6 do
        local px, py = x + pair*spacing*dx, y + pair*spacing*dy
        if not strip.positions or strip.spacing ~= spacing then
            -- Follow the pavement down from a curb. Server and client use
            -- the same pair centers for the rollout and wheel contacts.
            local prev = strip.positions and strip.positions[pair-1]
            local startZ = prev and prev[3] or z
            local hit, _, _, ground = processLineOfSight(px,py,startZ+1,px,py,startZ-10,true,false,false,true,false)
            strip.positions = strip.positions or {}
            strip.positions[pair] = {px, py, hit and ground+.15 or startZ}
        end
        local pos = strip.positions[pair]
        for side = 1, 2 do
            local index = (pair-1)*2 + side
            local rotation = heading + (side==1 and angle or -angle)
            local slat = strip.slats[index]
            if not slat then
                slat = createObject(id,pos[1],pos[2],pos[3],0,0,rotation)
                if slat then
                    strip.slats[index] = slat
                    setElementCollisionsEnabled(slat,false)
                    setElementDoubleSided(slat,true)
                    setElementInterior(slat,getElementInterior(ped))
                    setElementDimension(slat,getElementDimension(ped))
                end
            else
                setElementPosition(slat,pos[1],pos[2],pos[3])
                setElementRotation(slat,0,0,rotation)
            end
        end
    end
    strip.spacing = spacing
end

local function update()
    local now = getTickCount()
    for ped,strip in pairs(unfolding) do
        local age = math.min(2500,strip.age+(now-strip.received)%4294967296)
        pose(ped,strip,age)
        if age==2500 then unfolding[ped]=nil end
    end
    if not next(unfolding) then
        removeEventHandler("onClientPreRender",root,update)
        watching=false
    end
end

local function remove(ped)
    local strip = strips[ped]
    if not strip then return end
    for _,slat in pairs(strip.slats) do destroyElement(slat) end
    strips[ped],unfolding[ped]=nil,nil
end

local function observe(ped)
    local data = getElementData(ped,key,false)
    if type(data)~="table" or not isElementStreamedIn(ped) then remove(ped) return end
    local strip = strips[ped] or {slats={}}
    strips[ped]=strip
    local now = getTickCount()
    local age = data[6] or 2500
    if strip.received then age = math.min(2500, math.max(age, strip.age+(now-strip.received)%4294967296)) end
    strip.data,strip.age,strip.received=data,age,now
    if strip.age>=2500 then
        pose(ped,strip,2500)
        unfolding[ped]=nil
    else
        if not watching then
            addEventHandler("onClientPreRender",root,update)
            watching=true
        end
        unfolding[ped]=strip
    end
end

addEventHandler("onClientElementDataChange",resourceRoot,function(name) if name==key then observe(source) end end)
addEventHandler("onClientElementStreamIn",resourceRoot,function() if getElementType(source)=="ped" then observe(source) end end)
addEventHandler("onClientElementStreamOut",resourceRoot,function() remove(source) end)
addEventHandler("onClientElementDestroy",resourceRoot,function() remove(source) end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,ped in ipairs(getElementsByType("ped",resourceRoot,true)) do observe(ped) end
end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for ped in pairs(strips) do remove(ped) end
    if model then engineFreeModel(model) end
end)
