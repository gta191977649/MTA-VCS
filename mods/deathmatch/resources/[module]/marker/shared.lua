-- World-marker presentation is owned by frontend; this resource owns elements and API state.
local nativeCreateMarker = createMarker
local nativeSetMarkerType = setMarkerType
MarkerRecords = {}
MarkerStyles = {
    arrow = {native=1, collision="arrow", period=1024, pulse=0.2, rotation=250},
    arrow2 = {native=2, collision="arrow", period=1024, pulse=0.2, rotation=250},
    pointer = {native=3, collision="arrow", period=1, pulse=1, rotation=50},
    cylinder = {native=6, collision="cylinder", period=2048, pulse=0.1, rotation=50, double=true},
    checkpoint = {native=6, collision="checkpoint", period=128, pulse=0, rotation=0, height=100},
    cylinder2 = {native=7, collision="cylinder", period=1024, pulse=0.1, rotation=0},
    ring = {native=8, collision="ring", period=1, pulse=0, rotation=50},
    corona = {native=0, collision="corona", period=1, pulse=0, rotation=0},
}
local typeOrder = {"checkpoint", "ring", "cylinder", "arrow", "corona", "arrow2", "pointer", "cylinder2"}
local nativeNames = {[1]="arrow", [2]="arrow2", [3]="pointer", [6]="cylinder", [7]="cylinder2", [8]="ring"}

function MarkerFinite(n)
    return type(n)=="number" and n==n and n>-math.huge and n<math.huge
end

local function normalizeType(style)
    return nativeNames[style] or style
end

function getMarkerTypes()
    local result = {}
    for i, name in ipairs(typeOrder) do result[i]=name end
    return result
end

local function colors(r,g,b,a)
    local result = {r,g,b,a}
    for i=1,4 do
        local n=result[i]
        if not MarkerFinite(n) or n<0 or n>255 or n%1~=0 then return false end
    end
    return result
end

function MarkerCreate(x,y,z,style,size,r,g,b,a,visibleTo,ignoreAlphaLimits)
    if style==nil then style="checkpoint" end
    style=normalizeType(style)
    if size==nil then size=4 end
    if r==nil then r=237 end
    if g==nil then g=130 end
    if b==nil then b=180 end
    if a==nil then a=228 end
    local color=colors(r,g,b,a)
    if not MarkerFinite(x) or not MarkerFinite(y) or not MarkerFinite(z)
        or not MarkerFinite(size) or size<=0 or not MarkerStyles[style] or not color
        or (ignoreAlphaLimits~=nil and type(ignoreAlphaLimits)~="boolean") then return false end
    local element
    if localPlayer then
        element=nativeCreateMarker(x,y,z,MarkerStyles[style].collision,size,0,0,0,0,true)
    else
        visibleTo=visibleTo or root
        if not isElement(visibleTo) then return false end
        element=nativeCreateMarker(x,y,z,MarkerStyles[style].collision,size,0,0,0,0,visibleTo,true)
    end
    if not element then return false end
    local owner=sourceResource or getThisResource()
    local dynamicRoot=getResourceDynamicElementRoot(owner)
    if dynamicRoot then setElementParent(element,dynamicRoot) end
    MarkerRecords[element]={style=style,color=color,animation={},owner=owner,
        visibility=not localPlayer and {[root]=visibleTo==root,[visibleTo]=true} or nil}
    MarkerChanged(element)
    return element
end

function getMarkerType(element)
    return MarkerRecords[element] and MarkerRecords[element].style or false
end

function setMarkerType(element,style)
    local state=MarkerRecords[element]
    style=normalizeType(style)
    if not state or not MarkerStyles[style] then return false end
    if not nativeSetMarkerType(element,MarkerStyles[style].collision) then return false end
    -- Type changes can restore native arrow/checkpoint alpha limits.
    setMarkerColor(element,unpack(state.color))
    state.style=style
    MarkerChanged(element)
    return true
end

function getMarkerColor(element)
    local state=MarkerRecords[element]
    if not state then return false end
    return unpack(state.color)
end

function setMarkerColor(element,r,g,b,a)
    local state=MarkerRecords[element]
    local color=colors(r,g,b,a)
    if not state or not color then return false end
    state.color=color
    MarkerHideNative(element)
    MarkerChanged(element)
    return true
end

function setMarkerTarget(element,x,y,z)
    local state=MarkerRecords[element]
    if not state then return false end
    if x==false or x==nil then state.target=nil
    elseif MarkerFinite(x) and MarkerFinite(y) and MarkerFinite(z) then state.target={x,y,z}
    else return false end
    MarkerChanged(element)
    return true
end

function setMarkerAnimation(element,options)
    local state=MarkerRecords[element]
    if not state or type(options)~="table" then return false end
    local animation={}
    for key,value in pairs(options) do
        if key=="period" then
            if not MarkerFinite(value) or value<1 or value>32768 or value%1~=0
                or bitAnd(value,value-1)~=0 then return false end
        elseif key=="pulse" then
            if not MarkerFinite(value) or value<0 or value>1 then return false end
        elseif key=="rotation" then
            if not MarkerFinite(value) or math.abs(value)>3600 then return false end
        elseif key=="height" then
            if not MarkerFinite(value) or value<=0 or value>1000 then return false end
        else return false end
        animation[key]=value
    end
    state.animation=animation
    MarkerChanged(element)
    return true
end

function setMarkerBlipVisible(element,visible)
    local state=MarkerRecords[element]
    if not state or type(visible)~="boolean" then return false end
    state.blipVisible=visible
    MarkerChanged(element)
    return true
end

function isMarkerBlipVisible(element)
    local state=MarkerRecords[element]
    return state and state.blipVisible==true or false
end

function getMarkerBlip(element)
    local state=MarkerRecords[element]
    return state and isElement(state.blip) and state.blip or false
end

function MarkerSyncBlip(element)
    local state=MarkerRecords[element]
    if not state or not isElement(state.blip) then return end
    if localPlayer and not isElementLocal(state.blip) then return end
    setElementDimension(state.blip,getElementDimension(element))
    setElementInterior(state.blip,getElementInterior(element))
end

for _,event in ipairs(localPlayer and {"onClientElementDimensionChange","onClientElementInteriorChange"}
    or {"onElementDimensionChange","onElementInteriorChange"}) do
    addEventHandler(event,root,function() MarkerSyncBlip(source) end)
end

addEventHandler(localPlayer and "onClientElementDestroy" or "onElementDestroy",root,function()
    MarkerRecords[source]=nil
end)
