"""Exercise the PS2 factory, script, generator and respray paths in Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime


def check():
    resource = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[model]/vcs_vehicle"
    lua = LuaRuntime()
    lua.execute("""
        events={}
        function addEvent() end
        function addEventHandler(e,element,f) events[e]=f end
        function isElement(v) return type(v)=="table" end
        function getElementType(v) return "vehicle" end
        function getElementModel(v) return v.base end
        function getResourceFromName() return true end
        function getResourceState() return "running" end
        function call(_,_,id) return id end
        function getElementData(v,key) return v[key] end
        function setElementData(v,key,value)
            if v[key]==value then return false end
            v[key]=value
            return true
        end
        function getVehicleVariant(v) return v.sign or 255,v.secondSign or 255 end
        function setVehicleVariant(v,a,b) v.sign,v.secondSign=a,b;return true end
        function setVehicleColor(v,...) v.rgb={...} return true end
        function addVehicleSirens() return false end
        function createVehicle(base) return {base=base} end
        function destroyElement(v) v.destroyed=true end
    """)
    for script in ["controllers/vehicle.lua", "data/paint.lua", "vehicle_s.lua"]:
        lua.execute((resource / script).read_text(encoding="utf-8"))
    lua.execute("""
        local function matches(v,a,b)
            local expected={a[1],a[2],a[3],b[1],b[2],b[3]}
            assert(table.concat(v.rgb,",")==table.concat(expected,","),v.base)
        end
        local function checkPair(v,model,pair)
            matches(v,model.colors[pair[1]] or VcsPaint.palette[pair[1]],
                      model.colors[pair[2]] or VcsPaint.palette[pair[2]])
        end
        local models,variations=0,0
        for id,model in pairs(VcsPaint.models) do
            models=models+1
            local v=createVcsVehicle(id,0,0,0)
            if model.count==0 then matches(v,{5,5,5},{5,5,5}) end
            for i=1,model.count do
                local expected=(model.cursor+i)%model.count
                checkPair(v,model,model.pairs[expected+1])
                assert(setVcsVehiclePaint(v,-1,-1))
                variations=variations+1
            end
            for i=1,model.alternateCount do
                local alt=createVcsVehicle(id,0,0,0,0,0,0,-1,i-1)
                checkPair(alt,model,model.alternate[i])
                assert(setVcsVehiclePaint(alt,23,42))
                matches(alt,VcsPaint.palette[23],VcsPaint.palette[42])
                assert(bindVcsVehicle(alt,id))
                matches(alt,VcsPaint.palette[23],VcsPaint.palette[42])
                source=alt; events.onVehicleRespawn()
                checkPair(alt,model,model.alternate[i])
            end
        end
        assert(models==111 and variations==552)
        local fire=createVcsVehicle(188,0,0,0)
        matches(fire,{255,255,255},{36,57,100})
        local air=createVcsVehicle(189,0,0,0)
        matches(air,{255,255,255},{176,0,0})
        local taxi=createVcsVehicle(226,0,0,0)
        assert((taxi.sign==0 or taxi.sign==1) and taxi.secondSign==255)
        local sign=taxi.sign
        assert(resprayVcsVehicle(taxi) and taxi.sign==sign)
        source=taxi;events.onVehicleRespawn();assert(taxi.sign==sign)
        assert(not createVcsVehicle(183,0,0,0).sign) -- Cabbie's sign belongs to its chassis.
        local stockTaxi=createVehicle(420)
        source=stockTaxi;events.onElementStartSync()
        assert((stockTaxi.sign==0 or stockTaxi.sign==1) and stockTaxi.secondSign==255)
        local mesa=createVcsVehicle(259,0,0,0,0,0,0,5,-1)
        checkPair(mesa,VcsPaint.models[259],VcsPaint.models[259].pairs[6])
        assert(resprayVcsVehicle(mesa))
        source=mesa;events.onVehicleRespawn()
        checkPair(mesa,VcsPaint.models[259],VcsPaint.models[259].pairs[6])
        assert(not setVcsVehiclePaint(mesa,128,0) and not createVcsVehicle(188,0,0,0,0,0,0,11))
        local legacy=createVehicle(599)
        assert(not setVcsVehiclePaint(legacy,0,0))
        assert(bindVcsVehiclePaint(legacy,188) and not CVehicle.originalModel(legacy))
        matches(legacy,{255,255,255},{36,57,100})
        assert(setVcsVehiclePaint(legacy,2,2) and bindVcsVehiclePaint(legacy,188))
        matches(legacy,VcsPaint.palette[2],VcsPaint.palette[2])
        assert(resprayVcsVehicle(legacy))
        matches(legacy,{255,255,255},{36,57,100})
    """)
    print("Verified factory, generator, respray, rebind and scripted paint paths across 111 PS2 records.")


def check_dlc():
    resources = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[model]"
    vm = LuaRuntime()
    vm.execute("""
        root,resourceRoot,handlers,cars={},{},{},{}
        function print() end
        function addEvent() end
        function addEventHandler(name,where,fn) handlers[name]=fn end
        function createVehicle(model)
            local car={base=model,calls=0};cars[#cars+1]=car;return car
        end
        function getElementType() return "vehicle" end
        function getElementModel(e) return e.base end
        function isElement(e) return type(e)=="table" end
        function getElementsByType() return cars end
        function getElementData(e,k) return e[k] end
        function setElementData(e,k,value)
            local previous=source;source=e;e[k]=value
            handlers.onElementDataChange(k)
            source=previous
        end
        function fileExists() return true end
        exports={vcs_model={},vcs_vehicle={}}
        function exports.vcs_model:getVcsModelIdByName(...) return getVcsModelIdByName(...) end
        function exports.vcs_vehicle:bindVcsVehiclePaint(v,id)
            if v.id~=id then v.id=id;v.calls=v.calls+1 end
            return true
        end
        function exports.vcs_vehicle:bindVcsVehicle(v,id)
            v.catalog=true;return self:bindVcsVehiclePaint(v,id)
        end
    """)
    for name in ("vcs_model/model_catalog.lua","vcs_model/model_bindings_s.lua","model/mod.lua","model/mod_s.lua"):
        vm.execute((resources / name).read_text(encoding="utf-8"))
    vm.execute("""
        function applyVehicleCustomHanding() end
        for key,id in pairs({["6WEELAT"]=170,SPEED2=185,IDAHO=199,MOPED=202,BOBO=208,
                             CHOLO=265,GANGBUR=269,PHOENIX=256,TAXI=226}) do
            handlers["mod.server.spawnVehicle"](key,nil,0,0,10)
            local v=cars[#cars];assert(v.id==id and v.calls==1 and not v.catalog,key)
        end
        local tagged=createVehicle(420)
        client={};setElementData(tagged,"mod.model","TAXI");assert(not tagged.id)
        client=nil;setElementData(tagged,"mod.model","TAXI");assert(tagged.id==226)
        handlers.onResourceStart();assert(tagged.calls==1)
        local native=createVehicle(420)
        assert(bindDlcReplacementPaint(native) and native.id==226 and not native.catalog)
        assert(not bindDlcReplacementPaint(createVehicle(481))) -- shared BMX hull
        assert(not bindDlcReplacementPaint(createVehicle(432))) -- catalog-owned Rhino
        assert(not bindDlcReplacementPaint(createVehicle(611))) -- native trailer
        assert(not bindDlcReplacementPaint(createVehicle(426))) -- added non-VCS model
    """)
    print("Verified legacy spawn, freeroam tags, existing paint and untagged native hull selection.")


if __name__ == "__main__":
    check()
    check_dlc()
