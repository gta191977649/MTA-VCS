addEventHandler("onResourceStart", resourceRoot, function()
    -- The mall's PS2 interior is below SA's underworld warp threshold.
    if not setWorldSpecialPropertyEnabled("underworldwarp", false) then
        outputDebugString("ENEX: could not disable underworld warp for below-map interiors.", 1)
    end
end)
