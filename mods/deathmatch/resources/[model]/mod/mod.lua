SA_LAST_VID = 611
SA_LAST_SKIN = 312

IMG_GENERIC = {
    {
        name = "vehiclelightson128",
        path = "src/generic/vehiclelightson128.png",
    },
    {
        name = "vehiclegeneric256",
        path = "src/generic/vehiclegeneric256.png",
    },
    {
        name = "vehiclegrunge256",
        path = "src/generic/vehiclegrunge256.png",
    },
    {
        name = "vehicletyres128",
        path = "src/generic/vehicletyres128.png",
    },
    {
        name = "vehiclelights128",
        path = "src/generic/vehiclelights128.png",
    },
    {
        name = "vehiclesteering128",
        path = "src/generic/vehiclesteering128.png",
    },
    {
        name = "backplate",
        path = "src/generic/backplate.png",
    },
    {
        name = "plateback1",
        path = "src/generic/plateback1.png",
    },
    {
        name = "plateback2",
        path = "src/generic/plateback2.png",
    },
    {
        name = "plateback3",
        path = "src/generic/plateback3.png",
    },
}
IMG_PED = {
    --[[
    ["sfpd1"] = {
        parent = 281,
        replace=true,
        name= "sfpd1",
        txd="src/skin/sfpd1.txd",
        dff="src/skin/sfpd1.dff",
    },
    --]]
   
}
IMG_VEHICLE = {
    ["admiral"] = {
        parent = 445,
        name= "admiral",
        txd="src/vehicle/admiral.txd",
        dff="src/vehicle/admiral.dff",
        replace=true
    },
    ["banshee"] = {
        parent = 429,
        name= "banshee",
        txd="src/vehicle/banshee.txd",
        dff="src/vehicle/banshee.dff",
        replace=true
    },
    ["voodoo"] = {
        parent = 412,
        name= "voodoo",
        txd="src/vehicle/voodoo.txd",
        dff="src/vehicle/voodoo.dff",
        replace=true
    },
    ["cabbie"] = {
        parent = 438,
        name= "cabbie",
        txd="src/vehicle/cabbie.txd",
        dff="src/vehicle/cabbie.dff",
        replace=true
    },
    ["caddy"] = {
        parent = 457,
        name= "caddy",
        txd="src/vehicle/caddy.txd",
        dff="src/vehicle/caddy.dff",
        replace=true
    },
    ["infernus"] = {
        parent = 411,
        name= "infernus",
        txd="src/vehicle/infernus.txd",
        dff="src/vehicle/infernus.dff",
        replace=true
    },
    ["cheetah"] = {
        parent = 415,
        name= "cheetah",
        txd="src/vehicle/cheetah.txd",
        dff="src/vehicle/cheetah.dff",
        replace=true
    },
    ["pcj600"] = {
        parent = 461,
        name= "pcj600",
        txd="src/vehicle/pcj600.txd",
        dff="src/vehicle/pcj600.dff",
        replace=true
    },
    ["quad"] = {
        parent = 471,
        name= "quad",
        txd="src/vehicle/quad.txd",
        dff="src/vehicle/quad.dff",
        replace=true
    },
    ["sentinel"] = {
        parent = 405,
        name= "sentinel",
        txd="src/vehicle/sentinel.txd",
        dff="src/vehicle/sentinel.dff",
        replace=true
    },
    ["bmx"] = {
        parent = 481,
        name= "bmx",
        txd="src/vehicle/bmxboy.txd",
        dff="src/vehicle/bmxboy.dff",
        replace=true
    },
    ["hovercr"] = {
        parent = 539,
        name= "hovercr",
        txd="src/vehicle/hovercr.txd",
        dff="src/vehicle/hovercr.dff",
        replace=true
    },
    ["6atv"] = {
        parent = 504,
        name= "6atv",
        txd="src/vehicle/6atv.txd",
        dff="src/vehicle/6atv.dff",
    },
    ["stinger"] = {
        parent = 480,
        name= "stinger",
        txd="src/vehicle/stinger.txd",
        dff="src/vehicle/stinger.dff",
    },
    ["jetski"] = {
        parent = 473,
        name= "jetski",
        txd="src/vehicle/jetski.txd",
        dff="src/vehicle/jetski.dff",
    },

    
}
-- generate_id
local total_ped = 0
local total_veh = 0
for key,val in pairs(IMG_PED) do 
    total_ped = total_ped + 1
    val.id = SA_LAST_SKIN + total_ped
    
end

for key,val in pairs(IMG_VEHICLE) do 
    total_veh = total_veh + 1
    val.id = SA_LAST_VID + total_veh
end


print(string.format("Total %d custom mod is defined.",total_ped + total_veh))
