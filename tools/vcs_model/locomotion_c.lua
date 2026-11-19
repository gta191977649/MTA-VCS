local BLOCK = "vcs_traffic_locomotion"
local ifp
local failed
local applied = setmetatable({}, {__mode = "k"})
local reported = {}

local function nativeClip(originalId, native)
    -- SA model 280 uses the SWAT animation group. Its running slot
    -- uses swat_run, and its other movement slots match the man group.
    if native == "run_civi" and VCS_TRAFFIC_MODEL_CATALOG[originalId].base == 280 then
        return "swat_run"
    end
    return native
end

function applyVcsTrafficLocomotion(ped, originalId)
    local group = VCS_TRAFFIC_PEDESTRIAN_GROUPS[originalId]
    if group == nil or applied[ped] == originalId or failed then return end
    if not ifp then
        ifp = engineLoadIFP("traffic_locomotion.ifp", BLOCK)
        if not ifp then
            failed = true
            outputDebugString("[vcs_model] Could not load the PS2 pedestrian locomotion animations.", 1)
            return
        end
    end
    local clips = VCS_TRAFFIC_LOCOMOTION_GROUPS[group]
    local complete = true
    for index, native in ipairs(VCS_TRAFFIC_NATIVE_LOCOMOTION) do
        native = nativeClip(originalId, native)
        if not engineReplaceAnimation(ped, "ped", native, BLOCK, clips[index]) then
            complete = false
            if not reported[native] then
                reported[native] = true
                outputDebugString("[vcs_model] Could not replace SA pedestrian animation " .. native .. ".", 1)
            end
        end
    end
    if complete then applied[ped] = originalId end
end

addEventHandler("onClientElementStreamOut", root, function()
    applied[source] = nil
end)
