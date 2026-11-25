-- COL3 faces are indexed by 32 m cells. Decode only the tiles used by vehicles.
local cells, decoded, order, cursor = {}, {}, {}, 1
local terrain
local cellSize, maxTiles = 32, 96

local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end

local function short(bytes,pos)
    local a,b=bytes:byte(pos,pos+1)
    local n=a+b*256
    return n>=32768 and n-65536 or n
end

local function uint(bytes,pos)
    local a,b,c,d=bytes:byte(pos,pos+3)
    return a+256*(b+256*(c+256*d))
end

local function tileKey(x,y)
    return x*65536+y
end

local function loadTerrain()
    local f=fileOpen("vcs_road_surfaces.dat",true)
    if not f then return false end
    local bytes=fileRead(f,fileGetSize(f))
    fileClose(f)
    if not bytes or #bytes<8 or bytes:sub(1,4)~="VGS2" then return false end
    local count=uint(bytes,5)
    local body=9+count*16
    if body-1>#bytes then return false end
    for pos=9,body-1,16 do
        local start=body+uint(bytes,pos+4)
        local finish=start+18*uint(bytes,pos+8)
        local wallEnd=finish+18*uint(bytes,pos+12)
        if wallEnd-1>#bytes then return false end
        cells[tileKey(short(bytes,pos),short(bytes,pos+2))]={start,finish,wallEnd}
    end
    terrain=bytes
    return true
end

local function tile(x,y,walls)
    if x < -32768 or x > 32767 or y < -32768 or y > 32767 then return end
    if terrain==nil and not loadTerrain() then terrain=false end
    if not terrain then return end
    local key=tileKey(x,y)
    local offsets=cells[key]
    if not offsets then return end
    key=key*2+(walls and 1 or 0)
    if decoded[key] then return decoded[key] end
    local triangles={}
    local part=walls and 2 or 1
    for pos=offsets[part],offsets[part+1]-1,18 do
        local ax,ay,az=short(terrain,pos)/32,short(terrain,pos+2)/32,short(terrain,pos+4)/32
        local ux,uy=short(terrain,pos+6)/32-ax,short(terrain,pos+8)/32-ay
        local vx,vy=short(terrain,pos+12)/32-ax,short(terrain,pos+14)/32-ay
        local det=ux*vy-uy*vx
        if walls then
            triangles[#triangles+1]={ax,ay,az,ux,uy,short(terrain,pos+10)/32-az,
                vx,vy,short(terrain,pos+16)/32-az}
        elseif det~=0 then
            triangles[#triangles+1]={ax,ay,az,vy/det,-vx/det,-uy/det,ux/det,
                short(terrain,pos+10)/32-az,short(terrain,pos+16)/32-az}
        end
    end
    if order[cursor] then decoded[order[cursor]]=nil end
    order[cursor],decoded[key]=key,triangles
    cursor=cursor%maxTiles+1
    return triangles
end

-- Segment/triangle intersection against static faces steeper than 45 degrees.
-- Axle height rays handle the supporting faces independently.
local function crossesWall(x,y,z,dx,dy,dz,t)
    local ax,ay,az,ux,uy,uz,vx,vy,vz=unpack(t)
    local hx,hy,hz=dy*vz-dz*vy,dz*vx-dx*vz,dx*vy-dy*vx
    local det=ux*hx+uy*hy+uz*hz
    if math.abs(det)<0.000001 then return false end
    local sx,sy,sz=x-ax,y-ay,z-az
    local u=(sx*hx+sy*hy+sz*hz)/det
    if u<0 or u>1 then return false end
    local qx,qy,qz=sy*uz-sz*uy,sz*ux-sx*uz,sx*uy-sy*ux
    local v=(dx*qx+dy*qy+dz*qz)/det
    if v<0 or u+v>1 then return false end
    local entry=(vx*qx+vy*qy+vz*qz)/det
    return entry>=0 and entry<=1
end

function isVcsRoadPassClear(x,y,z,tx,ty,tz)
    local dx,dy,dz=tx-x,ty-y,tz-z
    for i=math.floor(math.min(x,tx)/cellSize),math.floor(math.max(x,tx)/cellSize) do
        for j=math.floor(math.min(y,ty)/cellSize),math.floor(math.max(y,ty)/cellSize) do
            local walls=tile(i,j,true)
            if not terrain then return false end
            if walls then
                local lx,ly=x-i*cellSize,y-j*cellSize
                for _,face in ipairs(walls) do
                    if crossesWall(lx,ly,z,dx,dy,dz,face) then return false end
                end
            end
        end
    end
    return true
end

function getVcsGroundHeight(x,y,referenceGroundZ)
    if not finite(x) or not finite(y) or not finite(referenceGroundZ) then return false end
    local tx,ty=math.floor(x/cellSize),math.floor(y/cellSize)
    local triangles=tile(tx,ty)
    if not triangles then return false end
    local lx,ly=x-tx*cellSize,y-ty*cellSize
    local best,delta=false,4
    for _,t in ipairs(triangles) do
        local dx,dy=lx-t[1],ly-t[2]
        local u,v=t[4]*dx+t[5]*dy,t[6]*dx+t[7]*dy
        if u>=-0.00001 and v>=-0.00001 and u+v<=1.00001 then
            local z=t[3]+u*t[8]+v*t[9]
            local error=math.abs(z-referenceGroundZ)
            if error<delta or error==delta and (not best or z>best) then best,delta=z,error end
        end
    end
    return best
end

local function wheelClearance(fit,loaded)
    local front,rear=fit[3],fit[4]
    local frontOffset,rearOffset=front[3]-front[2],rear[3]-rear[2]
    -- A new or frozen model renders the DFF dummy at its neutral height
    -- until the first physics frames install the loaded suspension.
    if loaded and fit[2] then
        local h=getModelHandling(fit[1])
        if h and h.suspensionForceLevel>0 then
            -- Same static suspension centre used by the client wheel contacts.
            local sag=h.suspensionUpperLimit-(1-1/(4*h.suspensionForceLevel))*
                (h.suspensionUpperLimit-h.suspensionLowerLimit)
            frontOffset,rearOffset=frontOffset-sag,rearOffset-sag
        end
    end
    return frontOffset,rearOffset
end

local function sampleAxle(axle,x,y,cosYaw,sinYaw,reference)
    local cx,cy=x-axle[1]*sinYaw,y+axle[1]*cosYaw
    local ox,oy=axle[4]*cosYaw,axle[4]*sinYaw
    local left=getVcsGroundHeight(cx-ox,cy-oy,reference)
    if axle[4]<0.01 then return left,left end
    return left,getVcsGroundHeight(cx+ox,cy+oy,reference)
end

local function groundPose(fit,x,y,reference,yaw,confirmedGround,bodyReference)
    if not fit or not finite(yaw) or not finite(x) or not finite(y) or not finite(reference)
        or confirmedGround~=nil and not finite(confirmedGround) then return false end
    local front,rear=fit[3],fit[4]
    local frontOffset,rearOffset=wheelClearance(fit,bodyReference)
    local span=front[1]-rear[1]
    local nominal=(front[1]*rearOffset-rear[1]*frontOffset)/span
    local referenceGroundZ=bodyReference and reference-nominal or reference
    local center=getVcsGroundHeight(x,y,confirmedGround or referenceGroundZ)
    if not center and not confirmedGround then return false end
    local cosYaw,sinYaw=math.cos(math.rad(yaw)),math.sin(math.rad(yaw))
    local base=confirmedGround or center
    local fl,fr,rl,rr
    if center and math.abs(base-center)<1 then
        fl,fr=sampleAxle(front,x,y,cosYaw,sinYaw,center)
        rl,rr=sampleAxle(rear,x,y,cosYaw,sinYaw,center)
    end
    -- A missing wheel hit, roadside hole or separate bridge deck must not
    -- tilt a chassis into another level. Retain the trusted centre surface.
    local function support(hit,axle)
        if hit and math.abs(hit-center)<=0.35+math.sqrt(axle[1]^2+axle[4]^2)*0.65 then
            return base+hit-center
        end
        return base
    end
    fl,fr=support(fl,front),support(fr,front)
    rl,rr=support(rl,rear),support(rr,rear)
    local fz,rz=(fl+fr)/2+frontOffset,(rl+rr)/2+rearOffset
    local body=(front[1]*rz-rear[1]*fz)/span
    local halfTrack=front[4]+rear[4]
    local roll=halfTrack>0.05 and -math.deg(math.atan((fr-fl+rr-rl)/(2*halfTrack))) or 0
    return body,math.deg(math.atan((fz-rz)/span)),roll,nominal
end

function getVcsRoadSpawnPose(original,x,y,referenceGroundZ,yaw,confirmedGround)
    return groundPose(VcsRoadWheelFits[original],x,y,referenceGroundZ,yaw,confirmedGround,false)
end

function getVcsRoadVehiclePose(car,x,y,referenceBodyZ,yaw)
    if not isElement(car) or getElementType(car)~="vehicle" then return false end
    local original=getElementData(car,"vcs_vehicle:originalModel",false) or getElementData(car,"npchlc_traffic:originalModel",false)
    return groundPose(VcsRoadWheelFits[original],x,y,referenceBodyZ,yaw,nil,true)
end
