-- VCS US PS2 MAIN.SCM, SRANGEH_1015. Opcode 04D7 delegates the camera to
-- the native vehicle director (SLUS_215.90 0x0037b938).
VCSCreditScene = {}
local origin = {269.4673, -1158.7444, 10.9}
local order = {0,21,7,3,20,1,21,8,2,20,5,2,22,1}
-- Lateral and forward displacement, height, maximum tracking distance.
local roadside = {
    [1] = {3,20,1.5,40}, [2] = {2.5,16,0.5,29},
    [3] = {8,30,16,48}, [5] = {-6,30,3.5,38}
}
local controls = {"forwards","backwards","left","right","jump","sprint","fire","aim_weapon",
    "action","crouch","enter_exit","next_weapon","previous_weapon"}
local scene

local function usable(car)
    if not isElement(car) or not isElementStreamedIn(car) or isVehicleBlown(car)
        or getElementHealth(car) <= 250 then return false end
    local driver = getVehicleOccupant(car, 0)
    return driver and getElementType(driver) == "ped" and getElementMatrix(car)[3][3] > 0
end

local function chooseCar()
    local x,y,z = unpack(scene.anchor)
    local chosen, count = nil, 0
    -- SCM checks X/Y bounds and requires a driver and an empty passenger seat.
    for _,car in ipairs(getElementsWithinRange(x,y,z,104,"vehicle",0,getElementDimension(localPlayer))) do
        local cx,cy = getElementPosition(car)
        if car ~= scene.car and math.abs(cx-x) <= 60 and math.abs(cy-y) <= 60 and usable(car) then
            for seat = 1,getVehicleMaxPassengers(car) or 0 do
                if not getVehicleOccupant(car,seat) then
                    count = count+1
                    if math.random(count) == 1 then chosen = car end
                    break
                end
            end
        end
    end
    return chosen
end

local function clearSight(x,y,z,tx,ty,tz)
    return isLineOfSightClear(x,y,z,tx,ty,tz,true,false,false,true,false,false,false,scene.car)
end

local function wheel(m, lateral)
    local right,front,up,pos = m[1],m[2],m[3],m[4]
    return pos[1]+right[1]*lateral-front[1]*2.3+up[1]*0.3,
           pos[2]+right[2]*lateral-front[2]*2.3+up[2]*0.3,
           pos[3]+right[3]*lateral-front[3]*2.3+up[3]*0.3
end

-- 00383c18 indexes GAME.DTZ's modelIndices. The values below are the
-- original minimum Z and maximum XYZ of each eligible collision box.
local poles = {
    lamppost1={-3.3942,1.1005,.5,3.7621}, lamppost2={-6.0254,3.7528,.8347,6.3689},
    lamppost3={-3.8744,1.6144,.6449,4.2608}, bollardlight={-.5706,.2803,.2811,.6695},
    mlamppost={-4.5229,1.9146,.5237,4.8759}, streetlamp1={-2.6388,.5054,.5,3.1344},
    streetlamp2={-2.7368,.8274,.6,3.1297}, telgrphpole02={-.0318,.8195,.8524,9.5307},
    mtraffic1={-3.0789,5.4509,1.9034,3.3451}, mtraffic2={-3.2381,7.9101,1.1471,3.2701}
}

local function polePosition(m, ahead, paired, exclude)
    local x,y,z = unpack(m[4])
    local fx,fy = x+m[2][1]*ahead,y+m[2][2]*ahead
    local best, bestDist, bestPole
    for _,obj in ipairs(getElementsWithinRange(fx,fy,z,50,"object",0,getElementDimension(localPlayer))) do
        local bounds = poles[string.lower(getElementID(obj) or "")]
        if bounds and obj ~= exclude and isElementStreamedIn(obj) then
            local t = getElementMatrix(obj)
            local dist = (x-t[4][1])^2+(y-t[4][2])^2
            if t[3][3] > 0.9 and dist > 25 and (not bestDist or dist < bestDist) then
                local px,py,pz = bounds[2],bounds[3],bounds[4]
                local cx = t[4][1]+px*t[1][1]+py*t[2][1]+pz*t[3][1]
                local cy = t[4][2]+px*t[1][2]+py*t[2][2]+pz*t[3][2]
                local cz = t[4][3]+px*t[1][3]+py*t[2][3]+pz*t[3][3]
                if paired then cz = cz-1-(pz-bounds[1]*0.5-1)*math.random()
                else cz = cz-(pz-bounds[1])*0.5 end
                -- The native world probe tests buildings. The pole is a
                -- separate object, so exclude it from its own MTA ray.
                if isLineOfSightClear(cx,cy,cz,x,y,z,true,false,false,true,false,false,false,obj) then
                    best,bestDist,bestPole = {cx,cy,cz},dist,obj
                end
            end
        end
    end
    return best,bestPole
end

local function beginMovingShot(id,m,elapsed)
    local x,y,z = unpack(m[4])
    local a,b
    if id == 20 then
        -- 00382f40 and 00382e30 initialize and vary the aerial endpoints.
        local front = 50*(0.1+1.4*math.random())
        local back = 30*(0.5+0.5*math.random())
        local h = 55*(0.5+0.5*math.random())
        local side = 50*(0.5+0.5*math.random())
        for _ = 1,8 do
            local l,r = side*(2*math.random(0,1)-1),side*(2*math.random(0,1)-1)
            a = {x-back*m[2][1]+l*m[1][1],y-back*m[2][2]+l*m[1][2],z-back*m[2][3]+h}
            b = {x+front*m[2][1]+r*m[1][1],y+front*m[2][2]+r*m[1][2],z+front*m[2][3]+h}
            if clearSight(a[1],a[2],a[3],x,y,z) then break end
            a = nil
        end
        scene.zoomTime = 0.05*(0.5+1.5*math.random())
        scene.zoomIn,scene.zoomOut = math.random(0,1)==0,math.random(0,1)==0
    elseif id == 21 then
        a = polePosition(m,50,false)
    else
        local firstPole
        a,firstPole = polePosition(m,100,true)
        if a then b = polePosition(m,-50,true,firstPole) end
        if not b or not clearSight(a[1],a[2],a[3],b[1],b[2],b[3]) then return false end
        local dx,dy,dz = b[1]-a[1],b[2]-a[2],b[3]-a[3]
        local d = math.sqrt(dx*dx+dy*dy+dz*dz)
        if d < 3 then return false end
        a,b = {b[1]-dx/d,b[2]-dy/d,b[3]-dz/d},{a[1]+2*dx/d,a[2]+2*dy/d,a[3]+2*dz/d}
    end
    if not a then return false end
    scene.from,scene.to,scene.mode = a,b,id
    scene.shotStart = elapsed
    scene.shotEnd = elapsed+(id == 20 and 20000 or id == 21 and 10000 or 5000)
    return true
end

local function ease(t)
    return (1-math.cos(math.pi*math.max(0,math.min(1,t))))*0.5
end

local function drawMovingShot(m,elapsed)
    local x,y,z = unpack(m[4])
    local a,b = scene.from,scene.to
    local cx,cy,cz = unpack(a)
    local t = (elapsed-scene.shotStart)/(scene.shotEnd-scene.shotStart)
    local fov = 70
    if scene.mode == 21 then
        local dx,dy,dz = x-cx,y-cy,z-cz
        local d = math.max(1,math.sqrt(dx*dx+dy*dy+dz*dz))
        cx,cy,cz = cx+dx/d,cy+dy/d,cz+dz/d
        fov = 70-55*ease((d-1)/30)
        if t < 0.1 then fov = 70+(fov-70)*ease(t/0.1) end
    else
        local p = scene.mode == 22 and ease(t) or t
        cx,cy,cz = cx+p*(b[1]-cx),cy+p*(b[2]-cy),cz+p*(b[3]-cz)
        if scene.mode == 20 then
            local vx,vy,vz = getElementVelocity(scene.car)
            local lead = 1+math.sqrt(vx*vx+vy*vy+vz*vz)
            x,y,z = x+m[2][1]*lead,y+m[2][2]*lead,z+m[2][3]*lead
            local d = getDistanceBetweenPoints3D(x,y,z,cx,cy,cz)
            fov = 22-10*ease((d-60)/50)
            if scene.zoomIn and t < scene.zoomTime then fov = 70+(fov-70)*ease(t/scene.zoomTime) end
            if scene.zoomOut and t > 0.75 then fov = fov+(70-fov)*ease((t-0.75)*5) end
        end
    end
    setCameraMatrix(cx,cy,cz,x,y,z,0,fov)
end

local function setShot(m, elapsed)
    local x,y,z = unpack(m[4])
    for _ = 1,#order do
        scene.index = scene.index % #order+1
        local id = order[scene.index]
        local s = roadside[id]
        if id == 0 then
            local cx,cy,cz = wheel(m,-1.4)
            if clearSight(x,y,z,cx,cy,cz) then
                local xmin = getElementBoundingBox(scene.car)
                scene.lateral = xmin and xmin-0.33 or -1.4
                scene.mode,scene.shotEnd = 0,elapsed+5000
                return
            end
        elseif id >= 20 then
            if beginMovingShot(id,m,elapsed) then return end
        elseif s then
            local dx,dy = getElementVelocity(scene.car)
            local norm = math.sqrt(dx*dx+dy*dy)
            if norm < 0.001 then dx,dy = m[2][1],m[2][2] else dx,dy = dx/norm,dy/norm end
            local cx = x+dy*s[1]+dx*s[2]
            local cy = y-dx*s[1]+dy*s[2]
            local ground = getGroundPosition(cx,cy,z+5)
            local cz = (id == 3 and z or (ground or z))+s[3]
            if clearSight(x,y,z,cx,cy,cz) then
                scene.mode,scene.fixed = id,{cx,cy,cz}
                scene.shotEnd = math.huge
                return
            end
        end
        -- 7/8 require the player to be pursued in the watched vehicle.
        -- The credits mission clears wanted level before entering this loop.
    end
    scene.mode,scene.shotEnd = 6,elapsed+1000
end

function VCSCreditScene.start()
    if scene then return false end
    scene = {
        camera = {getCameraMatrix()}, target = getCameraTarget(), interior = getCameraInterior(),
        time = {getTime()}, anchor = {unpack(origin)}, index = 0, nextSearch = 3500,
        controls = {}, position = {getElementPosition(localPlayer)},
        alpha = getElementAlpha(localPlayer), frozen = isElementFrozen(localPlayer),
        collision = getElementCollisionsEnabled(localPlayer),
        canMove = not getPedOccupiedVehicle(localPlayer) and getElementInterior(localPlayer) == 0
    }
    for _,control in ipairs(controls) do
        scene.controls[control] = isControlEnabled(control)
        toggleControl(control,false)
    end
    return true
end

function VCSCreditScene.update(elapsed)
    if not scene or elapsed < 1000 then return end
    if not scene.ready then
        scene.ready = true
        setTime(21,0)
        setCameraInterior(0)
        if scene.canMove then
            setElementFrozen(localPlayer,true)
            setElementCollisionsEnabled(localPlayer,false)
            setElementAlpha(localPlayer,0)
            setElementPosition(localPlayer,unpack(origin))
        elseif getElementInterior(localPlayer) == 0 then
            scene.anchor = {getElementPosition(localPlayer)}
        end
        local x,y,z = unpack(scene.anchor)
        setCameraMatrix(x,y,z+3,x,y+10,z+1,0,70)
    end
    if elapsed < 3500 then return end
    if scene.car and not usable(scene.car) then
        scene.car,scene.mode,scene.nextSearch = nil,nil,elapsed
    end
    if elapsed >= scene.nextSearch then
        local car = chooseCar()
        if car then
            scene.car,scene.mode = car,nil
            scene.nextSearch = elapsed+math.random(10000,17999)
        else
            scene.nextSearch = elapsed+250
        end
    end
    if not scene.car then return end
    local m = getElementMatrix(scene.car)
    local x,y,z = unpack(m[4])
    local anchor = scene.anchor
    if (x-anchor[1])^2+(y-anchor[2])^2+(z-anchor[3])^2 > 16 then
        anchor[1],anchor[2],anchor[3] = x,y,z
        if scene.canMove then setElementPosition(localPlayer,x,y,z) end
    end
    if not scene.mode or elapsed >= scene.shotEnd then setShot(m,elapsed) end
    if scene.mode == 0 then
        local cx,cy,cz = wheel(m,scene.lateral)
        setCameraMatrix(cx,cy,cz,cx+m[2][1],cy+m[2][2],cz+m[2][3],0,70)
    elseif scene.mode >= 20 then
        drawMovingShot(m,elapsed)
    elseif scene.mode == 6 then
        setCameraMatrix(x-m[2][1]*6,y-m[2][2]*6,z+2,x,y,z,0,70)
    else
        local cx,cy,cz = unpack(scene.fixed)
        local limit = roadside[scene.mode][4]
        setCameraMatrix(cx,cy,cz,x,y,z,0,70)
        if (x-cx)^2+(y-cy)^2+(z-cz)^2 > limit^2 then scene.shotEnd = elapsed end
    end
    if elapsed >= (scene.nextLOS or 0) then
        scene.nextLOS = elapsed+200
        local cx,cy,cz = getCameraMatrix()
        if not clearSight(x,y,z,cx,cy,cz) then scene.shotEnd = elapsed end
    end
end

function VCSCreditScene.fadeAlpha(elapsed)
    if elapsed < 1000 then return 255*elapsed/1000 end
    return scene and scene.car and 0 or 255
end

function VCSCreditScene.stop()
    if not scene then return end
    if scene.ready then
        if scene.canMove then
            if not isPedDead(localPlayer) then setElementPosition(localPlayer,unpack(scene.position)) end
            setElementCollisionsEnabled(localPlayer,scene.collision)
            setElementAlpha(localPlayer,scene.alpha)
            setElementFrozen(localPlayer,scene.frozen)
        end
        setTime(unpack(scene.time))
        setCameraInterior(scene.interior)
        if isElement(scene.target) then setCameraTarget(scene.target)
        else setCameraMatrix(unpack(scene.camera)) end
    end
    for control,enabled in pairs(scene.controls) do toggleControl(control,enabled) end
    scene = nil
end
