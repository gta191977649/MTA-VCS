color_black = tocolor(0,0,0,255)

function drawNode(x,y,z,rx,ry,color)
	local sx1,sy1 = getScreenFromWorldPosition(x+rx,y+ry,z,0x7FFFFFFF)
	if sx1 then
		local sx2,sy2 = getScreenFromWorldPosition(x-rx,y-ry,z,0x7FFFFFFF)
		if sx2 then
			dxDrawLine(sx1,sy1,sx2,sy2,color,2)
		end
	end
	local sx,sy = getScreenFromWorldPosition(x,y,z)
	if sx then
		dxDrawRectangle(sx-6,sy-6,12,12,color_black)
		dxDrawRectangle(sx-4,sy-4,8,8,color)
	end
end

--------------------------------------

function drawConnectionLine(x1,y1,z1,x2,y2,z2,color)
	local sx1,sy1 = getScreenFromWorldPosition(x1,y1,z1,0x7FFFFFFF)
	if not sx1 then return end
	local sx2,sy2 = getScreenFromWorldPosition(x2,y2,z2,0x7FFFFFFF)
	if not sx2 then return end
	dxDrawLine(sx1,sy1,sx2,sy2,color,2)
end

function drawConnectionBend(bx,by,x1,y1,z1,x2,y2,z2,color)
	local bz = (z1+z2)*0.5
	local sx1,sy1 = getScreenFromWorldPosition(x1,y1,z1,0x7FFFFFFF)
	x1,y1,z1 = x1-bx,y1-by,z1-bz
	x2,y2,z2 = x2-bx,y2-by,z2-bz
	local math_sin,math_cos = math.sin,math.cos
	local delta_a = math.pi*0.0625
	for a = delta_a,(math.pi+delta_a)*0.5,delta_a do
		local sina,cosa = math_sin(a),math_cos(a)
		local sx2,sy2 = getScreenFromWorldPosition(bx+x1*cosa+x2*sina,by+y1*cosa+y2*sina,bz+z1*cosa+z2*sina,0x7FFFFFFF)
		if sx1 and sx2 then
			dxDrawLine(sx1,sy1,sx2,sy2,color,2)
		end
		sx1,sy1 = sx2,sy2
	end
end

function drawConnectionArrow(x1,y1,z1,x2,y2,z2,color)
	local yx,yy,yz = 0,0,1
	local zx,zy,zz = x1-x2,y1-y2,z1-z2
	local xx,xy,xz = yy*zz-yz*zy,yz*zx-yx*zz,yx*zy-yy*zx
	      yx,yy,yz = zy*xz-zz*xy,zz*xx-zx*xz,zx*xy-zy*xx
	local xmult = 1/math.sqrt(xx*xx+xy*xy+xz*xz)
	local ymult = 1/math.sqrt(yx*yx+yy*yy+yz*yz)
	local zmult = 2/math.sqrt(zx*zx+zy*zy+zz*zz)
	xx,xy,xz = xx*xmult,xy*xmult,xz*xmult
	yx,yy,yz = yx*ymult,yy*ymult,yz*ymult
	zx,zy,zz = zx*zmult,zy*zmult,zz*zmult
	local ax,ay,az = x2+zx,y2+zy,z2+zz
	local sx ,sy  = getScreenFromWorldPosition(x2,y2,z2,0x7FFFFFFF)
	local sx1,sy1 = getScreenFromWorldPosition(ax+xx,ay+xy,az+xz,0x7FFFFFFF)
	local sx2,sy2 = getScreenFromWorldPosition(ax-xx,ay-xy,az-xz,0x7FFFFFFF)
	local sx3,sy3 = getScreenFromWorldPosition(ax+yx,ay+yy,az+yz,0x7FFFFFFF)
	local sx4,sy4 = getScreenFromWorldPosition(ax-yx,ay-yy,az-yz,0x7FFFFFFF)
	if sx then
		if sx1 then dxDrawLine(sx,sy,sx1,sy1,color,2) end
		if sx2 then dxDrawLine(sx,sy,sx2,sy2,color,2) end
		if sx3 then dxDrawLine(sx,sy,sx3,sy3,color,2) end
		if sx4 then dxDrawLine(sx,sy,sx4,sy4,color,2) end
	end
	if sx1 and sx2 then dxDrawLine(sx1,sy1,sx2,sy2,color,2) end
	if sx3 and sx4 then dxDrawLine(sx3,sy3,sx4,sy4,color,2) end
end

function drawTrafficLightMarker(x1,y1,z1,x2,y2,z2,dir,color)
	local offx,offy,offz = dir == CONN_LIT_WE and 2 or 0,dir == CONN_LIT_NS and 2 or 0,dir == CONN_LIT_PED and 2 or 0
	local dx,dy,dz = x1-x2,y1-y2,z1-z2
	local mult = 2.5/math.sqrt(dx*dx+dy*dy+dz*dz)
	local x,y,z = x2+dx*mult,y2+dy*mult,z2+dz*mult
	local x1,y1 = getScreenFromWorldPosition(x+offx,y+offy,z+1.5+offz,0x7FFFFFFF)
	if x1 then
		local x2,y2 = getScreenFromWorldPosition(x-offx,y-offy,z+1.5-offz,0x7FFFFFFF)
		if x2 then
			dxDrawLine(x1,y1,x2,y2,color,2)
		end
	end
	local x1,y1 = getScreenFromWorldPosition(x2,y2,z2,0x7FFFFFFF)
	if x1 then
		local x2,y2 = getScreenFromWorldPosition(x,y,z+1.5,0x7FFFFFFF)
		if x2 then
			dxDrawLine(x1,y1,x2,y2,color,2)
		end
	end
end

local color_black = tocolor(0,0,0,255)

function drawOutlinedText(x,y,text,color,halign,valign)
	dxDrawText(text,x-1,y,x-1,y,color_black,1,"default-bold",halign,valign)
	dxDrawText(text,x+1,y,x+1,y,color_black,1,"default-bold",halign,valign)
	dxDrawText(text,x,y-1,x,y-1,color_black,1,"default-bold",halign,valign)
	dxDrawText(text,x,y+1,x,y+1,color_black,1,"default-bold",halign,valign)
	dxDrawText(text,x,y,x,y,color,1,"default-bold",halign,valign)
end

function drawTextIn3D(x,y,z,text,color)
	x,y = getScreenFromWorldPosition(x,y,z)
	if not x then return end
	drawOutlinedText(x,y,text,color,"center","center")
end

--------------------------------------

function drawForb(x,y,z,x1,y1,z1,x2,y2,z2)
	x1,y1,z1 = x1-x,y1-y,z1-z
	x2,y2,z2 = x2-x,y2-y,z2-z
	local mult1 = 1/math.sqrt(x1*x1+y1*y1+z1*z1)
	local mult2 = 1/math.sqrt(x2*x2+y2*y2+z2*z2)
	x1,y1,z1 = x+x1*mult1,y+y1*mult1,z+z1*mult1
	x2,y2,z2 = x+x2*mult2,y+y2*mult2,z+z2*mult2
	local x ,y  = getScreenFromWorldPosition(x ,y ,z ,0x7FFFFFFF)
	local x1,y1 = getScreenFromWorldPosition(x1,y1,z1,0x7FFFFFFF)
	local x2,y2 = getScreenFromWorldPosition(x2,y2,z2,0x7FFFFFFF)
	local color = tocolor(255,96,0,192)
	if x and x1 then dxDrawLine(x,y,x1,y1,color,2) end
	if x and x2 then
		dxDrawLine(x,y,x2,y2,color,2)
		dxDrawLine(x2-8,y2-8,x2+8,y2+8,color,2)
		dxDrawLine(x2-8,y2+8,x2+8,y2-8,color,2)
	end
end

