local camera = getCamera()
local originalRadarVisibility, originalRadarControl
local reloadSnapshot = "leeds_engine:radarHud"


------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------


local SCREEN_WIDTH, SCREEN_HEIGHT = guiGetScreenSize()
local FONT_PATH = "font/"
local FONT_QUALITY = "antialiased"

-- SLUS_215.90 radar tile projection at 0x00117AF8: x/500+4, 4-y/500.
local MAP_WORLD_SIZE = 4000
local MAP_WORLD_SIZE_HALF = MAP_WORLD_SIZE / 2
local MAP_TILES_SIZE = 8
local MAP_TILES_SIZE_HALF = MAP_TILES_SIZE / 2
local MAP_TILE_WORLD_SIZE = MAP_WORLD_SIZE / MAP_TILES_SIZE
local MAP_TILE_COLOR = tocolor(255, 255, 255, 255)
local MAP_TILE_INTERIOR_COLOR = tocolor(0, 0, 0, 0)

local RADAR_RECTANGLE = false
local radarScreenX, radarScreenY, radarScreenWidth, radarScreenHeight
-- Keep the map and mask in a square render target. Apply the VCSPC screen rectangle at draw time.
local RADAR_HEIGHT = math.max(1, math.floor(99.2 * math.min(SCREEN_WIDTH / 640, SCREEN_HEIGHT / 480) + 0.5))
local RADAR_WIDTH = RADAR_RECTANGLE and RADAR_HEIGHT * (3 / 2) or RADAR_HEIGHT
local RADAR_TILES_RT_SIZE = RADAR_RECTANGLE and getDistanceBetweenPoints2D(0, 0, RADAR_WIDTH, RADAR_HEIGHT) or RADAR_HEIGHT
local radarScaleX, radarScaleY
local RADAR_COLOR = tocolor(255, 255, 255, 255)
local RADAR_BORDER_WIDTH = RADAR_HEIGHT / 24
local RADAR_BORDER_FADING = 2
local RADAR_BORDER_COLOR = tocolor(0, 0, 0, 255)

local RADAR_MAP_MASK_OFFSET = RADAR_HEIGHT * 4 / 64
local RADAR_MAP_MASK_FADING = 2
-- world radius (or height) of radar
local RADAR_MAP_MIN_RANGE = 180.0                                            -- Radar.cpp: RADAR_MIN_RANGE
local RADAR_MAP_MAX_RANGE = 350.0                                            -- Radar.cpp: RADAR_MAX_RANGE
local RADAR_MAP_MIN_RANGE_SPEED = 0.3                                        -- Radar.cpp: RADAR_MIN_SPEED
local RADAR_MAP_MAX_RANGE_SPEED = 0.9                                        -- Radar.cpp: RADAR_MAX_SPEED
local RADAR_MAP_DRAW_TILES_RADIUS = math.ceil(RADAR_MAP_MAX_RANGE * (RADAR_TILES_RT_SIZE / RADAR_HEIGHT) / MAP_TILE_WORLD_SIZE)
local RADAR_MAP_SHOW_IN_INTERIOR = false

local RING_PLANE_SPRITE_SCALE = 0.22
local ARTIFICIAL_HORIZON_SKY_COLOR = tocolor(0, 0, 0, 0)
local ARTIFICIAL_HORIZON_GROUND_COLOR = tocolor(20, 175, 20, 200)
local ALTIMETER_BG_COLOR = tocolor(10, 10, 10, 100)
local ALTIMETER_BG_WIDTH = RADAR_HEIGHT / 16
local ALTIMETER_BG_HEIGHT = RADAR_HEIGHT - (RADAR_BORDER_WIDTH * 2)
local ALTIMETER_COLOR = tocolor(200, 200, 200, 255)
local ALTIMETER_WIDTH = ALTIMETER_BG_WIDTH * 2
local ALTIMETER_HEIGHT = ALTIMETER_WIDTH / 16
local ALTIMETER_WORLD_HEIGHT_MAX = 950
local ALTIMETER_WORLD_HEIGHT_LOW = 200

local RADAR_BLIP_COLOR_ENABLED = false
local RADAR_BLIP_SIZE = RADAR_WIDTH * 18 / 99.2
local RADAR_BLIP_SIZE_GTASA_DEFAULT = 2
local RADAR_BLIP_ALPHA_MULTIPLIER = 1
local RADAR_BLIP_VECTOR_OFFSET = RADAR_MAP_MASK_OFFSET
local RADAR_BLIP_CENTRE_SIZE_MULTIPLIER = 17 / 18
local RADAR_BLIP_TRACE_SIZE_MULTIPLIER = 0.6
local RADAR_BLIP_TRACE_LOW_HEIGHT_DIFF = -4.0
local RADAR_BLIP_TRACE_HIGH_HEIGHT_DIFF = 2

local RADAR_TILES_RT_INTERVAL = 1000 / 60
local RADAR_BLIP_CACHE_INTERVAL = 1000 / 30
local RADAR_AREA_CACHE_INTERVAL = 1000 / 10

-- F11 map
local BIGMAP_ENABLED = true
local BIGMAP_CURSOR_ENABLED = false
local BIGMAP_CURSOR_SWITCHABLE = true
local BIGMAP_WAYPOINT_ENABLED = BIGMAP_CURSOR_SWITCHABLE or BIGMAP_CURSOR_ENABLED
local BIGMAP_ATTACH_TO_PLAYER = true
local BIGMAP_HIDE_CHAT = true
local BIGMAP_POST_GUI = false
local BIGMAP_SIZE = math.max(SCREEN_WIDTH, SCREEN_HEIGHT)
local BIGMAP_ZOOM_SCALE_MAX = 4
local BIGMAP_ZOOM_SCALE_MIN = 0.9
local BIGMAP_ZOOM_SCALE_STEP = 0.05
local BIGMAP_ZOOM_SCALE_DEFAULT = 1
local BIGMAP_CHANGE_OPACITY_STEP = 0.05
local BIGMAP_OPACITY_DEFAULT = 0.6
local BIGMAP_MOVE_STEP = math.min(SCREEN_WIDTH, SCREEN_HEIGHT) / 20
local BIGMAP_BLIP_HERE_SIZE = 6
local BIGMAP_SOUND_ENABLED = false
local BIGMAP_SHOW_SOUND_ID = 1
local BIGMAP_HIDE_SOUND_ID = 2
local BIGMAP_SET_WAYPOINT_SOUND_ID = 1
local BIGMAP_REMOVE_WAYPOINT_SOUND_ID = 2

local BIGMAP_TEXT_WINDOW_BG_COLOR = tocolor(0, 0, 0, 190)
local BIGMAP_TEXT_WINDOW_CONTENT_MARGIN = 10

local BIGMAP_HELP_TEXT_COLOR = tocolor(241, 241, 241, 255)
local BIGMAP_HELP_TEXT_FONT = dxCreateFont(FONT_PATH .. "sabankgothic.ttf", 14, false, FONT_QUALITY)

local BIGMAP_LEGEND_ENABLED = true
local BIGMAP_LEGEND_COLUMNS = 3
local BIGMAP_LEGEND_TEXT_COLOR = tocolor(172, 203, 241, 255)
local BIGMAP_LEGEND_TEXT_FONT = dxCreateFont(FONT_PATH .. "sabankgothic.ttf", 16, false, FONT_QUALITY)

local BIGMAP_SWITCH_COMMAND = "vcsmap"
local BIGMAP_ZOOM_IN_COMMAND = "radar_zoom_in"
local BIGMAP_ZOOM_OUT_COMMAND = "radar_zoom_out"
local BIGMAP_OPACITY_UP_COMMAND = "radar_opacity_up"
local BIGMAP_OPACITY_DOWN_COMMAND = "radar_opacity_down"
local BIGMAP_MOVE_NORTH_COMMAND = "radar_move_north"
local BIGMAP_MOVE_SOUTH_COMMAND = "radar_move_south"
local BIGMAP_MOVE_EAST_COMMAND = "radar_move_east"
local BIGMAP_MOVE_WEST_COMMAND = "radar_move_west"
local BIGMAP_SWITCH_HELP_COMMAND = "radar_help"
local BIGMAP_SWITCH_LEGEND_KEY = "l"
local BIGMAP_SWITCH_CURSOR_KEY = "mouse3"
local BIGMAP_MOVE_MOUSE_KEY = "mouse1"
local BIGMAP_SET_WAYPOINT_KEY = "mouse2"
local BIGMAP_ZOOM_IN_MOUSE_KEY = "mouse_wheel_up"
local BIGMAP_ZOOM_OUT_MOUSE_KEY = "mouse_wheel_down"
local BIGMAP_WAYPOINT_REMOVE_DISTANCE = 50


------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------


local drawData = {}

drawData.mapTileTextures = {}                    -- Radar.cpp: std::array<std::array<int32, MAX_RADAR_WIDTH_TILES>, MAX_RADAR_HEIGHT_TILES>& gRadarTextures
drawData.hudSpriteTextures = {}                  -- Hud.h: CSprite2d (&Sprites)[6]
drawData.radarSpriteTextures = {}                -- Radar.h: std::array<CSprite2d, MAX_RADAR_SPRITES>& RadarBlipSprites

drawData.areRenderTargetsReady = false
drawData.radarCircleShader = dxCreateShader("circle.fx")
drawData.radarShader = dxCreateShader("radar.fx")
drawData.radarMapTilesRt = dxCreateRenderTarget(RADAR_TILES_RT_SIZE, RADAR_TILES_RT_SIZE, true)
drawData.radarArtificialHorizonRt = dxCreateRenderTarget(RADAR_WIDTH, RADAR_HEIGHT, true)
drawData.radarMapMaskRt = dxCreateRenderTarget(RADAR_WIDTH, RADAR_HEIGHT, true, "a8") -- alpha only
drawData.radarBorderRt = dxCreateRenderTarget(RADAR_WIDTH, RADAR_HEIGHT, true)

drawData.cursorPrevPos = { 0, 0 }
drawData.cursorCurrPos = { 0, 0 }
drawData.cursorOnGui = false

drawData.playerElement = nil
drawData.playerElementMatrix = nil                -- Radar.h: CVector2D& vec2DRadarOrigin
drawData.playerCameraAngle = 0                    -- Radar.h: float& m_fRadarOrientation
drawData.playerInterior = nil
drawData.hasIndoorProfile = false
drawData.playerDimension = nil
drawData.flashingRadarAreaAlphaMultiplier = 0

drawData.showRadar = true
drawData.radarMapRtView = nil
drawData.radarMapRtRotView = nil                  -- Radar.h: float& cachedCos; float& cachedSin
drawData.radarTilesRtTicks = getTickCount() - RADAR_TILES_RT_INTERVAL * 2
drawData.radarBlipCacheTicks = getTickCount() - RADAR_BLIP_CACHE_INTERVAL * 2
drawData.radarAreaCacheTicks = getTickCount() - RADAR_AREA_CACHE_INTERVAL * 2

drawData.showBigMap = false
drawData.showBigMapHelp = true
drawData.showBigMapLegend = false
drawData.bigMapWasMoved = false
drawData.bigMapAlphaMultiplier = BIGMAP_OPACITY_DEFAULT
drawData.bigMapDrawnSprites = {}
drawData.bigMapScreenViewTransform = transform2.scale(BIGMAP_ZOOM_SCALE_DEFAULT, BIGMAP_ZOOM_SCALE_DEFAULT)
drawData.bigMapScreenViewResult = transform2.move(0, 0)
drawData.bigMapCursorEnabled = BIGMAP_CURSOR_ENABLED

drawData.waypointBlip = nil


------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

local TEXT = TEXT
local RADAR_SPRITE_TEXT = RADAR_SPRITE_TEXT

local math_sqrt = math.sqrt
local math_floor = math.floor
local math_abs = math.abs

local getElementPosition = getElementPosition
local getElementDimension = getElementDimension
local getElementInterior = getElementInterior
local dxDrawImage = dxDrawImage
local dxDrawRectangle = dxDrawRectangle
local tocolor = tocolor

local function math_clamp(value, min, max)

	return value < min and min or value > max and max or value
end

local function fromcolor(color)

	return
	bitExtract(color, 16, 8),
	bitExtract(color, 8, 8),
	bitExtract(color, 0, 8),
	bitExtract(color, 24, 8)
end

-- same as matrix multiplication but ignoring result rotation
local function getPositionFromMatrixOffset2D(m, x, y)

	local m1 = m[1]
	local m2 = m[2]
	local m3 = m[3]

	return
	x * m1[1] + y * m2[1] + m3[1],
	x * m1[2] + y * m2[2] + m3[2]
end

local function getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2)

	local dx = x2 - x1
	local dy = y2 - y1
	local dz = z2 - z1

	return math_sqrt(dx * dx + dy * dy + dz * dz)
end

local function getDistanceBetweenPoints2D(x1, y1, x2, y2)

	local dx = x2 - x1
	local dy = y2 - y1

	return math_sqrt(dx * dx + dy * dy)
end

local function getCursorAbsolutePosition()

	local cx, cy = getCursorPosition()
	return cx and (SCREEN_WIDTH * cx), cy and (SCREEN_HEIGHT * cy)
end

local function getVehicleRealType(vehicle)

	-- defines "Vortex" model as custom "Hovercraft" type (instead of "Plane" type)
	if getElementModel(vehicle) == 539 then
		return VEHICLE_REAL_TYPE.HOVERCRAFT
	end

	return getVehicleType(vehicle)
end

local function getVcsBlipIcon(blip)
    local name = getElementData(blip, "mradar:vcsIcon")
    if MRADAR_VCS_ICONS[name] then return name end
    local id = getBlipIcon(blip)
    return RADAR_SPRITE_TEXTURE_NAMES[id] and id or RADAR_SPRITE.NONE
end

local function getVisibleBlipsData(x, y, int, dim)

	local data = {}
	local number = 0

	for _, blip in ipairs(getElementsByType("blip")) do

		local bx, by, bz = getElementPosition(blip)
		local dis = getBlipVisibleDistance(blip)
		if (math_abs(bx - x) <= dis) and (math_abs(by - y) <= dis) then

			if (getElementInterior(blip) == int)
				and (getElementDimension(blip) == dim)
				and getDistanceBetweenPoints2D(x, y, bx, by) <= dis
				and not (getElementAttachedTo(blip) == localPlayer) then

				number = number + 1
				data[number] = {
					pos = { bx, by, bz },
					size = getBlipSize(blip),
					icon = getVcsBlipIcon(blip),
					shortRange = getElementData(blip, "mradar:shortRange", false) == true,
					color = { getBlipColor(blip) },
					ordering = getBlipOrdering(blip)
				}

			end

		end
	end

	if number <= 1 then return data end

	table.sort(data, function(a, b) return a.ordering < b.ordering end)

	return data
end

function dxDrawTextWithShadow(text, x, y, rightX, bottomY, color, scaleXY, scaleY, font, ...)

	x = math_floor(x)
	y = math_floor(y)

	local off = math_floor(dxGetFontHeight(scaleY or scaleXY, font) / 1.75 / 6)
	dxDrawText(text, x + off, y + off, rightX, bottomY, tocolor(0, 0, 0, 255), scaleXY, scaleY, font, ...)
	dxDrawText(text, x, y, rightX, bottomY, color, scaleXY, scaleY, font, ...)
end

local function dxDrawCircle(x, y, size, innerRadius, outerRadius, innerFading, outerFading, color)

	innerRadius = innerRadius or 0
	outerRadius = outerRadius or size / 2
	innerFading = math.max(innerFading or 2, 2)
	outerFading = math.max(outerFading or 2, 2)
	color = color or tocolor(255, 255, 255, 255)

	if innerRadius >= outerRadius then return false end

	dxSetShaderValue(drawData.radarCircleShader, "fInnerRadius", innerRadius / size)
	dxSetShaderValue(drawData.radarCircleShader, "fOuterRadius", outerRadius / size)
	dxSetShaderValue(drawData.radarCircleShader, "fInnerFading", innerFading / size)
	dxSetShaderValue(drawData.radarCircleShader, "fOuterFading", outerFading / size)

	return dxDrawImage(
		x,
		y,
		size,
		size,
		drawData.radarCircleShader,
		0, 0, 0,
		color
	)
end

local function dxDrawRectangleBorder(x, y, width, height, border, color)

	dxDrawRectangle(
		x, y,
		width, border,
		color
	)
	dxDrawRectangle(
		x, y + height - border,
		width, border,
		color
	)
	dxDrawRectangle(
		x, y + border,
		border, height - (border * 2),
		color
	)
	dxDrawRectangle(
		x + width - border, y + border,
		border, height - (border * 2),
		color
	)
	return true
end

------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------


-- CRadar::TransformRadarPointToScreenSpace(CVector2D& out, const CVector2D& in) // 0x583480
local function transformWorldToRadarMapRtView(x, y)

	return getPositionFromMatrixOffset2D(drawData.radarMapRtView, x, y)
end

-- Radar.cpp: CRadar::LoadTextures() // 0x5827D0
-- Hud.cpp: CHud::Initialise() // 0x5BA850
local loadedRadarTile
local function loadTexturesRadar()

	for id, name in pairs(RADAR_SPRITE_TEXTURE_NAMES) do
		drawData.radarSpriteTextures[id] = exports.frontend:getPs2HudTexture(name)
	end

	for name in pairs(MRADAR_VCS_ICONS) do
		drawData.radarSpriteTextures[name] = exports.frontend:getPs2HudTexture(name)
	end

	for id, name in pairs(HUD_SPRITE_TEXTURE_NAMES) do
		drawData.hudSpriteTextures[id] = exports.frontend:getPs2HudTexture(name)
	end

	for y = 0, MAP_TILES_SIZE - 1 do
		drawData.mapTileTextures[y] = {}
		for x = 0, MAP_TILES_SIZE - 1 do
			local name = ("radar%02d"):format(y * MAP_TILES_SIZE + x)
			local texture = exports.frontend:getPs2HudTexture(name)
			if not texture then return false end
			drawData.mapTileTextures[y][x] = texture
		end
	end

	loadedRadarTile = drawData.mapTileTextures[0][0]
	return true
end

-- Radar.cpp: CRadar::DrawMap() // 0x586B00
local function calcRadarMapRange(element, matrix)

	if getElementType(element) ~= "vehicle" then return RADAR_MAP_MIN_RANGE end

	local speed = 0
	if getVehicleRealType(element) == VEHICLE_REAL_TYPE.PLANE then
		-- actually this is height ratio, not speed
		speed = matrix[4][3] / ALTIMETER_WORLD_HEIGHT_LOW
	else
		local vx, vy, vz = getElementVelocity(element)
		speed = getDistanceBetweenPoints3D(0, 0, 0, vx, vy, vz)
	end

	if speed < RADAR_MAP_MIN_RANGE_SPEED then
		return RADAR_MAP_MIN_RANGE -- original plane's min range value is (RADAR_MAX_RANGE - 10.0)
	end
	if speed >= RADAR_MAP_MAX_RANGE_SPEED then
		return RADAR_MAP_MAX_RANGE
	end

	return (speed - RADAR_MAP_MIN_RANGE_SPEED)
		/ (RADAR_MAP_MAX_RANGE_SPEED - RADAR_MAP_MIN_RANGE_SPEED)
		* (RADAR_MAP_MAX_RANGE - RADAR_MAP_MIN_RANGE)
		+ RADAR_MAP_MIN_RANGE
end

local function prepareRadarMaskRt()

	dxSetRenderTarget(drawData.radarMapMaskRt, true)
	dxSetBlendMode("overwrite")

	if RADAR_RECTANGLE then

		dxDrawRectangle(
			RADAR_MAP_MASK_OFFSET,
			RADAR_MAP_MASK_OFFSET,
			RADAR_WIDTH - RADAR_MAP_MASK_OFFSET * 2,
			RADAR_HEIGHT - RADAR_MAP_MASK_OFFSET * 2,
			tocolor(255, 255, 255, 255)
		)

	else

		dxDrawCircle(
			0,
			0,
			RADAR_HEIGHT,
			0,
			RADAR_HEIGHT / 2 - RADAR_MAP_MASK_OFFSET,
			0,
			RADAR_MAP_MASK_FADING,
			tocolor(255, 255, 255, 255))
	end

	dxSetRenderTarget()
	dxSetBlendMode("blend")

	dxSetShaderValue(drawData.radarShader, "gMaskTexture", drawData.radarMapMaskRt)

	return true
end

local function prepareRadarBorderRt()

	dxSetRenderTarget(drawData.radarBorderRt, true)
	dxSetBlendMode("overwrite")

	if RADAR_RECTANGLE then
		dxDrawRectangleBorder(
			0,
			0,
			RADAR_WIDTH,
			RADAR_HEIGHT,
			RADAR_BORDER_WIDTH,
			RADAR_BORDER_COLOR)

	else
		dxDrawImage(0, 0, RADAR_WIDTH, RADAR_HEIGHT, drawData.hudSpriteTextures[HUD_SPRITE.RADAR_DISC])
	end

	dxSetRenderTarget()
	dxSetBlendMode("blend")

	dxSetShaderValue(drawData.radarShader, "gBorderTexture", drawData.radarBorderRt)

	return true
end

-- Radar.h: IsMapSectionInBounds(int32 x, int32 y)
local function isMapTileInBounds(x, y)

	return x >= 0 and x < MAP_TILES_SIZE and y >= 0 and y < MAP_TILES_SIZE;
end

-- Radar.cpp: CRadar::DrawRadarSection(int32 x, int32 y) // 0x586110
local function drawRadarMapTile(tx, ty)

	-- Radar.cpp: GetTextureCorners(int32 x, int32 y, CVector2D* corners) // 0x584D90
	-- Top left tile world corner
	local wx = MAP_TILE_WORLD_SIZE * (tx - MAP_TILES_SIZE_HALF)
	local wy = MAP_TILE_WORLD_SIZE * (MAP_TILES_SIZE_HALF - ty)

	-- Move by player position and scale
	local rtx, rty = transformWorldToRadarMapRtView(wx, wy)
	local rtx2, rty2 = transformWorldToRadarMapRtView(wx + MAP_TILE_WORLD_SIZE, wy - MAP_TILE_WORLD_SIZE)

	if RADAR_MAP_SHOW_IN_INTERIOR or (drawData.playerInterior == 0 and not drawData.hasIndoorProfile) then

		if isMapTileInBounds(tx, ty) then

			dxDrawImage(
				rtx, rty,
				rtx2 - rtx, rty2 - rty,
				drawData.mapTileTextures[ty][tx],
				0, 0, 0,
				MAP_TILE_COLOR
			)
		else

			-- as sea draws first pixel of top left tile
			dxDrawImageSection(
				rtx, rty,
				rtx2 - rtx, rty2 - rty,
				0, 0, 1, 1,
				drawData.mapTileTextures[0][0],
				0, 0, 0,
				MAP_TILE_COLOR
			)
		end

	else

		dxDrawRectangle(
			rtx, rty,
			rtx2 - rtx, rty2 - rty,
			MAP_TILE_INTERIOR_COLOR,
			false,
			true
		)
	end

	return true
end

local function drawRadarMapTiles()

	local x = math_floor((drawData.playerElementMatrix[4][1] + MAP_WORLD_SIZE_HALF) / MAP_TILE_WORLD_SIZE)
	local y = math_floor((MAP_WORLD_SIZE_HALF - drawData.playerElementMatrix[4][2]) / MAP_TILE_WORLD_SIZE)

	dxSetRenderTarget(drawData.radarMapTilesRt, true)
	dxSetBlendMode("modulate_add")

	for dy = -RADAR_MAP_DRAW_TILES_RADIUS, RADAR_MAP_DRAW_TILES_RADIUS do
		for dx = -RADAR_MAP_DRAW_TILES_RADIUS, RADAR_MAP_DRAW_TILES_RADIUS do
			drawRadarMapTile(x + dx, y + dy);
		end
	end

	dxSetBlendMode("blend")
	dxSetRenderTarget()

	return true
end

local function calcFlashingRadarAreaAlphaMultiplier()

	return (math.sin((getTickCount() % 1024) / (1024 / (math.pi * 2))) + 1.0) / 2.0
end

local function drawRadarArea(data)

	local x1, y1 = transformWorldToRadarMapRtView(data.pos[1], data.pos[2] + data.size[2])
	local x2, y2 = transformWorldToRadarMapRtView(data.pos[1] + data.size[1], data.pos[2])
	local a = data.color[4]
	if data.flashing then
		a = a * drawData.flashingRadarAreaAlphaMultiplier
	end

	dxDrawRectangle(
		x1, y1,
		x2 - x1, y2 - y1,
		tocolor(data.color[1], data.color[2], data.color[3], a),
		false,
		true
	)

	return true
end

local function getVisibleRadarAreasData(x, y, width, height, int, dim)

	local list = {}
	local number = 0

	for _, area in ipairs(getElementsByType("radararea")) do

		local ax, ay, _ = getElementPosition(area)
		if (ax <= x + width) and (ay <= y + height) then

			local aw, ah = getRadarAreaSize(area)
			if (ax + aw >= x) and (ay + ah >= y) then

				if (getElementDimension(area) == dim) and (getElementInterior(area) == int) then

					number = number + 1
					list[number] = {
						pos = { ax, ay },
						size = { aw, ah },
						color = { getRadarAreaColor(area) },
						flashing = isRadarAreaFlashing(area) }

				end

			end

		end
	end

	return list
end

-- Radar.cpp: CRadar::DrawRadarGangOverlay(bool inMenu) // 0x586650
local function drawRadarAreas()

	dxSetRenderTarget(drawData.radarMapTilesRt)
	dxSetBlendMode("modulate_add")

	if (getTickCount() - drawData.radarAreaCacheTicks) > RADAR_AREA_CACHE_INTERVAL then

		-- drawData.radarMapRange is radar world height, we need tiles RT world size
		local range = drawData.radarMapRange * (RADAR_TILES_RT_SIZE / RADAR_HEIGHT)
		drawData.radarAreaCache = getVisibleRadarAreasData(
			drawData.playerElementMatrix[4][1] - range,
			drawData.playerElementMatrix[4][2] - range,
			range * 2,
			range * 2,
			drawData.playerInterior,
			drawData.playerDimension)
		drawData.radarAreaCacheTicks = getTickCount()
	end

	for i, data in ipairs(drawData.radarAreaCache) do
		drawRadarArea(data)
	end

	dxSetBlendMode("blend")
	dxSetRenderTarget()

	return true
end

local function drawArtificialHorizon()

	dxSetRenderTarget(drawData.radarArtificialHorizonRt, true)
	dxSetBlendMode("overwrite")

	dxDrawRectangle(
		0, 0,
		RADAR_WIDTH, RADAR_HEIGHT / 2,
		ARTIFICIAL_HORIZON_SKY_COLOR,
		false,
		true
	)
	dxDrawRectangle(
		0, RADAR_HEIGHT / 2,
		RADAR_WIDTH, RADAR_HEIGHT / 2,
		ARTIFICIAL_HORIZON_GROUND_COLOR,
		false,
		true
	)

	dxSetRenderTarget()
	dxSetBlendMode("blend")

	dxSetShaderValue(drawData.radarShader, "gArtificialHorizonTexture", drawData.radarArtificialHorizonRt)

	return true
end

local function drawAltimeter()

	if getElementType(drawData.playerElement) ~= "vehicle" then return true end

	local vehicleRealType = getVehicleRealType(drawData.playerElement)
	if not (vehicleRealType == VEHICLE_REAL_TYPE.PLANE or vehicleRealType == VEHICLE_REAL_TYPE.HELICOPTER) then return true end
	local backgroundWidth = ALTIMETER_BG_WIDTH * radarScaleX
	local backgroundHeight = ALTIMETER_BG_HEIGHT * radarScaleY
	local backgroundX = radarScreenX - backgroundWidth * 3
	local backgroundY = radarScreenY + (radarScreenHeight - backgroundHeight) / 2
	local markerWidth = ALTIMETER_WIDTH * radarScaleX

	dxDrawRectangle(
		backgroundX, backgroundY,
		backgroundWidth, backgroundHeight,
		ALTIMETER_BG_COLOR,
		false,
		true
	)

	local height = drawData.playerElementMatrix[4][3]
	local limit = ALTIMETER_WORLD_HEIGHT_MAX
	if height <= ALTIMETER_WORLD_HEIGHT_LOW then
		limit = ALTIMETER_WORLD_HEIGHT_LOW
	end

	dxDrawRectangle(
		backgroundX + (backgroundWidth - markerWidth) / 2,
		backgroundY + backgroundHeight * (math_clamp(1 - height / limit, 0, 1)),
		markerWidth,
		ALTIMETER_HEIGHT * radarScaleY,
		ALTIMETER_COLOR,
		false,
		true
	)

	return true
end

local function drawRadarShader()

	-- TODO: move scaling by speed into shader (?)
	dxSetShaderValue(drawData.radarShader, "gTilesTexture", drawData.radarMapTilesRt)
	dxSetShaderValue(drawData.radarShader, "gTilesRot", -drawData.playerCameraAngle)

	dxSetShaderValue(drawData.radarShader, "gPlane", drawData.playerInPlane)
	if drawData.playerInPlane then
		-- TODO: move matrix into shader (?)
		dxSetShaderValue(drawData.radarShader, "gRingPlaneRot", math.atan2(drawData.playerElementMatrix[1][3], drawData.playerElementMatrix[3][3]))
		dxSetShaderValue(drawData.radarShader, "gArtificialHorizonRatio", math.atan2(drawData.playerElementMatrix[2][3], drawData.playerElementMatrix[3][3]) / math.pi / 2)
	end

	return dxDrawImage(
		radarScreenX,
		radarScreenY,
		radarScreenWidth,
		radarScreenHeight,
		drawData.radarShader,
		0, 0, 0,
		RADAR_COLOR
	)
end

-- Radar.cpp: CRadar::LimitRadarPoint(CVector2D& point) // 0x5832F0
local function limitVectorLength(x1, y1, x2, y2, limit)

	local length = getDistanceBetweenPoints2D(x1, y1, x2, y2)
	if length > limit then
		local k = limit / length
		x2, y2 = (x2 - x1) * k + x1, (y2 - y1) * k + y1
	end

	return x2, y2
end

local function limitVectorLengthRectangle(x1, y1, x2, y2, xl, yl)

	local x = x2 - x1
	local y = y2 - y1

	local k = math.min(
		math.min(1, math.abs(xl / x)),
		math.min(1, math.abs(yl / y)))

	return x * k + x1, y * k + y1
end

-- Radar.cpp: GetRadarAndScreenPos(float* radarPointDist)
-- Radar.h: CachedRotateClockwise(const CVector2D& point)
local function transformWorldToRadarMapBlipView(x, y)

	x, y = getPositionFromMatrixOffset2D(drawData.radarMapRtRotView, x, y)

	if RADAR_RECTANGLE then
		return limitVectorLengthRectangle(
			RADAR_WIDTH / 2,
			RADAR_HEIGHT / 2,
			x,
			y,
			RADAR_WIDTH / 2 - RADAR_BLIP_VECTOR_OFFSET,
			RADAR_HEIGHT / 2 - RADAR_BLIP_VECTOR_OFFSET) end

	return limitVectorLength(
		RADAR_HEIGHT / 2,
		RADAR_HEIGHT / 2,
		x,
		y,
		RADAR_HEIGHT / 2 - RADAR_BLIP_VECTOR_OFFSET)
end

local function getRadarSpriteBlipTraceFromHeight(z)

	local diff = z - drawData.playerElementMatrix[4][3]
	if diff > RADAR_BLIP_TRACE_HIGH_HEIGHT_DIFF then return RADAR_TRACE.HIGH end
	if diff < RADAR_BLIP_TRACE_LOW_HEIGHT_DIFF then return RADAR_TRACE.LOW; end
	return RADAR_TRACE.NORMAL
end

local function getRadarSpriteBlipSize(spriteId, size)

	size = size / RADAR_BLIP_SIZE_GTASA_DEFAULT * RADAR_BLIP_SIZE

	if spriteId == RADAR_SPRITE.CENTRE then return size * RADAR_BLIP_CENTRE_SIZE_MULTIPLIER end
	return size
end

local function drawRadarTrace(x, y, z, r, g, b, a, traceSize, scale, postGUI, squareFillScale)
	local shape = getRadarSpriteBlipTraceFromHeight(z)
	local border, ink = tocolor(0, 0, 0, a), tocolor(r, g, b, a)
	if shape == RADAR_TRACE.NORMAL then
		-- Scale the colored square and its outline in screen space.
		local fill = traceSize * scale * squareFillScale
		local radius = fill + scale
		local size = 2 * radius
		dxDrawRectangle(x - radius, y - radius, size, size, border, postGUI)
		return dxDrawRectangle(x - fill, y - fill, 2 * fill, 2 * fill, ink, postGUI)
	end
	local radius = traceSize / RADAR_BLIP_SIZE_GTASA_DEFAULT * 18 * RADAR_BLIP_TRACE_SIZE_MULTIPLIER * scale / 2
	local fill = math.max(0, radius - 1)
	local direction = shape == RADAR_TRACE.LOW and -1 or 1
	dxDrawPrimitive("trianglelist", postGUI, {x, y + direction * radius, border},
		{x - radius, y - direction * radius, border}, {x + radius, y - direction * radius, border})
	return dxDrawPrimitive("trianglelist", postGUI, {x, y + direction * fill, ink},
		{x - fill, y - direction * fill, ink}, {x + fill, y - direction * fill, ink})
end

-- Radar.cpp: CRadar::DrawRadarSprite(eRadarSprite spriteId, float x, float y, uint8 alpha) // 0x585FF0
local function drawRadarSprite(spriteId, x, y, z, r, g, b, a, size, rot)

	x, y = transformWorldToRadarMapBlipView(x, y)
	x = radarScreenX + x * radarScaleX
	y = radarScreenY + y * radarScaleY
	rot = rot and (math.deg(drawData.playerCameraAngle) - rot) or 0
	a = a * RADAR_BLIP_ALPHA_MULTIPLIER

	local texture = drawData.radarSpriteTextures[spriteId]
	if spriteId == RADAR_SPRITE.NONE then
		return drawRadarTrace(x, y, z, r, g, b, a, size, math.min(radarScreenWidth, radarScreenHeight) / 99.2, false, 2)
	end
	size = getRadarSpriteBlipSize(spriteId, size) * radarScaleX
	if not texture then return false end

	-- for CENTRE blip center is [0.5, 2/3]
	if spriteId == RADAR_SPRITE.CENTRE then

		dxDrawImage(
			x - (size / 2), y - (size * 2 / 3),
			size, size,
			texture,
			rot, 0, size * 1 / 6,
			tocolor(r, g, b, a)
		)
	else

		dxDrawImage(
			x - (size / 2), y - (size / 2),
			size, size,
			texture,
			rot, 0, 0,
			tocolor(r, g, b, a)
		)
	end

	return true
end

-- Radar.cpp: CRadar::DrawCoordBlip(int32 blipIndex, bool isSprite) // 0x586D60
local function drawRadarBlip(data)

	local r, g, b, a = data.color[1], data.color[2], data.color[3], data.color[4]
	if (not RADAR_BLIP_COLOR_ENABLED) and (data.icon ~= RADAR_SPRITE.NONE) then
		r, g, b = 255, 255, 255
	end

	drawRadarSprite(
		data.icon,
		data.pos[1], data.pos[2], data.pos[3],
		r, g, b, a,
		data.size);

	return true
end

-- Radar.cpp: CRadar::DrawBlips() // 0x588050
local function drawRadarBlips()

	drawRadarSprite(
		RADAR_SPRITE.NORTH,
		drawData.playerElementMatrix[4][1],
		drawData.playerElementMatrix[4][2] + MAP_WORLD_SIZE,
		drawData.playerElementMatrix[4][3],
		255, 255, 255, 255,
		RADAR_BLIP_SIZE_GTASA_DEFAULT)

	if (getTickCount() - drawData.radarBlipCacheTicks) > RADAR_BLIP_CACHE_INTERVAL then

		drawData.radarBlipCache = getVisibleBlipsData(
			drawData.playerElementMatrix[4][1],
			drawData.playerElementMatrix[4][2],
			drawData.playerInterior,
			drawData.playerDimension)
		drawData.radarBlipCacheTicks = getTickCount()
	end

	local player = drawData.playerElementMatrix[4]
	for _, blip in ipairs(drawData.radarBlipCache) do

		-- SCM short-range sprites don't pin to the edge while off the minimap.
		if not blip.shortRange or getDistanceBetweenPoints2D(
			player[1], player[2], blip.pos[1], blip.pos[2]) <= drawData.radarMapRange then
			drawRadarBlip(blip)
		end
	end

	if not drawData.playerInPlane then

		drawRadarSprite(
			RADAR_SPRITE.CENTRE,
			drawData.playerElementMatrix[4][1],
			drawData.playerElementMatrix[4][2],
			drawData.playerElementMatrix[4][3],
			255, 255, 255, 255,
			RADAR_BLIP_SIZE_GTASA_DEFAULT,
			math.deg(math.atan2(-drawData.playerElementMatrix[2][1], drawData.playerElementMatrix[2][2]))
		)
	end

	return true
end

local function updateRadarMapRtViews()

	-- Radar.h: float& m_radarRange (radar world radius)
	drawData.radarMapRange = calcRadarMapRange(drawData.playerElement, drawData.playerElementMatrix)

	local worldToRtRelView = transform2.mul(
		transform2.move(-drawData.playerElementMatrix[4][1], -drawData.playerElementMatrix[4][2]),
		transform2.scale(1 / drawData.radarMapRange, -1 / drawData.radarMapRange))

	drawData.radarMapRtView = transform2.mul(
		worldToRtRelView,
		transform2.mul(transform2.mul(
			transform2.move(1, 1),
			transform2.scale(RADAR_HEIGHT / 2, RADAR_HEIGHT / 2)),
			transform2.move((RADAR_TILES_RT_SIZE - RADAR_HEIGHT) / 2, (RADAR_TILES_RT_SIZE - RADAR_HEIGHT) / 2)))

	drawData.radarMapRtRotView = transform2.mul(transform2.mul(
		worldToRtRelView,
		transform2.rotate(drawData.playerCameraAngle)),
		transform2.mul(transform2.mul(
			transform2.move(1, 1),
			transform2.scale(RADAR_HEIGHT / 2, RADAR_HEIGHT / 2)),
			transform2.move((RADAR_WIDTH - RADAR_HEIGHT) / 2, 0)))

	return true
end

-- Hud.cpp: CHud::DrawRadar() // 0x58A330
local function drawRadar()

	setPlayerHudComponentVisible("radar", false)

	if not drawData.showRadar or not exports.frontend:isGameplayUiVisible() then return true end
	if drawData.showBigMap then return true end
	if isPlayerMapVisible() then return true end

	radarScreenX, radarScreenY, radarScreenWidth, radarScreenHeight = getVcsRadarRect(guiGetScreenSize())
	if RADAR_RECTANGLE then radarScreenWidth = radarScreenHeight * (3 / 2) end
	radarScaleX, radarScaleY = radarScreenWidth / RADAR_WIDTH, radarScreenHeight / RADAR_HEIGHT

	updateRadarMapRtViews()

	if not drawData.areRenderTargetsReady then
		prepareRadarMaskRt()
		prepareRadarBorderRt()
		drawArtificialHorizon()
		dxSetShaderValue(drawData.radarShader, "gTilesScale", RADAR_WIDTH / RADAR_TILES_RT_SIZE, RADAR_HEIGHT / RADAR_TILES_RT_SIZE)
		dxSetShaderValue(drawData.radarShader, "gRingPlaneTexture", drawData.hudSpriteTextures[HUD_SPRITE.RADAR_RING_PLANE])
		dxSetShaderValue(drawData.radarShader, "gRingPlaneScale", 1 / RING_PLANE_SPRITE_SCALE)
		drawData.areRenderTargetsReady = true
	end

	if (getTickCount() - drawData.radarTilesRtTicks) > RADAR_TILES_RT_INTERVAL then
		drawRadarMapTiles()
		drawRadarAreas()
		drawData.radarTilesRtTicks = getTickCount()
	end

	drawAltimeter()
	drawRadarShader()
	drawRadarBlips()

	return true
end

local function transformWorldToBigMapScreenView(x, y)

	return getPositionFromMatrixOffset2D(drawData.bigMapScreenViewResult, x, y)
end

local function transformBigMapScreenToWorld(screenX, screenY)

	local invMatrix = transform2.invert(drawData.bigMapScreenViewResult)
	if not invMatrix then return nil, nil end

	return getPositionFromMatrixOffset2D(invMatrix, screenX, screenY)
end

local function moveBigMap(x, y)

	drawData.bigMapScreenViewTransform = transform2.mul(
		drawData.bigMapScreenViewTransform,
		transform2.move(x, y))

	-- TODO: refactor
	local scale = drawData.bigMapScreenViewTransform[1][1]
	local bigMapSize = BIGMAP_SIZE * scale
	local bigMapSizeBordered = bigMapSize / BIGMAP_ZOOM_SCALE_MIN

	local x0 = (SCREEN_WIDTH - bigMapSize) / 2
	local y0 = (SCREEN_HEIGHT - bigMapSize) / 2

	local dx = math.max(0, (bigMapSizeBordered - SCREEN_WIDTH) / 2)
	local dy = math.max(0, (bigMapSizeBordered - SCREEN_HEIGHT) / 2)

	drawData.bigMapScreenViewTransform[3][1] = math_clamp(drawData.bigMapScreenViewTransform[3][1], x0 - dx, x0 + dx)
	drawData.bigMapScreenViewTransform[3][2] = math_clamp(drawData.bigMapScreenViewTransform[3][2], y0 - dy, y0 + dy)

	return true
end

local function updateBigMapCursorMoving()

	if not drawData.bigMapCursorEnabled then return end
	if not drawData.showBigMap then return end
	if not isCursorShowing() then return end
	if not getKeyState(BIGMAP_MOVE_MOUSE_KEY) then return end
	if guiGetInputEnabled() then return end
	if isMTAWindowActive() then return end
	if (not BIGMAP_POST_GUI) and drawData.cursorOnGui then return end

	drawData.bigMapWasMoved = true

	moveBigMap(
		drawData.cursorCurrPos[1] - drawData.cursorPrevPos[1],
		drawData.cursorCurrPos[2] - drawData.cursorPrevPos[2])

	return true
end

local function updateBigMapPlayerMoving()

	if not BIGMAP_ATTACH_TO_PLAYER then return end
	if not drawData.showBigMap then return end
	if drawData.bigMapWasMoved then return end

	local x, y = transformWorldToBigMapScreenView(drawData.playerElementMatrix[4][1], drawData.playerElementMatrix[4][2])
	moveBigMap(-x + SCREEN_WIDTH / 2, -y + SCREEN_HEIGHT / 2)

	return true
end

local function updateBigMapScreenView()

	drawData.bigMapScreenViewResult = transform2.mul(transform2.mul(transform2.mul(
		transform2.scale(1 / MAP_WORLD_SIZE, -1 / MAP_WORLD_SIZE),
		transform2.move(0.5, 0.5)),
		transform2.scale(BIGMAP_SIZE, BIGMAP_SIZE)),
		drawData.bigMapScreenViewTransform)

	return true
end

local function drawBigMapTiles()

	local sx1, sy1 = transformWorldToBigMapScreenView(-MAP_WORLD_SIZE_HALF, MAP_WORLD_SIZE_HALF)
	local sx2, sy2 = transformWorldToBigMapScreenView(MAP_WORLD_SIZE_HALF, -MAP_WORLD_SIZE_HALF)
	local size = (sx2 - sx1) / MAP_TILES_SIZE

	local r, g, b, a = fromcolor(MAP_TILE_COLOR)
	a = a * drawData.bigMapAlphaMultiplier
	local color = tocolor(r, g, b, a)

	for ty = 0, MAP_TILES_SIZE - 1 do
		for tx = 0, MAP_TILES_SIZE - 1 do

			dxDrawImage(
				sx1 + (tx * size), sy1 + (ty * size),
				size, size,
				drawData.mapTileTextures[ty][tx],
				0, 0, 0,
				color,
				BIGMAP_POST_GUI
			)
		end
	end

	local left = math.max(0, math.min(SCREEN_WIDTH, sx1))
	local right = math.max(0, math.min(SCREEN_WIDTH, sx2))
	local top = math.max(0, math.min(SCREEN_HEIGHT, sy1))
	local bottom = math.max(0, math.min(SCREEN_HEIGHT, sy2))
	local function drawSea(x, y, width, height)
		if width <= 0 or height <= 0 then return end
		dxDrawImageSection(x, y, width, height, 0, 0, 1, 1, drawData.mapTileTextures[0][0],
			0, 0, 0, color, BIGMAP_POST_GUI)
	end
	drawSea(0, 0, left, SCREEN_HEIGHT)
	drawSea(right, 0, SCREEN_WIDTH-right, SCREEN_HEIGHT)
	drawSea(left, 0, right-left, top)
	drawSea(left, bottom, right-left, SCREEN_HEIGHT-bottom)

	return true
end

local function drawBigMapRadarArea(area)

	local dim = getElementDimension(area)
	if dim ~= drawData.playerDimension then return false end

	local int = getElementInterior(area)
	if int ~= drawData.playerInterior then return false end

	local x, y, _ = getElementPosition(area)
	local width, height = getRadarAreaSize(area)

	local x1, y1 = transformWorldToBigMapScreenView(x, y + height)
	local x2, y2 = transformWorldToBigMapScreenView(x + width, y)
	local r, g, b, a = getRadarAreaColor(area)
	a = a * drawData.bigMapAlphaMultiplier
	if isRadarAreaFlashing(area) then
		a = a * drawData.flashingRadarAreaAlphaMultiplier
	end

	dxDrawRectangle(
		x1, y1,
		x2 - x1, y2 - y1,
		tocolor(r, g, b, a),
		BIGMAP_POST_GUI,
		true
	)

	return true
end

local function drawBigMapRadarAreas()

	for i, area in ipairs(getElementsByType("radararea")) do
		drawBigMapRadarArea(area)
	end

	return true
end

local function drawBigMapSprite(spriteId, x, y, z, r, g, b, a, size, rot)

	x, y = transformWorldToBigMapScreenView(x, y)
	rot = rot and (-rot) or 0
	a = a * drawData.bigMapAlphaMultiplier

	local texture = drawData.radarSpriteTextures[spriteId]
	if spriteId == RADAR_SPRITE.NONE then
		drawData.bigMapDrawnSprites[spriteId] = true
		return drawRadarTrace(x, y, z, r, g, b, a, size, RADAR_WIDTH / 99.2, BIGMAP_POST_GUI, 1)
	end
	size = getRadarSpriteBlipSize(spriteId, size)
	if not texture then return false end

	-- for MAP_HERE blip center is [0.5, 0.0]
	if spriteId == RADAR_SPRITE.MAP_HERE then

		dxDrawImage(
			x - (size / 2), y,
			size, size,
			texture,
			rot, 0, -size / 2,
			tocolor(r, g, b, a),
			BIGMAP_POST_GUI
		)
	else

		dxDrawImage(
			x - (size / 2), y - (size / 2),
			size, size,
			texture,
			rot, 0, 0,
			tocolor(r, g, b, a),
			BIGMAP_POST_GUI
		)
	end

	drawData.bigMapDrawnSprites[spriteId] = true

	return true
end

local function drawBigMapBlip(blip)

	local x, y, z = getElementPosition(blip)

	local icon = getVcsBlipIcon(blip)
	local r, g, b, a = getBlipColor(blip)
	if (not RADAR_BLIP_COLOR_ENABLED) and (icon ~= RADAR_SPRITE.NONE) then
		r, g, b = 255, 255, 255
	end

	drawBigMapSprite(icon, x, y, z, r, g, b, a, getBlipSize(blip));

	return true
end

local function drawBigMapBlips()

	--TODO: need sort by ordering?
	for _, blip in ipairs(getElementsByType("blip")) do
		if getElementInterior(blip) == drawData.playerInterior and getElementDimension(blip) == drawData.playerDimension then
			drawBigMapBlip(blip)
		end
	end

	drawBigMapSprite(
		RADAR_SPRITE.MAP_HERE,
		drawData.playerElementMatrix[4][1],
		drawData.playerElementMatrix[4][2],
		drawData.playerElementMatrix[4][3],
		255, 255, 255, 255 * (getTickCount() % 1000 < 700 and 1 or 0),
		BIGMAP_BLIP_HERE_SIZE,
		math.deg(math.atan2(-drawData.playerElementMatrix[2][1], drawData.playerElementMatrix[2][2]))
	)

	return true
end

local function getControlsKeys(controls)

	local keys = {}

	for i, control in ipairs(controls) do
		local t = getBoundKeys(control)
		if t then
			for key, state in pairs(t) do
				table.insert(keys, key)
			end
		end
	end

	table.sort(keys)

	return keys
end

local function drawBigMapHelp()

	if not drawData.showBigMapHelp then return false end

	local rows = {
		{ TEXT.HELP, table.concat(getControlsKeys({ BIGMAP_SWITCH_HELP_COMMAND }), " / ") },
		{ TEXT.LEGEND, BIGMAP_SWITCH_LEGEND_KEY },
		{ TEXT.ZOOM, table.concat(getControlsKeys({ BIGMAP_ZOOM_IN_COMMAND, BIGMAP_ZOOM_OUT_COMMAND }), " / ") },
		{ TEXT.MOVE, ((BIGMAP_CURSOR_SWITCHABLE or BIGMAP_CURSOR_ENABLED) and BIGMAP_MOVE_MOUSE_KEY .. " / " or "") .. table.concat(getControlsKeys({ BIGMAP_MOVE_NORTH_COMMAND, BIGMAP_MOVE_SOUTH_COMMAND, BIGMAP_MOVE_EAST_COMMAND, BIGMAP_MOVE_WEST_COMMAND }), " / ") },
		{ TEXT.OPACITY, table.concat(getControlsKeys({ BIGMAP_OPACITY_UP_COMMAND, BIGMAP_OPACITY_DOWN_COMMAND }), " / ") }
	}
	if BIGMAP_CURSOR_SWITCHABLE then rows[#rows + 1] = { TEXT.CURSOR, BIGMAP_SWITCH_CURSOR_KEY } end
	if BIGMAP_WAYPOINT_ENABLED then rows[#rows + 1] = { TEXT.WAYPOINT, BIGMAP_SET_WAYPOINT_KEY } end

	local actionTextWidth = 0
	local keysTextWidth = 0
	for i, row in ipairs(rows) do
		row[1] = row[1]
		row[2] = row[2]
		actionTextWidth = math.max(actionTextWidth, dxGetTextWidth(row[1], 1, BIGMAP_HELP_TEXT_FONT))
		keysTextWidth = math.max(keysTextWidth, dxGetTextWidth(row[2], 1, BIGMAP_HELP_TEXT_FONT))
	end

	local textHeight = dxGetFontHeight(1, BIGMAP_HELP_TEXT_FONT)
	local bgWidth = math_floor(actionTextWidth + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN * 2 + keysTextWidth + (BIGMAP_TEXT_WINDOW_CONTENT_MARGIN * 2))
	local bgHeight = math_floor(textHeight * #rows + (BIGMAP_TEXT_WINDOW_CONTENT_MARGIN * 2))
	local bgX = math_floor((SCREEN_WIDTH - bgWidth) / 2)
	local bgY = math_floor(SCREEN_HEIGHT - bgHeight - BIGMAP_TEXT_WINDOW_CONTENT_MARGIN)

	dxDrawRectangle(
		bgX, bgY,
		bgWidth, bgHeight,
		BIGMAP_TEXT_WINDOW_BG_COLOR,
		BIGMAP_POST_GUI,
		false
	)

	for i, row in ipairs(rows) do

		local x = bgX + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN
		local y = bgY + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN + ((i - 1) * textHeight)
		dxDrawTextWithShadow(
			row[1],
			x, y, nil, nil,
			BIGMAP_HELP_TEXT_COLOR,
			1, 1,
			BIGMAP_HELP_TEXT_FONT,
			nil,
			nil,
			nil,
			nil,
			BIGMAP_POST_GUI
		)

		x = x + actionTextWidth + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN * 2
		dxDrawTextWithShadow(
			row[2], x, y, nil, nil,
			BIGMAP_HELP_TEXT_COLOR,
			1, 1,
			BIGMAP_HELP_TEXT_FONT,
			nil,
			nil,
			nil,
			nil,
			BIGMAP_POST_GUI
		)
	end

	return true
end

local function collectBigMapLegendItems()

	local items = {}

	local icons = {}
	for icon, _ in pairs(drawData.bigMapDrawnSprites) do
		table.insert(icons, icon)
	end
	table.sort(icons, function(a, b) return tostring(a) < tostring(b) end)

	for _, icon in ipairs(icons) do
		local texture = drawData.radarSpriteTextures[icon]
		local name = MRADAR_VCS_ICONS[icon] or RADAR_SPRITE_TEXT[icon]
		if name and texture then
			table.insert(items, { texture, name })
		end
	end

	return items
end

local function drawBigMapLegend()

	if not BIGMAP_LEGEND_ENABLED then return false end
	if not drawData.showBigMapLegend then return false end

	local items = collectBigMapLegendItems()

	local columns = math.min(BIGMAP_LEGEND_COLUMNS, #items)
	local textWidth, textHeight = dxGetTextSize(string.rep("W", 15), 0, 1, 1, BIGMAP_LEGEND_TEXT_FONT)
	local itemHeight = textHeight + 5
	local iconSize = textHeight
	local itemWidth = iconSize + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN + textWidth

	local bgWidth = math_floor((columns * itemWidth) + (columns * BIGMAP_TEXT_WINDOW_CONTENT_MARGIN) + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN)
	local bgHeight = math_floor(itemHeight * math.ceil(#items / columns) + (BIGMAP_TEXT_WINDOW_CONTENT_MARGIN * 2))
	local bgX = math_floor((SCREEN_WIDTH - bgWidth) / 2)
	local bgY = math.min(bgX, math_floor((SCREEN_HEIGHT - bgHeight) / 2))

	dxDrawRectangle(
		bgX, bgY,
		bgWidth, bgHeight,
		BIGMAP_TEXT_WINDOW_BG_COLOR,
		BIGMAP_POST_GUI,
		false
	)

	for i, item in ipairs(items) do

		local column = (i - 1) % BIGMAP_LEGEND_COLUMNS + 1
		local row = math.ceil(i / BIGMAP_LEGEND_COLUMNS)

		local x = bgX + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN + ((column - 1) * (itemWidth + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN))
		local y = bgY + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN + ((row - 1) * itemHeight)

		dxDrawImage(
			x, y,
			iconSize, iconSize,
			item[1],
			0, 0, 0,
			tocolor(255, 255, 255, 255),
			BIGMAP_POST_GUI
		)

		x = x + iconSize + BIGMAP_TEXT_WINDOW_CONTENT_MARGIN
		dxDrawTextWithShadow(
			item[2],
			x, y,
			nil, nil,
			BIGMAP_LEGEND_TEXT_COLOR,
			1, 1,
			BIGMAP_LEGEND_TEXT_FONT,
			nil,
			nil,
			nil,
			nil,
			BIGMAP_POST_GUI)
	end

	return true
end

local function drawBigMap()

	if not BIGMAP_ENABLED then return true end
	if not drawData.showBigMap then return true end

	drawData.bigMapDrawnSprites = {}

	updateBigMapCursorMoving()
	updateBigMapPlayerMoving()
	updateBigMapScreenView()

	drawBigMapTiles()
	drawBigMapRadarAreas()
	drawBigMapBlips()
	drawBigMapHelp()
	drawBigMapLegend()

	return true
end

local function switchBigMap()

	-- enable F11 control back if default map is visible (for hiding it next time)
	-- disable F11 control if other resource enabled it
	toggleControl("radar", isPlayerMapVisible())

	drawData.showBigMap = not drawData.showBigMap
	exports.frontend:setGameplayUiVisible(not drawData.showBigMap)
	showCursor(drawData.bigMapCursorEnabled and drawData.showBigMap)

	if drawData.showBigMap then

		if BIGMAP_SOUND_ENABLED then playSoundFrontEnd(BIGMAP_SHOW_SOUND_ID) end

		drawData.bigMapWasMoved = false

		if BIGMAP_HIDE_CHAT then
			drawData.bigMapSwitchChatWasVisible = isChatVisible()
			if drawData.bigMapSwitchChatWasVisible then
				showChat(false)
			end
		end

	else

		if BIGMAP_SOUND_ENABLED then playSoundFrontEnd(BIGMAP_HIDE_SOUND_ID) end

		if drawData.bigMapSwitchChatWasVisible then
			showChat(true)
		end
	end
	return drawData.showBigMap
end

local function switchBigMapHelp()

	if not drawData.showBigMap then return false end

	drawData.showBigMapHelp = not drawData.showBigMapHelp

	return drawData.showBigMapHelp
end

local function switchBigMapLegend()

	if not drawData.showBigMap then return false end

	drawData.showBigMapLegend = not drawData.showBigMapLegend

	return drawData.showBigMapLegend
end

local function switchBigMapCursor()

	if not BIGMAP_CURSOR_SWITCHABLE then return false end
	if not drawData.showBigMap then return false end

	drawData.bigMapCursorEnabled = not drawData.bigMapCursorEnabled
	showCursor(drawData.bigMapCursorEnabled)

	return drawData.bigMapCursorEnabled
end

local function bigMapSetWaypoint()

	if not BIGMAP_WAYPOINT_ENABLED then return end
	if not drawData.showBigMap then return end
	if not isCursorShowing() then return end
	if guiGetInputEnabled() then return end
	if isMTAWindowActive() then return end
	if (not BIGMAP_POST_GUI) and drawData.cursorOnGui then return end

	local screenX, screenY = getCursorAbsolutePosition()
	if not screenX then return end

	local worldX, worldY = transformBigMapScreenToWorld(screenX, screenY)
	if not worldX then return end

	-- If waypoint exists and click is near it, remove it
	if drawData.waypointBlip and isElement(drawData.waypointBlip) then
		local wpX, wpY = getElementPosition(drawData.waypointBlip)
		local dist = getDistanceBetweenPoints2D(worldX, worldY, wpX, wpY)
		if dist < BIGMAP_WAYPOINT_REMOVE_DISTANCE then
			destroyElement(drawData.waypointBlip)
			drawData.waypointBlip = nil
			if BIGMAP_SOUND_ENABLED then playSoundFrontEnd(BIGMAP_REMOVE_WAYPOINT_SOUND_ID) end
			return
		end
	end

	-- Set new waypoint
	if drawData.waypointBlip and isElement(drawData.waypointBlip) then
		destroyElement(drawData.waypointBlip)
	end
	drawData.waypointBlip = createBlip(worldX, worldY, 0, RADAR_SPRITE.WAYPOINT)
	setBlipVisibleDistance(drawData.waypointBlip, MAP_WORLD_SIZE)
	if BIGMAP_SOUND_ENABLED then playSoundFrontEnd(BIGMAP_SET_WAYPOINT_SOUND_ID) end

end

local function zoomBigMap(step)

	if not drawData.showBigMap then return false end

	local cx, cy = drawData.cursorCurrPos[1], drawData.cursorCurrPos[2]
	cx, cy = cx or SCREEN_WIDTH / 2, cy or SCREEN_HEIGHT / 2

	local scale = 1 + step

	drawData.bigMapScreenViewTransform = transform2.mul(transform2.mul(
		drawData.bigMapScreenViewTransform,
		transform2.move(-cx, -cy)),
		transform2.scale(scale, scale))

	drawData.bigMapScreenViewTransform = transform2.mul(transform2.mul(
		drawData.bigMapScreenViewTransform,
		transform2.scale(
			math_clamp(drawData.bigMapScreenViewTransform[1][1], BIGMAP_ZOOM_SCALE_MIN, BIGMAP_ZOOM_SCALE_MAX) / drawData.bigMapScreenViewTransform[1][1],
			math_clamp(drawData.bigMapScreenViewTransform[2][2], BIGMAP_ZOOM_SCALE_MIN, BIGMAP_ZOOM_SCALE_MAX) / drawData.bigMapScreenViewTransform[2][2])),
		transform2.move(cx, cy))

	-- clamps offset
	moveBigMap(0, 0)
	updateBigMapScreenView()

	return true
end

local function changeBigMapOpacity(step)

	if not drawData.showBigMap then return false end

	drawData.bigMapAlphaMultiplier = math_clamp(
		drawData.bigMapAlphaMultiplier + step, 0.25, 1)

	return true
end

local function draw()

	-- The PS2 textures belong to frontend and are destroyed when it restarts.
	if not isElement(loadedRadarTile) then
		local frontend = getResourceFromName("frontend")
		if not frontend or getResourceState(frontend) ~= "running" or not loadTexturesRadar() then return end
		drawData.areRenderTargetsReady = false
	end

	drawData.cursorPrevPos = drawData.cursorCurrPos
	drawData.cursorCurrPos = { getCursorAbsolutePosition() }

	drawData.playerElement = getPedOccupiedVehicle(localPlayer) or localPlayer
	drawData.playerElementMatrix = getElementMatrix(drawData.playerElement)
	drawData.playerCameraAngle = math.rad(({ getElementRotation(camera) })[3])
	drawData.playerInterior = getElementInterior(localPlayer)
	drawData.playerDimension = getElementDimension(localPlayer)
	drawData.flashingRadarAreaAlphaMultiplier = calcFlashingRadarAreaAlphaMultiplier()

	drawData.playerInPlane = getElementType(drawData.playerElement) == "vehicle" and
		getVehicleRealType(drawData.playerElement) == VEHICLE_REAL_TYPE.PLANE

	drawRadar()
	drawBigMap()

	return true
end


------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

-- Radar.cpp: CRadar::Initialise() // 0x587FB0
local function interiorChanged(_, _, weather)
	drawData.hasIndoorProfile = type(weather) == "number"
end

local function initRadar()

	local previous = getElementData(localPlayer, reloadSnapshot, false)
	if previous then
		originalRadarVisibility = previous.visible
		setElementData(localPlayer, reloadSnapshot, nil, false)
	else
		originalRadarVisibility = isPlayerHudComponentVisible("radar")
	end
	setPlayerHudComponentVisible("radar", false)

	local interiorResource = getResourceFromName("interior")
	if interiorResource and getResourceState(interiorResource) == "running" then
		addEventHandler("onClientInteriorChanged", localPlayer, interiorChanged, false)
		interiorChanged(exports.interior:getInteriorState())
	end
	addEventHandler("onClientRestore", root, function() drawData.areRenderTargetsReady = false end)
	addEventHandler("onClientRender", root, draw)

	if BIGMAP_ENABLED then

		if previous and previous.control ~= nil then
			originalRadarControl = previous.control
		else
			originalRadarControl = isControlEnabled("radar")
		end
		toggleControl("radar", false)
		addEventHandler("onClientKey", root, function(key, pressed)
			if key ~= "f11" then return end
			if isMainMenuActive() or isConsoleActive() or isChatBoxInputActive() then return end
			cancelEvent()
			if pressed then switchBigMap() end
		end)

		bindKey(BIGMAP_SWITCH_LEGEND_KEY, "down", switchBigMapLegend)
		bindKey(BIGMAP_SWITCH_CURSOR_KEY, "down", switchBigMapCursor)
		bindKey(BIGMAP_ZOOM_IN_MOUSE_KEY, "down", BIGMAP_ZOOM_IN_COMMAND)
		bindKey(BIGMAP_ZOOM_OUT_MOUSE_KEY, "down", BIGMAP_ZOOM_OUT_COMMAND)
		bindKey(BIGMAP_SET_WAYPOINT_KEY, "up", bigMapSetWaypoint)
		addCommandHandler(BIGMAP_SWITCH_COMMAND, switchBigMap)
		addCommandHandler(BIGMAP_SWITCH_HELP_COMMAND, switchBigMapHelp)
		addCommandHandler(BIGMAP_ZOOM_IN_COMMAND, function() zoomBigMap(BIGMAP_ZOOM_SCALE_STEP) end)
		addCommandHandler(BIGMAP_ZOOM_OUT_COMMAND, function() zoomBigMap(-BIGMAP_ZOOM_SCALE_STEP) end)
		addCommandHandler(BIGMAP_OPACITY_UP_COMMAND, function() changeBigMapOpacity(BIGMAP_CHANGE_OPACITY_STEP) end)
		addCommandHandler(BIGMAP_OPACITY_DOWN_COMMAND, function() changeBigMapOpacity(-BIGMAP_CHANGE_OPACITY_STEP) end)
		addCommandHandler(BIGMAP_MOVE_NORTH_COMMAND, function()
			drawData.bigMapWasMoved = true
			moveBigMap(0, BIGMAP_MOVE_STEP)
		end)
		addCommandHandler(BIGMAP_MOVE_SOUTH_COMMAND, function()
			drawData.bigMapWasMoved = true
			moveBigMap(0, -BIGMAP_MOVE_STEP)
		end)
		addCommandHandler(BIGMAP_MOVE_WEST_COMMAND, function()
			drawData.bigMapWasMoved = true
			moveBigMap(BIGMAP_MOVE_STEP, 0)
		end)
		addCommandHandler(BIGMAP_MOVE_EAST_COMMAND, function()
			drawData.bigMapWasMoved = true
			moveBigMap(-BIGMAP_MOVE_STEP, 0)
		end)

		addEventHandler("onClientMouseEnter", root, function() drawData.cursorOnGui = true end)
		addEventHandler("onClientMouseMove", root, function() drawData.cursorOnGui = true end)
		addEventHandler("onClientMouseLeave", root, function(_, _, enteredGui) drawData.cursorOnGui = enteredGui ~= nil end)
	end

	return true
end

local function termRadar()

	local reloading = getElementData(root, "leeds_engine:reloading", false)
	if reloading and originalRadarVisibility ~= nil then
		setElementData(localPlayer, reloadSnapshot, {
			visible = originalRadarVisibility, control = originalRadarControl,
		}, false)
	elseif originalRadarVisibility ~= nil then
		setPlayerHudComponentVisible("radar", originalRadarVisibility)
	end

	if BIGMAP_ENABLED then

		if drawData.showBigMap then switchBigMap() end
		if not reloading and originalRadarControl ~= nil then toggleControl("radar", originalRadarControl) end
	end

	return true
end

addEventHandler("onClientResourceStart", resourceRoot, initRadar)
addEventHandler("onClientResourceStop", resourceRoot, termRadar)

------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

function getMRadarVisible()

	return drawData.showRadar
end

function getMBigMapVisible()
	return drawData.showBigMap
end

function setMRadarVisible(visible)

	visible = visible and true or false

	if drawData.showRadar == visible then return false end
	drawData.showRadar = visible

	return true
end
