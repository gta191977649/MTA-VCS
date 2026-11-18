transform2 = {}

function transform2.move(x, y)

	return
	{
		{ 1, 0, 0 },
		{ 0, 1, 0 },
		{ x, y, 1 }
	}
end

function transform2.scale(x, y)

	return
	{
		{ x, 0, 0 },
		{ 0, y, 0 },
		{ 0, 0, 1 }
	}
end

function transform2.rotate(rad)

	local c = math.cos(rad)
	local s = math.sin(rad)

	return
	{
		{ c, s, 0 },
		{ -s, c, 0 },
		{ 0, 0, 1 }
	}
end

function transform2.mul(m1, m2)

	return
	{
		{
			m1[1][1] * m2[1][1] + m1[1][2] * m2[2][1],
			m1[1][1] * m2[1][2] + m1[1][2] * m2[2][2],
			0
		},
		{
			m1[2][1] * m2[1][1] + m1[2][2] * m2[2][1],
			m1[2][1] * m2[1][2] + m1[2][2] * m2[2][2],
			0
		},
		{
			m1[3][1] * m2[1][1] + m1[3][2] * m2[2][1] + m2[3][1],
			m1[3][1] * m2[1][2] + m1[3][2] * m2[2][2] + m2[3][2],
			1
		}
	}
end

function transform2.invert(m)

	local a, b = m[1][1], m[1][2]
	local c, d = m[2][1], m[2][2]
	local tx, ty = m[3][1], m[3][2]

	local det = a * d - b * c
	if det == 0 then return nil end

	local invDet = 1 / det

	return
	{
		{ d * invDet, -b * invDet, 0 },
		{ -c * invDet, a * invDet, 0 },
		{ (c * ty - d * tx) * invDet, (b * tx - a * ty) * invDet, 1 }
	}
end