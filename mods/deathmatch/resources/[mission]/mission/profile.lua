-- A logged-in account and a guest on the same machine have distinct save slots.
local db = dbConnect("sqlite", "vehicle_missions.db")
assert(db and dbExec(db, [[CREATE TABLE IF NOT EXISTS progress (
    owner TEXT PRIMARY KEY, taxiFares INTEGER, taxiEarnings INTEGER,
    vigilante INTEGER, paramedic INTEGER, airrescue INTEGER)]]))
local columns = {}
for _,row in ipairs(assert(dbPoll(dbQuery(db,"PRAGMA table_info(progress)"),-1))) do columns[row.name]=true end
for _,name in ipairs({"firefighter","beachpatrol","firecopter","vicesights"}) do
    if not columns[name] then assert(dbExec(db,"ALTER TABLE progress ADD COLUMN "..name.." INTEGER NOT NULL DEFAULT 0")) end
end
assert(dbExec(db, [[CREATE TABLE IF NOT EXISTS course_records (
    owner TEXT NOT NULL, activity TEXT NOT NULL, course TEXT NOT NULL,
    time INTEGER, lap INTEGER, position INTEGER, score INTEGER, wins INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(owner,activity,course))]]))

function Mission.courseRecord(run, course)
    local rows = dbPoll(dbQuery(db, "SELECT time,lap,position,score,wins FROM course_records WHERE owner=? AND activity=? AND course=?",
        run.profile.owner,run.id,tostring(course)),-1)
    if not rows then return false end
    return rows[1] or {wins=0}
end

local function storeCourse(run,course,metrics,won)
    metrics = metrics or {}
    local previous = Mission.courseRecord(run,course)
    if not previous then return false end
    local values = {}
    for _,key in ipairs({"time","lap","position","score"}) do
        local value = metrics[key]
        local best = previous[key]
        if type(value)=="number" and value >= 0 and value < math.huge then
            value = math.floor(value)
            if not best or (key=="score" and value>best) or (key~="score" and value<best) then best=value end
        end
        values[#values+1]=best or -1
    end
    local wins = previous.wins + (won and 1 or 0)
    local query = dbQuery(db,[[INSERT OR REPLACE INTO course_records(owner,activity,course,time,lap,position,score,wins)
        VALUES (?,?,?,NULLIF(?,-1),NULLIF(?,-1),NULLIF(?,-1),NULLIF(?,-1),?)]],
        run.profile.owner,run.id,tostring(course),values[1],values[2],values[3],values[4],wins)
    return query and dbPoll(query,-1)~=false
end

function Mission.recordCourse(run,course,metrics)
    if not Mission.active(run) and not run.stopping then return false end
    return storeCourse(run,course,metrics,false)
end

function Mission.finishCourse(run,course,metrics,payout,won,outcome)
    if not Mission.active(run) or run.courseFinished then return false end
    run.courseFinished = true
    if not storeCourse(run,course,metrics,won) then return Mission.fail(run,"Your result could not be saved.") end
    Mission.pay(run,payout)
    if won then Mission.notify(run,"mission:payout",run.token,payout and payout>0 and payout or nil) end
    if metrics and metrics.time then
        local seconds=math.floor(metrics.time/1000)
        local clock=("%d:%02d"):format(math.floor(seconds/60),seconds%60)
        outcome=(outcome or (won and "New course record!" or "You failed to beat the target time.")).."  "..clock
    end
    Mission.endRun(run.player,outcome or (won and "Course complete." or "Course finished."),false,won)
    return true
end

local profiles, active, healthStats, armour = {}, {}, {}, {}
local rewardText = {
    paramedic="Paramedic mission complete. You won't tire while running.",
    vigilante="Vigilante mission complete. Body armour gives you increased protection!",
    airrescue="Air Rescue mission complete. Your maximum health has increased!",
    firefighter="Fire Fighter mission complete. You are now completely fireproof.",
    beachpatrol="Beach Patrol mission complete. You will no longer get tired when swimming!",
}

function Mission.profile(player)
    if active[player] then return active[player] end
    local account = getPlayerAccount(player)
    local owner = account and not isGuestAccount(account) and ("account/" .. getAccountName(account))
        or ("guest/" .. getPlayerSerial(player))
    local profile = profiles[owner]
    if not profile then
        local rows = dbPoll(dbQuery(db, "SELECT * FROM progress WHERE owner=?", owner), -1)
        if not rows then return false end
        profile = rows[1] or {owner=owner,taxiFares=0,taxiEarnings=0,vigilante=0,paramedic=0,airrescue=0,
            firefighter=0,beachpatrol=0,firecopter=0,vicesights=0}
        profiles[owner] = profile
    end
    active[player] = profile
    return profile
end

local function save(p)
    local query = dbQuery(db,[[INSERT OR REPLACE INTO progress
        (owner,taxiFares,taxiEarnings,vigilante,paramedic,airrescue,firefighter,beachpatrol,firecopter,vicesights)
        VALUES (?,?,?,?,?,?,?,?,?,?)]],p.owner,p.taxiFares,p.taxiEarnings,p.vigilante,p.paramedic,p.airrescue,
        p.firefighter,p.beachpatrol,p.firecopter,p.vicesights)
    return query and dbPoll(query,-1) ~= false
end

local function publish(player, key, value)
    if getElementData(player,key,false) ~= value then setElementData(player,key,value,"broadcast","deny") end
end

local function applyRewards(player)
    local p = Mission.profile(player)
    if not p then return end
    publish(player,"mission:unlimitedSprint",p.paramedic >= 15)
    publish(player,"mission:fireproof",p.firefighter >= 15)
    publish(player,"mission:unlimitedSwim",p.beachpatrol >= 15)
    publish(player,"mission:taxiJump",p.taxiFares >= 50 or p.taxiEarnings >= 5000)
    publish(player,"mission:maxArmour",p.vigilante >= 15 and 150 or 100)
    if p.vigilante >= 15 and not armour[player] then
        local current = getPedArmor(player)
        armour[player] = {last=current, health=getElementHealth(player), extra=current >= 99.9 and 50 or 0}
        publish(player,"mission:extraArmour",armour[player].extra)
    end
    if p.airrescue >= 15 and not isPedDead(player) then
        local original = healthStats[player] and healthStats[player].original or getPedStat(player,24)
        local boosted = math.min(1000, original + math.ceil(50/0.176))
        healthStats[player] = {original=original,boosted=boosted}
        setPedStat(player,24,boosted)
    end
end

local function refreshProfileRewards(profile)
    for player,current in pairs(active) do
        if current==profile then applyRewards(player) end
    end
end

local function clearRewards(player)
    local stat = healthStats[player]
    if stat and getPedStat(player,24) == stat.boosted then
        setPedStat(player,24,stat.original)
        if getElementHealth(player) > stat.original*0.176 then setElementHealth(player,stat.original*0.176) end
    end
    healthStats[player],armour[player] = nil,nil
    for _,key in ipairs({"mission:extraArmour","mission:maxArmour","mission:taxiJump","mission:unlimitedSprint",
        "mission:unlimitedSwim","mission:fireproof"}) do
        if hasElementData(player,key) then removeElementData(player,key) end
    end
end

function Mission.taxiFare(run, amount)
    if not Mission.active(run) or run.awardedUpdate==run.update then return end
    run.awardedUpdate=run.update
    local p = run.profile
    local unlocked = p.taxiFares >= 50 or p.taxiEarnings >= 5000
    p.taxiFares, p.taxiEarnings = p.taxiFares+1,p.taxiEarnings+amount
    if not save(p) then
        p.taxiFares,p.taxiEarnings=p.taxiFares-1,p.taxiEarnings-amount
        return Mission.fail(run,"Your fare could not be saved.")
    end
    Mission.pay(run,amount)
    if not unlocked and (p.taxiFares >= 50 or p.taxiEarnings >= 5000) then
        refreshProfileRewards(p)
        Mission.notify(run,"mission:payout",run.token)
        Mission.notify(run,"mission:help",run.token,"Taxi Driver mission complete. Use the horn to boost jump in a taxi!",6000)
    end
end

function Mission.finishLevel(run, amount)
    if not Mission.active(run) or run.awardedUpdate==run.update then return end
    run.awardedUpdate=run.update
    local p, level = run.profile,run.level
    if run.id == "vicesights" or run.id == "firecopter" then
        local complete = level == 5
        local first = complete and p[run.id] < 5
        if level > p[run.id] then
            local previous = p[run.id]
            p[run.id] = level
            if not save(p) then
                p[run.id] = previous
                return Mission.fail(run,"Your progress could not be saved.")
            end
        end
        Mission.pay(run,(amount or 0)+(first and 500 or 0))
        run.level = level+1
        if complete then
            exports.wanted:setPlayerWanted(run.player,0,run.id)
            if first then Mission.notify(run,"mission:payout",run.token,500) end
            Mission.endRun(run.player,first and "All runs complete. Bonus $500." or "All runs complete.",false,first)
            return false
        end
        Mission.message(run,("Level %d completed. Bonus: $%d"):format(level,amount or 0))
        return true
    end
    local firstCompletion = level == 15 and p[run.id] < 15
    if (level <= 15 or run.id=="beachpatrol") and level%5 == 0 and level > p[run.id] then
        local previous=p[run.id]
        p[run.id] = level
        if not save(p) then
            p[run.id]=previous
            return Mission.fail(run,"Your checkpoint could not be saved.")
        end
        if firstCompletion then
            refreshProfileRewards(p)
            -- PS2 opcodes 0340 and 0341 set both the maximum and current value.
            if run.id == "beachpatrol" then
                amount = (amount or 0)+1500
                exports.wanted:setPlayerWanted(run.player,0,run.id)
            elseif run.id == "airrescue" then
                amount = (amount or 0)+500
                setElementHealth(run.player,getPedStat(run.player,24)*0.176)
            elseif run.id == "vigilante" then
                setPedArmor(run.player,100)
                armour[run.player] = {last=100,health=getElementHealth(run.player),extra=50}
                publish(run.player,"mission:extraArmour",50)
            end
        end
        Mission.notify(run,"mission:help",run.token,firstCompletion and rewardText[run.id]
            or ("Checkpoint reached! " .. run.definition.title .. " will resume at level " .. (level+1) .. "."),6000)
    end
    Mission.pay(run,amount)
    if firstCompletion then
        Mission.notify(run,"mission:payout",run.token,run.id=="airrescue" and 500 or run.id=="beachpatrol" and 1500 or nil)
    end
    if amount and amount > 0 then
        Mission.message(run,("Level %d completed. Reward: $%d"):format(level,amount))
    end
    run.level = level+1
    return true
end

-- MTA synchronizes up to 100 native armour points. Keep the extra 50 in
-- reserve and replenish the native layer when hits consume it.
local function updateArmour(player, state)
    local current,health = getPedArmor(player),getElementHealth(player)
    if current > state.last and current >= 99.9 then state.extra = 50 end
    if current < state.last and state.extra > 0 and not isPedDead(player) then
        -- A single damage sync can exhaust all native armour and reach health.
        if current==0 and state.health and health<state.health then
            local spill=math.min(state.extra,state.health-health)
            if setElementHealth(player,health+spill) then health,state.extra=health+spill,state.extra-spill end
        end
        local used = math.min(state.extra,state.last-current)
        if setPedArmor(player,current+used) then
            current, state.extra = current+used,state.extra-used
        end
    end
    state.last,state.health = current,health
    publish(player,"mission:extraArmour",state.extra)
end
addEventHandler("onPlayerDamage",root,function()
    if armour[source] then updateArmour(source,armour[source]) end
end)
setTimer(function()
    for player,state in pairs(armour) do updateArmour(player,state) end
end, 100, 0)

addEventHandler("traffic:onPlayerBusted",root,function()
    if armour[source] then
        armour[source].last,armour[source].extra=getPedArmor(source),0
        publish(source,"mission:extraArmour",0)
    end
end)
addEventHandler("onPlayerWasted",root,function()
    armour[source]=nil
    publish(source,"mission:extraArmour",0)
end)

addEventHandler("onPlayerPickupHit",root,function(pickup)
    if armour[source] and getPickupType(pickup)==1 then
        local player=source
        setTimer(function()
            if isElement(player) and armour[player] and getPedArmor(player)>=99.9 then
                armour[player].extra=50
                updateArmour(player,armour[player])
            end
        end,100,1)
    end
end)

local lastJump = {}
local function jump(player)
    local p = active[player]
    if not p or (p.taxiFares < 50 and p.taxiEarnings < 5000) then return end
    local vehicle = getPedOccupiedVehicle(player)
    local model = Mission.model(vehicle)
    if (model ~= 183 and model ~= 226) or Mission.driverOf(vehicle) ~= player or not isVehicleOnGround(vehicle) then return end
    local now = getTickCount()
    if lastJump[player] and now-lastJump[player] < 1000 then return end
    local vx,vy,vz = getElementVelocity(vehicle)
    lastJump[player] = now
    setElementVelocity(vehicle,vx,vy,math.max(vz,0)+0.30)
end

local function bindPlayer(player)
    bindKey(player,"sub_mission","down",Mission.toggle)
    bindKey(player,"horn","down",jump)
    applyRewards(player)
end
local function changeProfile(silent)
    Mission.endRun(source,nil,silent)
    if not silent then Mission.clearUi(source) end
    clearRewards(source)
    local old=active[source]
    active[source]=nil
    if old then
        local shared=false
        for _,p in pairs(active) do if old==p then shared=true break end end
        if not shared then profiles[old.owner]=nil end
    end
end
for _,event in ipairs({"onPlayerLogin","onPlayerLogout"}) do
    addEventHandler(event,root,function() changeProfile() applyRewards(source) end)
end
addEventHandler("onPlayerJoin",root,function() bindPlayer(source) end)
addEventHandler("onPlayerSpawn",root,function() armour[source]=nil applyRewards(source) end)
addEventHandler("onPlayerQuit",root,function() changeProfile(true) lastJump[source]=nil end)
addEventHandler("onResourceStart",resourceRoot,function()
    for _,player in ipairs(getElementsByType("player")) do bindPlayer(player) end
end)
addEventHandler("onResourceStop",resourceRoot,function()
    for player in pairs(active) do clearRewards(player) end
end)
