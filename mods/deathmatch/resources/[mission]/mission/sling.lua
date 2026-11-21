-- Synchronize helicopter-relative endpoints. Physics runs in sling_c.lua.
local length = 31 * 6 / 32

function Mission.attachSling(run,hook)
    if not attachElements(hook,run.vehicle,0,0,-length) then return false end
    setElementData(hook,"mission:slingOwner",run.player,"broadcast","deny")
    run.sling={hook=hook,ox=0,oy=0,oz=-length}
    return true
end

local function withinReach(n)
    return type(n)=="number" and n>=-8 and n<=8
end

addEvent("mission:slingSample",true)
addEventHandler("mission:slingSample",resourceRoot,function(token,hook,a,b,c)
    if not client or source~=resourceRoot or not isElement(hook) then return end
    local id=getElementData(hook,"mission:airRescueCable",false)==true and "airrescue" or "firecopter"
    local run=Mission.forParticipant(client,token,id)
    local s=run and run.sling
    if not s or s.hook~=hook or not isElement(run.vehicle) or Mission.driverOf(run.vehicle)~=client then return end
    if not withinReach(a) or not withinReach(b) or not withinReach(c) or a*a+b*b+c*c>64 then return end
    local now=getTickCount()
    if s.received and now-s.received<75 then return end
    s.ox,s.oy,s.oz,s.received=a,b,c,now
    local x,y,z=getElementPosition(run.vehicle)
    local viewers=getElementsWithinRange(x,y,z,350,"player",run.interior,run.dimension)
    for i=#viewers,1,-1 do
        if viewers[i]==client then table.remove(viewers,i) end
    end
    if #viewers>0 then triggerClientEvent(viewers,"mission:slingSnapshot",resourceRoot,hook,a,b,c) end
end,false)

-- Use the same replicated offsets as the visible attachment. Server-side
-- world positions of nested attached MTA elements can lag the parent sync.
function Mission.slingPosition(run, m, ox, oy, oz)
    local s=run.sling
    if not s.received or getTickCount()-s.received>800 then return end
    local x,y,z=s.ox+(ox or 0),s.oy+(oy or 0),s.oz+(oz or 0)
    return m[4][1]+x*m[1][1]+y*m[2][1]+z*m[3][1],
        m[4][2]+x*m[1][2]+y*m[2][2]+z*m[3][2],
        m[4][3]+x*m[1][3]+y*m[2][3]+z*m[3][3]
end
