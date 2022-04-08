ZoneInfo = {}
SpecialZoneInfo = {}
TrafficZone = {}
Cities = {}
function loadZoneInfo() 
	local f = fileOpen("data/zone.dat")
	local lines = fileRead(f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i = 1,#lines do 
		local data = split(lines[i],",")
		ZoneInfo[data[1]] = {
			p1 = {tonumber(data[3]),tonumber(data[4])},
			p2 = {tonumber(data[6]),tonumber(data[7])},
			size_x = math.abs(tonumber(data[3]) - tonumber(data[6])),
			size_y = math.abs(tonumber(data[4]) - tonumber(data[7])),
		}
		--createRadarArea ( tonumber(data[3]),tonumber(data[4]), ZoneInfo[data[1]].size_x,ZoneInfo[data[1]].size_y, math.random(0,255),  math.random(0,255), math.random(0,255), 175) 
	end
	-- load city
	local f = fileOpen("data/city.dat")
	local lines = fileRead(f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i = 1,#lines do 
		local data = split(lines[i],",")
		Cities[data[1]] = {
			p1 = {tonumber(data[3]),tonumber(data[4])},
			p2 = {tonumber(data[6]),tonumber(data[7])},
			size_x = math.abs(tonumber(data[3]) - tonumber(data[6])),
			size_y = math.abs(tonumber(data[4]) - tonumber(data[7])),
		}
		--createRadarArea ( tonumber(data[3]),tonumber(data[4]), ZoneInfo[data[1]].size_x,Cities[data[1]].size_y, math.random(0,255),  math.random(0,255), math.random(0,255), 50) 
	end
	-- local special zone
	local f = fileOpen("data/zone_special.dat")
	local lines = fileRead(f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i = 1,#lines do 
		local data = split(lines[i],",")
		SpecialZoneInfo[data[1]] = {
			p1 = {tonumber(data[3]),tonumber(data[4])},
			p2 = {tonumber(data[6]),tonumber(data[7])},
			size_x = math.abs(tonumber(data[3]) - tonumber(data[6])),
			size_y = math.abs(tonumber(data[4]) - tonumber(data[7])),
		}
		--createRadarArea ( tonumber(data[3]),tonumber(data[4]), SpecialZoneInfo[data[1]].size_x,SpecialZoneInfo[data[1]].size_y,255,0,0, 255) 
	end
	--iprint(Cities)
end

function loadTrafficZone() 
	local f = fileOpen("data/trafficzone.dat")
	local lines = fileRead(f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i = 1,#lines do 
		local data = split(lines[i],",")
		local name = data[1]
		local prop_type = data[2]
		if prop_type then
			if prop_type == "traffic" then 
				if ZoneInfo[name] or SpecialZoneInfo[name] then
					local prop = string.gsub(data[3], "\r", "")
					TrafficZone[name] = {
						id = prop
					}
				end
			end
			if string.match(prop_type,"gang_") then 
				local gang_id = string.match(prop_type,"%d")
				if ZoneInfo[name] or SpecialZoneInfo[name] then
					local prop = string.gsub(data[3], "\r", "")
					TrafficZone[name] = {
						id = prop,
						gang = gang_id,
					}
				end
			end
		end
	end

end


function getPlayerCurrentZoneName(player)
	if not isElement(player) then return nil end
	local x,y = getElementPosition(player)
	for zone,val in pairs(SpecialZoneInfo) do 
		if x >= val.p1[1] and x < val.p2[1] and y >= val.p1[2] and y < val.p2[2] then 
			return zone
		end
	end
	for zone,val in pairs(ZoneInfo) do 
		if x >= val.p1[1] and x < val.p2[1] and y >= val.p1[2] and y < val.p2[2] then 
			return zone
		end
	end
	return nil
end

function getPlayerCurrentCityName(player)
	if not isElement(player) then return nil end
	local x,y = getElementPosition(player)
	for zone,val in pairs(Cities) do 
		if x >= val.p1[1] and x < val.p2[1] and y >= val.p1[2] and y < val.p2[2] then 
			return zone
		end
	end
	return nil
end

function getGangidFromZone(zone) 
	if TrafficZone[zone] and TrafficZone[zone].gang then
		return tonumber(TrafficZone[zone].gang)
	end
	return nil
end
function generateTrafficInZone(zone)

	if TrafficZone[zone] ~= nil then
		local id = TrafficZone[zone].id
		if id ~= nil and PedProps[id] ~= nil then 
			local choice = math.random(0,100)
			local chance = 0
			for type,possbility in pairs(PedProps[id].distribution) do 
				if choice >= chance and choice < chance+possbility and type ~= "POPCYCLE_GROUP_GANGS" then 
					if PedGroup[type] ~= nil then
						--iprint(PedGroup[type])
						return PedGroup[type]
					end
				end
				chance = chance + possbility
			end
		end
	end
	
	return nil

end



local function init() 
	loadZoneInfo()
	loadTrafficZone()
end
addCommandHandler("zone",function(player,cmd) 
	local zone = getPlayerCurrentZoneName(player)
	print(zone)	

	local city = getPlayerCurrentCityName(player)
	print(city)
end )

init()