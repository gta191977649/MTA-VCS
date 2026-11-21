local SCREEN_WIDTH, SCREEN_HEIGHT = guiGetScreenSize()

local CROSSHAIR_SHADER_NAME = "crosshair.fx"

local CROSSHAIR_REGULAR_ENABLED = true
local CROSSHAIR_REGULAR_TEXTURE_NAME = "sitem16"
local CROSSHAIR_REGULAR_TEXTURE
local regularShader

local CROSSHAIR_CAMERA_ENABLED = true
local CROSSHAIR_CAMERA_SIZE = SCREEN_HEIGHT
local CROSSHAIR_CAMERA_COLOR = tocolor(255, 255, 255, 127)
local CROSSHAIR_CAMERA_TEXTURE

local CROSSHAIR_ROCKET_ENABLED = true
local CROSSHAIR_ROCKET_SIZE = SCREEN_HEIGHT / 10
local CROSSHAIR_ROCKET_COLOR = tocolor(255, 255, 255, 255)
local CROSSHAIR_ROCKET_TEXTURE

local CROSSHAIR_SNIPER_ENABLED = true
local CROSSHAIR_SNIPER_SIZE = SCREEN_HEIGHT * 5/6
local CROSSHAIR_SNIPER_COLOR = tocolor(255, 255, 255, 255)
local CROSSHAIR_SNIPER_TEXTURE



local dxDrawImage = dxDrawImage
local dxDrawImageSection = dxDrawImageSection


------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------


local function dxDrawImageQuad(x, y, width, height, image, rot, rotX, rotY, color)
	local w2 = width / 2
	local h2 = height / 2

	dxDrawImage(x, y, w2, h2, image, rot, rotX, rotY, color)
	dxDrawImage(x + width, y, -w2, h2, image, rot, rotX, rotY, color)
	dxDrawImage(x + width, y + height, -w2, -h2, image, rot, rotX, rotY, color)
	dxDrawImage(x, y + height, w2, -h2, image, rot, rotX, rotY, color)

	return true
end

local function initCrosshairRegular()

	if not CROSSHAIR_REGULAR_ENABLED or not CROSSHAIR_REGULAR_TEXTURE then return false end

	if not isElement(regularShader) then
		regularShader = dxCreateShader(CROSSHAIR_SHADER_NAME, 0, 0, false, "world,other")
		if not regularShader then return false end
		engineApplyShaderToWorldTexture(regularShader, CROSSHAIR_REGULAR_TEXTURE_NAME)
	end
	dxSetShaderValue(regularShader, "gTexture", CROSSHAIR_REGULAR_TEXTURE)

	return true
end

local function drawCrosshairSniper()

	if not CROSSHAIR_SNIPER_ENABLED or not CROSSHAIR_SNIPER_TEXTURE then return true end

	setPlayerHudComponentVisible("crosshair", false)

	local x = (SCREEN_WIDTH - CROSSHAIR_SNIPER_SIZE) / 2
	local y = (SCREEN_HEIGHT - CROSSHAIR_SNIPER_SIZE) / 2

	-- background
	dxDrawImageSection(
		0, 0,
		SCREEN_WIDTH, y,
		0, 0, 1, 1,
		CROSSHAIR_SNIPER_TEXTURE,
		0, 0, 0,
		CROSSHAIR_SNIPER_COLOR)
	dxDrawImageSection(
		0, SCREEN_HEIGHT - y,
		SCREEN_WIDTH, y,
		0, 0, 1, 1,
		CROSSHAIR_SNIPER_TEXTURE,
		0, 0, 0,
		CROSSHAIR_SNIPER_COLOR)

	dxDrawImageSection(
		0, y,
		x, SCREEN_HEIGHT - (y * 2),
		0, 0, 1, 1,
		CROSSHAIR_SNIPER_TEXTURE,
		0, 0, 0,
		CROSSHAIR_SNIPER_COLOR)
	dxDrawImageSection(
		SCREEN_WIDTH - x, y,
		x, SCREEN_HEIGHT - (y * 2),
		0, 0, 1, 1,
		CROSSHAIR_SNIPER_TEXTURE,
		0, 0, 0,
		CROSSHAIR_SNIPER_COLOR)


	return dxDrawImageQuad(
		x, y,
		CROSSHAIR_SNIPER_SIZE, CROSSHAIR_SNIPER_SIZE,
		CROSSHAIR_SNIPER_TEXTURE,
		0,
		0,
		0,
		CROSSHAIR_SNIPER_COLOR)
end

local function drawCrosshairCamera()

	if not CROSSHAIR_CAMERA_ENABLED or not CROSSHAIR_CAMERA_TEXTURE then return true end

	setPlayerHudComponentVisible("crosshair", false)

	return dxDrawImageQuad(
		(SCREEN_WIDTH - CROSSHAIR_CAMERA_SIZE) / 2,
		(SCREEN_HEIGHT - CROSSHAIR_CAMERA_SIZE) / 2,
		CROSSHAIR_CAMERA_SIZE,
		CROSSHAIR_CAMERA_SIZE,
		CROSSHAIR_CAMERA_TEXTURE,
		0,
		0,
		0,
		CROSSHAIR_CAMERA_COLOR)
end

local function drawCrosshairRocket()

	if not CROSSHAIR_ROCKET_ENABLED or not CROSSHAIR_ROCKET_TEXTURE then return true end

	setPlayerHudComponentVisible("crosshair", false)

	return dxDrawImage(
		(SCREEN_WIDTH - CROSSHAIR_ROCKET_SIZE) / 2,
		(SCREEN_HEIGHT - CROSSHAIR_ROCKET_SIZE) / 2,
		CROSSHAIR_ROCKET_SIZE,
		CROSSHAIR_ROCKET_SIZE,
		CROSSHAIR_ROCKET_TEXTURE,
		0,
		0,
		0,
		CROSSHAIR_ROCKET_COLOR)
end

local function drawCrosshairRegular()

	if not CROSSHAIR_REGULAR_ENABLED then return true end

	setPlayerHudComponentVisible("crosshair", true)

	return true
end

local function drawCrosshair()

	if not isPlayerCrosshairVisible() then return true end
	if not isElement(CROSSHAIR_REGULAR_TEXTURE) then
		local frontend = getResourceFromName("frontend")
		if not frontend or getResourceState(frontend) ~= "running" then return end
		CROSSHAIR_REGULAR_TEXTURE = exports.frontend:getPs2HudTexture(CROSSHAIR_REGULAR_TEXTURE_NAME)
		CROSSHAIR_CAMERA_TEXTURE = exports.frontend:getPs2HudTexture("viewfinder_128")
		CROSSHAIR_ROCKET_TEXTURE = exports.frontend:getPs2HudTexture("siterocket")
		CROSSHAIR_SNIPER_TEXTURE = exports.frontend:getPs2HudTexture("sitesniper")
		if not isElement(CROSSHAIR_REGULAR_TEXTURE) then return end
		initCrosshairRegular()
	end

	local weapon = getPedWeapon(localPlayer)

	if weapon == 34 then return drawCrosshairSniper() end
	if weapon == 35 or weapon == 36 then return drawCrosshairRocket() end
	if weapon == 43 then return drawCrosshairCamera() end
	return drawCrosshairRegular()
end


------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

local function initCrosshair()
	addEventHandler("onClientHUDRender", root, drawCrosshair)

	return true
end

local function termCrosshair()

	setPlayerHudComponentVisible("crosshair", not getElementData(root, "leeds_engine:reloading", false))

	return true
end

addEventHandler("onClientResourceStart", resourceRoot, initCrosshair)
addEventHandler("onClientResourceStop", resourceRoot, termCrosshair)

