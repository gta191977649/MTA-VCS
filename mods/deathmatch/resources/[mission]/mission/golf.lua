local range=DrivingRange
local invitations={}
local function eligible(player)
    if not isElement(player) or getElementType(player)~="player" or isPedDead(player)
        or isPedInVehicle(player) or getElementDimension(player)~=0 or getElementInterior(player)~=0 then return false end
    local x,y,z=getElementPosition(player)
    return getDistanceBetweenPoints3D(x,y,z,unpack(range.entry))<=4
end

local function send(match,event,...)
    for _,run in ipairs(match.players) do Mission.notify(run,event,run.token,match.turn,...) end
end

local function showScore(match,shot)
    local score={label="Score",value=match.active.score}
    for _,viewer in ipairs(match.players) do
        Mission.hud(viewer,"Shot",("%d/%d"):format(shot,5),nil,nil,score)
    end
end

local function startTurn(match,run)
    match.turn=match.turn+1
    match.active,match.phase,match.fast=run,"ready",false
    local scores={}
    for _,other in ipairs(match.players) do
        scores[#scores+1]=getPlayerName(other.player)..": "..other.score
    end
    showScore(match,run.shots+1)
    send(match,"mission:golfTurn",run.player,run.shots+1,table.concat(scores,"   "),run.target)
end

local function begin(first,second)
    local match={players={first,second},turn=0}
    for _,run in ipairs(match.players) do
        local record=Mission.courseRecord(run,"round")
        if not record then
            for _,member in ipairs(match.players) do Mission.fail(member,"Could not load the driving range record.") end
            return
        end
        run.target=math.max(500,record.score or 0)
    end
    for _,run in ipairs(match.players) do
        run.match,run.score,run.shots=match,0,0
        run.frozen=isElementFrozen(run.player)
        setElementFrozen(run.player,true)
    end
    startTurn(match,first)
end

local function finish(match)
    match.finished=true
    for i,run in ipairs(match.players) do
        local rival=match.players[3-i]
        local text=("Score %d. "):format(run.score)
        if rival then
            text=text..("Opponent %d. "):format(rival.score)
            if run.score==rival.score then text=text.."Draw. "
            elseif run.score>rival.score then text=text.."You won the match. "
            else text=text.."Opponent wins. " end
        end
        local record=Mission.courseRecord(run,"round")
        if record then
            local passed=run.score>math.max(500,record.score or 0)
            Mission.finishCourse(run,"round",{score=run.score},passed and record.wins==0 and 1000 or 0,passed,
                text..(passed and "New high score!" or "You failed to beat the high score."))
        else Mission.fail(run,"Could not save the driving range result.") end
    end
end

local function advance(match)
    local players=match.players
    local nextRun=players[1]==match.active and players[2] or players[1]
    if nextRun and nextRun.shots<5 then return startTurn(match,nextRun) end
    if match.active.shots<5 then return startTurn(match,match.active) end
    finish(match)
end

local function setPhase(match,phase,now)
    match.phase,match.start=phase,now
    send(match,"mission:golfPhase",phase,now,match.power or 0,match.angle or 0)
end

local function lockMeter(match,now)
    local phase=match.phase
    local position=range.meter(phase,now-match.start,match.power)
    if phase=="power" then
        match.power=range.power(position)
        setPhase(match,"aim",now+500)
    else
        match.angle=range.angle(position)
        setPhase(match,"swing",now)
    end
end

local function scoreShot(match,now)
    local run=match.active
    local points=math.floor(match.distance)+(match.bonus and 50 or 0)
    run.shots,run.score=run.shots+1,run.score+points
    if match.bonus then Mission.pay(run,50) end
    Mission.recordCourse(run,"furthest_drive_cm",{score=math.floor(match.distance*100+0.5)})
    local result=("Distance %.1f m. %d points%s. Total %d."):format(match.distance,points,
        match.bonus and " including 50 buoy bonus" or "",run.score)
    showScore(match,run.shots)
    for _,other in ipairs(match.players) do
        Mission.message(other,result)
    end
    setPhase(match,"result",now)
end

local function clockFlight(match,now)
    match.elapsed=match.elapsed+(now-match.last)*(match.fast and 0.8 or 0.4)
    match.last=now
end

local function tick(run,now)
    if not eligible(run.player) then return Mission.fail(run,"You left the driving range.") end
    if run.invited and (not eligible(run.invited) or now>=run.expires or Mission.isPlayerBusy(run.invited)) then
        return Mission.fail(run,"Challenge expired.")
    end
    local m=run.match
    if not m or m.active~=run then return end
    local phase=m.phase
    if phase=="power" or phase=="aim" then
        local position=range.meter(phase,math.max(0,now-m.start),m.power)
        if phase=="power" and position>=100 or phase=="aim" and position<=0 then lockMeter(m,now) end
    elseif phase=="swing" and now-m.start>=800 then
        local points
        points,m.distance,m.bonus=range.flight(m.power,m.angle)
        m.duration,m.elapsed,m.last=(#points-1)*20,0,now
        setPhase(m,"flight",now)
    elseif phase=="flight" then
        clockFlight(m,now)
        if m.elapsed>=m.duration then scoreShot(m,now) end
    elseif phase=="result" and now-m.start>=3500 then advance(m) end
end

local function stop(run)
    if run.invited and invitations[run.invited]==run then invitations[run.invited]=nil end
    if isElement(run.player) then
        if not (Mission.stopping and run.silent) then
            triggerClientEvent(run.player,"mission:golfStop",resourceRoot,run.token)
        end
        if run.frozen~=nil then
            setElementFrozen(run.player,run.frozen)
            if not Mission.stopping and not run.silent and eligible(run.player) and not exports.npchlc_traffic:isTrafficPlayerInCustody(run.player) then
                setElementPosition(run.player,80.9973,586.7621,14.6)
                setElementRotation(run.player,0,0,290,"default",true)
            end
        end
    end
    local m=run.match
    if not m or m.finished or Mission.stopping then return end
    for i,r in ipairs(m.players) do if r==run then table.remove(m.players,i) break end end
    local survivor=m.players[1]
    if survivor and Mission.active(survivor) then
        if isElement(run.player) then Mission.notify(survivor,"mission:golfDepart",survivor.token,run.player) end
        Mission.message(survivor,"Your opponent left the driving range.")
        if m.active==run then
            if survivor.shots<5 then startTurn(m,survivor) else finish(m) end
        end
    end
end

local function start(run)
    local player=run.player
    local host=invitations[player]
    if host and Mission.active(host) and eligible(host.player) and host.expires>getTickCount() then
        invitations[player],host.invited=nil,nil
        host.waiting,run.host=run,host
        return Mission.selectCourse(run,{"Accept challenge from "..getPlayerName(host.player),"Decline"},function(r,index)
            if index==1 and Mission.active(host) and host.waiting==r and eligible(host.player) and eligible(player) then
                host.waiting,r.host=nil,nil
                begin(host,r)
            else Mission.endRun(player) end
        end)
    end
    invitations[player]=nil
    local options,candidates={"Play solo"},{}
    for _,other in ipairs(getElementsByType("player")) do
        if other~=player and eligible(other) and not Mission.isPlayerBusy(other) and not invitations[other] then
            options[#options+1]="Challenge "..getPlayerName(other)
            candidates[#options]=other
        end
    end
    if #options==1 then return begin(run) end
    Mission.selectCourse(run,options,function(r,index)
        if index==1 then return begin(r) end
        local other=candidates[index]
        if not eligible(other) or Mission.isPlayerBusy(other) or invitations[other] then
            return Mission.fail(r,"That golfer is unavailable.")
        end
        invitations[other],r.invited,r.expires=r,other,getTickCount()+30000
        Mission.message(r,"Challenge sent. Backspace to withdraw.")
        Mission.notify(r,"mission:golfWaiting",r.token)
        triggerClientEvent(other,"mission:golfPrompt",resourceRoot,getPlayerName(player))
    end)
end

Mission.register("golf",{title="Swinger's Club",onFoot=true,sideActivity=true,models={},canStart=eligible,
    start=start,tick=function(run,now)
        if run.waiting and (not Mission.active(run.waiting) or now>=run.expires) then
            return Mission.fail(run,"Challenge ended.")
        end
        if run.host and not Mission.active(run.host) then return Mission.fail(run,"Challenge ended.") end
        tick(run,now)
    end,stop=stop})

addEvent("mission:golfEnter",true)
addEventHandler("mission:golfEnter",resourceRoot,function()
    if client and source==resourceRoot and eligible(client) then Mission.startActivity(client,"golf") end
end,false)

addEvent("mission:golfInput",true)
addEventHandler("mission:golfInput",resourceRoot,function(token,turn,phase,action)
    if not client or source~=resourceRoot then return end
    local run=Mission.forParticipant(client,token,"golf")
    if not run then return end
    if action=="leave" then return Mission.endRun(client,"You left the driving range.") end
    local m=run.match
    if not m or m.active~=run or turn~=m.turn or phase~=m.phase then return end
    local now=getTickCount()
    if action=="strike" then
        if phase=="ready" then setPhase(m,"power",now)
        elseif (phase=="power" or phase=="aim") and now>=m.start then lockMeter(m,now) end
    elseif phase=="flight" and type(action)=="boolean" and m.fast~=action then
        clockFlight(m,now)
        m.fast=action
        send(m,"mission:golfSpeed",now,m.elapsed,m.fast)
    end
end,false)

addEventHandler("onResourceStart",resourceRoot,function()
    local p=range.entry
    local marker=exports.marker:createMarker(p[1],p[2],p[3]-0.85,"cylinder",2,237,130,180,228)
    if marker then addEventHandler("onMarkerHit",marker,function(player,matching)
        if matching and eligible(player) and not Mission.isPlayerBusy(player) then
            triggerClientEvent(player,"mission:golfPrompt",resourceRoot,false)
        end
    end) end
end)
