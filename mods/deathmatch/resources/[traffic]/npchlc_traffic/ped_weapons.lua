PedWeapons = {}

-- MAIN.SCM 0xF6EA..0xF72E initializes these pairs by gang index.
-- Keys here are the corresponding ped types, GANG1 through GANG9.
local gangWeapons = {
    [7]  = {19, 0},
    [8]  = {19, 6},
    [9]  = {26, 25},
    [10] = {28, 28},
    [11] = {0, 19},
    [12] = {19, 25},
    [13] = {19, 6},
    [14] = {3, 3},
    [15] = {26, 29},
}

-- Both VCS compact SMGs use MTA's Micro Uzi. Keep the chosen VCS ID for weapon info.
local hostWeapon = {[3]=2, [6]=5, [19]=22, [25]=28, [26]=28, [28]=31, [29]=30}

function PedWeapons.equipGang(ped, profile)
    local choices = profile and gangWeapons[profile.pedType]
    if not choices then return end
    -- 002B2908 draws once for each member, including passengers in the same car.
    local weapon = choices[math.random(0, 99) < 50 and 1 or 2]
    if weapon == 0 then
        setPedWeaponSlot(ped, 0)
        return
    end
    local host = hostWeapon[weapon]
    if giveWeapon(ped, host, 25001, true) then return weapon, host end
end

-- MAIN.SCM 0156 assigns the gang cars. 002B3CA0 scans from GANG1 upwards,
-- so GANG7 has priority over GANG9 for their shared vehicle, model 171.
local gangCarGroup = {[267]=1, [265]=2, [269]=3, [209]=4, [174]=5, [231]=6, [171]=7, [184]=8}

function PedWeapons.gangOccupant(originalVehicle, population, loaded)
    local group = gangCarGroup[originalVehicle]
    local pair = group and population and population.gangModels and population.gangModels[group]
    if not pair then return end
    local model = pair[math.random(1, 2)]
    if loaded(model) then return model, group + 6 end
    return 14 -- The native occupant factory uses the ordinary street ped here.
end
