-- US PS2 CBoat::ProcessControl (0019FDA0), side emitters (003F29D8)
-- and CParticle update (001E9C90). All velocities are metres per 20 ms.
VCSBoatParticles = {}

local carSplash, boatSplash = 0x2C, 0x2D
local period, step = 1000/30, 50/30
local profiles = {}
local displacement = {0.75,0.9,0.75, 0.95,1,0.95, 0.4,0.7,0.4}
local planing = {0.7,0.9,0.7, 0.95,1,0.95, 0.6,0.7,0.6}

-- GAME.DTZ model-info +44 -> boat handling. The stern nozzle force is
-- model-info +38 -> mass * transmission acceleration * 40.
local function profile(ids, carry, rise, spread, fore, beam, height, nozzleY, nozzleZ,
                       force, weights, sideScale, sternScale, bowScale)
    for _,id in ipairs(ids) do
        profiles[id]={carry=carry,rise=rise,spread=spread,fore=fore,beam=beam,height=height,
            nozzleY=nozzleY,nozzleZ=nozzleZ,force=force,weights=weights,
            sideScale=sideScale,sternScale=sternScale,bowScale=bowScale}
    end
end
profile({214},-.5,.19,.32,.61,1.5,0,.35,.6,11.2,displacement,1,.9,1)
profile({215,257,258},-.5,.25,.35,.75,.5,0,.65,1,17.6,planing,1,.83,1.25)
profile({219},-.5,.34,.55,.98,.52,0,.35,.6,11.968,displacement,1,.9,1.5)
profile({225},-.5,.25,.35,.75,.96,0,.41,1,17.6,planing,1,.83,1.25)
profile({233},-.5,.25,.35,.75,.5,0,1,.1,10.02439,displacement,1.5,.9,1)
profile({247},-.46,.15,1,.15,1.12,0,.66,.77,15.2,displacement,1,.9,1)
profile({248,249,250},-.5,.25,.35,.75,.5,0,.35,.6,11.2,displacement,1,.9,1)
profile({264},-.49,.04,.7,.43,1.21,.09,.94,1,17.6,planing,1,.83,1.25)
profile({277},-.5,.34,.55,.98,.52,0,.25,.76,11.968,displacement,1,.9,1.5)

-- Original model-info +14h collision box, independent of the MTA donor hull.
local collisionBoxes={
    [214]={-2.62895584, -5.05262852, -0.931939125, 2.63032341, 6.88692379, 4.6014514},
    [215]={-1.80572367, -4.55666256, -0.58204937, 1.79801559, 7.28390312, 1.60566854},
    [219]={-2.38583136, -4.71942711, -0.79800415, 2.38254642, 8.45184898, 3.18426013},
    [225]={-2.27410483, -6.63492107, -0.856649399, 2.27410483, 6.50653934, 2.43358612},
    [233]={-0.582748294, -1.19091344, -0.339749783, 0.583465338, 1.58836913, 0.786021471},
    [247]={-1.42714298, -2.18704128, -0.323543459, 1.44998348, 2.69789505, 0.933786988},
    [248]={-2.674716, -7.39885616, -1.80127454, 2.66945076, 13.1017771, 3.11782575},
    [249]={-2.46909618, -5.39033937, -1.58313155, 2.44872379, 6.99189997, 1.53261065},
    [250]={-3.37592411, -5.38102722, -2.14533949, 3.28379917, 9.52668953, 2.39056826},
    [257]={-2.40185595, -6.77815056, -0.60837996, 2.3713131, 7.60400772, 1.8768295},
    [258]={-2.35474491, -4.25993729, -0.53761214, 2.35412884, 9.29294968, 1.94760489},
    [264]={-1.92500007, -6.02204418, -1.3249886, 1.92500007, 6.04643631, 1.50669932},
    [277]={-1.51551962, -4.67060184, -0.290123701, 1.53156805, 4.56741619, 3.39254069},
}

function VCSBoatParticles.hasHull(original)
    return profiles[tonumber(original)]~=nil
end

function VCSBoatParticles.hull(boat,state)
    local model=getElementModel(boat)
    local s=state.splashHull
    local id=tonumber(getElementData(boat,"vcs_vehicle:originalModel",false)
        or getElementData(boat,"npchlc_traffic:originalModel",false))
    if not id and getElementData(boat,"mod.model",false)=="JETSKI" then id=233 end
    if s and s.model==model and s.originalId==id then return s end
    local p=profiles[id] or profiles[248]
    local left,rear,bottom,right,front,top
    if collisionBoxes[id] then
        left,rear,bottom,right,front,top=unpack(collisionBoxes[id])
    else
        left,rear,bottom,right,front,top=getElementBoundingBox(boat)
    end
    if not left or top<=bottom then return end
    s={model=model,originalId=id,p=p,left=left*p.sideScale,right=right*p.sideScale,
        stern=rear*p.sternScale,bow=front*p.bowScale,bottom=bottom,top=top,
        front=front,rear=rear,halfWidth=right}
    state.splashHull=s
    return s
end

local function point(m,x,y,z)
    return m[4][1]+m[1][1]*x+m[2][1]*y+m[3][1]*z,
           m[4][2]+m[1][2]*x+m[2][2]*y+m[3][2]*z,
           m[4][3]+m[1][3]*x+m[2][3]*y+m[3][3]*z
end

-- 0036A090 normalizes the sum of nine weighted squared depths. Its
-- frame-to-frame change feeds the vertical velocity of both spray banks.
local function sampleImmersion(s,m)
    local volume=0
    for row=0,2 do
        local y=s.stern+(s.bow-s.stern)*row/2
        for col=0,2 do
            local x=s.left+(s.right-s.left)*col/2
            local wx,wy,wz=point(m,x,y,0)
            local water=getWaterLevel(wx,wy,m[4][3],true)
            if type(water)=="number" then
                local weight=s.p.weights[1+row*3+col]
                local depth=math.min(s.top,water-wz)-s.bottom
                volume=volume+(math.max(0,depth-1+weight)*weight)^2
            end
        end
    end
    return volume/(9*(s.top-s.bottom))
end

local function spawn(kind,frame,x,y,z,vx,vy,vz,size,spin,angle,opacity,values)
    local car=kind==carSplash
    local rgbScale,dirScale=car and .5 or .6,car and .5 or .85
    local function tint(i)
        return math.min(255,rgbScale*(values[i]+dirScale*values[12+i]))
    end
    AddParticle(kind,x,y,z,vx,vy,vz,size,tint(1),tint(2),tint(3),255,spin,angle,frame,nil,opacity)
end

local function emitAt(boat,state,m,s,opacity,values)
    local driver=getVehicleController(boat)
    local npc=driver and getElementType(driver)=="ped"
    local vx,vy,vz=getElementVelocity(boat)
    local speed=math.sqrt(vx*vx+vy*vy)
    if m[3][3]<=0 then s.immersion=0 return end
    local immersion=sampleImmersion(s,m)
    if immersion<=0 then s.immersion=0 return end
    local impact=math.floor((immersion-(s.immersion or immersion))*10000)*.0003
    s.immersion=immersion
    local p=s.p
    if speed>.05 and (not npc or state.splashFrame%4<2) then
        local _,_,yaw=getElementAngularVelocity(boat)
        local gain=math.min(.75,speed)
        for sign=-1,1,2 do
            local x,y,z=point(m,sign*p.beam,s.front*p.fore,0)
            local water=getWaterLevel(x,y,z+p.height,true)
            if type(water)=="number" and z+p.height-water<3 then
                local lateral=sign*speed*p.spread
                local wx,wy,wz=m[1][1]*lateral,m[1][2]*lateral,m[1][3]*lateral
                local turn=(1+math.max(0,sign*yaw*70))*(npc and 1.5 or 1)
                local dx=(vx*p.carry+wx)*turn
                local dy=(vy*p.carry+wy)*turn
                local dz=(vz*p.carry+wz+p.rise*speed)*turn+impact
                spawn(carSplash,1,x,y,water,.75*dx,.75*dy,.75*dz,gain+.1,
                    math.random(0,9),math.random(0,89),opacity,values)
                spawn(boatSplash,0,x,y,water,dx,dy,dz,gain,0,math.random(0,44),opacity,values)
                VCSBoatSheet.add(state,sign<0 and "left" or "right",x,y,water,dx,dy,dz,wx,wy,wz)
            end
        end
    end

    -- 001A2098..001A2228: other controlled boats emit these two stern
    -- sprites on alternating ticks. The player status bypasses both calls.
    if not npc or state.splashFrame%2~=0 or not getVehicleEngineState(boat) then return end
    local throttle=getPedAnalogControlState(driver,"accelerate") or 0
    -- Rail-driven ambient boats advertise their cruise through velocity.
    if throttle==0 and getElementData(boat,"npchlc_traffic:originalModel",false) then
        throttle=math.min(1,math.max(0,(vx*m[2][1]+vy*m[2][2])/.15))
    end
    if throttle<=0 then return end
    local x,y,z=point(m,0,s.rear*p.nozzleY,s.bottom*p.nozzleZ)
    local water=getWaterLevel(x,y,z,true)
    if type(water)~="number" or water<=z-.5 then return end
    local steer=(getPedAnalogControlState(driver,"vehicle_left") or 0)
               -(getPedAnalogControlState(driver,"vehicle_right") or 0)
    local handling=getVehicleHandling(boat)
    local angle=math.rad(handling.steeringLock)*steer*math.abs(steer)
    local force=-.04*3.5*p.force*throttle*math.min(1,water-z+.5)^2
    local side,fore=math.sin(angle),math.cos(angle)
    local dx=(m[1][1]*side+m[2][1]*fore-m[3][1]*math.abs(angle))*force
    local dy=(m[1][2]*side+m[2][2]*fore-m[3][2]*math.abs(angle))*force
    spawn(boatSplash,0,x,y,z+.5,dx,dy,.015,1.25,math.random(0,4),math.random(0,89),opacity,values)
    spawn(carSplash,3,x,y,z+.5,dx*.75,dy*.75,.01125,.5,math.random(0,29),math.random(0,44),opacity,values)
end

function VCSBoatParticles.emit(boat,state,now,opacity,values)
    local dt=state.splashTick and (now-state.splashTick)%4294967296 or period
    state.splashTick=now
    state.splashTime=(state.splashTime or 0)+math.min(dt,100)*getGameSpeed()
    if state.splashTime<period then return end
    local m=getElementMatrix(boat)
    local s=VCSBoatParticles.hull(boat,state)
    local cx,cy,cz=getCameraMatrix()
    local visible=m and s and opacity>0 and (getVehicleOccupant(boat,0)==localPlayer or isElementOnScreen(boat))
        and (cx-m[4][1])^2+(cy-m[4][2])^2+(cz-m[4][3])^2<4900
    while state.splashTime>=period do
        state.splashTime=state.splashTime-period
        state.splashFrame=(state.splashFrame or 0)+1
        VCSBoatSheet.step(state,step)
        if visible then emitAt(boat,state,m,s,opacity,values)
        elseif s then s.immersion=nil end
    end
end
