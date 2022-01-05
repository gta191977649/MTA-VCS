--
-- c_switch.lua
--

----------------------------------------------------------------
----------------------------------------------------------------
-- Effect switching on and off
--
--	To switch on:
--			triggerEvent( "switchDR_renderTarget", root, true )
--
--	To switch off:
--			triggerEvent( "switchDR_renderTarget", root, false )
--
----------------------------------------------------------------
----------------------------------------------------------------

--------------------------------
-- onClientResourceStart/Stop
--------------------------------
addEventHandler( "onClientResourceStart", resourceRoot, function()
	if not isFXSupported then 
		outputChatBox( 'dl_core: Effects not supported', 255, 0, 0 )
		return
	end
	triggerEvent( "switchDL_core", resourceRoot, not isDREnabled )
	addCommandHandler( "deftest", function()
		triggerEvent( "switchDL_core", resourceRoot, not isDREnabled )
	end)
end)

addEventHandler( "onClientResourceStop", resourceRoot, function()
	switchDL_core( false )
end)

--------------------------------
-- Switch effect on or off
--------------------------------
function switchDL_core( blOn )
	outputDebugString( "switchDL_core: " .. tostring(blOn) )
	if blOn then
		switchDLOn()
	else
		switchDLOff()
		
	end
end

addEvent( "switchDL_core", true )
addEventHandler( "switchDL_core", resourceRoot, switchDL_core )