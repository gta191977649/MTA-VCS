loadstring(exports.dgs:dgsImportFunction())()
FONT = exports.font
STATIONS = {
	{
		name = "Flash Fm",
		file = "audio/flash.mp3",
	},
	{
		name = "VRock",
		file = "audio/vrock.mp3",
	},
	{
		name = "Paradise",
		file = "audio/paradise.mp3",
	},
	{
		name = "VCPR",
		file = "audio/vcpr.mp3",
	},
	{
		name = "VCFL Radio",
		file = "audio/vcfl.mp3",
	},
	{
		name = "The Wave 103",
		file = "audio/wave.mp3",
	},
	{
		name = "Fresh 105 Fm",
		file = "audio/fresh.mp3",
	},
	{
		name = "Espantoso",
		file = "audio/espant.mp3",
	},
	{
		name = "Emotion 98.3",
		file = "audio/emotion.mp3",
	},
	{
		name = "Smooth 95.3",
		file = "https://23153.live.streamtheworld.com/SMOOTH953_AAC48.aac",
		type = "ONLINE",
	}
}
Player = {
	select = 1,
	sound = nil,
	switchTimer = nil,
	uiTextTimer = nil,
	color = {
		["SWITCHING"] = tocolor(146,146,146,255),
		["SELECTED"] = tocolor(74,153,205,255),
	}
}
RADIO_PLAYING = false

-- UI
label = dgsCreateLabel(0,0,1, 0.18, "text", true)
dgsSetFont(label,FONT:getDxFont("RADIO"))
dgsSetProperty(label,"alignment",{"center","center"})
dgsSetProperty(label,"shadow",{2,2,tocolor(0,0,0,255),3})
dgsSetProperty(label,"textColor",Player.color["SWITCHING"])
dgsSetVisible(label,false)
function playRadio(station_id)
	if station_id == 0 then 
		return dgsSetProperty(label,"text","Radio Off")
	end
	if isElement(Player.sound) then 
		destroyElement(Player.sound)
	end
	Player.sound = playSound(STATIONS[station_id].file,true)
	setSoundVolume(Player.sound,0.7)
	if not STATIONS[station_id].type then
		playRadioInTimeCycle(Player.sound)
	end
	RADIO_PLAYING = true

end
function stopRadio() 
	if isElement(Player.sound) then 
		destroyElement(Player.sound)
	end
	RADIO_PLAYING = false
end
function turnToRadio(station_id) 
	Player.select = station_id
	local veh = getPedOccupiedVehicle(localPlayer)
	if veh then 
		setElementData(veh,"radio_station",Player.select,false)
	end
	
	local station_name = Player.select == 0 and "Radio Off" or STATIONS[Player.select].name
	dgsSetProperty(label,"textColor",Player.color["SWITCHING"])
	dgsSetProperty(label,"text",station_name)
	dgsSetVisible(label,true)
	if Player.select ~= 0 then
		playSoundFrontEnd(34)
		Player.switchTimer = setTimer(function() 
			playSoundFrontEnd(35)
			playRadio(Player.select)
			-- update ui
			dgsSetProperty(label,"textColor",Player.color["SELECTED"])
			Player.uiTextTimer = setTimer(dgsSetVisible,2000,1,label,false)

		end,1000,1)

	end
end
function playRadioInTimeCycle(sound) 
	local time = getRealTime()
	seconds = time["second"] + (time["minute"] * 60) + (time["hour"] * 3600)
	local length = getSoundLength(sound)
	setSoundPosition(sound,math.ceil(seconds % length))
end

function init() 
	-- disable SA default radio
	showPlayerHudComponent( "radio", false ) 
	setRadioChannel(0) 
	addEventHandler('onClientPlayerRadioSwitch',root, function() 
		cancelEvent() 
		local key_up = getKeyState ("mouse_wheel_up")
		local key_down = getKeyState ("mouse_wheel_down")
		-- stop audio
		if isElement(Player.sound) then 
			destroyElement(Player.sound)
		end
		if isTimer(Player.switchTimer) then
			killTimer(Player.switchTimer)
		end
		if isTimer(Player.uiTextTimer) then
			killTimer(Player.uiTextTimer)
		end
		local station_id = 1
		if key_down or key_up then 
			playSoundFrontEnd(35)
			if key_down then
				station_id = Player.select + 1 > #STATIONS and 0 or Player.select + 1
			else
				station_id = Player.select - 1 >= 0 and Player.select - 1 or #STATIONS
			end
			turnToRadio(station_id) 
		end
	end) 

end

init()