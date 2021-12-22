-- Author: KawaNoII (http://www.chinesemta.com) alexaxel705 (alexaxel705@gmail.com)
-- Source: https://wiki.multitheftauto.com/wiki/Quaternion

local identityMatrix = {
	[1] = {1, 0, 0},
	[2] = {0, 1, 0},
	[3] = {0, 0, 1}
}
 
function QuaternionTo3x3(x,y,z,w)
	local matrix3x3 = {[1] = {}, [2] = {}, [3] = {}}
 
	local symetricalMatrix = {
		[1] = {(-(y*y)-(z*z)), x*y, x*z},
		[2] = {x*y, (-(x*x)-(z*z)), y*z},
		[3] = {x*z, y*z, (-(x*x)-(y*y))} 
	}

	local antiSymetricalMatrix = {
		[1] = {0, -z, y},
		[2] = {z, 0, -x},
		[3] = {-y, x, 0}
	}
 
	for i = 1, 3 do 
		for j = 1, 3 do
			matrix3x3[i][j] = identityMatrix[i][j]+(2*symetricalMatrix[i][j])+(2*w*antiSymetricalMatrix[i][j])
		end
	end
	
	return matrix3x3
end

function getEulerAnglesFromMatrix(x1,y1,z1,x2,y2,z2,x3,y3,z3)
	local nz1,nz2,nz3
	nz3 = math.sqrt(x2*x2+y2*y2)
	nz1 = -x2*z2/nz3
	nz2 = -y2*z2/nz3
	local vx = nz1*x1+nz2*y1+nz3*z1
	local vz = nz1*x3+nz2*y3+nz3*z3
	return math.deg(math.asin(z2)),-math.deg(math.atan2(vx,vz)),-math.deg(math.atan2(x2,y2))
end

function fromQuaternion(x,y,z,w) 

	local matrix = QuaternionTo3x3(x,y,z,w)
	local ox,oy,oz = getEulerAnglesFromMatrix(
		matrix[1][1], matrix[1][2], matrix[1][3], 
		matrix[2][1], matrix[2][2], matrix[2][3],
		matrix[3][1], matrix[3][2], matrix[3][3]
	)
	-- check nan
	ox = ox == ox and ox or 0
	oy = oy == oy and oy or 0
	oz = oz == oz and oz or 0
	return ox,oy,oz
end