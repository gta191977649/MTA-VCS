-- A blocked direct attack uses walkable pedestrian links. Search backwards
-- from the target so the first reachable neighbor has the smallest hop count.
PedCombatNavigation = {}
local function firstStep(graph, goal, reachable)
    local queue,seen = {goal},{[goal]=true}
    for i=1,96 do
        local id = queue[i]
        if not id then break end
        if reachable[id] then return graph.nodes[id+1] end
        local node = graph.nodes[id+1]
        for k=1,node.linkCount do
            local nextId = graph.links[node.firstLink+k].to
            local dest = graph.nodes[nextId+1]
            if not seen[nextId] and dest.kind=="pedestrian" and math.floor(dest.flags/32)%2==0
                and math.floor(dest.flags/512)%2==0 then
                seen[nextId] = true
                queue[#queue+1] = nextId
            end
        end
    end
end

function PedCombatNavigation.update(manager,event,graph,now)
    if not graph or not graph.pedestrianCells then return false end
    local ped = manager.ped
    local owner = getElementSyncer(ped)
    if not isElement(owner) then return false end
    if event.navProbe and (now-event.navProbe)%4294967296<120 then return event.detour~=nil end
    event.navProbe=now
    local x,y,z = getElementPosition(ped)
    local tx,ty,tz = getElementPosition(event.target)
    if event.navChecked and (now-event.navChecked)%4294967296<750 then return event.detour~=nil end
    local anchor = TrafficGraph.pedestrianAnchor(graph,x,y,z)
    if not anchor then return false end
    local node = graph.nodes[anchor+1]
    local candidates = {{id=-1,x=tx,y=ty,z=tz}}
    if (node.x-x)^2+(node.y-y)^2+(node.z-z)^2>2.25 then candidates[#candidates+1]=node end
    for i=1,math.min(node.linkCount,13) do
        local dest = graph.nodes[graph.links[node.firstLink+i].to+1]
        if dest.kind=="pedestrian" and (x-dest.x)^2+(y-dest.y)^2>2.25 then candidates[#candidates+1]=dest end
    end
    -- Only transmit the candidate positions; nodes have other graph metadata.
    local positions = {}
    for i,n in ipairs(candidates) do positions[i]={id=n.id,x=n.x,y=n.y,z=n.z} end
    local key = "attack/"..anchor.."/"..math.floor(tx/3).."/"..math.floor(ty/3).."/"..math.floor(tz/2)
    local result = TrafficWorld.reachable(owner,ped,key,positions)
    if result==nil then return event.detour~=nil end
    event.navChecked = now
    local available = {}
    for _,id in ipairs(result or {}) do available[id] = true end
    local step
    if not available[-1] and next(available) then
        local goal = TrafficGraph.pedestrianAnchor(graph,tx,ty,tz)
        step = goal and firstStep(graph,goal,available)
    end
    if step and event.detour~=step.id then
        if exports.npc_hlc:setNPCTask(ped,{"walkTrafficToPoint",step.x,step.y,step.z,1}) then
            event.detour,event.task = step.id,nil
        end
    elseif not step then event.detour=nil end
    return event.detour~=nil
end
