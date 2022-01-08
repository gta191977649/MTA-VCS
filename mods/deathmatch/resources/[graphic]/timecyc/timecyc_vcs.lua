--[[
    Open Timecyc Parser (Vice City Stories Version)
    (C) Project Sparrow 2021
    By: Nurupo
]]
PS2 = exports.ps2
Weather = {
    id = 0,
    blend = false,
    blendTime = 1, -- 1 hour interval for blend weather
}
WeatherMapping ={ --deal with sa weather special effect
    -- vcs_id, sa_id
    [0] = 1, -- SUNNY
    [1] = 15, -- CLOUDY
    [2] = 8, -- RANING
    [3] = 9, -- FOGGY
    [4] = 17, --EXTRA SUNNY
    [5] = 4, --EXTRA CLOUD
    [6] = 22, --INTERIOR
}
T = {
    ambR = 1, ambG = 2, ambB = 3,
    ambR_obj = 4, ambG_obj = 5, ambB_obj = 6,
    ambR_bl = 7, ambG_bl = 8, ambB_bl = 9,
    ambR_obj_bl = 10, ambG_obj_bl = 11, ambB_obj_bl = 12,
    dirR = 13, dirG = 14, dirB = 15,
    skyTopR = 16, skyTopG = 17, skyTopB = 18,
    skyBotR = 19, skyBotG = 20, skyBotB = 21,
    sunCoreR = 22, sunCoreG = 23, sunCoreB = 24,
    sunCoronaR = 25, sunCoronaG = 26, sunCoronaB = 27,
    sunSz = 28, sprSz = 29, sprBght = 30,
    shad = 31, lightShad = 32, poleShad = 33,
    farClp = 34, fogSt = 35, radiosityIntensity = 36, radiosityLimit = 37, lightGnd = 38,
    cloudR = 39, cloudG = 40, cloudB = 41,
    fluffyTopR = 42, fluffyTopG = 43, fluffyTopB = 44,
    fluffyBotR = 45, fluffyBotG = 46, fluffyBotB = 47,
    blurR = 48, blurG = 49, blurB = 50,
    waterR = 51, waterG = 52, waterB = 53, waterA = 54,
    blurAlpha = 55, blurOffset = 56,
}

Timecyc = {}



local _,lastMin = getTime()
function applyWeatherMapping(vcs_id) 
    vcs_id = WeatherMapping[vcs_id] and vcs_id or 0
    setWeather(WeatherMapping[vcs_id])
end
function start() 
    function updateTimecyc ()
        local hour,min = getTime()
        if min ~= lastMin then --save a bit processing power
            applyWeatherMapping(Weather.id) 
            setWeatherFromTimecyc(Weather.id,hour,min)
        end
    end
    resetWaterColor()
    resetSunColor()
    resetSunSize()
    setColorFilter (0, 0, 0, 0, 0, 0, 0, 0)
    --resetColorFilter()
    updateTimecyc()
    addEventHandler ( "onClientRender", root, updateTimecyc )

end



function loadTimeCycle(filename) 
    local f = fileOpen(filename)
    local lines = fileRead(f,fileGetSize(f))
    lines = split(lines,'\n')
    fileClose(f)
    local weather_id = 0
    for i=1,#lines do 
        if string.find(lines[i],"///////////////////////////////////////////") then -- new line
            weather_id =  weather_id + 1
            Timecyc[weather_id] = {}
        end
        
        
        local data = split(lines[i]:gsub("\r","")," ")

        if #data == 56 then --dataline
            table.insert(Timecyc[weather_id],data)
        end
    end


    start()

end
 
function getTimeIntervalIndex(hour,min)
    --[[
        Time Range: 
            0,5,6,7,12,19,20,22
    ]]
    --[[
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
    ]]
    hour = hour == 0 and 1 or hour
    return hour+1
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
        --length = length + lengthMapping[i]
        length = length + 1
    end
    return length
end

function getInterpolationValue(a,b,hour,min) 
    a = tonumber(a)
    b = tonumber(b)

    --local length = getTimeIntervalLength(hour,min) -- hour as unit

    local length = 1
    local intervalIndex = getTimeIntervalIndex(hour,min)

    local current = min/60 
    local progress = current/length -- get time escapted percentage & normalized to 0-1 range

    if b > a then 
        return a + ((b - a) * progress)
    else
        return a - ((a - b) * progress)
    end
	
end

function getGradientInterpolationValue(startGrident,endGradient,hour,min)
    local s_r,s_g,s_b = unpack(startGrident)
    local e_r,e_g,e_b = unpack(endGradient)
    local r = getInterpolationValue(s_r,e_r,hour,min)
    local g = getInterpolationValue(s_g,e_g,hour,min)
    local b = getInterpolationValue(s_b,e_b,hour,min)
    return {math.floor(r),math.floor(g),math.floor(b)}
end
function setWeatherFromTimecyc(weather_id,hour,min) 
    weather_id = weather_id + 1 -- due to sa weather start from 0
    if not Timecyc[weather_id] then 
        weather_id = 1
    end
    local intervalIndex = getTimeIntervalIndex(hour,min)

    local WT_S = Timecyc[weather_id][intervalIndex]
    local endTntervalIndex = intervalIndex + 1 > #Timecyc[weather_id] and 1 or intervalIndex + 1
    local WT_E = Timecyc[weather_id][endTntervalIndex]
    -- sky gradient
    local skyTopGradient = getGradientInterpolationValue({WT_S[16],WT_S[17],WT_S[18]},{WT_E[16],WT_E[17],WT_E[18]},hour,min) -- SkytopGradient
    local skyBottomGradient = getGradientInterpolationValue({WT_S[19],WT_S[20],WT_S[21]},{WT_E[19],WT_E[20],WT_E[21]},hour,min) -- SkyBottomGradient
    setSkyGradient(skyTopGradient[1],skyTopGradient[2],skyTopGradient[3],skyBottomGradient[1],skyBottomGradient[2],skyBottomGradient[3])
    -- sun 
    --local sunColor = getGradientInterpolationValue({WT_S[T["sunCoreR"]],WT_S[T["sunCoreG"]],WT_S[T["sunCoreB"]]},{WT_E[T["sunCoreR"]],WT_E[T["sunCoreG"]],WT_E[T["sunCoreB"]]},hour,min) 
    --setSunColor(sunColor[1],sunColor[2],sunColor[3])
    --iprint(sunColor)
    local sunSize = getInterpolationValue(WT_S[T["sunSz"]],WT_E[T["sunSz"]],hour,min)
    setSunSize(sunSize )

    -- environmental effect
    setFarClipDistance(getInterpolationValue(WT_S[T["farClp"]],WT_E[T["farClp"]],hour,min))
    setFogDistance(getInterpolationValue(WT_S[T["fogSt"]],WT_E[T["fogSt"]],hour,min))

    -- radiosity
    --print("set radio")
    PS2:setRadiosity(getInterpolationValue(WT_S[T["radiosityIntensity"]],WT_E[T["radiosityIntensity"]],hour,min))

    --local blurRGB = getGradientInterpolationValue({WT_S[T["blurR"]],WT_S[T["blurG"]],WT_S[T["blurB"]]},{WT_E[T["blurR"]],WT_E[T["blurG"]],WT_E[T["blurB"]]},hour,min) 
    --local blurA = getInterpolationValue(WT_S[T["blurAlpha"]],WT_E[T["blurAlpha"]],hour,min)
    --PS2:setRadiosityBlendColor(blurRGB[1],blurRGB[2],blurRGB[3],100)
    -- color filter 48
    setColorFilter (WT_S[1], WT_S[2], WT_S[3],30, WT_S[1], WT_S[2], WT_S[3],30)
    -- total 57
    
    --  water
   
    --local waterColor = getGradientInterpolationValue({WT_S[T["waterR"]],WT_S[T["waterG"]],WT_S[T["waterB"]]},{WT_E[T["waterR"]],WT_E[T["waterG"]],WT_E[T["waterB"]]},hour,min) 
    --local waterAlpha = getInterpolationValue(WT_S[T["waterA"]],WT_E[T["waterA"]],hour,min)
    --setWaterColor(waterColor[1],waterColor[2],waterColor[3],waterAlpha)
    
    --setColorFilter (WT_S[T["blurR"]], WT_S[T["blurG"]], WT_S[T["blurB"]],WT_S[T["blurAlpha"]], WT_S[T["blurR"]], WT_S[T["blurG"]], WT_S[T["blurB"]], WT_S[T["blurAlpha"]])
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

function setTimecycWeather(id) 
    id = tonumber(id)
    if Timecyc[id] then
        Weather.id = id
    else
        Weather.id = 0
        outputChatBox("Invaild Weather ID!")
    end
end
loadTimeCycle("timecyc_vcs.dat")
