-- SLUS-21590 MAIN.SCM 0145: A, B and C (the fourth corner is B+C-A).
-- IDs match the numeric suffixes of the script's garage variables.
local function garage(id, kind, floor, ceiling, bay, door, doorPosition, lift, doorKind, capacity)
    local ax, ay, bx, by, cx, cy = unpack(bay)
    local ux, uy, vx, vy = bx - ax, by - ay, cx - ax, cy - ay
    return {
        id = id, kind = kind, floor = floor, ceiling = ceiling, bay = bay,
        door = door, doorPosition = doorPosition, lift = lift, capacity = capacity,
        doorKind = doorKind or "slide", interior = 0, dimension = 0,
        ax = ax, ay = ay, ux = ux, uy = uy, vx = vx, vy = vy,
        determinant = ux * vy - uy * vx,
        centerX = (bx + cx) / 2, centerY = (by + cy) / 2,
    }
end

VCS_GARAGES = {
    garage(913, 1, 10.515, 14.947, {-838.687, -1201.066, -830.975, -1198.333, -840.584, -1195.191}, nil, nil, nil, "slide", 1),
    garage(914, 1, 10.237, 13.613, {-1100.551, 358.494, -1100.551, 363.665, -1108.454, 358.494}, nil, nil, nil, "swing", 1),
    garage(915, 1, 10.0, 14.169, {268.883, -140.02, 264.639, -149.152, 258.528, -135.201}, nil, nil, nil, "slide", 3),
    garage(916, 5, 10.706, 14.421, {-914.129, -1263.54, -907.137, -1246.626, -906.3, -1266.9},
        "dk_paynspraydoor", {-910.001770, -1264.709595, 12.492321}, 3.5),
    garage(917, 5, 9.992, 15.58, {-886.157, -115.158, -882.699, -108.312, -876.7, -119.83},
        "haiwshpnsdoor", {-874.696167, -116.695641, 11.987481}, 3.5),
    garage(918, 5, 10.0, 15.7, {323.9, 427.4, 326.3, 434.5, 313.9, 430.53},
        "nbecpnsdoor", {325.083374, 431.136597, 11.587159}, 3.5),
    garage(919, 5, 9.322, 14.4, {-7.55, -1253.77, -7.55, -1261.2, 2.64, -1253.7},
        "wshpnsdoor", {-7.804682, -1257.642944, 10.818735}, 3.5),
    garage(920, 4, 10.0913, 15.0, {-904.886, 1125.84, -898.413, 1118.218, -892.443, 1136.3149},
        "me_bombdoor", {-901.647278, 1121.969482, 12.690296}, 4),
    garage(922, 17, 9.3865, 12.33, {168.9468, -949.7315, 165.846, -959.0292, 160.146, -946.632}),
    garage(923, 1, 11.72, 15.534, {-353.7, -539.484, -353.7, -554.62, -360.41, -539.484}, nil, nil, nil, "swing"),
}

function garageContainsXY(config, x, y, padding)
    local dx, dy = x - config.ax, y - config.ay
    local u = (dx * config.vy - dy * config.vx) / config.determinant
    local v = (config.ux * dy - config.uy * dx) / config.determinant
    padding = padding or 0
    return u >= -padding and u <= 1 + padding and v >= -padding and v <= 1 + padding
end

function garageInWorld(config, element)
    return getElementInterior(element) == config.interior and getElementDimension(element) == config.dimension
end

function garageTypeKey(kind)
    return "garage:active:" .. kind
end
