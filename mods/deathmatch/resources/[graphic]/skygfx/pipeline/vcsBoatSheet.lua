-- SLUS_215.90 00177900..001780FC. Each hull emitter owns a ring of
-- sixteen vertex pairs with one edge on the water and one edge in the air.
VCSBoatSheet={}

function VCSBoatSheet.add(state,slot,x,y,z,vx,vy,vz,wx,wy,wz)
    if not state.sheets then state.sheets={} end
    local sheet=state.sheets[slot]
    if sheet then
        local last=sheet.pairs[#sheet.pairs]
        if last and (x-last.x)^2+(y-last.y)^2+(z-last.z)^2>13^2 then sheet=nil end
    end
    if not sheet then
        sheet={pairs={},vx=0,vy=0,vz=0}
        state.sheets[slot]=sheet
    end
    sheet.vx,sheet.vy,sheet.vz=(sheet.vx+vx)*0.5,(sheet.vy+vy)*0.5,(sheet.vz+vz)*0.5
    local pairs=sheet.pairs
    if #pairs==16 then table.remove(pairs,1) end
    pairs[#pairs+1]={x=x,y=y,z=z,ax=x,ay=y,az=z,wx=wx,wy=wy,wz=wz,
        vx=sheet.vx,vy=sheet.vy,vz=sheet.vz,u=(state.splashFrame or 0)%2,alpha=255,age=0}
end

function VCSBoatSheet.step(state,step)
    for _,sheet in pairs(state.sheets or {}) do
        for i=#sheet.pairs,1,-1 do
            local p=sheet.pairs[i]
            p.age=p.age+1
            p.x,p.y,p.z=p.x+p.wx*step,p.y+p.wy*step,p.z+p.wz*step
            p.ax,p.ay,p.az=p.ax+p.vx*step,p.ay+p.vy*step,p.az+p.vz*step
            p.vx,p.vy,p.vz=p.vx*0.9,p.vy*0.9,p.vz-0.016*math.max(0.5,step)
            p.wx,p.wy,p.wz=p.wx*0.4,p.wy*0.4,p.wz*0.4
            p.alpha=p.alpha-15
            if p.az<p.z or p.age>=16 then table.remove(sheet.pairs,i) end
        end
    end
end

function VCSBoatSheet.draw(state,material,red,green,blue,opacity)
    if not state.sheets or not material then return 0 end
    local strips=0
    local edge=tocolor(red,green,blue,0)
    for _,sheet in pairs(state.sheets) do
        if #sheet.pairs>=2 then
            local vertices={}
            for i=#sheet.pairs,1,-1 do
                local p=sheet.pairs[i]
                vertices[#vertices+1]={p.x,p.y,p.z,edge,p.u,0}
                vertices[#vertices+1]={p.ax,p.ay,p.az,tocolor(red,green,blue,p.alpha*opacity),p.u,1}
            end
            if dxDrawMaterialPrimitive3D("trianglestrip",material,"postfx",unpack(vertices)) then strips=strips+1 end
        end
    end
    return strips
end
