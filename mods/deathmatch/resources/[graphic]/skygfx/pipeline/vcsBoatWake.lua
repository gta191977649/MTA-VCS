VCSBoatWake = {}

local states = {}
local waterTexture, waterMaterial, sheetMaterial
local particleMaterials, particleResources = {}, {}
local surfaceShader, wakeMap, mapX, mapY, mapZ, mapTick
local mapSpan, mapSize = 192, 512
local selected = {}
local lastScan, activeDimension
local stats = {boats = 0, strips = 0, spray = 0}
-- SLUS_215.90 0035AEB8 samples every two metres. Its wake lifetime is 150 game steps.
local wakeLifetime = 3000

local function isVcsBoat(vehicle)
    local original = getElementData(vehicle, "vcs_vehicle:originalModel", false)
        or getElementData(vehicle, "npchlc_traffic:originalModel", false)
    local custom = getElementData(vehicle, "mod.model", false)
    -- The DLC model name also identifies jetskis streamed by older servers.
    return original == 233 or custom == "JETSKI" or getVehicleType(vehicle) == "Boat" and (original or custom)
end

local function scan(cx, cy, lookX, lookY, now)
    local choices, tracked = {}, {}
    local dimension = getElementDimension(localPlayer)
    local viewX,viewY=lookX-cx,lookY-cy
    local length=math.sqrt(viewX*viewX+viewY*viewY)
    if length>0 then viewX,viewY=viewX/length,viewY/length end
    local vehicles=getElementsByType("vehicle",root,true)
    for i=#vehicles,1,-1 do
        local boat=vehicles[i]
        local vcsBoat=isVcsBoat(boat)
        if getElementDimension(boat) == dimension and getElementInterior(boat) == 0
                and (vcsBoat or getVehicleType(boat)=="Boat" or getElementModel(boat)==460) then
            local x,y=getElementPosition(boat)
            local dx,dy=x-cx,y-cy
            local distance=dx*dx+dy*dy
            local depth=viewX*dx+viewY*dy
            if distance<=10000 then
                tracked[boat]=true
                if not states[boat] then states[boat]={points={}} end
                states[boat].vcsBoat=vcsBoat
                if #states[boat].points>0 and depth>=-15 and depth<=100 then
                    local candidate={boat=boat,distance=distance}
                    if #choices<4 then
                        choices[#choices+1]=candidate
                    else
                        -- 0035ABD8 replaces the nearest existing slot when a
                        -- closer candidate is found, or always for the player.
                        local nearest=1
                        for slot=2,4 do
                            if choices[slot].distance<choices[nearest].distance then nearest=slot end
                        end
                        if distance<choices[nearest].distance or getVehicleOccupant(boat,0)==localPlayer then
                            choices[nearest]=candidate
                        end
                    end
                end
            end
        end
    end
    selected = {}
    for _,choice in ipairs(choices) do selected[choice.boat]=true end
    for boat in pairs(states) do if not tracked[boat] then states[boat]=nil end end
    lastScan = now
end

-- 00359BC0 advances the raster in opposite U/V directions at the PS2 frame rate.
local wakeClock, wakeU, wakeV, lastWakeTick = 0, 1, 0
local function advanceWake(now)
    local dt = lastWakeTick and (now-lastWakeTick)%4294967296 or 0
    lastWakeTick = now
    local elapsed = dt * getGameSpeed()
    wakeClock = wakeClock + elapsed
    local frames = elapsed * 0.03
    local wind = getTimeCycleValue("waterWind") or 0
    local base = 0.0006 + wind*0.0005
    local phase = (wakeClock%4096)*(2*math.pi/4096)
    wakeU = (wakeU - frames*(base + math.sin(phase)*0.0003))%1
    wakeV = (wakeV + frames*(base + math.cos(phase*0.7)*0.0003))%1
end

local function recordWake(boat, state, now)
    local points = state.points
    while points[1] and wakeClock-points[1].birth >= wakeLifetime do table.remove(points,1) end
    local matrix = getElementMatrix(boat)
    if not matrix then state.head=nil return end
    local forward, position = matrix[2], matrix[4]
    local x, y = position[1], position[2]
    local fx, fy = forward[1], forward[2]
    local hull=VCSBoatParticles.hull(boat,state)
    if not hull then return end
    state.original=hull.originalId
    state.width=hull.halfWidth*0.65*(state.original==278 and 0.4 or 1)
    local vx,vy=getElementVelocity(boat)
    local speed=math.sqrt(vx*vx+vy*vy)
    local water = getWaterLevel(x,y,position[3],true)
    if type(water)~="number" or not isElementInWater(boat) then state.head=nil return end
    -- Keep the previous track fading when the engine is stopped. Eligibility in
    -- 001A1454 is based on throttle or coasting speed while supported by water.
    local driver=getVehicleOccupant(boat,0)
    local pedal=driver and math.max(getPedAnalogControlState(driver,"accelerate") or 0,
        (getPedAnalogControlState(driver,"brake_reverse") or 0)*0.3) or 0
    local point={x=x,y=y,z=water,dx=fy,dy=-fx,birth=wakeClock,tick=now,power=math.min(1,speed*6.25)}
    state.head=point
    if pedal<=0.05 and speed<=0.05 then return end
    local latest=points[#points]
    local spacingSquared=state.original==170 and 0.5 or 4
    if not latest or (x-latest.x)^2+(y-latest.y)^2 > spacingSquared then
        points[#points+1]=point
        local limit=driver and getElementType(driver)=="player" and 32 or 16
        while #points>limit do table.remove(points,1) end
    end
end

local function drawTrail(state, red, green, blue, opacity, painting)
    local points=state.points
    if #points<2 then return end
    local vertices={}
    local cx,cy,cz=getCameraMatrix()
    local function row(point,dx,dy,width,alpha)
        local result={}
        local distance=(point.x-cx)^2+(point.y-cy)^2+(point.z-cz)^2
        local fade=math.max(0,math.min(1,1-math.max(0,distance-4800)*0.00067934784))
        for column=1,4 do
            local side=(column-1)*2/3-1
            local x,y=point.x+side*width*dx,point.y+side*width*dy
            local coverage=(column==2 or column==3) and alpha*fade*opacity or 0
            local surface=getWaterLevel(x,y,point.z,true)
            if type(surface)~="number" then return nil end
            if painting then
                local level=math.max(0,math.min(255,128+(surface-mapZ)*4))
                result[column]={(x-mapX)*mapSize/mapSpan,(y-mapY)*mapSize/mapSpan,tocolor(coverage,level,0,255)}
            else
                result[column]={x,y,surface+0.0755,tocolor(red,green,blue,coverage),x*0.25+wakeU,y*0.25+wakeV}
            end
        end
        return result
    end
    -- 00359D08 uses the live hull centre for the first row. Stored point 0
    -- supplies the tangent to point 1, but is not an additional rendered row.
    local head=state.head or points[#points]
    local older=points[#points-1]
    local sign=((head.x-older.x)*(-head.dy)+(head.y-older.y)*head.dx)<0 and -1 or 1
    local headAlpha=255
    if #points<4 then headAlpha=headAlpha*math.min(1,(wakeLifetime-wakeClock+older.birth)/(wakeLifetime*0.2)) end
    local previous=row(head,head.dx*sign,head.dy*sign,state.width*(state.original==233 and 2 or 1),headAlpha)
    for i=#points-1,1,-1 do
        local point,newer=points[i],points[i+1]
        local dx,dy=newer.y-point.y,point.x-newer.x
        local dist=dx*dx+dy*dy
        if dist>9 then local len=math.sqrt(dist) dx,dy=dx/len,dy/len end
        local age=(wakeClock-point.birth)/wakeLifetime
        local width=(state.width+age*3.8-age*0.01)*0.5
        local alpha=i==1 and 0 or math.min(140,math.max(0,500-600*age))
        local current=row(point,dx,dy,width,alpha)
        if previous and current and dist<=169 then
            if #vertices>0 then
                vertices[#vertices+1]=vertices[#vertices]
                vertices[#vertices+1]=previous[1]
            end
            for column=1,4 do
                vertices[#vertices+1]=previous[column]
                vertices[#vertices+1]=current[column]
            end
        end
        previous=current
    end
    if #vertices>=4 then
        if painting then
            dxDrawPrimitive("trianglestrip",false,unpack(vertices))
        elseif dxDrawMaterialPrimitive3D("trianglestrip",waterMaterial or waterTexture,"postfx",unpack(vertices)) then
            stats.strips=stats.strips+1
        end
    end
end

function VCSBoatWake.prepare(values)
    stats.boats, stats.strips, stats.spray, stats.sheets = 0, 0, 0, 0
    if not waterTexture or not values or getCameraInterior() ~= 0 or isMainMenuActive() then return end
    local dimension=getElementDimension(localPlayer)
    if activeDimension~=dimension then
        activeDimension=dimension
        mapTick=nil
        states,selected,lastScan={},{},nil
        VCSBoatParticles.clear()
    end
    local now = getTickCount()
    advanceWake(now)
    local cx,cy,cz,lookX,lookY=getCameraMatrix()
    if not lastScan or (now-lastScan)%4294967296 >= 250 then scan(cx,cy,lookX,lookY,now) end
    for boat,state in pairs(states) do
        if isElement(boat) and isElementStreamedIn(boat) and getElementInterior(boat)==0
            and getElementDimension(boat)==getElementDimension(localPlayer) then recordWake(boat,state,now) end
    end
    local red, green, blue = math.min(255,values[51]+64), math.min(255,values[52]+64), math.min(255,values[53]+64)
    local painting,previousBlend
    local anchor=next(selected)
    if wakeMap and not anchor then
        dxSetShaderValue(surfaceShader,"WakeActive",0)
        mapTick=nil
    elseif wakeMap and (not mapTick or (now-mapTick)%4294967296>=50) then
        painting=dxSetRenderTarget(wakeMap,true)
        if painting then
            mapX,mapY=math.floor(cx/4)*4-mapSpan/2,math.floor(cy/4)*4-mapSpan/2
            local anchorState=states[anchor]
            local point=anchorState and anchorState.points[#anchorState.points]
            mapZ=point and point.z or cz
            dxSetShaderValue(surfaceShader,"WakeOrigin",mapX,mapY,mapZ)
            previousBlend=dxGetBlendMode()
            dxSetBlendMode("overwrite")
            mapTick=now
        end
        dxSetShaderValue(surfaceShader,"WakeActive",painting and 1 or 0)
    end
    if surfaceShader then dxSetShaderValue(surfaceShader,"WakeScroll",wakeU,wakeV) end
    for boat in pairs(selected) do
        if isElement(boat) and isElementStreamedIn(boat) and getElementInterior(boat)==0
            and getElementDimension(boat)==getElementDimension(localPlayer) then
            local state = states[boat]
            local opacity = getElementAlpha(boat)/255
            if opacity > 0 and #state.points > 0 then
                stats.boats = stats.boats + 1
                if painting or not wakeMap then drawTrail(state,red,green,blue,opacity,painting) end
                if wakeMap and #state.points>=2 then stats.strips=stats.strips+1 end
            end
        end
    end
    if painting then dxSetBlendMode(previousBlend) dxSetRenderTarget() end
    for boat,state in pairs(states) do
        if state.vcsBoat and isElement(boat) and isElementStreamedIn(boat) and getElementInterior(boat)==0
                and getElementDimension(boat)==getElementDimension(localPlayer) then
            local opacity=getElementAlpha(boat)/255
            VCSBoatParticles.emit(boat,state,now,opacity,values)
            if opacity>0 then
                stats.sheets=stats.sheets+VCSBoatSheet.draw(state,sheetMaterial,red,green,blue,opacity)
            end
        end
    end
    stats.spray=VCSBoatParticles.draw(now,particleMaterials)
end

local function foamMaterial(texture, gain, additive)
    if not texture then return end
    local macros={VCS_BOAT_FOAM="1"}
    if additive then macros.VCS_SPLASH_ADDITIVE="1" end
    if additive==0x2c then macros.VCS_SPLASH_ONE="1" end
    local material = dxCreateShader("shader/vcsWater.fx", macros)
    if material then
        dxSetShaderValue(material, "SurfaceTexture", texture)
        dxSetShaderValue(material, "FoamGain", gain)
    end
    return material
end

local function loadParticleMaterial(name,additive)
    local raster=dxCreateTexture("txd/vcs-"..name..".png","argb",true,"clamp")
    if not raster then return end
    particleResources[#particleResources+1]=raster
    local material=foamMaterial(raster,1,additive)
    if material then particleResources[#particleResources+1]=material end
    -- The RGB-only CAR_SPLASH frames have opaque black backgrounds. They
    -- require additive blending even when the water surface shader failed.
    if additive then return material end
    return material or raster
end

function VCSBoatWake.start(texture,surface)
    if texture and surface then
        wakeMap=dxCreateRenderTarget(mapSize,mapSize,false)
        if wakeMap then
            surfaceShader=surface
            dxSetShaderValue(surface,"WakeCoverage",wakeMap)
            dxSetShaderValue(surface,"WakeRaster",texture)
        end
    end
    waterTexture = texture
    waterMaterial=foamMaterial(texture,1)
    sheetMaterial=loadParticleMaterial("boatwake")
    particleMaterials[0x2d]=loadParticleMaterial("boatwake2",0x2d)
    particleMaterials[0x2c]={}
    for frame=0,3 do
        particleMaterials[0x2c][frame]=loadParticleMaterial(string.format("carsplash_%02d",frame+1),0x2c)
    end
end

function VCSBoatWake.stop()
    if surfaceShader then dxSetShaderValue(surfaceShader,"WakeActive",0) end
    if wakeMap then destroyElement(wakeMap) end
    wakeMap,surfaceShader,mapTick=nil,nil,nil
    if waterMaterial then destroyElement(waterMaterial) end
    for i=#particleResources,1,-1 do destroyElement(particleResources[i]) end
    VCSBoatParticles.clear()
    particleMaterials,particleResources={},{}
    waterTexture,waterMaterial,sheetMaterial,lastScan,activeDimension=nil,nil,nil,nil,nil
    wakeClock, wakeU, wakeV, lastWakeTick = 0, 1, 0, nil
    states, selected = {}, {}
end

function VCSBoatWake.getStats()
    return stats
end
