-- ===========================
--       IMG Loading
-- ===========================
IMGNames = { "dff", "col", "txd", "custom" }  -- IMG archives to scan for per resource
maxIMG = 4                                    -- Number of IMG files to check (e.g. txd_1.img, txd_2.img, ...)

-- ===========================
--   Streaming & Distances
-- ===========================

streamEverything             = true     -- Stream all elements by default
removeDefaultMap             = true     -- Remove SA world map
removeDefaultInteriors       = true     -- Remove interiors (set false to keep stock ones)
allocateDefaultIDs           = true     -- Use model IDs from SA if needed (disable to reserve original IDs)
highDefLODs                  = false    -- Use model itself as LOD; disables separate default LODs
streamingMemoryAllowcation   = 512      -- (MB) Memory for streamed assets. Raise for big maps (default: 512, max: 1024)
streamingBufferAllowcation   = 150      -- (MB) Streaming buffer size (default: 150, max: 512)
drawDistanceMultiplier       = 1        -- Multiply all draw distances (set lower for performance if needed)

-- ===========================
--           Debug
-- ===========================

streamDebug          = false  -- Output debug messages
modelCrashDebug      = false  -- Crash finder: spawn all objects at 0,0,0 for testing
modelCrashDebugRate  = 25     -- Time (ms) between spawn attempts in crash debug
despawnDebug         = false  -- Remove object immediately after streaming in crash debug
crashIndex           = 0      -- Current index for crash debugging
disableLOD           = false  -- Disable LODs

forceObject          = false  -- Force all elements to be created as 'Objects' instead of buildings for easy debugging and map editing.

-- ===========================
--        LOD Attachments
-- ===========================

lodAttach = {                -- Set true for model IDs/names whose LODs should be attached (ex: Tram)
    ["Tram"] = true
}

-- ===========================
--           Other
-- ===========================

alphaFixApply      = { "*plant*", "*grass*", "*foliage*", "*flower*", "*leave*", "*fern*", "*palm*", "kbtree4_test" }
enableAlphaFix     = true    -- Apply alpha fix shader to plant/foliage textures
enableAlphaFix2    = false   -- Use experimental (alternate) alpha fix shader
