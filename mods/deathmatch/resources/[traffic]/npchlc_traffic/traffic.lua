function initTraffic()
	-- initial values
	--population_group = {peds = {},cars = {},boats = {},planes = {}}
	traffic_density = {peds = 0.008,cars = 0.008,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0}
	SQUARE_SIZE = 20
	STEP_SIZE = 4

	last_yield = getTickCount()
	initTrafficMap()
	loadPaths()
	calculateNodeLaneCounts()
	loadZOffsets()
	initAI()
	initTrafficGenerator()
	traffic_initialized = true
	debug = false
end

function startTrafficInitialization()
	traffic_initialization = coroutine.create(initTraffic)
	keepLoadingTraffic()
end
addEventHandler("onResourceStart",resourceRoot,startTrafficInitialization)

function keepLoadingTraffic()
	if traffic_initialized then
		traffic_initialized = nil
		last_yield = nil
		return
	end
	coroutine.resume(traffic_initialization)
	setTimer(keepLoadingTraffic,50,1)
end

function checkThreadYieldTime()
	local this_time = getTickCount()
	if this_time-last_yield >= 4000 then
		coroutine.yield()
		last_yield = this_time
	end
end

