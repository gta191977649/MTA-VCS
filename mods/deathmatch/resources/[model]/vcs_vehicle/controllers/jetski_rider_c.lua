-- VCS BIKES associations D0..D5. GTA keeps the native boat seat, controls
-- and boarding task while the streamed rider uses the original bone poses.
local riders = {}
local clips

local function isJetSki(vehicle)
    return CVehicle.resolve(vehicle) == CJetSki
end

local function seat(ped, vehicle, index)
    if not isJetSki(vehicle) then riders[ped] = nil return end
    local state = riders[ped]
    if state and state.vehicle == vehicle then
        state.seat = index
        if state.clip and state.clip:find("getoff",1,true) then state.clip = nil end
    else
        riders[ped] = {vehicle=vehicle,seat=index}
    end
end

local function collect(element)
    local kind = getElementType(element)
    if kind == "vehicle" and isJetSki(element) then
        for index, ped in pairs(getVehicleOccupants(element) or {}) do seat(ped,element,index) end
    elseif kind == "player" or kind == "ped" then
        local vehicle = getPedOccupiedVehicle(element)
        if vehicle then seat(element,vehicle,getPedOccupiedVehicleSeat(element)) end
    end
end

local function transition(ped, index, name, door)
    if not isJetSki(source) then return end
    local right
    if door and door >= 0 and door <= 3 then
        right = door % 2 == 1
    else
        local mat = getElementMatrix(source)
        local x,y = getElementPosition(ped)
        right = mat and (x-mat[4][1])*mat[1][1] + (y-mat[4][2])*mat[1][2] > 0
    end
    riders[ped] = {vehicle=source, seat=index, tick=getTickCount(),
        clip=right and name or name.."_mirror"}
end

local function seatPose(ped,vehicle,index)
    seat(ped,vehicle,index)
    local state=riders[ped]
    if not state then return end
    state.clip=nil
    state.boardTick=getTickCount()
    if not clips or not CJetSki.UpdateRider or getPedOccupiedVehicle(ped)~=vehicle then return end
    CJetSki.UpdateRider(ped,state,getTickCount())
end

addEvent("vcs_vehicle:jetSkiMounted",true)
addEvent("vcs_vehicle:jetSkiFell",true)
addEventHandler("vcs_vehicle:jetSkiFell",root,function(ped)
    if riders[ped] and riders[ped].vehicle == source then riders[ped] = nil end
end)
addEventHandler("vcs_vehicle:jetSkiMounted",root,function(ped)
    if isElement(ped) and isJetSki(source) then
        -- The server has already placed the rider in seat zero. The water-side
        -- entry track is reserved for onClientVehicleStartEnter.
        seatPose(ped, source, 0)
    end
end)

addEventHandler("onClientVehicleStartEnter",root,function(ped,index,door)
    transition(ped,index,"jetski_on",door)
end)
addEventHandler("onClientVehicleStartExit",root,function(ped,index,door)
    transition(ped,index,"jetski_getoff",door)
end)
addEventHandler("onClientVehicleEnter",root,function(ped,index) seatPose(ped,source,index) end)
addEventHandler("onClientVehicleExit",root,function(ped)
    local state = riders[ped]
    if state and state.vehicle == source and not (state.clip and state.clip:find("getoff",1,true)) then
        riders[ped] = nil
    end
end)
addEventHandler("onClientElementStreamIn",root,function() collect(source) end)
addEventHandler("onClientElementDataChange",root,function(key)
    if key == CVehicle.modelKey or key == "npchlc_traffic:originalModel" or key == "mod.model" then collect(source) end
end)
local function remove()
    riders[source] = nil
    if getElementType(source) == "vehicle" then
        for ped,state in pairs(riders) do if state.vehicle == source then riders[ped] = nil end end
    end
end
addEventHandler("onClientElementDestroy",root,remove)
addEventHandler("onClientElementStreamOut",root,remove)
addEventHandler("onClientResourceStart",resourceRoot,function()
    local file = fileOpen("data/jetski_rider.json",true)
    if not file then return end
    clips = fromJSON(fileRead(file,fileGetSize(file)))
    fileClose(file)
    for _,vehicle in ipairs(getElementsByType("vehicle",root,true)) do collect(vehicle) end
end,false)

-- Tracks are sampled at 30 Hz and use the same 1/4096 quaternion scale as
-- the converted ANP3 animations. GTA's own task supplies seat translation.
local function pose(ped, name, frame)
    local clip = clips[name]
    local last = #clip.frames
    frame = math.min(last,1+frame)
    local i = math.floor(frame)
    local a,b = clip.frames[i],clip.frames[math.min(last,i+1)]
    local t = frame-i
    for n,bone in ipairs(clip.bones) do
        local k = n*4-3
        local ax,ay,az,aw = a[k],a[k+1],a[k+2],a[k+3]
        local bx,by,bz,bw = b[k],b[k+1],b[k+2],b[k+3]
        local blend = ax*bx+ay*by+az*bz+aw*bw < 0 and -t or t
        local x,y,z,w = ax*(1-t)+bx*blend,ay*(1-t)+by*blend,az*(1-t)+bz*blend,aw*(1-t)+bw*blend
        local norm = math.sqrt(x*x+y*y+z*z+w*w)
        setElementBoneQuaternion(ped,bone,x/norm,y/norm,z/norm,w/norm)
    end
end

-- Each lean clip contains intermediate keyframes. Sample the signed axes
-- independently, then blend associations as in SLUS_215.90 001DC3E8.
local function frames(clip, phase)
    local frame = 1 + math.min(1, math.abs(phase)) * (#clip.frames - 1)
    local index = math.floor(frame)
    return index, math.min(#clip.frames,index+1), frame-index
end

local function sampleQuat(clip, i, j, t, k)
    local a,b=clip.frames[i],clip.frames[j]
    local sign=a[k]*b[k]+a[k+1]*b[k+1]+a[k+2]*b[k+2]+a[k+3]*b[k+3] < 0 and -1 or 1
    local x,y,z,w=a[k]*(1-t)+b[k]*t*sign,a[k+1]*(1-t)+b[k+1]*t*sign,
        a[k+2]*(1-t)+b[k+2]*t*sign,a[k+3]*(1-t)+b[k+3]*t*sign
    local l=math.sqrt(x*x+y*y+z*z+w*w)
    return x/l,y/l,z/l,w/l
end

local function ridePose(ped,state,steer,fore,forward,step)
    local padBlend = math.min(1,0.2*step)
    state.padSide = (state.padSide or 0) + (steer-(state.padSide or 0))*padBlend
    state.padFore = (state.padFore or 0) + (fore-(state.padFore or 0))*padBlend
    -- GAME.DTZ 004C13A0 handling +58 gives max reverse speed -0.2.
    local fastReverse=getElementType(ped)=="player" and forward < -0.2*1.5
    local backing=forward < -0.02 and forward > -0.2*1.5
        and (getPedAnalogControlState(ped,"brake_reverse") or 0)>0.05
    state.reverse=math.max(0,math.min(1,(state.reverse or 0)+(backing and 1 or -1)*4*0.02*step))
    local side = fastReverse and 0 or -state.padSide*0.92105263
    state.side = side + ((state.side or 0)-side)*0.86^step
    local longitudinal = fastReverse and -1 or getElementType(ped)=="player" and state.padFore or 0
    if forward>0.01 and (getPedAnalogControlState(ped,"brake_reverse") or 0)>0.5 then
        longitudinal=math.max(0.1,longitudinal)
    end
    longitudinal=longitudinal*math.max(0,1-math.max(0,math.abs(side)-0.3)*3.846154)
    state.fore=longitudinal+((state.fore or 0)-longitudinal)*0.89^step

    local x,y=math.abs(state.side),math.abs(state.fore)
    local length=math.sqrt(x*x+y*y)
    local wx,wy=1,0
    if x<=0.56 and getElementType(ped)=="player" then
        if y>0.56 then wx,wy=0,1
        elseif length>0.01 then wx,wy=x/length,y/length
        else wx,wy=x,y end
    end
    local total=math.max(1,wx+wy)
    wx,wy=wx/total,wy/total
    local neutral=clips.bikes_ride
    local sx=state.side<0 and clips.bikes_left or clips.bikes_right
    local sy=state.fore<0 and clips.bikes_back or clips.bikes_fwd
    local i,j,t=frames(sx,x)
    local u,v,h=frames(sy,y)
    for n,bone in ipairs(neutral.bones) do
        local k=n*4-3
        local ax,ay,az,aw=sampleQuat(neutral,1,1,0,k)
        local bx,by,bz,bw=sampleQuat(sx,i,j,t,k)
        local cx,cy,cz,cw=sampleQuat(sy,u,v,h,k)
        local b=ax*bx+ay*by+az*bz+aw*bw<0 and -wx or wx
        local c=ax*cx+ay*cy+az*cz+aw*cw<0 and -wy or wy
        local a=1-wx-wy
        local qx,qy,qz,qw=a*ax+b*bx+c*cx,a*ay+b*by+c*cy,a*az+b*bz+c*cz,a*aw+b*bw+c*cw
        -- D2 is a single head track. Its original association fades at 4/s.
        if bone==5 and state.reverse>0 then
            local rx,ry,rz,rw=sampleQuat(clips.jetski_back,1,1,0,1)
            local blend=qx*rx+qy*ry+qz*rz+qw*rw<0 and -state.reverse or state.reverse
            local base=1-state.reverse
            qx,qy,qz,qw=qx*base+rx*blend,qy*base+ry*blend,qz*base+rz*blend,qw*base+rw*blend
        end
        local norm=math.sqrt(qx*qx+qy*qy+qz*qz+qw*qw)
        setElementBoneQuaternion(ped,bone,qx/norm,qy/norm,qz/norm,qw/norm)
    end
    local root={}
    for k=1,3 do
        local base=neutral.root[1][k]
        root[k]=(wx*(sx.root[i][k]*(1-t)+sx.root[j][k]*t-base)
            +wy*(sy.root[u][k]*(1-h)+sy.root[v][k]*h-base))/4096
    end
    return root
end

local function row(m,i)
    return Vector3(m[i][1],m[i][2],m[i][3])
end

local function world(matrix,x,y,z)
    return row(matrix,4)+row(matrix,1)*x+row(matrix,2)*y+row(matrix,3)*z
end

local skeleton={0,1,2,3,4,5,6,7,8,21,22,23,24,25,26,31,32,33,34,35,36,41,42,43,44,51,52,53,54,201,301,302}
local function unit(v)
    return v/v.length
end

local function rotateAxis(v,from,to)
    local cross=from:cross(to)
    local dot=math.max(-1,math.min(1,from:dot(to)))
    if dot < -0.99999 then
        local axis=math.abs(from.z)<0.8 and Vector3(0,0,1) or Vector3(1,0,0)
        axis=unit(from:cross(axis))
        return axis*(2*axis:dot(v))-v
    end
    return v+cross:cross(v)+cross:cross(cross:cross(v))/(1+dot)
end

local function orient(matrix,oldAxis,newAxis)
    matrix.right=rotateAxis(matrix.right,oldAxis,newAxis)
    matrix.forward=rotateAxis(matrix.forward,oldAxis,newAxis)
    matrix.up=rotateAxis(matrix.up,oldAxis,newAxis)
end

-- Preserve each skin's segment lengths and the bend plane of its VCS clip.
local function reachJoint(bones,first,target,pole)
    local upper,middle,tip=bones[first],bones[first+1],bones[first+2]
    if not upper or not middle or not tip then return end
    local origin,joint,finish=upper.position,middle.position,tip.position
    local one,two=joint-origin,finish-joint
    local a,b=one.length,two.length
    local toward=target-origin
    if math.min(a,b,toward.length)<0.0001 then return end
    local dir=unit(toward)
    local reach=math.max(math.abs(a-b)+0.00001,math.min(a+b-0.00001,toward.length))
    local along=(a*a-b*b+reach*reach)/(2*reach)
    local bend=one-dir*one:dot(dir)
    if bend.length<0.0001 then bend=pole-dir*pole:dot(dir) end
    if bend.length<0.0001 then return end
    local newJoint=origin+dir*along+unit(bend)*math.sqrt(math.max(0,a*a-along*along))
    local newFinish=origin+dir*reach
    orient(upper,unit(one),unit(newJoint-origin))
    orient(middle,unit(two),unit(newFinish-newJoint))
    middle.position=newJoint
    local delta=newFinish-finish
    for id=first+2,first+4 do
        if bones[id] then bones[id].position=bones[id].position+delta end
    end
end

local function plantFoot(bones,thigh,m,side)
    local foot,toe=bones[thigh+2],bones[thigh+3]
    if not foot or not toe then return end
    local axis=toe.position-foot.position
    if axis.length<0.001 then return end
    -- Along the original hull's footwell the deck rises from z=.160 at
    -- y=-.50 to .170 at -.35. Leave clearance below the toe joint for the sole.
    local ankle=world(m,side*0.30,-0.50,0.235)
    local down=unit(row(m,2)-row(m,3)*0.31)
    orient(foot,unit(axis),down)
    orient(toe,unit(axis),down)
    toe.position=foot.position+down*axis.length
    reachJoint(bones,thigh,ankle,row(m,2))
end

local function placeDriver(ped,vehicle,m,root)
    if not getElementBoneMatrix or not setElementBoneMatrix then return end
    -- Both the converted model and legacy JETSKI have these original frame
    -- and mesh coordinates. Runtime component yaw includes handlebar steering.
    local x,y,z=getVehicleComponentPosition(vehicle,"handlebars","root")
    local _,_,yaw=getVehicleComponentRotation(vehicle,"handlebars","root")
    if not x or not yaw then return end
    local seatX,seatY,seatZ=getVehicleComponentPosition(vehicle,"ped_frontseat","root")
    if not seatX then seatX,seatY,seatZ=0,-0.456,0.658 end
    -- At ped_frontseat the rendered saddle is 0.152 m above the dummy.
    -- SA bone 1 is the pelvis joint, with the seated skin below its centre.
    local seatWorld=world(m,seatX+root[1],seatY+root[2],seatZ+0.152+0.08+root[3])
    local bones={}
    for _,id in ipairs(skeleton) do
        local bone=getElementBoneMatrix(ped,id)
        if bone then
            local matrix=Matrix()
            matrix.right,matrix.forward,matrix.up=row(bone,1),row(bone,2),row(bone,3)
            matrix.position=row(bone,4)
            bones[id]=matrix
        end
    end
    if not bones[1] then return end
    local delta=seatWorld-bones[1].position
    for _,bone in pairs(bones) do bone.position=bone.position+delta end
    local c,s=math.cos(math.rad(yaw)),math.sin(math.rad(yaw))
    local cj=getElementType(ped)=="player" and getElementModel(ped)==0
    if cj and bones[2] then
        -- Let the chest follow the bars while the pelvis stays aligned with the saddle.
        local twist=math.rad(((yaw+180)%360-180)*0.45)
        local forward=row(m,2)
        local facing=forward*math.cos(twist)-row(m,1)*math.sin(twist)
        local pivot=bones[2].position
        for id,bone in pairs(bones) do
            if (id>=2 and id<=36) or id>=201 then
                bone.position=pivot+rotateAxis(bone.position-pivot,forward,facing)
                orient(bone,forward,facing)
            end
        end
    end
    -- Midpoint between the inner and outer rubber rings at x=.2656/.3849.
    local wrists={}
    for _,arm in ipairs({22,32}) do
        local sign=arm==22 and 1 or -1
        local px,py=sign*0.3252,-0.0477
        local target=world(m,x+px*c-py*s,y+px*s+py*c,z+0.4336)
        local hand,finger=bones[arm+2],bones[arm+3]
        if hand and finger and bones[arm] and bones[arm+1] then
            local palm=(finger.position-hand.position)*0.5
            wrists[arm]=target-palm
        end
    end
    -- At full lock the outer grip moves forwards. Slide the pelvis along
    -- the saddle just enough to keep both arms within this skin's reach.
    for _,arm in ipairs({22,32}) do
        if wrists[arm] then
            local shoulder,elbow,hand=bones[arm].position,bones[arm+1].position,bones[arm+2].position
            local upper,lower=(elbow-shoulder).length,(hand-elbow).length
            -- Leave CJ about 45 degrees of elbow flexion at the outside grip.
            local reach=cj and math.sqrt(upper^2+lower^2+2*upper*lower*0.70710678)
                or upper+lower-0.0001
            local gap=wrists[arm]-shoulder
            local up=row(m,3)
            local height=gap:dot(up)
            local flat=gap-up*height
            local available=math.sqrt(math.max(0,reach*reach-height*height))
            if flat.length>available and flat.length>0.0001 then
                local shift=flat*(1-available/flat.length)
                for _,bone in pairs(bones) do bone.position=bone.position+shift end
            end
        end
    end
    for _,arm in ipairs({22,32}) do
        if wrists[arm] then reachJoint(bones,arm,wrists[arm],row(m,1)*(arm==22 and 1 or -1)) end
    end
    plantFoot(bones,41,m,-1)
    plantFoot(bones,51,m,1)
    for _,id in ipairs(skeleton) do
        if bones[id] then setElementBoneMatrix(ped,id,bones[id]) end
    end
end

function CJetSki.UpdateRider(ped, state, now)
    local vehicle = state.vehicle
    if not isElement(ped) or not isJetSki(vehicle) or isPedDead(ped) then return false end
    local occupied = getPedOccupiedVehicle(ped)
    if occupied and occupied ~= vehicle then return false end
    if state.boardTick then
        if not occupied then return (now-state.boardTick)%4294967296 < 1000 end
        state.boardTick=nil
        local block=getPedAnimation and getPedAnimation(ped)
        if block and string.find(string.lower(block),"swim",1,true) then setPedAnimation(ped) end
    end
    local visible = ped==localPlayer or isElementStreamedIn(ped) and isElementOnScreen(ped)
    if state.clip then
        local frame = (now-state.tick)%4294967296 * 0.03
        if frame < #clips[state.clip].frames-1 then
            if visible then pose(ped,state.clip,frame) updateElementRpHAnim(ped) end
            return true
        end
        state.clip = nil
    end
    if occupied ~= vehicle then return false end
    if state.seat == 0 and CJetSki.CheckRiderMotion then CJetSki.CheckRiderMotion(ped,vehicle) end
    if not visible then return true end
    if state.seat == 0 then
        local m = getElementMatrix(vehicle)
        if not m then return true end
        local vx,vy,vz = getElementVelocity(vehicle)
        local forward = vx*m[2][1]+vy*m[2][2]+(vz or 0)*m[2][3]
        local steer = (getPedAnalogControlState(ped,"vehicle_left") or 0)-(getPedAnalogControlState(ped,"vehicle_right") or 0)
        local fore = (getPedAnalogControlState(ped,"steer_forward") or 0)-(getPedAnalogControlState(ped,"steer_back") or 0)
        if ped~=localPlayer and math.abs(steer)<0.01 then
            if getElementType(ped)=="ped" and getElementData(vehicle,"npchlc_traffic:rail") then
                -- The rail moves the hull without applying angular velocity.
                local heading=math.atan2(-m[2][1],m[2][2])
                local dt=(now-(state.headingTick or now))%4294967296
                if not state.headingTick or dt>=100 then
                    local delta=(heading-(state.heading or heading)+math.pi)%(2*math.pi)-math.pi
                    state.turnInput=dt>0 and dt<=300 and delta*500/dt or 0
                    state.heading,state.headingTick=heading,now
                end
                steer=state.turnInput or 0
            else
                local _,_,yaw=getElementAngularVelocity(vehicle)
                steer=(yaw or 0)*25
                state.headingTick=nil
            end
            steer=math.max(-1,math.min(1,steer))
        end
        local step=math.min(100,(now-(state.lastTick or now-20))%4294967296)/20
        if getGameSpeed then step=step*getGameSpeed() end
        state.lastTick=now
        local root=ridePose(ped,state,steer,fore,forward,step)
        if ped~=localPlayer then CJetSki.SetHandlebars(vehicle,state.padSide) end
        updateElementRpHAnim(ped)
        placeDriver(ped,vehicle,m,root)
        return true
    else
        pose(ped,"bikes_passenger",0)
    end
    updateElementRpHAnim(ped)
    return true
end

addEventHandler("onClientPedsProcessed",root,function()
    if not clips or not setElementBoneQuaternion then return end
    local now = getTickCount()
    -- A native warp can publish the local seat one rendered frame before
    -- onClientVehicleEnter, including when remounting after an ejection.
    local vehicle=getPedOccupiedVehicle(localPlayer)
    local state=riders[localPlayer]
    if vehicle and (not state or state.vehicle~=vehicle or state.clip and state.clip:find("jetski_on",1,true))
            and isJetSki(vehicle) then
        local index=getPedOccupiedVehicleSeat(localPlayer)
        if index and getVehicleOccupant(vehicle,index)==localPlayer then
            seat(localPlayer,vehicle,index)
            riders[localPlayer].clip=nil
            riders[localPlayer].boardTick=now
        end
    end
    for ped,state in pairs(riders) do
        if not CJetSki.UpdateRider(ped,state,now) then riders[ped] = nil end
    end
end)
