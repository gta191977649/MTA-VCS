-- SLUS-21590 0016B9B8 / 0016BC58 / 0016C4B0. Marker owns gameplay elements.
local meshes,styles,textures={},{},{}
local materials={}
local lighting
local markers={}
local owner
local coronaMaterial
local arrowGlowMaterial
local clock,lastTick=0,getTickCount()
local tau=2*math.pi

function registerWorldMarkerAssets(models,presets)
    if type(models)~="table" or type(presets)~="table" then return false end
    if owner and owner~=sourceResource then return false end
    owner=sourceResource
    if isElement(coronaMaterial) then destroyElement(coronaMaterial) end
    if isElement(arrowGlowMaterial) then destroyElement(arrowGlowMaterial) end
    for _,material in pairs(materials) do if isElement(material) then destroyElement(material) end end
    for _,texture in pairs(textures) do if isElement(texture) then destroyElement(texture) end end
    meshes,styles,textures,materials=models,presets,{},{}
    local prefix=":"..getResourceName(owner).."/assets/"
    for _,mesh in pairs(meshes) do
        if not textures[mesh.texture] then
            textures[mesh.texture]=dxCreateTexture(prefix..mesh.texture..".png","argb",true,"clamp")
            materials[mesh.texture]=exports.skygfx:createVcsMarkerMaterial(textures[mesh.texture],false)
        end
    end
    textures.coronaringa=dxCreateTexture(prefix.."coronaringa.png","argb",true,"clamp")
    coronaMaterial=exports.skygfx:createVcsMarkerMaterial(textures.coronaringa,true)
    textures.coronastar=dxCreateTexture(":skygfx/txd/vcs-coronastar.png","argb",true,"clamp")
    arrowGlowMaterial=exports.skygfx:createVcsMarkerMaterial(textures.coronastar,true)
    return true
end

function setWorldMarker(element,definition)
    if sourceResource~=owner or not isElement(element) or getElementType(element)~="marker" then return false end
    if definition==false then markers[element]=nil return true end
    if type(definition)~="table" or not styles[definition.style] then return false end
    local old=markers[element]
    markers[element]={definition=definition,started=old and old.started or clock,
        ground=old and old.ground,groundX=old and old.groundX,groundY=old and old.groundY,
        groundZ=old and old.groundZ,angle=old and old.angle or 0}
    return true
end

-- Read-only presentation state is useful to consumers positioning related world effects.
function getWorldMarkerState(element)
    local marker=markers[element]
    if not marker or not marker.render then return false end
    local result={}
    for k,v in pairs(marker.render) do result[k]=v end
    return result
end

local function basis(dx,dy,dz)
    local length=math.sqrt(dx*dx+dy*dy+dz*dz)
    if length<0.0001 then dx,dy,dz,length=0,1,0,1 end
    dx,dy,dz=dx/length,dy/length,dz/length
    local rx,ry,rz=-dy,dx,0
    length=math.sqrt(rx*rx+ry*ry)
    if length<0.0001 then rx,ry,rz,length=1,0,0,1 end
    rx,ry,rz=rx/length,ry/length,rz/length
    return {rx,ry,rz},{dx,dy,dz},{ry*dz-rz*dy,rz*dx-rx*dz,rx*dy-ry*dx}
end

local function drawMesh(mesh,x,y,z,scale,height,angle,color,target,native)
    local material=materials[mesh.texture]
    if not isElement(material) then return false end
    local right,forward,up
    -- Type 6 grows vertically from its snapped ground origin, even with a next checkpoint.
    if target and native==6 then angle=-math.atan2(target[1]-x,target[2]-y) end
    if target and native~=6 then
        local dz=native==8 and target[3]-z or 0
        right,forward,up=basis(target[1]-x,target[2]-y,dz)
    else
        local c,s=math.cos(angle),math.sin(angle)
        right,forward,up={c,s,0},{-s,c,0},{0,0,1}
    end
    local transformed={}
    for i,v in ipairs(mesh.vertices) do
        local vx,vy,vz=v[1]*scale,v[2]*scale,v[3]*height
        if target and (native==1 or native==3) then
            local c,s=math.cos(-0.34906587),math.sin(-0.34906587)
            vy,vz=c*vy-s*vz,s*vy+c*vz
        end
        -- SkyGfx supplies the recovered marker light and current VCS timecycle.
        local lr,lg,lb=1,1,1
        if v[10] and lighting then
            local nx,ny,nz=v[10],v[11],v[12]
            if target and (native==1 or native==3) then
                local c,s=math.cos(-0.34906587),math.sin(-0.34906587)
                ny,nz=c*ny-s*nz,s*ny+c*nz
            end
            local wx=right[1]*nx+forward[1]*ny+up[1]*nz
            local wy=right[2]*nx+forward[2]*ny+up[2]*nz
            local wz=right[3]*nx+forward[3]*ny+up[3]*nz
            local d=lighting.direction
            local diffuse=math.max(0,wx*d[1]+wy*d[2]+wz*d[3])
            lr=lighting.ambient[1]+lighting.directional[1]*diffuse
            lg=lighting.ambient[2]+lighting.directional[2]*diffuse
            lb=lighting.ambient[3]+lighting.directional[3]*diffuse
        end
        transformed[i]={x+right[1]*vx+forward[1]*vy+up[1]*vz,
            y+right[2]*vx+forward[2]*vy+up[2]*vz,z+right[3]*vx+forward[3]*vy+up[3]*vz,
            tocolor(math.min(255,color[1]*(v[6] or 255)/255*lr),math.min(255,color[2]*(v[7] or 255)/255*lg),
                math.min(255,color[3]*(v[8] or 255)/255*lb),color[4]*(v[9] or 255)/255),v[4],v[5]}
    end
    local vertices={}
    for i,index in ipairs(mesh.indices) do vertices[i]=transformed[index] end
    return dxDrawMaterialPrimitive3D("trianglelist",material,"postfx",unpack(vertices))
end

local function groundPosition(marker,x,y,z,size)
    if marker.groundX~=x or marker.groundY~=y or marker.groundZ~=z or not marker.ground then
        marker.ground=getGroundPosition(x,y,z+1)
        marker.groundX,marker.groundY,marker.groundZ=x,y,z
    end
    return marker.ground and marker.ground~=0 and marker.ground-size*.05 or z
end

local function drawCorona(material,x,y,z,diameter,color,cx,cy,cz)
    if not isElement(material) then return false end
    local dx,dy,dz=cx-x,cy-y,cz-z
    if dx*dx+dy*dy+dz*dz<0.0001
        or not isLineOfSightClear(cx,cy,cz,x,y,z,true,false,false,true,false,false,false) then return false end
    local right,_,up=basis(-dx,-dy,-dz)
    local vertices={}
    for _,corner in ipairs({{-1,-1,0,1},{-1,1,0,0},{1,-1,1,1},{1,1,1,0}}) do
        local sx,sy=corner[1]*diameter*.5,corner[2]*diameter*.5
        vertices[#vertices+1]={x+right[1]*sx+up[1]*sy,y+right[2]*sx+up[2]*sy,
            z+right[3]*sx+up[3]*sy,tocolor(unpack(color)),corner[3],corner[4]}
    end
    return dxDrawMaterialPrimitive3D("trianglestrip",material,"postfx",unpack(vertices))
end

local function render(marker,element,distance,dt,cx,cy,cz)
    local definition=marker.definition
    local preset=styles[definition.style]
    local native=preset.native
    local options=definition.animation or {}
    local period=options.period or preset.period
    local elapsed=clock-marker.started
    -- Native uses a bit mask, including its period=1 constant-phase case.
    local sine=math.sin(bitAnd(math.floor(elapsed),period-1)*tau/period)
    local size=getMarkerSize(element)
    local x,y,z=getElementPosition(element)
    -- SLUS_215.90 00113D50, entity blip cases 1 and 2.
    if native==1 or native==2 then
        local target=getElementAttachedTo(element)
        if target then
            local kind=getElementType(target)
            if kind=="ped" or kind=="player" or kind=="vehicle" then
                local car=kind=="vehicle" and target or getPedOccupiedVehicle(target)
                size=kind=="vehicle" and 2.5 or native==1 and 1.5 or 0.5
                x,y,z=getElementPosition(car or target)
                if car then
                    local _,_,_,_,_,top=getElementBoundingBox(car)
                    z=z+size+1.2*(top or 1)
                else
                    z=z+size+(native==1 and 1 or 0.8)
                end
            end
        end
    end
    local base=size
    local color={unpack(definition.color)}
    if native>=1 and native<=3 then
        base=size*(1-.3*math.max(0,math.min(1,(25-distance)/20)))
    end
    local scale=base
    if native~=7 and native~=8 then scale=base*(1-(options.pulse or preset.pulse)*sine) end
    local height=options.height or preset.height or scale
    if native==1 or native==3 then z=z+base*sine*.25 end
    if native==7 then z=z+.7+base*sine*.6 end
    if native==6 then
        z=groundPosition(marker,x,y,z,size)
        color[4]=color[4]*(1-.7*math.max(0,math.min(1,(size+12-distance)/11)))
    end
    marker.angle=(marker.angle+math.rad(options.rotation or preset.rotation)*dt/1000)%tau
    local submitted=false
    if native==0 then
        -- Original mission coronas use the camera-facing coronaringa sprite (type 5).
        submitted=drawCorona(coronaMaterial,x,y,z,size,color,cx,cy,cz)
    else
        local mesh=meshes[native]
        if mesh then
            -- API sizes are diameters; the PS2 hoop model has a 4.6846-unit diameter.
            if native==8 then scale,height=scale/4.6846,height/4.6846 end
            submitted=drawMesh(mesh,x,y,z,scale,height,marker.angle,color,definition.target,native)
            if preset.double then
                drawMesh(mesh,x,y,z,scale*.93,height*.93,-marker.angle,color,definition.target,native)
            end
            if native==1 or native==2 then
                -- 0016C020 submits corona type0, alpha132, radius 2.2/1.2 times scale.
                local glow={color[1],color[2],color[3],132*color[4]/255}
                drawCorona(arrowGlowMaterial,x,y,z,scale*(native==1 and 4.4 or 2.4),glow,cx,cy,cz)
            end
        end
    end
    marker.render={visible=submitted==true,x=x,y=y,z=z,scale=scale,height=height,
        angle=math.deg(marker.angle),phase=sine,alpha=color[4],nativeType=native,elapsed=elapsed}
end

addEventHandler("onClientPreRender",root,function()
    local now=getTickCount()
    local dt=(now-lastTick)%4294967296
    lastTick=now
    clock=clock+dt*getGameSpeed()
    if owner and next(markers) and getResourceState(getResourceFromName("skygfx"))=="running" then
        lighting=exports.skygfx:getVcsMarkerLighting()
    end
    local cx,cy,cz=getCameraMatrix()
    local px,py=getElementPosition(localPlayer)
    local dimension,interior=getElementDimension(localPlayer),getCameraInterior()
    local list,coronas={},{}
    for element,marker in pairs(markers) do
        if not isElement(element) then markers[element]=nil
        else
            marker.render={visible=false}
            if getElementDimension(element)==dimension and getElementInterior(element)==interior then
                local x,y=getElementPosition(element)
                local distance=math.sqrt((x-px)^2+(y-py)^2)
                if distance<150 or (marker.definition.style=="checkpoint" and distance<150+getMarkerSize(element)*10) then
                    local listForType=marker.definition.style=="corona" and coronas or list
                    listForType[#listForType+1]={element=element,marker=marker,distance=distance}
                end
            end
        end
    end
    for _,entries in ipairs({list,coronas}) do
        table.sort(entries,function(a,b) return a.distance<b.distance end)
        for i=math.min(32,#entries),1,-1 do
            local entry=entries[i]
            render(entry.marker,entry.element,entry.distance,dt*getGameSpeed(),cx,cy,cz)
        end
    end
end)
addEventHandler("onClientElementDestroy",root,function() markers[source]=nil end)
addEventHandler("onClientResourceStop",root,function(stopped)
    if stopped~=owner then return end
    if isElement(coronaMaterial) then destroyElement(coronaMaterial) end
    if isElement(arrowGlowMaterial) then destroyElement(arrowGlowMaterial) end
    for _,material in pairs(materials) do if isElement(material) then destroyElement(material) end end
    coronaMaterial,arrowGlowMaterial=nil,nil
    for _,texture in pairs(textures) do if isElement(texture) then destroyElement(texture) end end
    meshes,styles,textures,materials,markers,owner={},{},{},{},{},nil
end)
