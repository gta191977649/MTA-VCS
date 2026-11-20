PedVoice = {}

-- SLUS_215.90 0x00485AA8, rows indexed by speech event minus 0x66.
local rules = {
    mugVictim = {id=0x7B, delay=800, jitter=400, repeatDelay=2000, repeatJitter=1000, global=3200},
    mugger = {id=0x79, delay=800, jitter=200, repeatDelay=1000, repeatJitter=500, global=2200},
    serviceOffer = {id=0x93, delay=2500, jitter=1000, repeatDelay=5000, repeatJitter=5000, global=3000},
    serviceAction = {id=0x7F, delay=800, jitter=400, repeatDelay=1200, repeatJitter=500, global=3000},
    serviceEnd = {id=0x7E, delay=4000, jitter=1000, repeatDelay=5000, repeatJitter=1000, global=2000},
    chat = {id=0x9C, delay=1500, jitter=1000, repeatDelay=2500, repeatJitter=1000, global=2500},
    look = {id=0x99, delay=1000, jitter=500, repeatDelay=3000, repeatJitter=2000, global=3200},
    treat = {id=0x8B, delay=2000, jitter=1000, repeatDelay=4000, repeatJitter=1000, global=3200},
    arrive = {id=0x8C, delay=2000, jitter=1000, repeatDelay=4000, repeatJitter=1000, global=4000},
    revived = {id=0x7C, delay=2000, jitter=2000, repeatDelay=4000, repeatJitter=4000, global=3400},
    fireScene = {id=0x96, delay=1000, jitter=500, repeatDelay=2000, repeatJitter=4000, global=3000},
    arrest = {id=0x6D, delay=5000, jitter=2000, repeatDelay=7000, repeatJitter=3000, global=2500},
    arrested = {id=0x6C, delay=2000, jitter=50, repeatDelay=2050, repeatJitter=1000, global=3000},
    gunpoint = {id=0x76, delay=1000, jitter=500, repeatDelay=2000, repeatJitter=1500, global=3100},
    fear = {id=0x77, delay=1700, jitter=1000, repeatDelay=3000, repeatJitter=1000, global=3000},
    pain = {id=0x6A, delay=100, jitter=2, repeatDelay=100, repeatJitter=2, global=1000},
    impact = {id=0x8A, delay=200, jitter=200, repeatDelay=200, repeatJitter=200, global=1000},
    carjack = {id=0x7A, delay=800, jitter=400, repeatDelay=2000, repeatJitter=1000, global=2600},
    evade = {id=0x8D, delay=1000, jitter=500, repeatDelay=3000, repeatJitter=1000, global=3000},
    crash = {id=0x8F, delay=3000, jitter=2000, repeatDelay=5000, repeatJitter=1000, global=3000},
    reclaim = {id=0x8E, delay=1000, jitter=500, repeatDelay=1000, repeatJitter=1000, global=3000},
}
-- Older catalogs store events directly under the model instead of a list of variants.
local banksByModel = {}
for model, entry in pairs(PedVoiceClips) do
    if #entry > 0 then
        banksByModel[model] = entry
    elseif next(entry) then
        banksByModel[model] = {entry}
    end
end
local speakers, listeners = {}, {}
local audibleRange = 40
local function elapsed(now, before) return (now - before) % 4294967296 end

local function deliver(ped)
    local state = speakers[ped]
    if not state then return end
    state.timer = nil
    local kind = state.pending
    state.pending = nil
    if not kind or not isElement(ped) or isPedDead(ped) then return end
    local model = getElementType(ped)=="player" and 0 or getElementData(ped,"npchlc_traffic:originalModel",false)
    local variants = banksByModel[model]
    if not variants then return end
    if state.model ~= model then
        state.model, state.variant = model, math.random(#variants)
        state.clip = nil
    end
    local bank = variants[state.variant]
    local clips = bank and (bank[kind] or kind == "impact" and bank.pain)
    if not clips or #clips == 0 then return end
    local spec, now = rules[kind], getTickCount()
    local x,y,z = getElementPosition(ped)
    local nearby = getElementsWithinRange(x,y,z,audibleRange,"player",getElementInterior(ped),getElementDimension(ped))
    local recipients = {}
    for _, player in ipairs(nearby or {}) do
        local heard = listeners[player] or {}
        if not heard[kind] or elapsed(now,heard[kind]) >= spec.global then
            heard[kind], listeners[player] = now, heard
            recipients[#recipients+1] = player
        end
    end
    if #recipients == 0 then return end
    local index = math.random(#clips)
    if clips[index] == state.clip then index = index % #clips + 1 end
    state.clip, state.kind, state.tick = clips[index], kind, now
    state.delay = spec.delay + math.random(0,spec.jitter-1)
    triggerClientEvent(recipients,"npchlc_traffic:pedVoice",resourceRoot,ped,state.clip,audibleRange)
end

function PedVoice.emit(ped, kind, delay)
    local spec = rules[kind]
    if not spec or not isElement(ped) or isPedDead(ped) then return false end
    local state = speakers[ped] or {}
    if state.pending and rules[state.pending].id <= spec.id then return false end
    local age = state.tick and elapsed(getTickCount(),state.tick)
    if state.kind == kind and age < spec.repeatDelay + math.random(0,spec.repeatJitter-1) then return false end
    state.pending, speakers[ped] = kind, state
    if not state.timer then
        state.timer = setTimer(deliver,math.max(50, delay or 0, age and state.delay-age or 0),1,ped)
    end
    return true
end

addEventHandler("onElementDestroy",root,function()
    local state = speakers[source]
    if state and state.timer and isTimer(state.timer) then killTimer(state.timer) end
    speakers[source], listeners[source] = nil,nil
end)
addEventHandler("onPlayerQuit",root,function() listeners[source] = nil end)
