--=============================--
--   Alpha Fix Shader Loader   --
--=============================--

local RAW_ALPHA_FIX_SHADER = [[
technique AlphaFix {
    pass P0 { }
}
]]

local ALPHA_FIX_SHADER_PATH = "client/fx/alpha_fix.fx"  -- Use your .fx file or fallback to RAW string

local alphaFixShader = nil

-- Creates the alpha fix shader, from file if enabled, otherwise from inline string
local function createAlphaFixShader()
    if enableAlphaFix2 then
        alphaFixShader = dxCreateShader(ALPHA_FIX_SHADER_PATH, 1, 0, false, "object,world")
    else
        -- The compatibility shader only needs to replace the original pass.
        -- Layering it draws every matched foliage surface a second time.
        alphaFixShader = dxCreateShader(RAW_ALPHA_FIX_SHADER, 1, 0, false, "object,world")
    end
    return alphaFixShader
end

-- Applies the alpha fix shader to the world textures in alphaFixApply list
local function applyAlphaFix()
    if not alphaFixShader then
        if not createAlphaFixShader() then
            outputDebugString("Failed to create alpha fix shader.", 1)
            return
        end
    end

    if not alphaFixApply or type(alphaFixApply) ~= "table" then
        outputDebugString("alphaFixApply texture list not defined.", 1)
        return
    end

    for _, textureName in ipairs(alphaFixApply) do
        engineApplyShaderToWorldTexture(alphaFixShader, textureName)
    end
end


if enableAlphaFix then
    addEventHandler("onClientResourceStart", resourceRoot, applyAlphaFix)
end
