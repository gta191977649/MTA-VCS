--[[
    Open Timecyc Parser
    (C) Project Sparrow 2021
    By: Nurupo
]]
Weather = {
    id = 0,
    blend = false,
    blendTime = 1, -- 1 hour interval for blend weather
}
Timecyc = {}
function loadTimeCycle(filename) 
    local f = fileOpen(filename)
    local lines = fileRead(f,fileGetSize(f))
    lines = split(lines,'\n')
    fileClose(f)
    local weather_id = 0
    for i=1,#lines do 
        if string.find(lines[i],"////////////") then -- new line
            weather_id =  weather_id + 1
            Timecyc[weather_id] = {}
        end
        if string.find(lines[i],"^[0-9]+") then -- if is data lines
            local data = split(lines[i],"\t")
            table.insert(Timecyc[weather_id],data)
        end
    end
end
 
function getTimeIntervalIndex(hour,min)
    --[[
        Time Range: 
            0,5,6,7,12,19,20,22
    ]]
    if hour >= 0 and hour < 5 and min >= 0 and min <= 59 then -- from 0 -> 4:59
        return 1
    elseif hour >= 5 and hour < 6 and min >= 0 and min <= 59 then -- from 5 -> 5:59
        return 2
    elseif hour >= 6 and hour < 7 and min >= 0 and min <= 59 then -- from 6 -> 6:59
        return 3
    elseif hour >= 7 and hour < 12 and min >= 0 and min <= 59 then -- from 7 -> 11:59
        return 4
    elseif hour >= 12 and hour < 19 and min >= 0 and min <= 59 then -- from 12 -> 18:59
        return 5
    elseif hour >= 19 and hour < 20 and min >= 0 and min <= 59 then -- from 19 -> 19:59
        return 6
    elseif hour >= 20 and hour < 22 and min >= 0 and min <= 59 then -- from 20 -> 21:59
        return 7
    elseif hour >= 22 then -- from 22 -> 23:59
        return 8
    end
end
function getTimeIntervalLength(hour,min)
    --[[
        Time Range: 
            0,5,6,7,12,19,20,22
    ]]
    if hour >= 0 and hour < 5 and min >= 0 and min <= 59 then -- from 0 -> 4:59
        return 5
    elseif hour >= 5 and hour < 6 and min >= 0 and min <= 59 then -- from 5 -> 5:59
        return 1
    elseif hour >= 6 and hour < 7 and min >= 0 and min <= 59 then -- from 6 -> 6:59
        return 1
    elseif hour >= 7 and hour < 12 and min >= 0 and min <= 59 then -- from 7 -> 11:59
        return 5
    elseif hour >= 12 and hour < 19 and min >= 0 and min <= 59 then -- from 12 -> 18:59
        return 7
    elseif hour >= 19 and hour < 20 and min >= 0 and min <= 59 then -- from 19 -> 19:59
        return 1
    elseif hour >= 20 and hour < 22 and min >= 0 and min <= 59 then -- from 20 -> 21:59
        return 2
    elseif hour >= 22 then -- from 22 -> 23:59
        return 2
    end
end
function getTimeIntervalLengthFromIndex(index)
    --[[
        Time Range: 
            0,5,6,7,12,19,20,22
    ]]
    local lengthMapping = {
        5,1,1,5,7,1,2,2
    }
    local length = 0
    for i = 1,index-1 do 
        length = length + lengthMapping[i]
    end
    return length
end

function getInterpolationValue(a,b,hour,min) 
    a = tonumber(a)
    b = tonumber(b)
    local length = getTimeIntervalLength(hour,min) -- hour as unit
    local intervalIndex = getTimeIntervalIndex(hour,min)
    local current = (hour-getTimeIntervalLengthFromIndex(intervalIndex)) + min/60 
    local progress = current/length -- get time escapted percentage & normalized to 0-1 range
   
    local result = a * (1-progress) + b * progress
	if result >= b then
		result = b
	elseif result <= a then
		result = a
	end
	return result
end
function getGradientInterpolationValue(startGrident,endGradient,hour,min)
    local s_r,s_g,s_b = unpack(startGrident)
    local e_r,e_g,e_b = unpack(endGradient)
    local r = getInterpolationValue(s_r,e_r,hour,min)
    local g = getInterpolationValue(s_g,e_g,hour,min)
    local b = getInterpolationValue(s_b,e_b,hour,min)
    return {r,g,b}
end
function setWeatherFromTimecyc(weather_id,hour,min) 
    weather_id = weather_id + 1 -- due to sa weather start from 0
    local intervalIndex = getTimeIntervalIndex(hour,min)
    local WT_S = Timecyc[weather_id][intervalIndex]
    local endTntervalIndex = intervalIndex + 1 > #Timecyc[weather_id] and 1 or intervalIndex + 1
    local WT_E = Timecyc[weather_id][endTntervalIndex]

    -- sky gradient
    local skyTopGradient = getGradientInterpolationValue({WT_S[10],WT_S[11],WT_S[12]},{WT_E[10],WT_E[11],WT_E[12]},hour,min) -- SkytopGradient
    local skyBottomGradient = getGradientInterpolationValue({WT_S[13],WT_S[14],WT_S[15]},{WT_E[13],WT_E[14],WT_E[15]},hour,min) -- SkyBottomGradient
    setSkyGradient(skyTopGradient[1],skyTopGradient[2],skyTopGradient[3],skyBottomGradient[1],skyBottomGradient[2],skyBottomGradient[3])
    -- sun 
    local sunColor = getGradientInterpolationValue({WT_S[16],WT_S[17],WT_S[18]},{WT_E[19],WT_E[20],WT_E[21]},hour,min) 
    setSunColor(sunColor[1],sunColor[2],sunColor[3])
    --local sunSize = getInterpolationValue(WT_S[22],WT_E[22],hour,min)
    --setSunSize(sunSize)
    --  water
    local waterColor = getGradientInterpolationValue({WT_S[37],WT_S[38],WT_S[39]},{WT_E[37],WT_E[38],WT_E[39]},hour,min) 
    local waterAlpha = getInterpolationValue(WT_S[40],WT_E[40],hour,min)
    setWaterColor(waterColor[1],waterColor[2],waterColor[3],waterAlpha)
    -- environmental effect
    setFarClipDistance(getInterpolationValue(WT_S[28],WT_E[28],hour,min))
    setFogDistance(getInterpolationValue(WT_S[29],WT_E[29],hour,min))
end
--[[
function setWeatherFromTimecyc(weather_id,hour,min) 
    local WT = Timecyc[weather_id][time]
    setSkyGradient(WT[10],WT[11],WT[12],WT[13],WT[14],WT[15])
    setSunColor(WT[16],WT[17],WT[18],WT[19],WT[20],WT[21])
    setSunSize(WT[22])
    setWaterColor(WT[37],WT[38],WT[39],WT[40])
    setFarClipDistance(WT[28])
    setFogDistance(WT[29])
end
]]

function setBlendWeatherFromTimecyc(weather_id) 
    local from = Weather.blendData.from_weather
    local to = Weather.blendData.to_weather
    
end
function blendWeatherFromTimecyc(weather_id) 
    local fromWeatherId = Weather.id
    local toWeatherId = weather_id

end
loadTimeCycle("timecyc_ps2.dat")

function updateTimecyc ()
    local hour,min = getTime()
    local weatherid = getWeather()
	setWeatherFromTimecyc(weatherid,hour,min)
end
addEventHandler ( "onClientPreRender", root, updateTimecyc )
