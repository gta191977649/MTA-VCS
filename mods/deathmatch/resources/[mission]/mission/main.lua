Mission = {}
local definitions, byModel, runs, lastAction = {}, {}, {}, {}
local owners, readyClients, prompted = {}, {}, {}
local vehicles, sites, nextToken = {}, {}, 0
local enteringVehicle = setmetatable({}, {__mode="kv"})

function Mission.driverOf(vehicle)
    local driver = getVehicleOccupant(vehicle, 0)
    if driver and enteringVehicle[driver] ~= vehicle then return driver end
end

local runEpoch = tostring(getTickCount())
local legacyModels = {
    TAXI=226, CABBIE=183, POLICEM=207, FBICAR=193, ENFORCE=234, FBIRAN=268,
    ELECTRAP=191, ELECTRP=191, RHINO=246, HUNTER=275, VICECHEE=204, VICECHE=204,
    AMBULAN=227, AIRAMB=189, HUEYHOSP=189, FIRETRUK=194, BFINJECT=255, MAVERICK=213, HUEY=188,
}

function Mission.model(vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    return tonumber(getElementData(vehicle, "vcs_vehicle:originalModel", false))
        or tonumber(getElementData(vehicle, "npchlc_traffic:originalModel", false))
        or legacyModels[getElementData(vehicle, "mod.model", false)]
        or (getElementModel(vehicle) == 424 and 255)
end

function Mission.register(id, definition)
    assert(not definitions[id], "Duplicate mission " .. id)
    definition.id, definitions[id] = id, definition
    for _, model in ipairs(definition.models) do
        local candidates = byModel[model] or {}
        byModel[model] = candidates
        table.insert(candidates, definition)
    end
end

local function vehicleActivity(player, vehicle)
    local fallback
    for _, def in ipairs(byModel[Mission.model(vehicle)] or {}) do
        if def.canStart then
            if def.canStart(player, vehicle) then return def end
        else
            fallback = def
        end
    end
    return fallback
end

function Mission.track(run, element)
    if owners[element] and owners[element] ~= run then return false end
    if isElement(element) then
        run.elements[element],owners[element] = true,run
        local kind=getElementType(element)
        if kind=="vehicle" and run.definition.course then
            setElementData(element,"mission:raceOwner",run.player,"broadcast","deny")
        end
        if kind=="vehicle" or kind=="ped" then setElementData(element,"mission:actorOwner",run.player,"broadcast","deny") end
    end
    return element
end

function Mission.lease(run, ped)
    if owners[ped] and owners[ped] ~= run then return false end
    if isElement(ped) then
        run.leases[ped],owners[ped] = true,run
        setElementData(ped,"mission:actorOwner",run.player,"broadcast","deny")
    end
    return ped
end

function Mission.forParticipant(player, token, id)
    local run = runs[player]
    if run and run.token == token and run.id == id and getElementDimension(player)==run.dimension
        and getElementInterior(player)==run.interior then return run end
end

function Mission.runForActor(actor)
    return owners[actor]
end

function Mission.participants(run)
    return run.participants
end

function Mission.notify(run, event, ...)
    if runs[run.player] ~= run then return false end
    for _, player in ipairs(Mission.participants(run)) do
        triggerClientEvent(player, event, resourceRoot, ...)
    end
    return true
end

function Mission.vehicleAvailable(run, vehicle)
    return isElement(vehicle) and (not vehicles[vehicle] or vehicles[vehicle] == run)
        and (not owners[vehicle] or owners[vehicle] == run)
end

function Mission.claimVehicle(run, vehicle)
    if not Mission.vehicleAvailable(run,vehicle) then return false end
    vehicles[vehicle], run.vehicles[vehicle] = run,true
    if run.definition.course then setElementData(vehicle,"mission:raceOwner",run.player,"broadcast","deny") end
    return true
end

function Mission.releaseVehicle(run, vehicle)
    if vehicles[vehicle] ~= run then return end
    vehicles[vehicle],run.vehicles[vehicle] = nil,nil
    if run.definition.course and isElement(vehicle) and not run.elements[vehicle] then
        removeElementData(vehicle,"mission:raceOwner")
    end
end

function Mission.switchVehicle(run, vehicle)
    if not Mission.claimVehicle(run,vehicle) then return false end
    if vehicle ~= run.vehicle then
        Mission.releaseVehicle(run,run.vehicle)
        run.vehicle = vehicle
    end
    return true
end

local function siteKey(run, key)
    return ("%d/%d/%s"):format(run.dimension,run.interior,key)
end

function Mission.siteAvailable(run,key)
    return not sites[siteKey(run,key)]
end

function Mission.claimSite(run,key)
    local fullKey = siteKey(run,key)
    if sites[fullKey] then return false end
    sites[fullKey],run.sites[fullKey] = run,true
    return true
end

function Mission.releaseSites(run)
    for key in pairs(run.sites) do sites[key],run.sites[key] = nil,nil end
end

function Mission.releaseSite(run,key)
    local fullKey=siteKey(run,key)
    if sites[fullKey]==run then sites[fullKey],run.sites[fullKey]=nil,nil end
end

function Mission.release(run, ped)
    if not run.leases[ped] then return false end
    run.leases[ped],owners[ped] = nil,nil
    if not isElement(ped) then return false end
    removeElementData(ped,"mission:actorOwner")
    local traffic=getResourceFromName("npchlc_traffic")
    return traffic and getResourceState(traffic)=="running" and exports.npchlc_traffic:releaseTrafficPed(ped)
end

function Mission.marker(run, x, y, z, style, size, color, blip)
    color = color or {237,130,180,228}
    local marker = exports.marker:createMarker(x,y,z,style,size,color[1],color[2],color[3],color[4] or 228,run.player)
    if marker then
        Mission.track(run, marker)
        setElementInterior(marker, run.interior)
        setElementDimension(marker, run.dimension)
        exports.marker:setMarkerBlipVisible(marker, blip == true, 255)
    end
    return marker
end

-- The marker renderer places entity arrows above the ped or vehicle bounds.
function Mission.entityArrow(run,target,color,blip)
    if not isElement(target) then return end
    local x,y,z=getElementPosition(target)
    local marker=Mission.marker(run,x,y,z+1,"arrow",1.5,color,blip)
    if not marker then return end
    if attachElements(marker,target,0,0,1) then return marker end
    destroyElement(marker)
end

function Mission.clearReturnVehicle(run)
    if isElement(run.returnMarker) then destroyElement(run.returnMarker) end
    run.returnMarker=nil
end

function Mission.showReturnVehicle(run,vehicle)
    if isElement(run.returnMarker) and getElementAttachedTo(run.returnMarker)==vehicle then return end
    Mission.clearReturnVehicle(run)
    run.returnMarker=Mission.entityArrow(run,vehicle,{0,0,255,255},true)
end

function Mission.message(run, text)
    if runs[run.player] == run then
        Mission.notify(run, "mission:message", text,run.token)
    end
end

function Mission.hud(run, label, value, barLabel, percent, secondCounter)
    run.label, run.value, run.barLabel, run.percent = label, value, barLabel, percent
    run.secondCounter = secondCounter
end

local function updateHud(run, now, force)
    local seconds = run.deadline and math.max(0, math.ceil((run.deadline-now)/1000))
        or run.elapsedFrom and math.max(0,math.floor((now-run.elapsedFrom)/1000))
    local countdown = run.deadline and true or false
    local signature = table.concat({run.level,tostring(countdown),seconds or "",run.label or "",run.value or "",run.barLabel or "",run.percent or "",
        run.secondCounter and run.secondCounter.label or "",run.secondCounter and run.secondCounter.value or ""}, "|")
    if force or signature ~= run.lastHud then
        run.lastHud = signature
        Mission.notify(run, "mission:hud", run.id, run.level, seconds or false,
            run.label or false, run.value or "", run.barLabel or false, run.percent or 0,run.token,countdown,run.secondCounter or false)
    end
end

function Mission.endRun(player, message, silent, passed)
    local run = runs[player]
    if not run then return end
    runs[player],run.silent,prompted[player] = nil,silent,nil
    if run.definition.stop then
        run.stopping = true
        local ok, reason = pcall(run.definition.stop, run)
        run.stopping = nil
        if not ok then outputDebugString("[mission] " .. tostring(reason), 1) end
    end
    for ped in pairs(run.leases) do Mission.release(run, ped) end
    for vehicle in pairs(run.vehicles) do Mission.releaseVehicle(run,vehicle) end
    Mission.releaseSites(run)
    for element in pairs(run.elements) do if isElement(element) then destroyElement(element) end end
    if isElement(player) and not silent then
        triggerClientEvent(player, "mission:end", resourceRoot, message or false,passed==true,run.token)
    end
end

function Mission.fail(run, message)
    if runs[run.player] == run then Mission.endRun(run.player, message) end
end

function Mission.pay(run, amount)
    if runs[run.player] ~= run or not amount or amount <= 0 then return end
    givePlayerMoney(run.player, math.floor(amount))
end

local function invoke(run, fn, ...)
    local ok, reason = pcall(fn, run, ...)
    if not ok then
        outputDebugString(("[mission] %s: %s"):format(run.id, tostring(reason)), 1)
        Mission.fail(run, "Mission interrupted.")
    end
end

function Mission.startActivity(player, id, vehicle)
    local def = definitions[id]
    if not def or runs[player] or not isElement(player) or isPedDead(player)
        or exports.npchlc_traffic:isTrafficPlayerInCustody(player) then return false end
    if vehicle then
        if not Mission.vehicleAvailable(nil, vehicle) or Mission.driverOf(vehicle) ~= player
            or isVehicleBlown(vehicle) then return false end
        if not def.onFoot and vehicleActivity(player,vehicle) ~= def then return false end
    elseif not def.onFoot then return false end
    if def.onFoot and def.canStart and not def.canStart(player,vehicle) then return false end
    local now = getTickCount()
    local profile = Mission.profile(player)
    if not profile then return end
    nextToken = nextToken+1
    local run = {player=player, vehicle=vehicle, definition=def, id=def.id, profile=profile, token=runEpoch.."/"..nextToken,
        vehicles={}, sites={}, participants={player}, update=0,
        level=def.startLevel and def.startLevel(profile) or (profile[def.id] or 0)+1, elements={},
        leases={}, interior=getElementInterior(player), dimension=getElementDimension(player)}
    runs[player] = run
    if vehicle then Mission.claimVehicle(run,vehicle) end
    Mission.notify(run, "mission:start", def.title, run.token)
    invoke(run, def.start, now)
    if runs[player] == run then updateHud(run, now, true) end
    return runs[player] == run
end

local function replacementActivity(player, run, vehicle)
    if not isElement(vehicle) or Mission.driverOf(vehicle) ~= player or isVehicleBlown(vehicle)
        or not Mission.vehicleAvailable(run,vehicle) or run.elements[vehicle] then return end
    local def = vehicleActivity(player,vehicle)
    if def and def ~= run.definition and (vehicle ~= run.vehicle or def.canStart) then return def end
end

local function toggle(player)
    if not isElement(player) or isPedDead(player) or not isControlEnabled(player, "sub_mission") then return end
    local now = getTickCount()
    if lastAction[player] and now-lastAction[player] < 200 then return end
    lastAction[player] = now
    local run = runs[player]
    local vehicle = getPedOccupiedVehicle(player)
    if vehicle and enteringVehicle[player]==vehicle then return end
    if run and run.definition.sideActivity then return end
    if run then
        local replacement = replacementActivity(player,run,vehicle)
        if replacement then
            Mission.endRun(player,run.definition.title.." cancelled.")
            Mission.startActivity(player,replacement.id,vehicle)
            return
        end
        if run.definition.toggle then invoke(run, run.definition.toggle, now)
        elseif run.cancelAt and now-run.cancelAt < 2500 then Mission.fail(run, run.definition.title .. " cancelled.")
        else
            run.cancelAt = now
            Mission.message(run, "Press the sub-mission control again to cancel.")
        end
        return
    end
    local def = vehicleActivity(player, vehicle)
    if def then Mission.startActivity(player, def.id, vehicle) end
end
Mission.toggle = toggle
function Mission.isPlayerBusy(player) return runs[player] ~= nil end
function Mission.active(run) return runs[run.player] == run end
function Mission.countdown(run,value)
    Mission.notify(run,"mission:raceCue",run.token,value)
end

function Mission.checkpointCue(run,lapComplete)
    Mission.notify(run,"mission:raceCue",run.token,lapComplete and "lap" or "checkpoint")
end

function Mission.selectCourse(run, options, callback, initialIndex)
    if not Mission.active(run) or #options == 0 then return false end
    run.menuSerial = (run.menuSerial or 0)+1
    run.courseMenu = {options=options, select=callback, initialIndex=initialIndex or 1}
    return Mission.notify(run,"mission:courseMenu",run.token,run.id,options,run.menuSerial,run.courseMenu.initialIndex)
end

addEvent("mission:courseChoice",true)
addEventHandler("mission:courseChoice",resourceRoot,function(token,id,index,serial)
    if source ~= resourceRoot or not client then return end
    local run = Mission.forParticipant(client,token,id)
    local menu = run and run.courseMenu
    if not menu or run.menuSerial ~= serial then return end
    if index==false and (id=="turismo" or id=="golf") then return Mission.endRun(client) end
    if type(index) ~= "number" or index % 1 ~= 0 or not menu.options[index] then return end
    run.courseMenu = nil
    Mission.notify(run,"mission:courseSelected",token,serial)
    invoke(run, menu.select, index)
end,false)

function Mission.clearUi(player)
    if readyClients[player] then triggerClientEvent(player,"mission:clearUi",resourceRoot) end
end
addCommandHandler("vehiclemission", toggle)

local function prompt(player, vehicle)
    if not readyClients[player] then return end
    local run = runs[player]
    local def
    if run then
        def = replacementActivity(player,run,vehicle)
        if not def then return end
    else def = vehicleActivity(player,vehicle) end
    if def and not Mission.vehicleAvailable(run,vehicle) then def = nil end
    if def ~= prompted[player] then
        prompted[player] = def
        triggerClientEvent(player,"mission:prompt",resourceRoot,def and def.title or false,vehicle)
    end
end
addEvent("mission:ready", true)
addEventHandler("mission:ready", resourceRoot, function()
    if not client or source ~= resourceRoot then return end
    readyClients[client] = true
    prompted[client] = nil
    local run = runs[client]
    if run then Mission.notify(run,"mission:start",run.definition.title,run.token) updateHud(run, getTickCount(), true)
        if run.courseMenu then Mission.notify(run,"mission:courseMenu",run.token,run.id,run.courseMenu.options,run.menuSerial,run.courseMenu.initialIndex) end
    end
end, false)
addEvent("mission:driverEntered",true)
addEventHandler("mission:driverEntered",resourceRoot,function(vehicle)
    if source~=resourceRoot or not client or not isElement(vehicle) or getElementType(vehicle)~="vehicle" then return end
    if getVehicleOccupant(vehicle,0)==client and getPedOccupiedVehicle(client)==vehicle then
        prompt(client,vehicle)
    end
end,false)
addEventHandler("onVehicleEnter",root,function(player) enteringVehicle[player]=nil end)
addEventHandler("onVehicleExit",root,function(player,seat)
    enteringVehicle[player]=nil
    if seat==0 then prompted[player]=nil end
end)
addEventHandler("onVehicleStartEnter",root,function(player,seat)
    if getElementType(player)=="player" then enteringVehicle[player]=source end
    local run=vehicles[source] or owners[source]
    if run and getElementType(player)=="player" and runs[player]~=run then
        -- Keep the driver's seat and scripted support vehicles available for the objective.
        if seat==0 or owners[source]==run then cancelEvent() end
    end
end)
addEventHandler("onElementDestroy",root,function()
    if vehicles[source] then Mission.releaseVehicle(vehicles[source],source) end
    local run = owners[source]
    if run then run.elements[source],run.leases[source],owners[source] = nil,nil,nil end
end)
addEventHandler("traffic:onPlayerBusted",root,function() Mission.endRun(source,"You were busted.") end)
addEventHandler("onPlayerWasted", root, function() Mission.endRun(source, "You were wasted.") end)
addEventHandler("onPlayerQuit", root, function() Mission.endRun(source,nil,true) lastAction[source],readyClients[source],prompted[source] = nil,nil,nil end)
local runtimeDependencies={marker=true,wanted=true,npchlc_traffic=true,npc_hlc=true,vcs_vehicle=true}
addEventHandler("onResourceStop", root, function(stopped)
    if source==resourceRoot then
        Mission.stopping=true
        for player in pairs(runs) do Mission.endRun(player,nil,true) end
    elseif stopped and runtimeDependencies[getResourceName(stopped)] then
        Mission.stopping=true
        for player in pairs(runs) do Mission.endRun(player,"Mission interrupted.") end
        Mission.stopping=nil
    end
end)
setTimer(function()
    local now = getTickCount()
    for player, run in pairs(runs) do
        if getElementInterior(player) ~= run.interior or getElementDimension(player) ~= run.dimension then
            Mission.fail(run, "You left the mission area.")
        elseif run.deadline and now >= run.deadline then
            if run.definition.expire then invoke(run,run.definition.expire,now)
            else Mission.fail(run, run.definition.timeout or "Time is up!") end
        else
            run.update=run.update+1
            invoke(run, run.definition.tick, now)
            if runs[player] == run then updateHud(run, now) end
        end
    end
end, 200, 0)
