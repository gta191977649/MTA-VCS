local x,y,z = -1461,-827,18

function spawnHandler(player)
	spawnPlayer(player, x, y, z)
	fadeCamera(player, true)
	setCameraTarget(player, player)
end

function start()
	local players = getElementsByType ( "player" )
	for i, v in ipairs(players) do
		spawnHandler(v)
	end
end
addEventHandler ( "onResourceStart", getResourceRootElement(getThisResource()), start )

function join()
	spawnHandler(source)
end
addEventHandler("onPlayerJoin", getRootElement(), join)