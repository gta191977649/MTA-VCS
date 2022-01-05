SHADER = exports["dl_core"]
function initModels() 
    -- generic txd fix (for vcs)
    for idx,txd in pairs(IMG_GENERIC) do 
        --[[
        local shader = dxCreateShader( "shader/replace.fx",{},1)
        local texture = dxCreateTexture(txd.path)
        dxSetShaderValue (shader, "Tex0",texture)
        engineApplyShaderToWorldTexture(shader,txd.name)
        --]]
        local texture = dxCreateTexture(txd.path)
        SHADER:applyTextureReplaceToVehicle(txd.name,texture)
    end

    for key,val in pairs(IMG_PED) do 
        if val.replace == nil or val.replace == false then
            val.pointer = engineRequestModel("ped")
            if val.pointer then 
                local txd = engineLoadTXD(val.txd)
                engineImportTXD(txd, val.pointer)
                local dff = engineLoadDFF(val.dff)
                engineReplaceModel(dff, val.pointer)
                print(string.format("%s is loaded.",val.name))
            end
        else 
            local txd = engineLoadTXD(val.txd)
            engineImportTXD(txd, val.parent)
            local dff = engineLoadDFF(val.dff)
            engineReplaceModel(dff,val.parent)
            print(string.format("%s is loaded.",val.name))
            print(string.format("skin %s is replaced.",val.name))
        end
    end

    for key,val in pairs(IMG_VEHICLE) do 
        if val.replace == nil or val.replace == false then
            if val.parent ~= nil then
                val.pointer = engineRequestModel("vehicle",val.parent)
            else 
                val.pointer = engineRequestModel("vehicle")
            end
            if val.pointer then 
                local txd = engineLoadTXD(val.txd)
                engineImportTXD(txd, val.pointer)
                local dff = engineLoadDFF(val.dff)
                engineReplaceModel(dff, val.pointer)
                print(string.format("vehicle %s is import.",val.name))
            end
        else -- deal with replace vehicle
            local txd = engineLoadTXD(val.txd)
            engineImportTXD(txd, val.parent)
            local dff = engineLoadDFF(val.dff)
            engineReplaceModel(dff,val.parent)
            print(string.format("vehicle %s is replaced.",val.name))
        end
    end
end


function setElementModModel(element,model)
    local type = getElementType(element)
    if type == "player" then 
        local id = IMG_PED[model].pointer
        setElementModel(element,id)
    elseif type == "vehicle" then 
        local id = IMG_VEHICLE[model].pointer
        setElementModel(element,id)
    else 
        print("[MOD]: Unsupported element type!")
    end
end

function createModVehicle(model,x,y,z)
    if IMG_VEHICLE[model] ~= nil then 
        --local id = IMG_VEHICLE[model].pointer
        local parent = IMG_VEHICLE[model].parent == nil and 500 or IMG_VEHICLE[model].parent
        --createVehicle(id,x,y,z)
        triggerServerEvent("mod.server.spawnVehicle",root,model,parent,x,y,z)
    else
        outputChatBox(string.format( "ERROR: Mod %s is invaild.",model))
    end
end

function getVehicleName(source) 
    if getElementType( source ) == "vehicle" then
        local model = getElementData(source,"mod.model")
        if model ~= false then 
            return IMG_VEHICLE[model].name
        end
    end
    return ""
end
initModels() 


-- sync
addEventHandler( "onClientElementStreamIn", root,
    function ( )
        if getElementType( source ) == "vehicle" or getElementType( source ) == "player" then
            local model = getElementData(source,"mod.model")
            if model ~= false then 
                setElementModModel(source,model)
                print("Synced mod model for "..model)
            end
        end
    end
);

addCommandHandler("dlc",function(name,param) 
    print(param)
    local x, y, z = getElementPosition ( localPlayer )
    createModVehicle(param,x+2,y+2,z)
end)
