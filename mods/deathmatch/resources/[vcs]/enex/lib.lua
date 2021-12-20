function readFile(path) 
    local file = fileOpen(path)
    if not file then
        return false
    end
    local count = fileGetSize(file)
    local data = fileRead(file, count)
    fileClose(file)
    return data
end
function readFileInLines(path)
    local file = fileOpen(path)
    if not file then
        return false
    end
    local count = fileGetSize(file)
    local data = fileRead(file, count)
    fileClose(file)
    data = split(data,"\n")
    iprint(data)
    return data
end

function isComment(line) 
    return line:sub(1,1) == "#" or line:sub(1,1) == "\r"
end

local cos = math.cos
local sin = math.sin
local mathAtan2 = math.atan2
local degToPi = math.pi/180
function getPositionFromOffsetByPosRot(x,y,z,rx,ry,rz,offx,offy,offz)
    local rx,ry,rz = rx*degToPi,ry*degToPi,rz*degToPi
	local rxCos,ryCos,rzCos,rxSin,rySin,rzSin = cos(rx),cos(ry),cos(rz),sin(rx),sin(ry),sin(rz)
	m11,m12,m13,m21,m22,m23,m31,m32,m33 = rzCos*ryCos-rzSin*rxSin*rySin,ryCos*rzSin+rzCos*rxSin*rySin,-rxCos*rySin,-rxCos*rzSin,rzCos*rxCos,rxSin,rzCos*rySin+ryCos*rzSin*rxSin,rzSin*rySin-rzCos*ryCos*rxSin,rxCos*ryCos
	return offx*m11+offy*m21+offz*m31+x,offx*m12+offy*m22+offz*m32+y,offx*m13+offy*m23+offz*m33+z
end
