FADE_DIST = 100
LIGHT = exports.dl_lightmanager

LIGHT_OBJ_NAMES = {
    ["lampost_coast"] = {"point",255,255,255,180,10},
    ["high_lampost"] = {"point",255,255,255,180,10,-6},
    ["lamppost"] = {"point",255,215,123,180,15},
    ["Streetlamp"] = {"point",255,255,255,180,10},
    ["bollardlight"] = {"point",255,255,255,180,10},
    ["doublestreetlght1"] = {"point",109,201,201,255,15},
}
LIGHT_OBJS = {}
TOTAL = 0
RENDERED = 0
IS_NIGHT = false
local h,m = getTime()
function applyLightShadowPatch(object,modelname) 
    for k,v in pairs(LIGHT_OBJ_NAMES) do
        if string.find(modelname,k) then 
            local x,y,z = getElementPosition(object)
            LIGHT_OBJS[object] = {
                pos = {x,y,z},
                light = nil,
                isdamage = false,
                accu = v[6],
                offset = v[7] or 0,
                color = {v[2],v[3],v[4],v[5]},
            }
            TOTAL = TOTAL + 1
            return
        end
    end
end

function create2dFX(object) 
    if LIGHT_OBJS[object] and LIGHT_OBJS[object].light == nil then
        local x,y,z = unpack(LIGHT_OBJS[object].pos)
        local offset = LIGHT_OBJS[object].offset
        local r,g,b,a = unpack(LIGHT_OBJS[object].color)
        local acc = LIGHT_OBJS[object].accu
        LIGHT_OBJS[object].light = LIGHT:createPointLight(x,y,z+offset,r,g,b,a,acc,false)
        LIGHT:setLightDistFade(LIGHT_OBJS[object].light,FADE_DIST,FADE_DIST*0.6)
        LIGHT_OBJS[object].damage = false
        RENDERED = RENDERED + 1
    end
end
function remove2dFX(object) 
    if LIGHT_OBJS[object] and LIGHT_OBJS[object].light ~= nil then -- recreate damaged light
        LIGHT:destroyLight(LIGHT_OBJS[object].light)
        LIGHT_OBJS[object].light = nil
        RENDERED = RENDERED - 1
    end
end
function forceRender() 
    for k,v in ipairs( getElementsByType ("object",root,true)) do
        if LIGHT_OBJS[v] and LIGHT_OBJS[v].light == nil then 
            create2dFX(v) 
        end
    end
end
function forceDestory() 
    for k,v in ipairs( getElementsByType ("object",root)) do
        if LIGHT_OBJS[v] and LIGHT_OBJS[v].light then 
            remove2dFX(v) 
        end
    end
end

function init() 
    for k,v in ipairs(getElementsByType("object")) do
        local name = getElementID(v)
        applyLightShadowPatch(v,name) 
    end
    -- first render 2dfx
    if IS_NIGHT then forceRender() end
   
    print(TOTAL)
end

addEventHandler("onClientObjectBreak", root,function()
    if LIGHT_OBJS[source] and LIGHT_OBJS[source].light ~= nil then
        remove2dFX(source) 
        LIGHT_OBJS[source].damage = true
    end
end)

addEventHandler( "onClientElementStreamIn", root,
    function ( )
        if not IS_NIGHT then return end
        --if not IS_NIGHT then return end -- skip if is day
        if getElementType(source) == "object" and LIGHT_OBJS[source] then
            if not LIGHT_OBJS[source].light then -- recreate damaged light
                create2dFX(source) 
            end
        end
    end
)

addEventHandler( "onClientElementStreamOut", root,
    function ( )
        if not IS_NIGHT then return end
        if getElementType(source) == "object" and LIGHT_OBJS[source] then
            remove2dFX(source)
        end
    end
)

function lightSwitch(toogle) 
    if toogle then 
        forceRender() 
    else
        forceDestory()
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

addCommandHandler("lightoff",function() 
    lightSwitch(false)
end)
addCommandHandler("lighton",function() 
    lightSwitch(true)
end)

init()



--addEventHandler("onClientResourceStart", resourceRoot,init)