local isStarted = false
-- event
function SKYGFX.onClientElementStreamIn()
    if SKYGFX.vehicleClassicFx then
        if getElementType( source ) == "vehicle" and not renderCache[source] then
            initVehicleRenderCache(source) 
        end
    end
end
function SKYGFX.onClientElementStreamOut()
    if SKYGFX.vehicleClassicFx then
        if renderCache[source]  then
            destoryAllVehicleClassicLights(source)
            renderCache[source] = nil
        end
    end
end
function SKYGFX.onClientRender() 
    doBuildingSimplePS()
    doVehiclePipeline()
    if SKYGFX.fixRotor then
        renderRotorEffect()
    end
    if SKYGFX.disableZTest then
        doSunFX() 
    end
    if SKYGFX.vehicleClassicFx then
        doClassicFX() 
    end
    if SKYGFX.trashOnGround then
        --doTrashOnGround()
    end
end
function SKYGFX.onClientPreRender() 
    if SKYGFX.vehicleClassicFx then
        doClassicFXPreRender() 
    end
end
function SKYGFX.onClientHUDRender() 
    renderPostFX() 
end
function SKYGFX.onClientElementDestroy()
    if SKYGFX.vehicleClassicFx then
        destoryAllVehicleClassicLights(source)
    end
end

function addEventHandlerEx(sEventName, pElementAttachedTo, func,pro,priority) 
    if not isEventHandlerAdded( sEventName, pElementAttachedTo, func ) then 
        addEventHandler( sEventName, pElementAttachedTo, func,pro,priority )
    end
end
function removeEventHandlerEx(sEventName, pElementAttachedTo, func ) 
    if isEventHandlerAdded( sEventName, pElementAttachedTo, func ) then 
        removeEventHandler( sEventName, pElementAttachedTo, func )
    end
end


function SKYGFX.start() 
    if isStarted then return end
    if SKYGFX.profile == "VCS" then
        VCSGraphics.start()
        isStarted = true
        return
    end
    if not VCSWeather.reloaded then
        resetColorFilter()
        resetSunColor()
        resetSkyGradient()
        resetSunSize()
    end
    -- loadtxdDB
    loadtxdDB()
    -- start skygfx
    initBuildingSimplePSPipeline()
    initVehiclePiple()
    initPostFx()
    initWorldMiscFx()
    
    if SKYGFX.fixRotor then 
        enableRotorPs2Fix()
    end
    --noZTest() -- no needed now
    -- add events
    addEventHandlerEx("onClientElementStreamIn", root,SKYGFX.onClientElementStreamIn)
    addEventHandlerEx("onClientElementStreamOut", root,SKYGFX.onClientElementStreamOut)
    addEventHandlerEx("onClientRender", root,SKYGFX.onClientRender,false,"low")
    addEventHandlerEx("onClientPreRender", root,SKYGFX.onClientPreRender,false,"low")
    addEventHandlerEx("onClientHUDRender", root,SKYGFX.onClientHUDRender,false,"low")
    addEventHandlerEx("onClientElementDestroy", root,SKYGFX.onClientElementDestroy)
    isStarted = true
end

function SKYGFX.stop(reloading)
    if not isStarted then return end
    if SKYGFX.profile == "VCS" then
        VCSGraphics.stop(reloading)
        isStarted = false
        return
    end
    if not reloading then
        resetColorFilter()
        resetSunColor()
        resetSkyGradient()
        resetSunSize()
    end
    if SKYGFX.fixRotor then 
        disableRotorPs2Fix()
    end
    -- remove events
    removeEventHandlerEx("onClientElementStreamIn", root,SKYGFX.onClientElementStreamIn)
    removeEventHandlerEx("onClientElementStreamOut", root,SKYGFX.onClientElementStreamOut)
    removeEventHandlerEx("onClientRender", root,SKYGFX.onClientRender)
    removeEventHandlerEx("onClientPreRender", root,SKYGFX.onClientPreRender)
    removeEventHandlerEx("onClientHUDRender", root,SKYGFX.onClientHUDRender)
    removeEventHandlerEx("onClientElementDestroy", root,SKYGFX.onClientElementDestroy)
    isStarted = false
end


addEventHandler( "onClientResourceStart",resourceRoot,function ( startedRes )
    VCSWeather.start()
    if SKYGFX.autoStart then 
        SKYGFX.start() 
    end
    VCSWeather.reloaded = nil
    
end)

addEventHandler( "onClientResourceStop",resourceRoot,
    function (  )
        local reloading = getElementData(root, "leeds_engine:reloading", false)
        SKYGFX.stop(reloading)
        VCSWeather.stop(reloading)
    end
)

