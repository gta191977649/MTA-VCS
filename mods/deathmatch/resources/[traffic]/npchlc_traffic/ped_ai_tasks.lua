PedTaskManager = {}
PedTaskManager.__index = PedTaskManager
local hlc = exports.npc_hlc

function PedTaskManager.new(ped)
    return setmetatable({ped = ped}, PedTaskManager)
end

function PedTaskManager:clear(restoreWalk)
    hlc:clearNPCTasks(self.ped)
    if restoreWalk then hlc:setNPCWalkSpeed(self.ped, "walk") end
end

function PedTaskManager:hasRangedWeapon()
    return PedAIRules.ranged(getPedWeapon(self.ped)) and getPedTotalAmmo(self.ped) > 0
end

local diagonal=math.sqrt(.5)
local escapeDirections={{1,0},{diagonal,diagonal},{diagonal,-diagonal},{0,1},{0,-1}}

local function fleeDestination(ped, graph, event, origin)
    local x, y, z = getElementPosition(ped)
    if origin then x,y,z=origin.x,origin.y,origin.z end
    local owner = getElementSyncer(ped)
    if not isElement(owner) or not graph then return end
    local anchor = origin and origin.id and origin.id>=0 and origin.id or TrafficGraph.pedestrianAnchor(graph, x, y, z)
    local node = anchor and graph.nodes[anchor + 1]
    local tx, ty
    if event.origin then tx, ty = event.origin[1], event.origin[2]
    else tx, ty = getElementPosition(event.target) end
    local dx, dy = x - tx, y - ty
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then
        local yaw = math.rad(getPedRotation(ped))
        dx, dy = -math.sin(yaw), math.cos(yaw)
    else
        dx, dy = dx / length, dy / length
    end
    local candidates = {}
    if node and getDistanceBetweenPoints3D(x, y, z, node.x, node.y, node.z) < 25 then
        for offset = 1, node.linkCount do
            local link = graph.links[node.firstLink + offset]
            local dest = graph.nodes[link.to + 1]
            if math.floor(dest.flags / 32) % 2 == 0 and (not event.failedPoint or dest.id~=event.failedPoint.id) then
                candidates[#candidates + 1] = {id = dest.id, x = dest.x, y = dest.y, z = dest.z}
            end
        end
    end
    -- Keep graph links first. If all are occluded (often by the car the
    -- driver just left), also test short exits away and to either side.
    for i,direction in ipairs(escapeDirections) do
        if #candidates>=15 then break end
        local c,s=direction[1],direction[2]
        candidates[#candidates+1]={id=-i,x=x+6*(dx*c-dy*s),y=y+6*(dy*c+dx*s),z=z}
    end
    local key = "flee/" .. tostring(anchor)
    if origin then key=key.."/"..origin.x.."/"..origin.y end
    local reachable,tested = TrafficWorld.reachable(owner, ped, key, candidates,origin,nil,event)
    if type(reachable) ~= "table" then return end
    local best, bestScore = nil, -math.huge
    local ids = {}
    for _, id in ipairs(reachable) do ids[id] = true end
    local failed=event.failedPoint
    for _, dest in ipairs(tested or candidates) do
        if ids[dest.id] and (not failed or (dest.x-failed.x)^2+(dest.y-failed.y)^2>1) then
            local vx, vy = dest.x - x, dest.y - y
            local len = math.sqrt(vx * vx + vy * vy)
            if len > 1 then
                local score = (vx * dx + vy * dy) / len + (dest.id>=0 and 3 or 0)
                if score > bestScore then best, bestScore = dest, score end
            end
        end
    end
    return best
end

function PedTaskManager:flee(graph,event,now)
    hlc:setNPCWalkSpeed(self.ped,"sprint")
    local owner=getElementSyncer(self.ped)
    if event.routeOwner and event.routeOwner~=owner then
        self:clear()
        event.task,event.preview,event.probe,event.steering=nil,nil,nil,nil
    end
    event.routeOwner=owner
    if not event.task then event.preview=nil end
    if event.intent and event.task then
        local x,y=getElementPosition(self.ped)
        if not event.routeCheck or (x-event.routeX)^2+(y-event.routeY)^2>=0.25 then
            event.routeCheck,event.routeX,event.routeY=now,x,y
        elseif (now-event.routeCheck)%4294967296>=4000 then
            event.failedPoint=event.task
            self:clear()
            event.task,event.preview,event.routeCheck,event.probe=nil,nil,nil,nil
        end
    end
    if event.preview or event.probe and (now-event.probe)%4294967296<120 then return end
    event.probe=now
    if not event.task then
        local first=fleeDestination(self.ped,graph,event)
        if not first then
            if event.intent=="flee" and not event.steering then
                local tx,ty
                if event.origin then tx,ty=event.origin[1],event.origin[2]
                else tx,ty=getElementPosition(event.target) end
                event.steering=hlc:setNPCTask(self.ped,{"fleeFromPoint",tx,ty})
            end
            return
        end
        if not hlc:setNPCTask(self.ped,{"walkTrafficToPoint",first.x,first.y,first.z,1,flee=true}) then return end
        event.steering=nil
        event.task,event.issued=first,now
    end
    if not event.intent then -- Fire owns its own lifetime and completion.
        if getDistanceBetweenPoints2D(event.task.x,event.task.y,getElementPosition(self.ped))<=1.5
            or (now-event.issued)%4294967296>=4000 then event.task=nil end
        return
    end
    local nextPoint=fleeDestination(self.ped,graph,event,event.task)
    if nextPoint and hlc:addNPCTask(self.ped,{"walkTrafficToPoint",nextPoint.x,nextPoint.y,nextPoint.z,1,flee=true}) then
        event.preview=nextPoint
    end
end

addEventHandler("npc_hlc:onNPCTaskDone",root,function(task)
    local brain=PedAI.brain(source)
    local event=brain and brain.event
    local point=event and event.intent=="flee" and event.task
    if point and task[1]=="walkTrafficToPoint" and point.x==task[2] and point.y==task[3] and point.z==task[4] then
        event.task,event.preview,event.probe,event.routeCheck=event.preview,nil,nil,nil
        TrafficAmbient.wakeReaction(source,event)
    end
end)

addEventHandler("onElementStartSync",root,function()
    local brain=PedAI.brain(source)
    local event=brain and brain.event
    if event and event.intent=="flee" and event.routeOwner and event.routeOwner~=getElementSyncer(source) then
        TrafficAmbient.wakeReaction(source,event)
    end
end)

function PedTaskManager:execute(graph, event, now)
    local ped = self.ped
    if event.committed and PedCarjack.confront(self, event, now) then return end
    if event.kind == "roadRage" and not event.committed then
        if not event.gestureAt then
            local x, y = getElementPosition(ped)
            local tx, ty = getElementPosition(event.target)
            setPedRotation(ped, -math.deg(math.atan2(tx - x, ty - y)))
            -- CTaskSimpleShakeFist plays PED/fucku (80 ticks at 60 Hz).
            setPedAnimation(ped, "PED", "fucku", -1, false, false, false, false, 150)
            event.gestureAt = now
            return
        end
        if (now - event.gestureAt) % 4294967296 < 1333 then return end
    end
    if event.kind == "nearMiss" and PedVehicleEvasion then
        PedVehicleEvasion.bullet(ped,event)
        return
    end
    if event.intent == "look" or event.intent == "evade" then
        if event.task then return end
        local x, y = getElementPosition(ped)
        local tx, ty = getElementPosition(event.target)
        setPedRotation(ped, -math.deg(math.atan2(tx - x, ty - y)))
        if event.intent == "evade" then
            setPedAnimation(ped, "PED", event.animation, 850, false, false, true, false)
        end
        event.task = true
        return
    end
    if event.intent == "fight" then
        if not event.committed and PedCarjack.confront(self, event, now) then return end
        hlc:setNPCWalkSpeed(ped,event.pace or "run")
        if PedCombatNavigation and PedCombatNavigation.update(self,event,graph,now) then return end
        local armed = self:hasRangedWeapon()
        if armed and PedSpecial then PedSpecial.sampleAim(ped) end
        local vehicle = (armed or event.kind == "damage" or event.kind == "gunpoint" or event.attackOccupied or event.kind == "roadRage" or event.kind == "carjack" and event.road)
            and getPedOccupiedVehicle(event.target) or false
        local weapon = getPedWeapon(ped)
        if not event.task or event.weapon ~= weapon or event.armed ~= armed or event.targetVehicle ~= vehicle then
            event.armed, event.targetVehicle, event.weapon = armed, vehicle, weapon
            if not armed and PedAIRules.ranged(getPedWeapon(ped)) then setPedWeaponSlot(ped, 0)
                event.weapon = getPedWeapon(ped)
            end
            local original = weapon == self.hostWeapon and self.originalWeapon
            local range = armed and PedAIRules.attackRange(weapon, original) or 1.7
            event.task = hlc:setNPCTask(ped, {vehicle and "attackOccupiedVehicle" or "killPed",
                event.target, range, armed and range / 3 or range * 0.8, armed and 1 or 0})
        end
    else
        self:flee(graph, event, now)
    end
end
