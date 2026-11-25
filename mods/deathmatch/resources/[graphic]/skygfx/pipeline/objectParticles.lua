-- CObject impact and destruction effects (00132C50). Indexed by the original
-- ObjectData selector; type 6 deliberately has no particle case in the US ELF.
ObjectParticles={}
local debrisFrame=0
local damage=setmetatable({},{__mode="k"})
local contacts=setmetatable({},{__mode="k"})
local jets={}
local counts={[1]=10,[2]=45,[3]=20,[4]=32,[5]=16,[7]=5,[9]=10,[10]=10}
local running=false
local function range(a,b) return a+math.random()*(b-a) end
local function visibleWorld(element)
    return getElementDimension(element)==getElementDimension(localPlayer)
        and getElementInterior(element)==getCameraInterior()
end
local function isHydrant(object)
    local model=getElementModel(object)
    return model==1211 or model==1366 or getElementID(object)=="fire_hydrant"
end

local function emit(effect,x,y,z,force)
    if effect==0 or effect==6 then return end
    if effect==8 then
        local cx,cy=getCameraMatrix()
        local dx,dy=cx-x,cy-y
        local length=math.sqrt(dx*dx+dy*dy)
        if length<.1 then dx,dy=1,0 else dx,dy=dx/length,dy/length end
        for i=0,11 do
            local a=math.floor(i*1024/12)*math.pi/512
            AddParticle(79,x,y,z,-dy*.1*math.sin(a),dx*.1*math.sin(a),.1*math.cos(a),range(1.5,2))
        end
        return
    end
    local count=counts[effect]
    if not count then return end
    local speedZ=(force or 0)*.0002
    for i=0,count-1 do
        debrisFrame=(debrisFrame+1)%4
        local vx,vy,vz=range(-.35,.35),range(-.35,.35),range(.1,.25)+speedZ
        local spin=math.random(-40,39)
        if effect==7 then
            local shade=math.random(64,95)
            AddParticle(22,x,y,z,range(-.005,.005),range(-.005,.005),range(-.01,0),
                        .1,shade,shade,shade,128,spin,0,debrisFrame)
        else
            local r,g,b,a,size
            if effect==2 or effect==3 then
                r=math.random(64,127)
                g,b,a=r,r,255
                size=effect==2 and range(.02,.2) or range(.01,.04)
            elseif effect==9 or effect==10 then
                if debrisFrame%2==1 then r,g,b,a=144,173,196,100 else r,g,b,a=142,190,198,120 end
                size=range(.01,.05)
            elseif effect==5 then
                r,g,b,a,size=255,255,255,255,range(.02,.2)
            else
                r=200
                g=debrisFrame%2==1 and 0 or 200
                b,a,size=g,255,range(.02,.2)
            end
            AddParticle(62,x,y,z,vx,vy,vz,size,r,g,b,a,spin,0,debrisFrame)
            if effect==5 and i%7==0 then
                local tint=({{160,96,96},{96,160,96},{96,96,160},{160,160,160}})[debrisFrame+1]
                AddParticle(9,x,y,z,vx*.5,vy*.5,vz*.5,.1,tint[1],tint[2],tint[3],255,spin,0,1)
            end
        end
    end
end

local function hydrantJet(object,x,y,z)
    local state=contacts[object]
    if state and state.active then return end
    local jet={x=x,y=y,z=z-.5,age=0,dimension=getElementDimension(object),
               interior=getElementInterior(object),active=true}
    contacts[object]=jet
    jets[#jets+1]=jet
end

-- Save the intact model before eagleLoader changes it at the end of its
-- damage callback. Shop props emit once for each confirmed damage transition.
local function objectDamage(loss)
    if not running or not visibleWorld(source) or not loss or loss<=0 then return end
    local name=getElementID(source)
    if not ObjectDamageEffects[name] then return end
    local previous=damage[source]
    if previous and previous.broken then return end
    local record={loss=loss or 0,intact=previous and previous.intact or getElementModel(source)}
    damage[source]=record
    -- Eagle confirms these placements after applying their damage-model swap.
    if ObjectDamageEffects[name][3] then return end
    if ObjectDamageEffects[name][1]==0 or ObjectDamageEffects[name][1]==6 then return end
    setTimer(function(object)
        if running and isElement(object) and visibleWorld(object) and damage[object]==record and not record.handled then
            local x,y,z=getElementPosition(object)
            emit(ObjectDamageEffects[name][1],x,y,z,record.loss)
        end
    end,100,1,source)
end
local function shopDamage(owner,name)
    if not running or owner~="vcs" or not visibleWorld(source) then return end
    local effects=ObjectDamageEffects[name]
    local record=damage[source]
    if not effects or not record or record.handled then return end
    record.handled=true
    local broken=record.intact~=getElementModel(source)
    record.broken=broken
    local x,y,z=getElementPosition(source)
    emit(effects[broken and 2 or 1],x,y,z,record.loss)
end
local function objectBreak()
    if not running or not visibleWorld(source) or wasEventCancelled() then return end
    local x,y,z=getElementPosition(source)
    if isHydrant(source) then hydrantJet(source,x,y,z) return end
    local effects=ObjectDamageEffects[getElementID(source)]
    if effects then
        local record=damage[source]
        if record then record.handled=true end
        emit(effects[2],x,y,z,record and record.loss or 0)
    end
end
-- Physical hydrants can be uprooted without the engine's mesh-break event.
local function collision(object)
    if not isElement(object) or getElementType(object)~="object" or not visibleWorld(object) or not isHydrant(object) then return end
    if contacts[object] then return end
    local x,y,z=getElementPosition(object)
    contacts[object]={x=x,y=y,z=z,pending=3}
end

function ObjectParticles.Update()
    if not running then return end
    for object,p in pairs(contacts) do
        if not isElement(object) or not visibleWorld(object) then
            contacts[object]=nil
        elseif p.pending then
            local x,y,z=getElementPosition(object)
            local vx,vy,vz=getElementVelocity(object)
            if (x-p.x)^2+(y-p.y)^2+(z-p.z)^2>.0025 or vx*vx+vy*vy+vz*vz>.001 then
                hydrantJet(object,p.x,p.y,p.z)
            else
                p.pending=p.pending-1
                if p.pending==0 then contacts[object]=nil end
            end
        end
    end
    local cx,cy,cz=getCameraMatrix()
    for i=#jets,1,-1 do
        local p=jets[i]
        p.age=p.age+1
        if p.age>150 or p.dimension~=getElementDimension(localPlayer) or p.interior~=getCameraInterior() then
            table.remove(jets,i)
        elseif p.age%2==0 and (cx-p.x)^2+(cy-p.y)^2+(cz-p.z)^2>25 then
            -- CParticleObject::Update close-list case 5 (002294A8).
            for n=1,4 do
                AddParticle(44,p.x+(n<=2 and .01 or -.01),p.y,p.z,0,0,.3+range(.004,.008),
                            range(.005,.0075),nil,nil,nil,nil,0,0,1,300)
            end
            AddParticle(47,p.x,p.y,p.z,0,0,.3)
        end
    end
end

local function respawn()
    damage[source],contacts[source]=nil,nil
end
function ObjectParticles.start()
    if running then return end
    running=true
    addEvent("onClientEagleObjectDamageEffect",false)
    addEventHandler("onClientObjectDamage",root,objectDamage,true,"high")
    addEventHandler("onClientObjectBreak",root,objectBreak,true,"low-5")
    addEventHandler("onClientEagleObjectDamageEffect",root,shopDamage)
    addEventHandler("onClientVehicleCollision",root,collision)
    addEventHandler("onClientElementStreamIn",root,respawn)
end
function ObjectParticles.stop()
    if not running then return end
    running=false
    removeEventHandler("onClientObjectDamage",root,objectDamage)
    removeEventHandler("onClientObjectBreak",root,objectBreak)
    removeEventHandler("onClientEagleObjectDamageEffect",root,shopDamage)
    removeEventHandler("onClientVehicleCollision",root,collision)
    removeEventHandler("onClientElementStreamIn",root,respawn)
    damage,contacts,jets=setmetatable({},{__mode="k"}),setmetatable({},{__mode="k"}),{}
end
