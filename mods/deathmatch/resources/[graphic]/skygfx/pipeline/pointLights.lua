CPointLights = {}
local pending, registered, lastCount = {}, setmetatable({}, {__mode="k"}), 0

function AddLight(x,y,z,radius,r,g,b)
    if not AreParticlesEnabled() or type(x)~="number" or type(y)~="number" or type(z)~="number"
        or type(radius)~="number" or radius<=0 or type(r)~="number" or type(g)~="number" or type(b)~="number" then return false end
    pending[#pending+1]={x,y,z,1/(radius*radius),r,g,b}
    return true
end

function CPointLights.Register(shader)
    if shader then registered[shader]=true end
end

local function apply()
    if #pending==0 and lastCount==0 then return end
    local cx,cy,cz=getCameraMatrix()
    local first,second,d1,d2=nil,nil,math.huge,math.huge
    for _,v in ipairs(pending) do
        local distance=(v[1]-cx)^2+(v[2]-cy)^2+(v[3]-cz)^2
        if distance<d1 then
            first,second,d1,d2=v,first,distance,d1
        elseif distance<d2 then second,d2=v,distance end
    end
    local off={0,0,0,0,0,0,0}
    first,second=first or off,second or off
    for shader in pairs(registered) do
        if isElement(shader) then
            dxSetShaderValue(shader,"FireLights",first[1],first[2],first[3],first[4],second[1],second[2],second[3],second[4])
            dxSetShaderValue(shader,"FireColors",first[5],first[6],first[7],0,second[5],second[6],second[7],0)
        else registered[shader]=nil end
    end
    lastCount=#pending
    pending={}
end

function CPointLights.Initialise()
    addEventHandler("onClientPreRender",root,apply,true,"low-10")
end

function CPointLights.Shutdown()
    removeEventHandler("onClientPreRender",root,apply)
    pending,registered,lastCount={},setmetatable({}, {__mode="k"}),0
end
