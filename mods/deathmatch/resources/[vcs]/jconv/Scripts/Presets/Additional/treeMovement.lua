original = {}

JustDone = {}

function string.count (text, search)
	if ( not text or not search ) then return false end

	return select ( 2, text:gsub ( search, "" ) )
end

Tree = {"veg_"}

function isVeg(Input)
	for i,v in pairs(Tree) do
		if (string.count(Input,v) or 0) > 0 then
			return true
		end
	end
end

-- Get Standard rotations

for i,v in pairs(getElementsByType('object')) do
	if isVeg(getElementID(v)) then
		local xr,yr,zr = getElementRotation(v)
		original[v] = {xr,yr,zr}
		local x,y,z = getElementPosition(v)
		setElementPosition(v,x,y,z-0.5)
		local randomA = math.random(1,3)
		if randomA == 1	then
			JustDone[v] = {0,0}
		else
			JustDone[v] = nil
		end
	end
end


function moveStuff()
	Weather1,Weather2 = getWeather()

	if Weather1 == 8 then
		Limit = 10
	else
		Limit = 3
	end


	for i,v in pairs(original) do
		if isElementStreamedIn(i) then
			local x,y,z = getElementPosition(i)
			local ox,oy,oz = unpack(v)
			if JustDone[i] then
				local nx,ny = unpack(JustDone[i])
				JustDone[i] = nil
				moveObject ( i, 5000,x,y,z,-nx,-ny,0 )
			else
				local xr,yr = math.random(Limit-3,Limit),math.random(Limit-3,Limit)
				JustDone[i] = {xr,yr}
				moveObject ( i, 5000,x,y,z,xr,yr,0 )
			end
		end
	end
end

moveStuff()

setTimer ( moveStuff, 5000, 0)
