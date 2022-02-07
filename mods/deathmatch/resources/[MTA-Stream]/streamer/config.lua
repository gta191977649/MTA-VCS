debug.sethook(nil)
-- Config -- 
USE_LODS = true -- if disabled, we will use the model itself as lod.
MAX_DRAW_DIST = true -- enable this if you want your map ignore the ide draw distance
FORCE_LODS = false --if enable, the lod will apply to all objects
USE_REQUEST_MODEL = false -- if you don't want replace the sa model, use the new feature from mta 1.5.9
-- define map you want load when player join
AUTO_LOAD = {
    --["lcs"] = true,
    ["vcs"] = true,
}