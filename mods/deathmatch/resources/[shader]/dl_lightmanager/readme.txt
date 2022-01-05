Resource: dl_lightManager v0.1.2 
Author: Ren712
Contact: knoblauch700@o2.pl

Description:
This resource adds an ability to create simple light sources.
The purpose of this resource is  to give an efficient alternative to
dynamic lighting resource and introduce new deferred rendering
approach. Instead of applying shaders to world textures, I have decided 
to recreate needed information from scene depth to apply effect post world
(drawn on primitiveMAterial3D billboard or light shape). You can add virtually 
limitless number of lights. In order to work the effects
require shader model 3 GFX with readable depth buffer support.

Effects:
primitive3D_pointLight, primitive3D_pointLight_normalGen
primitive3D_spotLight, primitive3D_spotLight_normalGen

Required resource:
dl_core: https://community.mtasa.com/index.php?p=resources&s=details&id=18510

Requirements:
Shader model 3.0 GFX, readable depth buffer in PS access.

Exports:
Exported functions have conforming input to the ones of dynamic_lighting
resurce, the main difference is that color is represented by int(0-255) instead 
float(0-1) https://wiki.multitheftauto.com/wiki/Resource:Dynamic_lighting 
Look into c_exports for details.

createPointLight
createSpotLight
destroyLight
attachLightToElement
detachLight
detachFromElement
setLightDimension
setLightInterior
setLightDirection
setLightRotation
setLightPosition
setLightColor
setLightBlend
setLightAttenuation
setLightFalloff
setLightTheta
setLightPhi
getLightDimension
getLightInterior
getLightDirection
getLightRotation
getLightPosition
getLightColor
getLightBlend
getLightAttenuation
getLightFalloff
getLightTheta
getLightPhi

Core resource for deferred lighting:
dl_core: https://community.mtasa.com/index.php?p=resources&s=details&id=18510

dl_core is required for:
dl_lightmanager: https://community.mtasa.com/index.php?p=resources&s=details&id=18512
dl_flashlight: https://community.mtasa.com/index.php?p=resources&s=details&id=18514
dl_vehicles: https://community.mtasa.com/index.php?p=resources&s=details&id=18513
dl_blendshad: https://community.mtasa.com/?p=resources&s=details&id=18547
dl_projectiles: https://community.mtasa.com/?p=resources&s=details&id=18548
dl_normalgehttps://community.mtasa.com/?p=resources&s=details&id=18555n: 
dl_image3dlight: https://community.mtasa.com/?p=resources&s=details&id=18553
dl_material3dlight: https://community.mtasa.com/?p=resources&s=details&id=18554
dl_primitive3dlight: https://community.mtasa.com/?p=resources&s=details&id=18550

used by but not required:
dl_shader_detail: https://community.mtasa.com/?p=resources&s=details&id=18549
dl_carpaint: https://community.mtasa.com/?p=resources&s=details&id=18551
dl_ssao: https://community.mtasa.com/?p=resources&s=details&id=18552
dl_neon: https://community.mtasa.com/index.php?p=resources&s=details&id=18511