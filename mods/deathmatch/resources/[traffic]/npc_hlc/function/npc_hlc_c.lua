UPDATE_COUNT = 16

AI = {}
AI.config = {
	sensorOffset = 2,
	sensorOffsetZ = 0,
	sensorOffsetY = 1,
	sensorDetectLength = 7,
	backwardsTimer = 1500,
	decision_timeout = 2000,
	decision_walk_timeout = 1000,
	drive_wait_obstcleTimer = 30000,
}
AI.decisions = {
	"DRIVE_NORMAL",
	"FORWARD_AVOID_OBSTCLE",
	"BACKWARD_AVOID_OBSTCLE",
	"WAIT_OBSTCLE",
	"WALK_OBSTCLE_RIGHT",
	"WALK_OBSTCLE_LEFT",
	"WALK_OBSTCLE_BACK",
}


function initNPCData(npc)
	streamed_npcs[npc] = {
		thistask = 1,
		lasttask = 1,
		drive_speed = 0,
		walk_speed = "walk",
		drive_style = "normal",
		avoid_crash = false,
		tasks = {},
		ai = {},
	}
	
	initalAIParameter(npc)
	addEventHandler("onClientElementDestroy",npc, function ()
		streamed_npcs[npc] = nil
	end)
	-- debug
	if debug then 
		streamed_npcs[npc].blip = createBlipAttachedTo(npc,0,2,255,255,255,180)
		streamed_npcs[npc].arrow = createMarker(0,0,0,"arrow",2.0,220,220,220,0)
		attachElements(streamed_npcs[npc].arrow,npc,0,0,5)
		setElementParent(streamed_npcs[npc].arrow,npc)
		setElementParent(streamed_npcs[npc].blip,npc)
	end
end
function initNPCControl()
	--addEventHandler("onClientRender",root,cycleNPCs_old,true,"low")
	setTimer ( cycleNPCs, UPDATE_COUNT,1)
	--setTimer ( cycleNPCs_old,UPDATE_COUNT,1)
end

-- this function deal with the rpc cache table
function setNPCData(npc,key,data) 
	if streamed_npcs[npc] then 
		streamed_npcs[npc][key] = data
		if key == "thistask" and data == nil then 
			streamed_npcs[npc].tasks = {}
			stopAllNPCActions(npc)
		end
	end
end

function initNPCHLC()
	streamed_npcs = {}
	initNPCControl()
	debug = false
end

addEventHandler("onClientResourceStart",resourceRoot,initNPCHLC)