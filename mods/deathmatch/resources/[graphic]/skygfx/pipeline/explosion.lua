-- CExplosion::AddExplosion (002E1140), Update (002E23A0) and
-- CParticle::AddJetExplosion (001EBD28), SLUS-21590.
CExplosion = {}
local explosions, frame, running = {}, 0, false
local random = math.random
local radii = {[0]=9,[2]=10,[3]=9,[4]=9,[5]=9,[6]=6,[7]=12,[8]=10,[9]=7,[10]=10,[11]=8}
-- The host has one aircraft explosion selector and adds a weak rocket.
local selectors = {[0]=0,[2]=2,[3]=2,[4]=3,[5]=4,[6]=5,[7]=6,[8]=8,[9]=9,[10]=10}

function CParticle.AddJetExplosion(x,y,z,power,size)
    local dx,dy,dz=random()*1.6-.8,random()*1.6-.8,random()*.4+.2
    for i=1,math.floor(math.max(1,power)*4) do
        AddParticle(42,x,y,z,random()*.04-.02,random()*.04-.02,random()*.02-.02,size,240,240,240,255)
        for j=1,2 do
            AddParticle(42,x,y,z,random()*.08-.04,random()*.08-.04,random()*.07,size,240,240,240,255)
        end
        x,y,z=x+dx,y+dy,z+dz
    end
end

local function component(vehicle,name)
    local components=getVehicleComponents(vehicle)
    if components and components[name]~=nil then
        return getVehicleComponentPosition(vehicle,name,"world")
    end
end

local function jetOrigin(vehicle,secondary)
    local kind=getVehicleType(vehicle)
    if kind=="Boat" or kind=="Train" then return end
    if kind=="Bike" or kind=="BMX" or kind=="Quad" then
        return component(vehicle,"forks_rear")
    end
    if secondary then return component(vehicle,"wing_lr_dummy") end
    local x,y,z=component(vehicle,"bump_rear_dummy")
    local bx,by,bz=component(vehicle,"wheel_lb_dummy")
    if x and bx then return (x+bx)*.5,(y+by)*.5,(z+bz)*.5 end
    return component(vehicle,"boot_dummy")
end

local function entry(kind,x,y,z)
    if #explosions>=48 then return end
    local e={kind=kind,x=x,y=y,z=z,tick=0,radius=radii[kind],created=getTickCount(),
        dimension=getElementDimension(localPlayer),interior=getCameraInterior()}
    explosions[#explosions+1]=e
    return e
end

-- Vehicle and explosion notifications can arrive in either order. Merge only
-- a matching pair, keeping coincident independent explosions as separate slots.
local function vehicleExplosion(kind,x,y,z,vehicle)
    local now,nearest,distance=getTickCount(),nil,16
    for _,e in ipairs(explosions) do
        if e.kind==kind and now-e.created<250 and e.interior==getCameraInterior() and
            e.dimension==getElementDimension(localPlayer) and (vehicle and not e.host or not vehicle and not e.event) then
            local d=(e.x-x)^2+(e.y-y)^2+(e.z-z)^2
            if d<distance then nearest,distance=e,d end
        end
    end
    local e=nearest or entry(kind,x,y,z)
    if not e then return end
    if not vehicle then e.event=true return end
    e.host=vehicle
    local jx,jy,jz=jetOrigin(vehicle,false)
    if jx then
        for i=1,random(1,2)*2 do CParticle.AddJetExplosion(jx,jy,jz,3.5+random(0,7)*.5,.3) end
    end
end

local function onVehicleExplode()
    local class=getVehicleType(source)
    if class=="Helicopter" or class=="Plane" then return end
    local model=getElementModel(source)
    local kind=class=="Boat" and 5 or ((model==441 or model==564) and 4 or 3)
    local x,y,z=getElementPosition(source)
    vehicleExplosion(kind,x,y,z,source)
end

local function offset(scale) return random(-128,127)*scale end
function CExplosion.AddExplosion(kind,x,y,z)
    if kind>=3 and kind<=5 then vehicleExplosion(kind,x,y,z) return end
    if not entry(kind,x,y,z) then return end
    local cx,cy,cz=getCameraMatrix()
    local dist=(cx-x)^2+(cy-y)^2+(cz-z)^2
    if kind==0 and dist<40^2 then
        local shade=96+random(-64,-1)
        AddParticle(43,x,y,z,0,0,0,4.5,96,shade,shade,255)
    elseif kind==2 and dist<200^2 then
        AddParticle(43,x,y,z,0,0,0,5.5,160,160,160,255)
    elseif kind==6 or kind==7 then
        for i=1,10 do
            AddParticle(42,x+offset(.05),y+offset(.05),z+offset(.05),0,0,0,2.5,160,160,160,255)
            AddParticle(43,x+offset(.05),y+offset(.05),z+offset(.05),0,0,0,5,160,160,160,255)
            CParticle.AddJetExplosion(x+offset(.05),y+offset(.05),z+offset(.05),1.4,3)
        end
    elseif kind==9 then
        for i=1,6 do AddParticle(40,x+offset(.02),y+offset(.02),z+offset(.04),0,0,0,0) end
    end
end

local function onExplosion(x,y,z,id)
    local kind=selectors[id]
    if kind and not wasEventCancelled() then CExplosion.AddExplosion(kind,x,y,z) end
end

function CExplosion.Update()
    frame=frame+1
    for i=#explosions,1,-1 do
        local e=explosions[i]
        local vehicle=e.kind>=3 and e.kind<=5
        e.tick=e.tick+1
        if e.tick> (vehicle and 128 or 23) or e.dimension~=getElementDimension(localPlayer) or
            e.interior~=getCameraInterior() then
            table.remove(explosions,i)
        elseif e.kind>=10 then
            if e.tick<5 then
                local radius=e.tick*.65*(e.tick+1)*.2
                for j=1,math.floor(e.tick*.65)*10 do
                    local dx,dy,dz=offset(1),offset(1),random(1,128)
                    local scale=radius/math.sqrt(dx*dx+dy*dy+dz*dz)
                    AddParticle(41,e.x+dx*scale,e.y+dy*scale,e.z+.5+dz*scale,0,0,0,0,
                        nil,nil,nil,nil,random(-3,2),random(-180,179))
                end
            end
        else
            e.radius=e.radius+25/30
            if vehicle and e.tick<=22 and isElement(e.host) and random(16)==1 then
                local x,y,z=jetOrigin(e.host,true)
                if x then CParticle.AddJetExplosion(x,y,z,.5,0) end
            elseif vehicle and e.tick>22 and not e.host and e.tick%2==1 then
                AddParticle(56,e.x,e.y,e.z+1,0,0,.11,.5+random()*1.5)
            end
        end
    end
end

local function corona(e,radius,uv,color,right,up,material)
    local w,h=right*radius,up*radius
    local x,y,z=e.x,e.y,e.z
    dxDrawMaterialPrimitive3D("trianglestrip",material,"postfx",
        {x-w.x+h.x,y-w.y+h.y,z-w.z+h.z,color,uv[1],uv[2]},
        {x+w.x+h.x,y+w.y+h.y,z+w.z+h.z,color,uv[3],uv[2]},
        {x-w.x-h.x,y-w.y-h.y,z-w.z-h.z,color,uv[1],uv[4]},
        {x+w.x-h.x,y+w.y-h.y,z+w.z-h.z,color,uv[3],uv[4]})
end

function CExplosion.Render()
    if #explosions==0 then return end
    local cx,cy,cz,tx,ty,tz,roll=getCameraMatrix()
    local forward=Vector3(tx-cx,ty-cy,tz-cz)
    if forward.length<.0001 then return end
    forward=forward/forward.length
    local right=Vector3(forward.y,-forward.x,0)
    right=right.length<.0001 and Vector3(1,0,0) or right/right.length
    local up=right:cross(forward)
    local angle=math.rad(roll or 0)
    right,up=right*math.cos(angle)+up*math.sin(angle),up*math.cos(angle)-right*math.sin(angle)
    local material=CParticle.GetMaterial("addOverlay")
    local values=getTimeCycleValue("values")
    local spriteSize=values and values[29] or 1
    local bright=frame%2==1
    for _,e in ipairs(explosions) do
        local vehicle=e.kind>=3 and e.kind<=5
        local dist=(cx-e.x)^2+(cy-e.y)^2+(cz-e.z)^2
        local range=vehicle and 80 or 120
        if e.kind<10 and e.tick<=22 and dist<range^2 and dist>.01 then
            -- CCoronas projects the source once, then subtracts 1.5 from its
            -- depth (0027CB00). Test that pulled point before submitting the
            -- projected glow. A world quad cuts its lower half into the road.
            local distance=math.sqrt(dist)
            local pull=math.min(1,1.5/distance)
            local px,py,pz=e.x+(cx-e.x)*pull,e.y+(cy-e.y)*pull,e.z+(cz-e.z)*pull
            local visible=isLineOfSightClear(cx,cy,cz,px,py,pz,true,false,false,true,false,false,false)
            local gain=math.min(1,e.tick*25/255)*math.min(1,2-2*distance/range)
            if not vehicle or not e.host then
                if bright then AddLight(e.x,e.y,e.z,vehicle and 15 or 20,1,vehicle and 0 or 1,vehicle and 0 or .5) end
                local r,g,b
                if vehicle then r,g,b=bright and 200 or 128,bright and 100 or 0,0
                else r,g,b=bright and 255 or 128,bright and 255 or 128,bright and 200 or 100 end
                if visible then corona(e,(vehicle and bright and 6 or 8)*spriteSize,ParticleRasters.coronastar,
                    tocolor(r*gain,g*gain,b*gain,255),right,up,material) end
            end
            if visible then corona(e,e.radius*spriteSize,ParticleRasters.coronaringa,
                tocolor(30*gain,(vehicle and 15 or 30)*gain,(vehicle and 0 or 25)*gain,255),right,up,material) end
        end
    end
end

function CExplosion.start()
    if running then return end
    running=true
    addEventHandler("onClientExplosion",root,onExplosion,true,"low-1000")
    addEventHandler("onClientVehicleExplode",root,onVehicleExplode)
end

function CExplosion.stop()
    if not running then return end
    running=false
    removeEventHandler("onClientExplosion",root,onExplosion)
    removeEventHandler("onClientVehicleExplode",root,onVehicleExplode)
    explosions,frame={},0
end
