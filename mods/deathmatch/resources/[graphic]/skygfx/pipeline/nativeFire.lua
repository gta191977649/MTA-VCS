-- Render the SA flame batches that do not have a script-visible emitter.
NativeFire = {}
local shaders={}
local sources={}
local previousCount=0
local world,area

function NativeFire.Register(id,x,y,z)
    if #shaders==0 then return end
    local dimension,interior=getElementDimension(localPlayer),getCameraInterior()
    if dimension~=world or interior~=area then sources={} world,area=dimension,interior end
    local now=getTickCount()
    local radius=id==74 and 4 or (id>=40 and id<=43 and 6 or 2.6)
    for _,s in ipairs(sources) do
        if (s.x-x)^2+(s.y-y)^2+(s.z-z)^2<2 then
            s.untilTime=now+250
            s.radius=math.max(radius,s.radius)
            return
        end
    end
    sources[#sources+1]={x=x,y=y,z=z,radius=radius,untilTime=now+250}
end

local function update()
    local now=getTickCount()
    local cx,cy,cz=getCameraMatrix()
    if world~=getElementDimension(localPlayer) or area~=getCameraInterior() then sources={} end
    for i=#sources,1,-1 do
        local s=sources[i]
        if now>s.untilTime then table.remove(sources,i)
        else s.distance=(s.x-cx)^2+(s.y-cy)^2+(s.z-cz)^2 end
    end
    if #sources==0 and previousCount==0 then return end
    table.sort(sources,function(a,b) return a.distance<b.distance end)
    local values={}
    for i=1,4 do
        local s=sources[i]
        local n=#values
        if s then values[n+1],values[n+2],values[n+3],values[n+4]=s.x,s.y,s.z,s.radius*s.radius
        else values[n+1],values[n+2],values[n+3],values[n+4]=0,0,0,-1 end
    end
    for _,shader in ipairs(shaders) do dxSetShaderValue(shader,"Sources",unpack(values)) end
    previousCount=#sources
end

function NativeFire.Initialise(atlas)
    -- prt_sand and prt_sand2 share bullethitsmoke with a secondary layer of
    -- fire_car. A world-texture shader cannot identify the originating FX
    -- system. Leave that entire batch to the host, including its blend state.
    for texture,ratio in pairs({wjet6=150/255,sphere=-1}) do
        local shader=dxCreateShader("shader/fireParticles.fx",{BILLBOARD_CENTRE="1"},20,0,false,"world,other")
            or dxCreateShader("shader/fireParticles.fx",20,0,false,"world,other")
        if shader then
            dxSetShaderValue(shader,"FireGreenRatio",ratio)
            dxSetShaderValue(shader,"ParticleAtlas",atlas)
            dxSetShaderValue(shader,"FlameUV",unpack(ParticleRasters.flame1))
            engineApplyShaderToWorldTexture(shader,texture,nil,false)
            shaders[#shaders+1]=shader
        end
    end
    local blast=dxCreateShader("shader/fireParticles.fx",{NATIVE_EXPLOSION="1"},20,0,false,"world,other")
    if blast then
        engineApplyShaderToWorldTexture(blast,"fireball6",nil,false)
        shaders[#shaders+1]=blast
    end
    if #shaders==0 then return end
    previousCount=1
    update()
    addEventHandler("onClientPreRender",root,update,true,"low-10")
end

function NativeFire.Shutdown()
    if #shaders>0 then removeEventHandler("onClientPreRender",root,update) end
    for _,shader in ipairs(shaders) do destroyElement(shader) end
    shaders,sources,previousCount={},{},0
end
