DGS = exports.dgs
FADE_DIST = 100
DEBUG = false
LIGHT = exports.dl_lightmanager

LIGHT_OBJ_NAMES = {
    ["lampost_coast"] = {"point",255,255,255,180,10},
    ["high_lampost"] = {"point",255,255,255,180,10,-6},
    ["lamppost"] = {"point",255,215,123,180,15},
    ["Streetlamp"] = {"point",255,255,255,180,10},
    ["bollardlight"] = {"point",255,255,255,180,5},
    ["doublestreetlght1"] = {"point",109,201,201,255,15},
}
LIGHT_TRAFFIC_NAMES = {
    ["MTraffic1"] = {}
}
LIGHT_OBJS = {}
TRAFFIC_OBJS = {}
TRAFFIC_LIGHT_COLORS = {
    ["YELLOW"] = {255,234,0,30},
    ["RED"] = {255,0,0,30},
    ["GREEN"] = {0,255,0,30},
}
TRAFFIC_LIGHT_COLOR_MAPPING = {
    ["NS"] = {
        [0] = TRAFFIC_LIGHT_COLORS["GREEN"],
        [5] = TRAFFIC_LIGHT_COLORS["GREEN"],
        [8] = TRAFFIC_LIGHT_COLORS["GREEN"],
        [2] = TRAFFIC_LIGHT_COLORS["RED"],
        [3] = TRAFFIC_LIGHT_COLORS["RED"],
        [4] = TRAFFIC_LIGHT_COLORS["RED"],
        [1] = TRAFFIC_LIGHT_COLORS["YELLOW"],
        [6] = TRAFFIC_LIGHT_COLORS["YELLOW"],
        [7] = TRAFFIC_LIGHT_COLORS["YELLOW"],
    },
    ["WE"] = {
        [3] = TRAFFIC_LIGHT_COLORS["GREEN"],
        [5] = TRAFFIC_LIGHT_COLORS["GREEN"],
        [7] = TRAFFIC_LIGHT_COLORS["GREEN"],
        [0] = TRAFFIC_LIGHT_COLORS["RED"],
        [1] = TRAFFIC_LIGHT_COLORS["RED"],
        [2] = TRAFFIC_LIGHT_COLORS["RED"],
        [4] = TRAFFIC_LIGHT_COLORS["YELLOW"],
        [6] = TRAFFIC_LIGHT_COLORS["YELLOW"],
        [8] = TRAFFIC_LIGHT_COLORS["YELLOW"],
    },
}


TOTAL = 0
RENDERED = 0
IS_NIGHT = false
local h,m = getTime()
local traffic_status = getTrafficLightState()

function getTrafficLightDirection(rotation) 
    local angleMapping = {
        ["NS"] = {
            {0,45},
            {135,180},
            {180,225},
            {315,360},
        }
    }
    for _,bounds in ipairs(angleMapping["NS"]) do 
        if rotation >= bounds[1] and rotation <= bounds[2] then 
            return "NS"
        end
    end
    return "WE"
end

function applyTrafficLightPatch(object,modelname) 
    for k,v in pairs(LIGHT_TRAFFIC_NAMES) do
        if string.find(modelname,k) then 
            local x,y,z = getElementPosition(object)
            local _,_,rz = getElementRotation(object)
            LIGHT_OBJS[object] = {
                type = "Traffic",
                pos = {x,y,z},
                rot = getTrafficLightDirection(rz),
                light = nil,
                isdamage = false,
                color = {255,234,0,30},
            }
            if DEBUG then 
                local r,g,b,a = unpack(TRAFFIC_LIGHT_COLOR_MAPPING[LIGHT_OBJS[object].rot][traffic_status])
                LIGHT_OBJS[object].label = DGS:dgsCreate3DText(x,y,z,getTrafficLightDirection(rz) ,tocolor(r,g,b,a))
                attachElements(LIGHT_OBJS[object].label,object)
            end
            
            TOTAL = TOTAL + 1
            return
        end
    end
end
function applyLightShadowPatch(object,modelname) 
    for k,v in pairs(LIGHT_OBJ_NAMES) do
        if string.find(modelname,k) then 
            local x,y,z = getElementPosition(object)
            LIGHT_OBJS[object] = {
                type = "Street",
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
    if LIGHT_OBJS[object].light then return end
    if LIGHT_OBJS[object] then
        if LIGHT_OBJS[object].type == "Street" then -- street
            local x,y,z = unpack(LIGHT_OBJS[object].pos)
            local offset = LIGHT_OBJS[object].offset
            local r,g,b,a = unpack(LIGHT_OBJS[object].color)
            local acc = LIGHT_OBJS[object].accu
            LIGHT_OBJS[object].light = LIGHT:createPointLight(x,y,z+offset,r,g,b,a,acc,false)
            LIGHT:setLightDistFade(LIGHT_OBJS[object].light,FADE_DIST,FADE_DIST*0.6)
            LIGHT_OBJS[object].damage = false
            RENDERED = RENDERED + 1
        end
        if LIGHT_OBJS[object].type == "Traffic" then -- traffic light
            local x,y,z = unpack(LIGHT_OBJS[object].pos)
            local heading = LIGHT_OBJS[object].rot
            local r,g,b,a = unpack(LIGHT_OBJS[object].color)

            LIGHT_OBJS[object].light = LIGHT:createPointLight(x,y,z,r,g,b,a,10,false)
            LIGHT:setLightDistFade(LIGHT_OBJS[object].light,FADE_DIST,FADE_DIST*0.6)
            LIGHT_OBJS[object].damage = false
            RENDERED = RENDERED + 1
        end
    end
end
function remove2dFX(object) 
    if LIGHT_OBJS[object] and LIGHT_OBJS[object].light then -- recreate damaged light
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
function updateTrafficLights(status) 
    local objects = getElementsByType("object",root,true) 
    for k,v in ipairs(objects) do 
        if LIGHT_OBJS[v] and LIGHT_OBJS[v].type == "Traffic" and LIGHT_OBJS[v].light then 
            local r,g,b,a = unpack(TRAFFIC_LIGHT_COLOR_MAPPING[LIGHT_OBJS[v].rot][status])
            LIGHT:setLightColor(LIGHT_OBJS[v].light,r,g,b,a)
            if DEBUG then 
                DGS:dgsSetProperty(LIGHT_OBJS[v].label,"color",tocolor(r,g,b,a))
            end
        end
    end
end 
function init() 
    for k,v in ipairs(getElementsByType("object")) do
        local name = getElementID(v)
        applyLightShadowPatch(v,name) 
        applyTrafficLightPatch(v,name) 
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
            if LIGHT_OBJS[source].light then return end
            create2dFX(source) 
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
        -- light toogle
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

    -- traffic light direction 
    local new_status = getTrafficLightState()
    if traffic_status ~= new_status then
        print(new_status)
        updateTrafficLights(new_status)
        traffic_status = new_status           
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