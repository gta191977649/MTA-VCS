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
                LIGHT:setLightDistFade(light,FADE_DIST,FADE_DIST*0.5)
                LIGHT:attachLightToElement(light,object,0,0,v[7] or 0)
                addEventHandler("onClientObjectBreak", object,function()
                    if LIGHT_OBJS[source] ~= "damaged" then
                        LIGHT:destroyLight(LIGHT_OBJS[source])
                        LIGHT_OBJS[object] = "damaged"
                    end
                end)
                LIGHT_OBJS[object] = light
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
        if getElementType( source ) == "object" and LIGHT_OBJS[source] ~= nil then
            if LIGHT_OBJS[source] == "damaged" then -- recreate damaged light
                local name = getElementID(source)
                applyLightShadowPatch(source,name) 
            end
        end
    end
);

--addEventHandler("onClientResourceStart", resourceRoot,init)