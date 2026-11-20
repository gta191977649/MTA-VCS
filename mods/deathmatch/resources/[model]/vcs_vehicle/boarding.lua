-- ped_frontseat in the converted VCS hull's local RenderWare frame.
local helms = {
    [214]={0.41,1.57,1.43}, [215]={0.50,2.98,0.82}, [219]={0.40,0.13,0.98},
    [225]={0,-4.18,1.44}, [233]={0,-0.46,0.66}, [247]={0,0.35,0.99},
    [248]={0,-5.01,1.41}, [249]={0.31,-2.15,1}, [250]={-0.55,2.73,2.35},
    [257]={0.70,-0.81,1.16}, [258]={-0.67,0.60,0.90}, [264]={-0.62,-1.42,0.13}
}

function CBoat.boardingReach(player,vehicle)
    local original=CVehicle.originalModel(vehicle)
    local helm=helms[original]
    if not helm or getElementDimension(player)~=getElementDimension(vehicle)
        or getElementInterior(player)~=getElementInterior(vehicle) then return end
    local m=getElementMatrix(vehicle)
    if not m then return end
    local px,py,pz=getElementPosition(player)
    local dx,dy,dz=px-m[4][1],py-m[4][2],pz-m[4][3]
    local side=dx*m[1][1]+dy*m[1][2]+dz*m[1][3]
    local fore=dx*m[2][1]+dy*m[2][2]+dz*m[2][3]
    local up=dx*m[3][1]+dy*m[3][2]+dz*m[3][3]
    local nearSeat=(side-helm[1])^2+(fore-helm[2])^2
    local center=side^2+fore^2
    if original==233 then
        if center+up^2>16 or math.abs(up)>2 then return end
        return center,math.abs(side)<=1.1 and math.abs(fore)<=1.8 and up>=-0.15 and up<=1.6,side>=0
    end
    -- Reach the helm from alongside, or board amidships on long hulls.
    -- The outer bound keeps the bow of a long sailboat outside seat reach.
    local distance=math.min(nearSeat,center)
    if distance>16 or nearSeat>7^2 or up < -1.8 or up > helm[3]+1.5 then return end
    local deck=(nearSeat<=2.2^2 or center<=2.2^2) and up>=-0.15
    return distance,deck,side>=helm[1]
end
