-- 
-- c_common.lua
--
				
---------------------------------------------------------------------------------------------------
-- texture lists
---------------------------------------------------------------------------------------------------
textureListTable = { }

textureListTable.RemoveList = {
						"",	"unnamed", "fire*",                                    -- unnamed
						"basketball2","skybox_tex*",                               -- other
						"font*","radar*","sitem16","snipercrosshair",              -- hud
						"siterocket","cameracrosshair",                            -- hud
						"*shad*",                                                  -- shadows
						"coronastar","coronamoon","coronaringa",
						"coronaheadlightline",                                     -- coronas
						"lunar",                                                   -- moon
						"tx*",                                                     -- grass effect
						"cj_w_grad",                                               -- checkpoint texture
						"*cloud*",                                                 -- clouds
						"*smoke*",                                                 -- smoke
						"sphere_cj",                                               -- nitro heat haze mask
						"water*","newaterfal1_256",
						"boatwake*","splash_up","carsplash_*",
						"fist","*icon","headlight*",
						"unnamed","sphere","plaintarmac*",
						"vehiclegrunge256","?emap*","vehiclegeneric*",
						"gensplash",
						"*wind*","washdecowall2256","cj_w_grad"

					}
					
textureListTable.ApplyList = {
						"ws_tunnelwall2smoked","shadover_law",
						"greenshade_64","greenshade2_64","venshade*", 
						"blueshade2_64","blueshade4_64","greenshade4_64",
						"metpat64shadow","bloodpool_*","plaintarmac1"
					}
					
textureListTable.ApplySpecial = {
						"newaterfal1_256","casinolit2_128","casinolights6lit3_256",
						"casinolights1b_128n", "royaleroof01_64","flmngo11_128",
						"flmngo05_256","flmngo04_256"

					}
					
textureListTable.ZDisable = { -- disable from SHWorld
						"roucghstonebrtb", "shad_exp", "shad_ped","shad_car", "headlight", 
						"headlight1" , "shad_bike", "shad_heli", "shad_rcbaron" , 
						"vehiclescratch64" , "lamp_shad_64", "particleskid","boatsplash",
						"waterwake", "boatwake1", "coronaringa"				
					}

textureListTable.Detail = {				
						"boatsplash", "boatwake*", "coronaringa"
					}
					
textureListTable.ZDisableApply = { -- apply to shader SHWorldNoZWrite
						"roucghstonebrtb", "vehiclescratch64" , "lamp_shad_64", "particleskid",							
					}

textureListTable.TextureGrun = {
						"vehiclegrunge256", "?emap*", "vehicleshatter128", 
						"predator92body128", "monsterb92body256a", "monstera92body256a", "andromeda92wing","fcr90092body128",
						"hotknifebody128b", "hotknifebody128a", "rcbaron92texpage64", "rcgoblin92texpage128", "rcraider92texpage128",
						"rctiger92body128","rhino92texpage256", "petrotr92interior128","artict1logos","rumpo92adverts256","dash92interior128",
						"coach92interior128","combinetexpage128","policemiami86body128", "policemiami868bit128","hotdog92body256",
						"raindance92body128", "cargobob92body256", "andromeda92body", "at400_92_256", "nevada92body256",
						"polmavbody128a" , "sparrow92body128" , "hunterbody8bit256a" , "seasparrow92floats64" ,
						"dodo92body8bit256" , "cropdustbody256", "beagle256", "hydrabody256", "rustler92body256",
						"shamalbody256", "skimmer92body128", "stunt256", "maverick92body128", "leviathnbody8bit256" 
					}	

---------------------------------------------------------------------------------------------------
-- prevent memory leaks
---------------------------------------------------------------------------------------------------
addEventHandler( "onClientResourceStart", resourceRoot, function()
	collectgarbage( "setpause", 100 )
end
)

---------------------------------------------------------------------------------------------------
-- material primitive functions
---------------------------------------------------------------------------------------------------
trianglelist = {}
trianglelist.plane = {
	{ -0.5, 0.5, 0, 0, 1 },{ -0.5, -0.5, 0, 0, 0 },{ 0.5, 0.5, 0, 1, 1 },
	{ 0.5, -0.5, 0, 1, 0 },{ 0.5, 0.5, 0, 1, 1 },{ -0.5, -0.5, 0, 0, 0 }
}

---------------------------------------------------------------------------------------------------
-- manage after effect zBuffer recovery
---------------------------------------------------------------------------------------------------
CPrmFixZ = { }
function CPrmFixZ.create()
	if CPrmFixZ.shader then return true end
	CPrmFixZ.shader = dxCreateShader( "fx/primitive2D_fixZBuffer.fx" )
	if CPrmFixZ.shader then
		dxSetShaderValue( CPrmFixZ.shader, "fViewportSize", guiGetScreenSize() )
		return true
	end
	return false
end

function CPrmFixZ.draw()
	if CPrmFixZ.shader then
		-- draw the outcome
		dxDrawMaterialPrimitive3D( "trianglelist", CPrmFixZ.shader, false, unpack( trianglelist.plane ) )
	end
end

function CPrmFixZ.destroy()
	if CPrmFixZ.shader then
		destroyElement( CPrmFixZ.shader )
		CPrmFixZ.shader = nil
	end
end

---------------------------------------------------------------------------------------------------
-- the interval between this frame and the previous one in milliseconds (delta time).
---------------------------------------------------------------------------------------------------
addEventHandler("onClientPreRender", root, function(msSinceLastFrame)
    lastFrameTickCount = msSinceLastFrame
end
)
