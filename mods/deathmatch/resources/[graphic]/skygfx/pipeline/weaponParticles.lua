-- US PS2 firearm effects. The two side planes and the end cap come from
-- 001692E0, separate from CParticle's camera-facing gunflash family.
WeaponParticles = {}
local flashes, running = {}, false
local lastShellX, lastShellY, lastShellZ = 0,0,0
local minigunParity = 0
local white = tocolor(255,255,255,255)
local weapons = {
    [22]=19,[24]=20,[25]=21,[26]=23,[27]=22,[28]=24,[29]=27,
    [30]=28,[31]=29,[32]=26,[33]=30,[34]=31,[38]=35,
}
local flashSizes = {
    [0]={0.25,1.3}, [1]={0.2,0.8}, [2]={0.3,0.8}, [3]={0.5,2},
}

local function drawQuad(material, uv, a,b,c,d)
    local function vertex(p,u,v) return {p.x,p.y,p.z,white,u,v} end
    dxDrawMaterialPrimitive3D("trianglestrip",material,"postfx",
        vertex(a,uv[3],uv[4]),vertex(b,uv[3],uv[2]),vertex(c,uv[1],uv[4]),vertex(d,uv[1],uv[2]))
end

local function renderFlashes()
    if #flashes==0 then return end
    local mat = CParticle.GetMaterial("add")
    local side,back = ParticleRasters.muzzleflash,ParticleRasters.muzzleflashback
    if mat and side and back then
        for _,flash in ipairs(flashes) do
            local p,dir,size = flash.p,flash.dir,flashSizes[flash.style]
            local length = size[2]*(1+math.random()*0.2)
            local width = size[1]*(1+math.random()*0.2)
            local right = Vector3(dir.y,-dir.x,0)
            local up = dir:cross(right) * width
            right = right*width
            if math.random(2)==1 then right=right*-1 end
            if math.random(2)==1 then up=up*-1 end
            local tip = p+dir*length
            drawQuad(mat,side,tip+up,tip-up,p+up,p-up)
            drawQuad(mat,side,tip+right,tip-right,p+right,p-right)
            local endCap = p+dir*(length*0.25)
            drawQuad(mat,back,endCap+right+up,endCap+right-up,endCap-right+up,endCap-right-up)
        end
    end
    flashes={}
end

local function addGunshell(shooter,muzzle,dir,longGun)
    local dx,dy = dir.x,dir.y
    local norm = math.sqrt(dx*dx+dy*dy)
    if norm>0.0001 then dx,dy=dx/norm,dy/norm end
    -- 002C5AB0 selects the floor-querying shell after 1.5 units of
    -- Manhattan movement from the last such emitter, shared across shooters.
    local x,y,z = getElementPosition(shooter)
    local shell=70
    if math.abs(x-lastShellX)+math.abs(y-lastShellY)+math.abs(z-lastShellZ)>1.5 then
        shell=69
        lastShellX,lastShellY,lastShellZ=x,y,z
    end
    local offset = longGun and 0.65 or 0.2
    AddParticle(shell,muzzle.x-dx*offset,muzzle.y-dy*offset,muzzle.z,
        dy*0.05,-dx*0.05,0.02+math.random()*0.06,longGun and 0.02 or 0.015,
        nil,nil,nil,nil,math.random(-20,19))
end

local function addGunFlash(shooter,weapon,muzzle,dir)
    local shotgun = weapon>=21 and weapon<=23
    -- The scoped local sniper uses CBulletInfo instead of FireInstantHit.
    if (weapon==30 or weapon==31) and shooter==localPlayer then return end
    if weapon==35 then
        minigunParity=(minigunParity+1)%2
        if minigunParity==1 then return end
    end
    local longGun = weapon==28 or weapon==29 or weapon==35
    local style = shotgun and 2 or (weapon==35 and 3 or (longGun and 0 or 1))
    if shotgun then
        local m = getElementMatrix(shooter)
        if m then
            dir=Vector3(m[2][1],m[2][2],0)
            if dir.length>0.0001 then dir=dir/dir.length end
        end
        -- 002C9190 emits the four shotgun smoke puffs at the muzzle.
        for i=0,3 do
            local v=dir*(0.1+i*0.05)
            AddParticle(18,muzzle.x,muzzle.y,muzzle.z,v.x,v.y,0,0.1)
        end
    elseif weapon~=20 then
        addGunshell(shooter,muzzle,dir,longGun)
    end
    if #flashes<8 then flashes[#flashes+1]={p=muzzle,dir=dir,style=style} end
end

local function addImpact(shooter,weapon,start,hit,element)
    local dir=hit-start
    local distance=dir.length
    if distance<0.0001 then return end
    dir=dir/distance
    local targetType=isElement(element) and getElementType(element)
    if targetType=="ped" or targetType=="player" then
        local ex,ey=getElementPosition(element)
        local shotgun=weapon>=21 and weapon<=23
        local count=shotgun and 32 or 8
        for i=1,count do
            AddParticle(7,hit.x,hit.y,hit.z,(hit.x-ex)*0.01,(hit.y-ey)*0.01,0.01)
        end
        return
    end
    local water,wx,wy,wz=testLineAgainstWater(start.x,start.y,start.z,hit.x,hit.y,hit.z)
    if water then
        AddParticle(89,wx,wy,wz,0,0,0,0,68,140,203,255)
        AddParticle(36,wx,wy,wz,0,0,0)
        return
    end
    -- Cast a short line around the reported impact for the material and its
    -- normal. A shot whose endpoint is open air has no impact emitter.
    local a,b=hit-dir*0.4,hit+dir*0.4
    local collided,x,y,z,_,nx,ny,nz,surface,_,piece=processLineOfSight(
        a.x,a.y,a.z,b.x,b.y,b.z,true,true,false,true,true,false,false,false,shooter)
    if not collided then return end
    if targetType=="vehicle" and piece and piece>=13 and piece<=16 then
        for i=1,4 do AddParticle(68,x,y,z,nx*0.05,ny*0.05,nz*0.05) end
        return
    end
    local soft=surface and ((surface>=9 and surface<=17) or surface==20 or (surface>=25 and surface<=33))
    if soft then
        AddParticle(89,x,y,z,0,0,0,0,96,57,19,255)
    else
        for i=1,(targetType=="vehicle" and 16 or 10) do
            AddParticle(0,x,y,z,nx*0.05,ny*0.05,nz*0.05)
        end
    end
    local smoke
    if targetType=="vehicle" then
        local minOffset=(weapon>=21 and weapon<=23) and 2 or 0.5
        local offset=math.max(minOffset,distance*0.2)
        smoke=Vector3(x-dir.x*offset,y-dir.y*offset,z)
    else
        smoke=Vector3(x,y,z)-dir*math.max(0.2,distance*0.1)
        smoke=smoke+Vector3(math.random()*.4-.2,math.random()*.4-.2,math.random()*.4-.2)
    end
    AddParticle(68,smoke.x,smoke.y,smoke.z,0,0,0)
end

local function onWeaponFire(id,ammo,clip,x,y,z,element,sx,sy,sz)
    local weapon=weapons[id]
    if not weapon or not x or getElementDimension(source)~=getElementDimension(localPlayer)
        or getElementInterior(source)~=getCameraInterior() or not AreParticlesEnabled() then return end
    local mx,my,mz=getPedWeaponMuzzlePosition(source)
    if not mx then return end
    local muzzle,hit=Vector3(mx,my,mz),Vector3(x,y,z)
    local dir=hit-muzzle
    if dir.length<0.0001 then return end
    if source==localPlayer then
        local matrix=getElementMatrix(source)
        CParticle.ShootBirds(mx,my,mz,matrix[2][1],matrix[2][2])
    end
    addGunFlash(source,weapon,muzzle,dir/dir.length)
    addImpact(source,weapon,sx and Vector3(sx,sy,sz) or muzzle,hit,element)
end

function WeaponParticles.start()
    if running then return end
    running=true
    addEventHandler("onClientPedWeaponFire",root,onWeaponFire)
    addEventHandler("onClientPlayerWeaponFire",root,onWeaponFire)
    addEventHandler("onClientPreRender",root,renderFlashes)
end

function WeaponParticles.stop()
    if not running then return end
    running=false
    removeEventHandler("onClientPedWeaponFire",root,onWeaponFire)
    removeEventHandler("onClientPlayerWeaponFire",root,onWeaponFire)
    removeEventHandler("onClientPreRender",root,renderFlashes)
    flashes={}
    minigunParity,lastShellX,lastShellY,lastShellZ=0,0,0,0
end
