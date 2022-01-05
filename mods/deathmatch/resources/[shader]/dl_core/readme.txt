Resource: dl_core v0.1.7
Author: Ren712
Contact: knoblauch700@o2.pl

Description:
This resource provides render targets for deferred lighting resources
and some exported functions for it's management.
The purpose of this resource is to give an efficient alternative to
dynamic lighting resource and introduce deferred rendering
approach. It's much more efficient and customizable dr_rendertarget.
Light (or any other effect) is produced after world is rendered
based on information (scene depth, world normals, texture color) generated before. 

Exported functions:
RTColor, RTNormal = getRenderTargets()
passGTASAObjectNormals(true) -- should existing normals (dff) be passed to RTNormal
applyEmissiveEffectToWorld(texName, [object])
applyEmissiveTextureToWorld(texName, texture,[object]) 
setEmissivePostEffectEnabled(bool)-- draw the outcome on screen
setEmissiveTextureBlurIntensity(shaderElement 0-1)
setEmissiveTextureBrightnessAdd(shaderElement 0-1)
applyNormalTextureToPed(texName,normalTex,[bumpHeight, pedElement])
applyNormalTextureToWorld(texName,normalTex,[bumpHeight, object])
setNormalStrength(shaderElement, normalStrength)
applyTextureReplaceToWorld(texName,colorTex,[object])
applyTextureReplaceToPed(texName,colorTex,[pedElement])
applyTextureReplaceToVehicle(texName,colorTex,[vehicleElement])

Core resource for deferred lighting:
dl_core: https://community.mtasa.com/index.php?p=resources&s=details&id=18510

dl_core is required for:
dl_lightmanager: https://community.mtasa.com/index.php?p=resources&s=details&id=18512
dl_flashlight: https://community.mtasa.com/index.php?p=resources&s=details&id=18514
dl_vehicles: https://community.mtasa.com/index.php?p=resources&s=details&id=18513
dl_blendshad: https://community.mtasa.com/?p=resources&s=details&id=18547
dl_projectiles: https://community.mtasa.com/?p=resources&s=details&id=18548
dl_normalgen: https://community.mtasa.com/?p=resources&s=details&id=18555
dl_image3dlight: https://community.mtasa.com/?p=resources&s=details&id=18553
dl_material3dlight: https://community.mtasa.com/?p=resources&s=details&id=18554
dl_primitive3dlight: https://community.mtasa.com/?p=resources&s=details&id=18550

used by but not required:
dl_shader_detail: https://community.mtasa.com/?p=resources&s=details&id=18549
dl_carpaint: https://community.mtasa.com/?p=resources&s=details&id=18551
dl_ssao: https://community.mtasa.com/?p=resources&s=details&id=18552
dl_neon: https://community.mtasa.com/index.php?p=resources&s=details&id=18511

More detailed description is presented here:
https://gamedevelopment.tutsplus.com/articles/forward-rendering-vs-deferred-rendering--gamedev-12342

Requirements:
Shader model 3.0 GFX, MRT and readable depth buffer in PS access. 

Thanks goes to rifleh700 for his research to recreate exact gtasa vehicle processing.


