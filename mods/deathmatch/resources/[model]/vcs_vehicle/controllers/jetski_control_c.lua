-- Water-specific handling cannot be written through MTA's generic handling
-- setter. Correct the local axes after the native 473 hull applies its drag.
local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local mass, turnMass = 978.94458, CJetSki.turnMass
local massOverInertia = mass/turnMass
-- Inflated GAME.DTZ, 0x43F270 (JETSKI COL1), and 0x4C23E0+0x40.
local minX, minY, minZ = -0.5827483, -1.1909134, -0.3397498
local maxX, maxY, maxZ = 0.5834653, 1.5883691, 0.7860215
local skiVolume = {0.75,0.9,0.75, 0.95,1,0.95, 0.4,0.7,0.4}
local dinghyVolume = {0.65,0.85,0.65, 0.85,1.1,0.85, 0.65,0.95,0.65}

-- 00369630/0036A090/00369EE8: nine hull columns. The native SA solver
-- already applies one grid. Evaluate both and apply only the difference.
local function displacement(m, vz, wx, wy, limits, weights, original)
    local left, stern, bottom, right, bow, top = unpack(limits)
    local lift, rollX, rollY, immersion, turnY, count = 0, 0, 0, 0, 0, 0
    for row = 0,2 do
        local fore = stern + (bow-stern)*row/2
        for column = 0,2 do
            local side = left + (right-left)*column/2
            local x = m[1][1]*side + m[2][1]*fore
            local y = m[1][2]*side + m[2][2]*fore
            local z = m[1][3]*side + m[2][3]*fore
            local water = getWaterLevel(m[4][1]+x,m[4][2]+y,m[4][3],true)
            if type(water) == "number" then
                local depth = clamp(water-m[4][3]-z, bottom, top)
                local weight = weights[row*3+column+1]
                local volume = (math.max(0, depth-bottom-(1-weight))*weight)^2/(9*(top-bottom))
                local force = volume*(0.8/17)*math.max(0,1-3*(vz+wx*y-wy*x))
                lift = lift+force
                local armZ = original and top or depth
                rollX = rollX + (y+m[3][2]*armZ)*force
                rollY = rollY - (x+m[3][1]*armZ)*force
                immersion = immersion + volume
                if volume>0 then
                    turnY = turnY + fore*volume*9*(top-bottom)
                    count = count+1
                end
            end
        end
    end
    return lift,rollX,rollY,immersion,turnY/math.max(1,count)
end

local skiHull = {minX*1.5,minY*0.9,minZ,maxX*1.5,maxY,maxZ}
local nativeDinghy = {minX,minY*0.9,minZ-0.2,maxX,maxY*1.3,maxZ}
local nativeGeneric = {minX,minY*0.9,minZ,maxX,maxY*1.05,maxZ}

function CJetSki.HasOverturnLift(vehicle)
    local m = getElementMatrix(vehicle)
    if not m or m[3][3]>=-0.6 or not isElementInWater(vehicle) then return false end
    local _,_,vz = getElementVelocity(vehicle)
    local wx,wy = getElementAngularVelocity(vehicle)
    return displacement(m,vz,wx,wy,skiHull,skiVolume,true)>0.0008
end

local function damp(matrix, x, y, z, right, forward, up)
    local a,b,c = matrix[1],matrix[2],matrix[3]
    right = (a[1]*x+a[2]*y+a[3]*z)*(right-1)
    forward = (b[1]*x+b[2]*y+b[3]*z)*(forward-1)
    up = (c[1]*x+c[2]*y+c[3]*z)*(up-1)
    return x+a[1]*right+b[1]*forward+c[1]*up,
        y+a[2]*right+b[2]*forward+c[2]*up, z+a[3]*right+b[3]*forward+c[3]*up
end

function CJetSki:ApplyWaterResistance(m, step)
    local x,y,z = getElementVelocity(self.vehicle)
    local strength = clamp((math.sqrt(x*x+y*y)-0.1)*10,0,1)
    local balance = getPedControlState(localPlayer,"handbrake") and 1 or -self.longitudinal
    local yaw = clamp(0.902+balance*strength*0.09,0.1,0.99)
    local side = clamp(0.28+0.2*balance,0.001,0.99)
    side = clamp(side+(1-side)*(1-m[3][3]),0.001,0.99)
    local up = clamp(0.843+0.157*math.abs(m[2][3]),0.001,0.99)
    local fwd = m[2][1]*x+m[2][2]*y+m[2][3]*z
    local moveY = y
    local drag = (fwd*fwd+0.05)*0.2*mass/1000
    local ratio = (1+drag*self.nativeImmersion^2)/(1+drag*self.immersion^2)
    local rx,ry = damp(m,x,y,z,(ratio*side/0.94)^(step/2),
        (ratio*0.997/0.993)^(step/2),(ratio*up/0.997)^(step/2))
    local resistance = 1/(1+drag*self.immersion^2)
    local vertical = (resistance*up)^(step/2)
    -- The horizontal velocity above comes back from SA's tilted hull.
    -- Heave is integrated separately in ProcessBuoyancy. Projecting the
    -- measured sideslip onto it applies a second downward impulse in turns.
    setElementVelocity(self.vehicle,rx,ry,z*vertical*vertical)
    x,y,z = getElementAngularVelocity(self.vehicle)
    -- 001A3650 also applies the longitudinal water resistance below the
    -- centre of mass. The drag flattens the bow as forward speed builds.
    -- 001A3920/001A39C8 load world move-speed Y for this moment.
    local pitch = ((resistance*0.997)^(step/2)-1)*moveY*massOverInertia
    x,y,z = x+m[1][1]*pitch,y+m[1][2]*pitch,z+m[1][3]*pitch
    setElementAngularVelocity(self.vehicle,damp(m,x,y,z,0.772^step,0.729^step,(yaw/0.94)^step))
end

function CJetSki:ProcessBuoyancy(m, step, throttle)
    local x,y,z = getElementVelocity(self.vehicle)
    local wx,wy,wz = getElementAngularVelocity(self.vehicle)
    -- Continue the VCS vertical and tilt velocities across native frames.
    -- Keep native yaw, horizontal motion and collision impulses.
    local previous = self.surfaceMotion
    if previous then
        z = previous.z
        local yaw = wx*m[3][1]+wy*m[3][2]+wz*m[3][3]
        wx = m[1][1]*previous.pitch+m[2][1]*previous.roll+m[3][1]*yaw
        wy = m[1][2]*previous.pitch+m[2][2]*previous.roll+m[3][2]*yaw
        wz = m[1][3]*previous.pitch+m[2][3]*previous.roll+m[3][3]*yaw
    end
    local ski, sx, sy, immersion, turnY = displacement(m,z,wx,wy,skiHull,skiVolume,true)
    local dinghy = getElementModel(self.vehicle)==473
    local native,_,_,nativeImmersion = displacement(m,z,wx,wy,
        dinghy and nativeDinghy or nativeGeneric, dinghy and dinghyVolume or skiVolume)
    self.immersion,self.nativeImmersion = immersion,nativeImmersion
    local centre = self:GetCentreOfMass()
    local dx = m[1][1]*centre[1]+m[2][1]*centre[2]
    local dy = m[1][2]*centre[1]+m[2][2]*centre[2]
    local lift = ski*step
    z = z + (ski-getGravity())*step
    wx = wx+(sx-dy*ski)*step*massOverInertia
    wy = wy+(sy+dx*ski)*step*massOverInertia

    -- The original treats a capsized jetski separately from a drowning boat.
    -- 001A07xx applies local right * 10 at the up vector (forward-axis roll).
    if m[3][3]<-0.6 and ski>0.0008 then
        local roll = 10*step/turnMass
        wx,wy,wz = wx+m[2][1]*roll,wy+m[2][2]*roll,wz+m[2][3]*roll
    end
    if self.skipTime and self.skipTime < 0 then
        local speed = math.sqrt(x*x+y*y+z*z)
        local dot = speed>0 and (x*m[2][1]+y*m[2][2]+z*m[2][3])/speed or 0
        self.skipTime = math.max(0,50*(1-math.abs(m[1][3]))*
            (1-math.min(1,math.abs(m[2][3]+0.5)))*dot*math.abs(m[2][3]))
    end
    if self.skipTime and self.skipTime > 0 then
        local lean = self.longitudinal
        self.skipTime = math.max(0,self.skipTime-step+lean*step*(lean<0 and 1 or 0.3)
            -(math.abs(self.lateral)>0.1 and math.abs(self.lateral)*step or 0))
        if self.skipTime > 0 then z=z-0.7*lift end
    end
    if m[3][3]>0 and throttle>0.05 then
        local scale=(x*x+y*y+z*z)*step*0.5*throttle
        local skiPlane=math.min(5.3*scale*ski,0.53*0.008)*step
        local donorPlane=math.min(5*scale*native,0.30*0.008)*step
        local delta=skiPlane-donorPlane
        x,y,z=x+m[3][1]*delta,y+m[3][2]*delta,z+m[3][3]*skiPlane
        local pitch=(turnY+0.3-centre[2])*skiPlane*massOverInertia
        wx,wy,wz=wx+m[1][1]*pitch,wy+m[1][2]*pitch,wz+m[1][3]*pitch
    end
    setElementVelocity(self.vehicle,x,y,z)
    setElementAngularVelocity(self.vehicle,wx,wy,wz)
end

-- 001A15xx: submerged jet outlet and thrust application point are distinct.
function CJetSki:ProcessThrust(m,step)
    if m[3][3]<-0.6 or not getVehicleEngineState(self.vehicle) then return end
    if not self.customThrust then
        self.customThrust = getVehicleHandling(self.vehicle).engineAcceleration==0
        if not self.customThrust then return end
    end
    local rx = minY*m[2][1]+minZ*0.1*m[3][1]
    local ry = minY*m[2][2]+minZ*0.1*m[3][2]
    local rz = minY*m[2][3]+minZ*0.1*m[3][3]
    local water = getWaterLevel(m[4][1]+rx,m[4][2]+ry,m[4][3]+rz,true)
    if type(water)~="number" then return end
    local depth = clamp(water-m[4][3]-rz+0.5,0,1)^2
    if depth==0 then return end
    local x,y,z = getElementVelocity(self.vehicle)
    local forward = m[2][1]*x+m[2][2]*y+m[2][3]*z
    local speed = math.sqrt(x*x+y*y)
    if math.abs(self.throttle)<=0.05 and speed<=0.01 then return end
    local steering = self.steer*math.abs(self.steer)*math.rad(40)
    local nozzle = steering*clamp(1-forward*0.15,0,1)
    local impulse = 40*0.000256*depth*self.throttle*step
    if self.throttle<0 and forward>0 and x*x+y*y+z*z>0.001 then impulse=impulse*10 end
    local side,fore,down = math.sin(nozzle),math.cos(nozzle),-math.abs(steering)
    local fx = (m[1][1]*side+m[2][1]*fore+m[3][1]*down)*impulse
    local fy = (m[1][2]*side+m[2][2]*fore+m[3][2]*down)*impulse
    local fz = (m[1][3]*side+m[2][3]*fore+m[3][3]*down)*impulse
    local direction = self.throttle < 0 and -1 or 1
    local baseZ = direction*fz*mass/step
    if baseZ>0.8 then
        if m[4][3]>=water then fx,fy,fz = fx*0.5,fy*0.5,0 end
    elseif baseZ>0.2 then
        fz = direction*((1.2-baseZ)^2+0.2)*step/mass
    end
    setElementVelocity(self.vehicle,x+fx,y+fy,z+fz)
    rx,ry,rz = rx+0.2*m[3][1],ry+0.2*m[3][2],rz+0.2*m[3][3]
    -- The turning jet continues to produce a moment when coasting. The
    -- original scales it from zero to full over the first 0.15 velocity units.
    if math.abs(self.throttle)<0.1 then
        local residual = 40*0.000256*step*depth*math.min(1,speed/0.15)
        if forward<=0 then residual=-residual end
        fx = (m[1][1]*side+m[2][1]*fore+m[3][1]*down)*residual
        fy = (m[1][2]*side+m[2][2]*fore+m[3][2]*down)*residual
        fz = (m[1][3]*side+m[2][3]*fore+m[3][3]*down)*residual
    end
    -- The lateral jet force also acts against traction at the up vector.
    local bank = -(m[1][1]*fx+m[1][2]*fy+m[1][3]*fz)
    local wx,wy,wz = getElementAngularVelocity(self.vehicle)
    setElementAngularVelocity(self.vehicle,wx+(ry*fz-rz*fy+m[2][1]*bank)*massOverInertia,
        wy+(rz*fx-rx*fz+m[2][2]*bank)*massOverInertia,
        wz+(rx*fy-ry*fx+m[2][3]*bank)*massOverInertia)
end

local bars = setmetatable({}, {__mode="k"})
function CJetSki.SetHandlebars(vehicle, steer)
    local rest = bars[vehicle]
    if not rest then
        if (getVehicleComponents(vehicle) or {}).handlebars == nil then return end
        local x,y,z = getVehicleComponentRotation(vehicle, "handlebars")
        if not x then return end
        rest = {x,y,z}
        bars[vehicle] = rest
    end
    setVehicleComponentRotation(vehicle, "handlebars", rest[1], rest[2], rest[3]+40*steer*math.abs(steer))
end

local function resetBars(vehicle)
    local rest = bars[vehicle]
    if rest and isElement(vehicle) then setVehicleComponentRotation(vehicle, "handlebars", unpack(rest)) end
    bars[vehicle] = nil
end

local active
local watercraft = setmetatable({}, {__mode="k"})
local function track(vehicle)
    if getElementType(vehicle)=="vehicle" then watercraft[vehicle]=CVehicle.resolve(vehicle)==CJetSki or nil end
end
addEventHandler("onClientElementStreamIn",root,function() track(source) end)
addEventHandler("onClientElementStreamOut",root,function() watercraft[source]=nil end)
addEventHandler("onClientElementDataChange",root,function(key)
    if (key==CVehicle.modelKey or key=="mod.model" or key=="npchlc_traffic:originalModel")
        and isElementStreamedIn(source) then track(source) end
end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,vehicle in ipairs(getElementsByType("vehicle",root,true)) do track(vehicle) end
end,false)

-- 0019FDA0 statuses 4/5 still run the wet subtype-2 capsized branch.
-- An empty hull can roll upright after the driver has fallen off.
local function rightUnoccupied(step)
    for vehicle in pairs(watercraft) do
        if isElement(vehicle) and isElementSyncer(vehicle) and not getVehicleOccupant(vehicle,0)
            and isElementInWater(vehicle) and not isElementFrozen(vehicle) then
            local m=getElementMatrix(vehicle)
            if m and m[3][3]<-0.6 and CJetSki.HasOverturnLift(vehicle) then
                local x,y,z=getElementAngularVelocity(vehicle)
                local impulse=10*step/turnMass
                setElementAngularVelocity(vehicle,x+m[2][1]*impulse,
                    y+m[2][2]*impulse,z+m[2][3]*impulse)
            end
        end
    end
end

local function release()
    if active then resetBars(active.vehicle) end
    active = nil
end

local function input(name)
    return isControlEnabled(name) and getAnalogControlState(name) or 0
end

local function clearedWater(vehicle,m)
    local water = getWaterLevel(m[4][1],m[4][2],m[4][3],true)
    if type(water)~="number" or isVehicleOnGround(vehicle) then return false end
    local lowest = m[4][3] + math.min(minX*m[1][3],maxX*m[1][3])
        + math.min(minY*m[2][3],maxY*m[2][3]) + math.min(minZ*m[3][3],maxZ*m[3][3])
    return lowest>water
end

function CJetSki:ProcessControl(step)
    self:ProcessControlInputs(input("accelerate"), input("brake_reverse"),
        input("vehicle_left")-input("vehicle_right"), input("steer_forward")-input("steer_back"),
        getPedControlState(localPlayer,"handbrake"), step)
    CJetSki.SetHandlebars(self.vehicle, self.steer)
    local m = getElementMatrix(self.vehicle)
    if not m or step<=0 then return end
    if self.contactTick and (getTickCount()-self.contactTick)%4294967296<100 then
        self.surfaceMotion = nil
        return
    end
    if isElementInWater(self.vehicle) then
        self:ProcessBuoyancy(m,step,self.throttle)
        self:ProcessThrust(m,step)
        self:ApplyWaterResistance(m,step)
        local _,_,z = getElementVelocity(self.vehicle)
        local wx,wy,wz = getElementAngularVelocity(self.vehicle)
        self.surfaceMotion = {z=z,pitch=wx*m[1][1]+wy*m[1][2]+wz*m[1][3],
            roll=wx*m[2][1]+wy*m[2][2]+wz*m[2][3]}
    else
        self.surfaceMotion = nil
        if clearedWater(self.vehicle,m) then
            self.skipTime = -1
            -- 001A3278/001A347C apply an up or right force at the forward arm.
            local x,y,z = getElementVelocity(self.vehicle)
            local speed = math.min(0.1,math.sqrt(x*x+y*y+z*z))*step
            local pitch = -self.longitudinal*0.01*speed
            local yaw = self.lateral*0.49*0.01*speed
            local wx,wy,wz = getElementAngularVelocity(self.vehicle)
            setElementAngularVelocity(self.vehicle,wx+m[1][1]*pitch+m[3][1]*yaw,
                wy+m[1][2]*pitch+m[3][2]*yaw,wz+m[1][3]*pitch+m[3][3]*yaw)
        else
            self.skipTime = nil
        end
    end
end

addEventHandler("onClientPreRender",root,function(elapsed)
    local step = math.min(elapsed,100)*getGameSpeed()/20
    rightUnoccupied(step)
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicle or getVehicleController(vehicle) ~= localPlayer or CVehicle.resolve(vehicle) ~= CJetSki then
        if active then release() end
        return
    end
    if not active or active.vehicle ~= vehicle then release() active = CJetSki:New(vehicle) end
    active:ProcessControl(step)
end)
addEventHandler("onClientVehicleCollision",root,function()
    if active and active.vehicle==source then active.contactTick=getTickCount() end
end)
addEventHandler("onClientVehicleExit",root,function(_,seat)
    if seat==0 then resetBars(source) end
end)
addEventHandler("onClientElementStreamOut",root,function() resetBars(source) end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for vehicle in pairs(bars) do resetBars(vehicle) end
    active = nil
end,false)
