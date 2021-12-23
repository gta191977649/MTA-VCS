local water_shader = dxCreateShader( "fx/water_vc.fx")
local water = dxCreateTexture( "images/waterclear256.png")
dxSetShaderValue (water_shader, "Tex0", water)
engineApplyShaderToWorldTexture(water_shader, "waterclear256")

local water_wake = dxCreateShader( "fx/water_vc.fx")
local wake = dxCreateTexture( "images/waterwake.png")
dxSetShaderValue (water_wake, "Tex0", wake)
engineApplyShaderToWorldTexture(water_wake, "waterwake")
