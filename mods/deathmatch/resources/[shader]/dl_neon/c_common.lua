--
-- c_common.lua
--

---------------------------------------------------------------------------------------------------
-- primitive triaggle lists
---------------------------------------------------------------------------------------------------
trianglelist = {}
trianglelist.cube = {
	{ -0.5, -0.5, -0.5, 1, 0 },{ -0.5, 0.5, -0.5, 1, 1 },{ 0.5, 0.5, -0.5, 0, 1 },
	{ 0.5, 0.5, -0.5, 0, 1 },{ 0.5, -0.5, -0.5, 0, 0 },{ -0.5, -0.5, -0.5, 1, 0 },
	{ -0.5, -0.5, 0.5, 0, 0 },{ 0.5, -0.5, 0.5, 1, 0 },{ 0.5, 0.5, 0.5, 1, 1 },
	{ 0.5, 0.5, 0.5, 1, 1 },{ -0.5, 0.5, 0.5, 0, 1 },{ -0.5, -0.5, 0.5, 0, 0 },
	{ -0.5, -0.5, -0.5, 0, 0 },{ 0.5, -0.5, -0.5, 1, 0 },{ 0.5, -0.5, 0.5, 1, 1 },
	{ 0.5, -0.5, 0.5, 1, 1 },{ -0.5, -0.5, 0.5, 0, 1 },{ -0.5, -0.5, -0.5, 0, 0 },
	{ 0.5, -0.5, -0.5, 0, 0 },{ 0.5, 0.5, -0.5, 1, 0 },{ 0.5, 0.5, 0.5, 1, 1 },
	{ 0.5, 0.5, 0.5, 1, 1 },{ 0.5, -0.5, 0.5, 0, 1 },{ 0.5, -0.5, -0.5, 0, 0 },
	{ 0.5, 0.5, -0.5, 0, 0 },{ -0.5, 0.5, -0.5, 1, 0 },{ -0.5, 0.5, 0.5, 1, 1 },
	{ -0.5, 0.5, 0.5, 1, 1 },{ 0.5, 0.5, 0.5, 0, 1 },{ 0.5, 0.5, -0.5, 0, 0 },
	{ -0.5, 0.5, -0.5, 0, 0 },{ -0.5, -0.5, -0.5, 1, 0 },{ -0.5, -0.5, 0.5, 1, 1 },
	{ -0.5, -0.5, 0.5, 1, 1 },{ -0.5, 0.5, 0.5, 0, 1 },{ -0.5, 0.5, -0.5, 0, 0 }
}


trianglelist.plane = {
	{ -0.5, 0.5, 0, 0, 1 },{ -0.5, -0.5, 0, 0, 0 },{ 0.5, 0.5, 0, 1, 1 },
	{ 0.5, -0.5, 0, 1, 0 },{ 0.5, 0.5, 0, 1, 1 },{ -0.5, -0.5, 0, 0, 0 }
}

---------------------------------------------------------------------------------------------------
-- variables
---------------------------------------------------------------------------------------------------
isFullDX9Supported = tonumber(dxGetStatus().VideoCardPSVersion) > 2 and dxGetStatus().DepthBufferFormat	

---------------------------------------------------------------------------------------------------
-- manage after effect zBuffer recovery
---------------------------------------------------------------------------------------------------
CPrmFixZ = { }
function CPrmFixZ.create()
	if CPrmFixZ.shader then return true end
	CPrmFixZ.shader = dxCreateShader( "fx/primitive2D_fixZBuffer.fx" )
	if CPrmFixZ.shader then
		dxSetShaderValue(CPrmFixZ.shader, "fViewportSize", guiGetScreenSize() )
		return true
	end
	return false
end

function CPrmFixZ.draw()
	if renderTarget.isOn then return end
	if CPrmFixZ.shader then
		-- draw the outcome
		dxDrawMaterialPrimitive3D( "trianglelist", CPrmFixZ.shader, false, unpack( trianglelist.plane ) )
	end
end

function CPrmFixZ.destroy()
	if CPrmFixZ.shader then
		CPrmFixZ.shader:destroy()
	end
end	

addEventHandler('onClientPreRender', root, function()
	-- fix for gtasa effects and line material after readable depth buffer is used 	
	if dxGetStatus().UsingDepthBuffer then
		if CPrmFixZ.create() then
		  CPrmFixZ.draw()
		end
	end
end
,true,"high+10")

------------------------------------------------------------------------------------------------------------
-- check if element is drawn in front of cam plane
------------------------------------------------------------------------------------------------------------
localCamera = {}

addEventHandler("onClientPreRender", getRootElement(), function()
	localCamera.mat = getCamera().matrix
	localCamera.pos = getCamera().position
	localCamera.fw = localCamera.mat.forward
	localCamera.farClipFront = localCamera.pos + (localCamera.mat.forward * getFarClipDistance())
	localCamera.farClipDistance = getFarClipDistance()
end, true, "high+20" )

function isEntityInCameraFront(pos, rads)
	if localCamera.fw:dot(pos - localCamera.pos) > -rads then
		return true
	else
		return false
	end
end

function isEntityInFrontalSphere(pos, rads)
	if (localCamera.farClipFront - pos).length < localCamera.farClipDistance + rads * 0.5 then
		return true
	else
		return false
	end
end	

---------------------------------------------------------------------------------------------------
-- prevent memory leaks
---------------------------------------------------------------------------------------------------
addEventHandler( "onClientResourceStart", resourceRoot, function()
	collectgarbage( "setpause", 100 )
end
)
