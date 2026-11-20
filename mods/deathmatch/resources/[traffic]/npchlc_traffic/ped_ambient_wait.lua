PedAmbientWait = {}
local motion = "npchlc_traffic:activityMotion"
local serial = 0

local function clip(ped,wait,name)
    serial = serial+1
    wait.clip = name
    setElementData(ped,motion,{name,false,serial,PedActivityClips[name],getTickCount()},"broadcast","deny")
end

function PedAmbientWait.cancel(ped,walk)
    if not walk.wait then return end
    if walk.wait.clip and isElement(ped) then removeElementData(ped,motion) end
    walk.wait = nil
end

function PedAmbientWait.start(ped,walk,id,now,route)
    local wait = {id=id,started=now,route=route}
    walk.wait,walk.blockedSince = wait,nil
    if id == 2 or id == 8 then clip(ped,wait,"idle_hbhb") end
end

function PedAmbientWait.update(ped,walk,now,continueRoute)
    local wait = walk.wait
    if not wait then return false end
    local age = (now-wait.started)%4294967296
    if wait.id == 1 then
        local phase = math.floor(now%32768/2)
        if age <= 500 or phase < 12000 or phase >= 15384 then return true end
    elseif wait.id == 2 then
        if age <= 1000 then return true end
        if math.random(0,1) == 0 then
            wait.id,wait.started,wait.duration = 3,now,math.random(2000,4999)
            clip(ped,wait,"roadcross")
            return true
        end
    elseif wait.id == 3 then
        if age <= wait.duration then return true end
    elseif wait.id == 8 then
        if not wait.scratched and age > 1000 and age < 1500 then
            wait.scratched = true
            clip(ped,wait,"xpressscratch")
        end
        if age <= (wait.scratched and 3000 or 3500) then return true end
    end
    local route = wait.route
    PedAmbientWait.cancel(ped,walk)
    if route then continueRoute(ped,walk,unpack(route)) end
    return true
end
