local scx, scy = guiGetScreenSize()
local myScreenSource = dxCreateScreenSource(scx, scy)
local Settings = {
    ["fadeSpeed"] = 0,
    ["streng"] = 5,
    ["maxStreng"] = 5,
    ["speed"] = 0,
    ["intens"] = 0.003,
    ["blur"] = 0.02,
    ["choke"] =0,
    ["maxAlpha"] = 15,
}

function applyEsotropiaH( Src, blur, propX, propY, pSpeed, pChoke, strenght )
	if not Src then return nil end
	local mx,my = dxGetMaterialSize( Src )
	local newRT = RTPool.GetUnused( mx, my )
	if not newRT then return nil end
	dxSetRenderTarget( newRT, true ) 
    local prop = { propX, propY }
	dxSetShaderValue( esotropiaHShader, "TEX0", Src )
	dxSetShaderValue( esotropiaHShader, "TEX0SIZE", mx,my )
	dxSetShaderValue( esotropiaHShader, "pendulumSpeed", pSpeed )
	dxSetShaderValue( esotropiaHShader, "pendulumChoke", pChoke )
	dxSetShaderValue( esotropiaHShader, "Prop", prop )
	dxSetShaderValue( esotropiaHShader, "sBlur", blur )
	dxSetShaderValue( esotropiaHShader, "strenght", strenght )	
	dxDrawImage( 0, 0, mx, my, esotropiaHShader )
	return newRT
end
function applyEsotropiaV( Src, blur, propX, propY, pSpeed, pChoke, strenght )
	if not Src then return nil end
	local mx,my = dxGetMaterialSize( Src )
	local newRT = RTPool.GetUnused( mx, my )
	if not newRT then return nil end
	dxSetRenderTarget( newRT, true ) 
    local prop = { propX, propY }
	dxSetShaderValue( esotropiaVShader, "TEX0", Src )
	dxSetShaderValue( esotropiaVShader, "TEX0SIZE", mx,my )
	dxSetShaderValue( esotropiaVShader, "pendulumSpeed", pSpeed )
	dxSetShaderValue( esotropiaVShader, "pendulumChoke", pChoke )
	dxSetShaderValue( esotropiaVShader, "Prop", prop )
	dxSetShaderValue( esotropiaVShader, "sBlur", blur )
	dxSetShaderValue( esotropiaVShader, "strenght", strenght )	
	dxDrawImage( 0, 0, mx,my, esotropiaVShader )
	return newRT
end

function processTrail()
    local v = Settings.var	
    -- Reset render target pool
    RTPool.frameStart()			
    -- Update screen
    dxUpdateScreenSource( myScreenSource, true )

    -- Start with screen
    local current = myScreenSource

    current = applyEsotropiaH( current, Settings.maxStreng * Settings.blur, 0, Settings.intens / 100, Settings.speed, Settings.choke, Settings.streng ) 
    current = applyEsotropiaV( current, Settings.maxStreng * Settings.blur, Settings.intens, 0, Settings.speed, Settings.choke, Settings.streng ) 

    -- When we're done, turn the render target back to default
    dxSetRenderTarget()

    local scrAlpha = math.max( Settings.streng, Settings.streng, Settings.streng, Settings.streng ) * 255
    local col = tocolor( 255, 255, 255, scrAlpha * Settings.maxAlpha/255 )
    if current and scrAlpha > 0 then
        dxDrawImage( 0, 0, scx, scy, current, 0, 0, 0, col )
    end
end
function enableTrail()
    if isElement(esotropiaHShader) then 
        destroyElement(esotropiaHShader)
    end
    if isElement(esotropiaVShader) then 
        destroyElement(esotropiaVShader)
    end
    esotropiaHShader = dxCreateShader( "fx/esotropiaH.fx" )
    esotropiaVShader = dxCreateShader( "fx/esotropiaV.fx" )
    addEventHandler( "onClientHUDRender", root,processTrail)
    print("PS2 Trail Enabled")
end
function disableTrail()
    if isElement(esotropiaHShader) then
        destroyElement(esotropiaHShader)
        destroyElement(esotropiaVShader)
    end
    removeEventHandler( "onClientHUDRender", root,processTrail)
    print("PS2 Trail Disabled")

end

--setColorFilter(0.000 ,2.124, 0.000, -0.007,0.000, 0.000 ,2.124, -0.007)
