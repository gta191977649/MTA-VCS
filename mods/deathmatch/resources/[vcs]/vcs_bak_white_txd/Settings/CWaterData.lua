Water = {
}

	for i,v in pairs(Water) do
		local water = createWater (unpack(v))
		local x,y,z = getElementPosition(water)
		setElementPosition(water,x,y,z)
	end