UI = exports.ui

function putPlayerInPosition(timeslice)
	local cx,cy,cz,ctx,cty,ctz = getCameraMatrix()
	ctx,cty = ctx-cx,cty-cy
	timeslice = timeslice*0.1
	if getKeyState("lshift") then timeslice = timeslice*4 end
	if getKeyState("lalt") then timeslice = timeslice*0.25 end
	local mult = timeslice/math.sqrt(ctx*ctx+cty*cty)
	ctx,cty = ctx*mult,cty*mult
	if getKeyState("w") then abx,aby = abx+ctx,aby+cty end
	if getKeyState("s") then abx,aby = abx-ctx,aby-cty end
	if getKeyState("d") then abx,aby = abx+cty,aby-ctx end
	if getKeyState("a") then abx,aby = abx-cty,aby+ctx end
	if getKeyState("e") then abz = abz+timeslice end
	if getKeyState("q") then abz = abz-timeslice end
	setElementPosition(localPlayer,abx,aby,abz)
end

function toggleAirBrake()
	air_brake = not air_brake or nil
	if air_brake then
		abx,aby,abz = getElementPosition(localPlayer)
		addEventHandler("onClientPreRender",root,putPlayerInPosition)
		UI.showTextBox(localPlayer,"Airbrake Enabled",3000)
	else
		abx,aby,abz = nil
		removeEventHandler("onClientPreRender",root,putPlayerInPosition)
		UI.showTextBox(localPlayer,"Airbrake Disabled",3000)
	end
end

bindKey("num_0","down",toggleAirBrake)

addCommandHandler("fly",toggleAirBrake)