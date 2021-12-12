local srcX,srcY =  guiGetScreenSize()
wetRoadPuddlesTextures = {	"*freew*",
									"*road*",
									"tar_*",
									"hiwaym*",
									"hiwayi*",
									"hiwayo*",
									"hiwaye*",
									"snpedtest*",
									"*junction*",
									"cos_hiwaymid_256",
									"cos_hiwayout_256",
									"gm_lacarpark1",
									"des_1line256",
									"des_1linetar",
									"ws_carpark*",
									"*crossing_law*",
									"*tarmac*",
									"ws_whitestripe",
									"ws_airpt_concrete",
									"ws_yellowline"}

addEventHandler("onClientResourceStart", resourceRoot,
    function()
        reflectiveSrc = dxCreateScreenSource ( srcX,srcY )          -- Create a screen source texture which is 640 x 480 pixels
        src = dxCreateScreenSource ( 640, 480 )       
        mask = dxCreateShader("fx/wetroad_mask.fx") 
        wet_shader = dxCreateShader("fx/wetroad.fx",1,400,false,"world,object" ) 
        -- render target

        r_mask = dxCreateRenderTarget(srcX,srcY)
    	--engineApplyShaderToWorldTexture(mask,"*")
        --engineRemoveShaderFromWorldTexture(mask,"coronastar")
        -- mask
	
        for _,txd in ipairs(wetRoadPuddlesTextures) do 
            engineApplyShaderToWorldTexture(wet_shader,txd)
        end
		
        
    end
)

addEventHandler( "onClientHUDRender", root,
    function()
       
        RTPool.frameStart()
        dxUpdateScreenSource(reflectiveSrc)
        dxSetRenderTarget()
        dxSetShaderValue(wet_shader,"screenSource",reflectiveSrc)
        
      

    end
)

-----------------------------------------------------------------------------------
-- Pool of render targets
-----------------------------------------------------------------------------------
RTPool = {}
RTPool.list = {}

function RTPool.frameStart()
	for rt,info in pairs(RTPool.list) do
		info.bInUse = false
	end
end

function RTPool.GetUnused( mx, my )
	-- Find unused existing
	for rt,info in pairs(RTPool.list) do
		if not info.bInUse and info.mx == mx and info.my == my then
			info.bInUse = true
			return rt
		end
	end
	-- Add new
	local rt = dxCreateRenderTarget( mx, my )
	if rt then
		outputDebugString( "creating new RT " .. tostring(mx) .. " x " .. tostring(mx) )
		RTPool.list[rt] = { bInUse = true, mx = mx, my = my }
	end
	return rt
end
