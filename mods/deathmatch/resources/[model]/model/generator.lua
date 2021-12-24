PATH_VEHICLE_IDE = "data/vehicles.ide"
PATH_HANDING_CFG = "data/handing.dat"
PATH_PREFIX_VEHICLE = "src/vehicle/"
VEHICLE_TABLE = ""
VEHICLE_META = ""
VEHICLE_CUSTOM_MAPPING_TABLE = {
    ["MOPED"] = 462,
    ["ANGEL"] = 463,
}
VEHICLE_HANDING_TABLE = {}
function readVehicleHanding(name) 
    
end
function getVehicleSAIDMapping(name) 
    return VEHICLE_CUSTOM_MAPPING_TABLE[name] or 411
end
function getVehicleHandingLine(name) 
    return VEHICLE_HANDING_TABLE[name] or false
end
function generateVehicleTable(name,handing_id,dff,txd) 
    if name == "SALEFT" then return end
    -- check if sa has this vehicle
    --<file src="src/vehicle/admiral.txd" type="client"/>
    local txd_exits = fileExists(string.format("src/vehicle/%s.txd",txd))
    local dff_exits = fileExists(string.format("src/vehicle/%s.dff",txd))
    if not txd_exits or not dff_exits then return end
    VEHICLE_META = VEHICLE_META..string.format("<file src=\"src/vehicle/%s.txd\" type=\"client\"/>\n",txd)
    VEHICLE_META = VEHICLE_META..string.format("<file src=\"src/vehicle/%s.dff\" type=\"client\"/>\n",dff)
    VEHICLE_TABLE = VEHICLE_TABLE .. "\t[\""..name.."\"] = {\n"
    local default_parent = 411
    local savehicle_id = getVehicleModelFromName(name)
    local content = {}
    content = {
        savehicle_id and "parent = "..savehicle_id or "parent = "..getVehicleSAIDMapping(name),
        "name = ".."\""..name.."\"",
        "txd = ".."\""..PATH_PREFIX_VEHICLE..txd..".txd\"",
        "dff = ".."\""..PATH_PREFIX_VEHICLE..dff..".dff\"",
        getVehicleHandingLine(handing_id) and "handing = ".."\""..getVehicleHandingLine(handing_id).."\"" or "handing = false",
        savehicle_id and "replace = true" or "replace = false",
    }

    for _,line in ipairs(content) do 
        VEHICLE_TABLE = VEHICLE_TABLE..string.format("\t\t%s,\n",line)
    end

    VEHICLE_TABLE = VEHICLE_TABLE .. "\t},\n"
end


function loadModels() 
    -- LOAD VEHICLES
    if fileExists("vehicleTable.txt") then return end
  
    if(fileExists(PATH_VEHICLE_IDE)) then 
        print("Start load vehicle handing...")
        local f = fileOpen(PATH_HANDING_CFG)
        local l = fileRead(f,fileGetSize(f))
        VEHICLE_HANDING_TABLE = readHandingSection(l)

        print("Start load vehicle ide...")

        local f = fileOpen(PATH_VEHICLE_IDE)
        local l = fileRead(f,fileGetSize(f))
        local data = readIDESection("cars",l)
        VEHICLE_TABLE = "{\n"
        for id,line in ipairs(data) do 
            local dff = line[2]
            local txd = line[3]
            local handing_id = line[5]
            local name = line[6]
            generateVehicleTable(name,handing_id,dff,txd)
        end
        VEHICLE_TABLE = VEHICLE_TABLE .."\n}\n"..VEHICLE_META

        --print(VEHICLE_TABLE)
        saveToFile("vehicleTable.txt",VEHICLE_TABLE)
    end
end

addEventHandler("onResourceStart",resourceRoot,loadModels)