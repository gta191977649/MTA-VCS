TrafficCustodyCamera = {}
local shot
local recoveryBearings={0,1,-1,2,-2,3,-3,4}

-- Mode 0x20, SLUS_215.90 0029A8F0. The model numbers in GAME.DTZ
-- root[15] resolve to these Eagle map IDs. Values are the original collision
-- box maxima at modelInfo->collision + 0x20, used as camera anchors.
local anchors = {
    lamppost1={1.1005,.5,3.7621}, lamppost2={3.7528,.8347,6.3689},
    lamppost3={1.6144,.6449,4.2608}, bollardlight={.2803,.2811,.6695},
    mlamppost={1.9146,.5237,4.8759}, streetlamp1={.5054,.5,3.1344},
    streetlamp2={.8274,.6,3.1297}, telgrphpole02={.8195,.8524,9.5307},
    mtraffic1={5.4509,1.9034,3.3451}, mtraffic2={7.9101,1.1471,3.2701}
}

local function unit(x,y,z)
    local n=math.sqrt(x*x+y*y+z*z)
    if n<.00001 then return 1,0,0,0 end
    return x/n,y/n,z/n,n
end

local function focus()
    -- The native camera follows node 1 of the ped skeleton. MTA's spine
    -- is the stable torso reference across on-foot and seated animations.
    local actor=localPlayer
    local vehicle=getPedOccupiedVehicle(localPlayer)
    if vehicle then
        actor=getVehicleOccupant(vehicle,0)
        if not actor or isPedDead(actor) then return getElementPosition(vehicle) end
    end
    local x,y,z=getPedBonePosition(actor,3)
    if x then return x,y,z end
    return getElementPosition(actor)
end

local function ground(x,y,z)
    local hit,_,_,h=processLineOfSight(x,y,z,x,y,z-100,true,false,false,true,false)
    return hit and h+.7 or z
end

local function officerView(s,mode,tx,ty,tz)
    if not isElement(s.officer) then return false end
    local ox,oy,oz=getElementPosition(s.officer)
    local dx,dy=unit(tx-ox,ty-oy,0)
    if mode==2 then
        -- 002A4538 places a low camera off to one side of the suspect.
        s.x,s.y=tx+5*dx+10*dy,ty+5*dy-10*dx
        s.z=ground(s.x,s.y,tz+5)
        return true
    end
    local fx,fy,fz=unit(tx-ox,ty-oy,tz-oz)
    fz=math.max(-.7071,math.min(0,fz))
    local horizontal=math.sqrt(1-fz*fz)
    fx,fy=dx*horizontal,dy*horizontal
    local cx,cy,cz=ox+3*dy-5*fx,oy-3*dx-5*fy,oz-5*fz
    local nx,ny,nz,distance=unit(cx-tx,cy-ty,cz-tz)
    distance=math.max(8,distance)
    s.x,s.y,s.z=tx+nx*distance,ty+ny*distance,tz+nz*distance
    return true
end

local function streetView(s,tx,ty,tz)
    local best=math.huge
    for _,kind in ipairs({"object","building"}) do
        local nearby=getElementsWithinRange(tx,ty,tz,30,kind,getElementInterior(localPlayer),getElementDimension(localPlayer))
        for _,element in ipairs(nearby or {}) do
            local id=getElementID(element) or ""
            local anchor=anchors[(id:gsub("_%x%x%x%x%x$",""))]
            if anchor and isElementStreamedIn(element) then
                local x,y,z=getElementPosition(element)
                local score=math.abs(17-math.sqrt((x-tx)^2+(y-ty)^2))
                local m=getElementMatrix(element)
                if score<best and m and m[3][3]>.9 then
                    local ax,ay,az=unpack(anchor)
                    x=x+m[1][1]*ax+m[2][1]*ay+m[3][1]*az
                    y=y+m[1][2]*ax+m[2][2]*ay+m[3][2]*az
                    z=z+m[1][3]*ax+m[2][3]*ay+m[3][3]*az
                    local dx,dy,dz=unit(x-tx,y-ty,z-tz)
                    if isLineOfSightClear(x,y,z,tx+dx,ty+dy,tz+dz,true,false,false,true,false,false,false,element) then
                        s.x,s.y,s.z,best=x,y,z,score
                    end
                end
            end
        end
    end
    return best<math.huge
end

local function ownsCamera(s)
    local target=getCameraTarget()
    if target and target~=s.lastTarget then return false end
    local current={getCameraMatrix()}
    if target==s.lastTarget then
        local same=true
        for i=1,#s.last do
            if math.abs(current[i]-s.last[i])>.002 then same=false; break end
        end
        if same then return true end
    end
    -- Some clients expose the fixed matrix on the next render rather than
    -- on the same Lua stack. Look-at distance in the getter is normalized.
    local x,y,z,tx,ty,tz,roll,fov=unpack(current)
    local fx,fy,fz=unit(tx-x,ty-y,tz-z)
    local v=s.command
    return not target and math.abs(x-v[1])<.002 and math.abs(y-v[2])<.002 and math.abs(z-v[3])<.002
        and math.abs(fx-v[4])<.002 and math.abs(fy-v[5])<.002 and math.abs(fz-v[6])<.002
        and math.abs(roll)<.01 and math.abs(fov-45)<.02
end

local function clip(x,y,z,tx,ty,tz)
    local hit,hx,hy,hz=processLineOfSight(tx,ty,tz,x,y,z,true,false,false,true,false)
    if hit then
        local dx,dy,dz=unit(tx-hx,ty-hy,tz-hz)
        x,y,z=hx+dx*.2,hy+dy*.2,hz+dz*.2
    end
    return x,y,z,(x-tx)^2+(y-ty)^2+(z-tz)^2
end

local function place(s,tx,ty,tz)
    local x,y,z,range=clip(s.x,s.y,s.z,tx,ty,tz)
    if range<4 then
        -- On a roof edge a ground-level candidate can lie a storey below
        -- the subject. Recover on the subject's floor before shortening the
        -- shot into the player's body. Try the current bearing first.
        local bearing=math.atan2(s.y-ty,s.x-tx)
        for _,offset in ipairs(recoveryBearings) do
            local angle=bearing+offset*math.pi/4
            local cx,cy,cz=tx+8*math.cos(angle),ty+8*math.sin(angle),tz+.7
            local ax,ay,az,clearance=clip(cx,cy,cz,tx,ty,tz)
            if clearance>range then
                x,y,z,range=ax,ay,az,clearance
                if clearance>=16 then
                    s.x,s.y,s.z=cx,cy,cz
                    break
                end
            end
        end
    end
    setCameraMatrix(x,y,z,tx,ty,tz,0,45)
    local fx,fy,fz=unit(tx-x,ty-y,tz-z)
    s.command={x,y,z,fx,fy,fz}
    s.last={getCameraMatrix()}
    s.lastTarget=getCameraTarget()
end

local function update(ms)
    local s=shot
    if not ownsCamera(s) then
        -- A fixed matrix may take a render to replace the previous follow
        -- camera. Do not write over an unrelated camera during that interval.
        if s.pendingReadback then
            s.pendingReadback=s.pendingReadback-1
            if s.pendingReadback>0 then return end
        end
        s.released=true
        removeEventHandler("onClientPreRender",root,update)
        return
    end
    s.pendingReadback=nil
    local tx,ty,tz=focus()
    local step=math.min(ms,100)*.05
    if s.mode==1 then
        local oldZ=s.z
        if officerView(s,1,tx,ty,tz) then s.z=math.min(oldZ+.1*step,s.z) end
    elseif s.mode>=3 then
        local fx,fy=unit(tx-s.x,ty-s.y,0)
        local dx,dy=fy,-fx
        if s.mode==5 or s.mode==6 then dx,dy=-dx,-dy end
        if s.mode==7 then dx,dy=unit(tx-s.x+10*dx,ty-s.y+10*dy,0) end
        if isLineOfSightClear(s.x,s.y,s.z,s.x+dx*.5,s.y+dy*.5,s.z,true,true,false,true,false) then
            s.x,s.y=s.x+dx*.1*step,s.y+dy*.1*step
            if s.mode==4 or s.mode==6 then s.z=s.z+.05*step
            elseif s.mode~=7 then s.z=ground(s.x,s.y,s.z) end
        end
    end
    place(s,tx,ty,tz)
end

function TrafficCustodyCamera.finish()
    if not shot then return end
    local s=shot
    shot=nil
    if not s.released then removeEventHandler("onClientPreRender",root,update) end
    if ownsCamera(s) then
        if isElement(s.previousTarget) then setCameraTarget(s.previousTarget)
        elseif s.previousTarget then setCameraTarget(localPlayer)
        else setCameraMatrix(unpack(s.previous)) end
    end
end

function TrafficCustodyCamera.begin(officer)
    if shot then return end
    local s={officer=officer,previousTarget=getCameraTarget(),previous={getCameraMatrix()},pendingReadback=2}
    local tx,ty,tz=focus()
    local vehicle=getPedOccupiedVehicle(localPlayer)
    if vehicle and s.previousTarget==vehicle then s.previousTarget=localPlayer end
    local choices
    if vehicle then choices=math.random()>.5 and {1,2,7} or {2,1,7}
    else choices=math.random()>.65 and {1,7,2} or {7,2,1} end
    for _,mode in ipairs(choices) do
        if (mode==7 and streetView(s,tx,ty,tz)) or (mode~=7 and officerView(s,mode,tx,ty,tz)) then
            s.mode=mode==2 and math.random(2,6) or mode
            shot=s
            place(s,tx,ty,tz)
            addEventHandler("onClientPreRender",root,update)
            return true
        end
    end
    return false
end

addEventHandler("onClientResourceStop",resourceRoot,TrafficCustodyCamera.finish)
addEventHandler("onClientPlayerWasted",localPlayer,TrafficCustodyCamera.finish)
