CWidescreenSupport = {}

function getVcsHudViewport(width, height)
    -- VCSPC WidescreenSupport::Recalculate, automatic aspect ratio mode.
    if width == 720 and height == 576 then
        return width / 640, height / 448
    end
    local scaleX = math.min(width / 640, height / 480)
    return scaleX, scaleX * 480 / 448
end

function CWidescreenSupport:playerHud()
    local width, height = guiGetScreenSize()
    local scaleX, scaleY = getVcsHudViewport(width, height)
    -- Player and text coordinates use the PS2 game's 480 x 272 logical space.
    return width, scaleX * 640 / 480, scaleY * 448 / 272
end
