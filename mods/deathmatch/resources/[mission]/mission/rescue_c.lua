local cableKey = "mission:airRescueCable"
local attachmentKey = "mission:attachmentModel"

-- Both SCM scripts set the patient to be damaged only by the mission player.
addEventHandler("onClientPedDamage",root,function(attacker)
    local owner=getElementData(source,"mission:rescuePatient",false)
    if not isElement(owner) then return end
    if isElement(attacker) and getElementType(attacker)=="vehicle" then attacker=getVehicleController(attacker) end
    if attacker~=owner then cancelEvent() end
end)

local rigs = {}
local flightKey="mission:preserverFlight"
local releaseTicks=setmetatable({}, {__mode="k"})
local assets = { [7350]={file="assets/ndc_helibucket"}, [7353]={file="assets/ndc_helirescuerig"},
    [7375]={file="assets/dr_lifesaver"} }

local function releaseModel(a)
    local model, dictionary, mesh = a.model, a.dictionary, a.mesh
    if model then
        engineRestoreModel(model)
        engineFreeModel(model)
    end
    if isElement(mesh) then destroyElement(mesh) end
    if isElement(dictionary) then destroyElement(dictionary) end
    a.model, a.dictionary, a.mesh, a.users = nil, nil, nil, 0
end

local function loadModel(a)
    if a.model then return a.model end
    local model, dictionary, mesh
    model = engineRequestModel("object",1271)
    if model then
        dictionary = engineLoadTXD(a.file..".txd")
        if dictionary and engineImportTXD(dictionary,model) then
            mesh = engineLoadDFF(a.file..".dff")
            if mesh and engineReplaceModel(mesh,model,true) then
                engineSetModelLODDistance(model,200)
                a.model, a.dictionary, a.mesh = model, dictionary, mesh
                return model
            end
        end
    end
    a.model, a.dictionary, a.mesh = model, dictionary, mesh
    releaseModel(a)
    outputDebugString("Could not load mission attachment "..a.file,1)
    return false
end

local function releaseUnused(asset)
    if asset.model and (asset.users or 0)==0 then releaseModel(asset) end
end

local function removeHook(hook)
    local rig = rigs[hook]
    if not rig then return end
    rigs[hook] = nil
    if rig.id~=7375 then
        local frontend=getResourceFromName("frontend")
        if frontend and getResourceState(frontend)=="running" then
            exports.frontend:setRescueWinchVisible(hook,false)
        end
    end
    if isElement(rig.object) then destroyElement(rig.object) end
    local asset=assets[rig.id]
    asset.users=asset.users-1
    releaseUnused(asset)
end

local function registerHook(hook)
    if getElementType(hook) ~= "object" or not isElementStreamedIn(hook) then return end
    local tag = getElementData(hook,cableKey,false)
    local id = getElementData(hook,attachmentKey,false) or (tag==true and 7353 or tag)
    if rigs[hook] then
        if rigs[hook].id==id and isElement(rigs[hook].object) then return end
        removeHook(hook)
    end
    local asset=assets[id]
    if not asset then return end
    local model = loadModel(asset)
    if not model then return end
    local rig = createObject(model,getElementPosition(hook))
    if not rig then return releaseUnused(asset) end
    setElementInterior(rig,getElementInterior(hook))
    setElementDimension(rig,getElementDimension(hook))
    setElementCollisionsEnabled(rig,false)
    setElementDoubleSided(rig,true)
    if not attachElements(rig,hook) then
        destroyElement(rig)
        return releaseUnused(asset)
    end
    asset.users=(asset.users or 0)+1
    rigs[hook] = {object=rig,id=id}
    setElementData(rig,"mission:rescueRigModel",id,false)
    if id~=7375 then exports.frontend:setRescueWinchVisible(hook,true) end
end

addEventHandler("onClientElementStreamIn",resourceRoot,function() registerHook(source) end)
addEventHandler("onClientElementStreamOut",resourceRoot,function() removeHook(source) end)
addEventHandler("onClientElementDestroy",resourceRoot,function() removeHook(source) end)
addEventHandler("onClientElementDataChange",resourceRoot,function(key)
    if key==flightKey then releaseTicks[source]=getTickCount() end
    if key==cableKey or key==attachmentKey then registerHook(source) end
end)
addEventHandler("onClientPreRender",root,function()
    for hook,rig in pairs(rigs) do
        if rig.id==7375 then
            if not rig.flight then
                local launch=getElementData(hook,flightKey,false)
                local guard=getElementAttachedTo(hook)
                if launch then
                    rig.flight=launch
                    rig.released=releaseTicks[hook] or getTickCount()
                    if getElementAttachedTo(rig.object) then detachElements(rig.object) end
                elseif isElement(guard) and getElementType(guard)=="ped" then
                    local x,y,z=getPedBonePosition(guard,25)
                    if x then
                        if getElementAttachedTo(rig.object) then detachElements(rig.object) end
                        rig.hand={x,y,z}
                        setElementPosition(rig.object,x,y,z)
                        setElementRotation(rig.object,0,-90,0)
                    end
                end
            end
            local f=rig.flight
            if f then
                local t=math.min(f.waterAt,((getTickCount()-rig.released)%4294967296+f.age)/1000)
                local x,y,z=f.x+f.vx*t,f.y+f.vy*t,f.z+f.vz*t-0.5*f.gravity*t*t
                if rig.hand then
                    -- Carry the animated hand offset into the first frames of flight.
                    local blend=math.max(0,1-t/0.14)
                    x,y,z=x+(rig.hand[1]-f.x)*blend,y+(rig.hand[2]-f.y)*blend,z+(rig.hand[3]-f.z)*blend
                end
                setElementPosition(rig.object,x,y,z)
                setElementRotation(rig.object,0,-90*(1-t/f.waterAt),f.side*300*t)
            end
        end
    end
end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,hook in ipairs(getElementsByType("object",resourceRoot,true)) do registerHook(hook) end
end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for hook in pairs(rigs) do removeHook(hook) end
    for _,a in pairs(assets) do releaseModel(a) end
end)
