FADE_DIST = 100
LIGHT = exports.dl_lightmanager

LIGHT_OBJ_NAMES = {
    ["lampost_coast"] = {"point",255,255,255,255,10},
    ["high_lampost"] = {"point",255,255,255,255,10,-8},
    ["lamppost"] = {"point",255,215,123,255,15},
    ["Streetlamp"] = {"point",255,255,255,255,10},
    ["bollardlight"] = {"point",255,255,255,255,10},
    ["doublestreetlght1"] = {"point",109,201,201,255,15},
}
LIGHT_OBJS = {}
IS_NIGHT = false
local h,m = getTime()
function applyLightShadowPatch(object,modelname) 
    for k,v in pairs(LIGHT_OBJ_NAMES) do
        if string.find(modelname,k) then 
            local x,y,z = getElementPosition(object)
            local light = nil
            if v[1] == "point" then
                light = LIGHT:createPointLight(x,y,z,v[2],v[3],v[4],v[5],v[6],true)
            end
            if v[1] == "spot" then
                light = LIGHT:createSpotLight(x,y,z,v[2],v[3],v[4],v[5],0,0,0,1.5,math.rad(180),math.rad(45),15, false, true)
            end

            if light ~= nil then
                LIGHT:setLightDistFade(light,FADE_DIST,FADE_DIST*0.6)
                --LIGHT:attachLightToElement(light,object,0,0,v[7] or 0)
                LIGHT_OBJS[object] = {
                    light = light,
                    isdamage = false,
                    accu = v[6],
                    color = {v[2],v[3],v[4],v[5]}
                }
                addEventHandler("onClientObjectBreak", object,function()
                    if not LIGHT_OBJS[object].isdamage then
                        --LIGHT:destroyLight(LIGHT_OBJS[source])
                        LIGHT:setLightColor(LIGHT_OBJS[source].light,0,0,0,0)
                        LIGHT_OBJS[object].isdamage = true
                    end
                end)
            end
            
        end
    end
end



function init() 
    for k,v in ipairs(getElementsByType("object")) do
        local name = getElementID(v)
        applyLightShadowPatch(v,name) 
    end
end


addEventHandler( "onClientElementStreamIn", root,
    function ( )
        if not IS_NIGHT then return end -- skip if is day
        if getElementType( source ) == "object" and LIGHT_OBJS[source] ~= nil then
            if LIGHT_OBJS[source].isdamage then -- recreate damaged light
                local r,g,b,a = unpack(LIGHT_OBJS[source].color)
                LIGHT:setLightColor(LIGHT_OBJS[source].light,r,g,b,a)
                LIGHT_OBJS[source].isdamage = false
            end
        end
    end
);



function lightSwitch(toogle) 
    if toogle then 
        for k,v in pairs(LIGHT_OBJS) do 
            local r,g,b,a = unpack(v.color)
            LIGHT:setLightColor(v.light,r,g,b,a)
        end
    else
        for k,v in pairs(LIGHT_OBJS) do 
            --LIGHT:destroyLight(v.light)
            LIGHT:setLightColor(v.light,0,0,0,0)
        end
        
    end
end
-- light timer

addEventHandler("onClientRender",root,function() 
    newh,newm = getTime()
    if m ~= newm then
        h,m = newh,newm
        if h > 7 and h < 21 then -- day
            if IS_NIGHT then 
                lightSwitch(false)
                IS_NIGHT = false

            end
        else
            if not IS_NIGHT then 
                lightSwitch(true)
                IS_NIGHT = true
            end
        end
       
    end
end)
--[[
setTimer(function()
    h,m = getTime()
    if h > 7 and h < 21 then -- day
        if not IS_NIGHT then 

            lightSwitch(false)
            print("turn on light")
            IS_NIGHT = true
        end
    else
        if IS_NIGHT then 
            lightSwitch(true)
            print("turn off light")
            IS_NIGHT = false
        end
    end
end,1000,0)
]]
init()
addCommandHandler("lightoff",function() 
    lightSwitch(false)
end)
addCommandHandler("lighton",function() 
    lightSwitch(true)
end)

--addEventHandler("onClientResourceStart", resourceRoot,init)