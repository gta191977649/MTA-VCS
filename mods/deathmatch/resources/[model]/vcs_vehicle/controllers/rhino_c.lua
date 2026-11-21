-- On native model 432 GTA draws its middle wheel templates four times per
-- side. The VCS model has three axles and supplies six separate visible
-- components. The original SA wheel dummies still provide animated poses.
local rhinos = {}

local function track(vehicle)
    if getElementType(vehicle) ~= "vehicle" then return end
    rhinos[vehicle] = getElementModel(vehicle) == 432 and {} or nil
end

local function forget()
    rhinos[source] = nil
end

local function findWheels(vehicle)
    local components = getVehicleComponents(vehicle)
    if not components then return end
    local wheels = {}
    for _, axle in ipairs({"f","m","b"}) do
        for _, side in ipairs({"l","r"}) do
            local key = side..axle
            local visible, native = "vcs_wheel_"..key, "wheel_"..key.."_dummy"
            if components[visible] == nil or components[native] == nil then return end
            local x,y = getVehicleComponentPosition(vehicle,visible,"root")
            if not x then return end
            wheels[key] = {visible=visible, native=native, x=x, y=y}
        end
    end
    return wheels
end

local function pose(vehicle,wheel,z)
    local rx,ry,rz = getVehicleComponentRotation(vehicle,wheel.native,"root")
    if not rx then return end
    setVehicleComponentRotation(vehicle,wheel.visible,rx,ry,rz,"root")
    setVehicleComponentPosition(vehicle,wheel.visible,wheel.x,wheel.y,z,"root")
end

local function updateSide(vehicle,front,middle,rear)
    local _,_,fz = getVehicleComponentPosition(vehicle,front.native,"root")
    local _,_,rz = getVehicleComponentPosition(vehicle,rear.native,"root")
    if not fz or not rz then return false end
    local fraction = (middle.y-rear.y)/(front.y-rear.y)
    pose(vehicle,front,fz)
    pose(vehicle,middle,rz+(fz-rz)*fraction)
    pose(vehicle,rear,rz)
    return true
end

addEventHandler("onClientElementStreamIn",root,function() track(source) end)
addEventHandler("onClientElementModelChange",root,function()
    if isElementStreamedIn(source) then track(source) end
end)
addEventHandler("onClientElementStreamOut",root,forget)
addEventHandler("onClientElementDestroy",root,forget)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,vehicle in ipairs(getElementsByType("vehicle",root,true)) do track(vehicle) end
end)

addEventHandler("onClientPreRender",root,function()
    local now = getTickCount()
    for vehicle,state in pairs(rhinos) do
        if not state.checked or (now-state.checked)%4294967296 >= 1000 then
            -- Model replacement can arrive after stream-in, including for
            -- untagged vehicles already using the globally replaced slot.
            state.checked = now
            state.wheels = findWheels(vehicle)
        end
        local w = state.wheels
        if w and (not updateSide(vehicle,w.lf,w.lm,w.lb) or not updateSide(vehicle,w.rf,w.rm,w.rb)) then
            state.wheels = nil
        end
    end
end)

addEventHandler("onClientResourceStop",resourceRoot,function()
    for vehicle,state in pairs(rhinos) do
        for _,wheel in pairs(state.wheels or {}) do
            resetVehicleComponentPosition(vehicle,wheel.visible)
            resetVehicleComponentRotation(vehicle,wheel.visible)
        end
    end
end)
