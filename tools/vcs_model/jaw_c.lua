local tracked = setmetatable({}, {__mode = "k"})
local correction

local function word(data, offset)
    local a, b, c, d = data:byte(offset, offset + 3)
    if not d then return end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function child(data, start, finish, kind)
    while start + 12 <= finish do
        local id, size = word(data, start), word(data, start + 4)
        if not size or start + 12 + size > finish then return end
        if id == kind then return start + 12, start + 12 + size end
        start = start + 12 + size
    end
end

local function float(data, offset)
    local bits = word(data, offset)
    local exponent = math.floor(bits / 8388608) % 256
    local fraction = bits % 8388608
    local sign = bits < 2147483648 and 1 or -1
    if exponent == 0 then return sign * fraction * 2 ^ -149 end
    if exponent < 255 then return sign * (1 + fraction / 8388608) * 2 ^ (exponent - 127) end
end

function getTrafficJawBindPivot(data)
    local clump, clumpEnd = child(data, 1, #data + 1, 0x10)
    if not clump then return end
    local frames, framesEnd = child(data, clump, clumpEnd, 0x0e)
    if not frames then return end
    local frameData, extensions = child(data, frames, framesEnd, 1)
    if not frameData or extensions - frameData < 4 then return end
    local count = word(data, frameData)
    if not count or count > 512 or frameData + 4 + count * 56 > extensions then return end
    local head, jaw
    for index = 0, count - 1 do
        if extensions + 12 > framesEnd or word(data, extensions) ~= 3 then return end
        local finish = extensions + 12 + word(data, extensions + 4)
        if finish > framesEnd then return end
        local hAnim, hAnimEnd = child(data, extensions + 12, finish, 0x11e)
        if hAnim and hAnim + 8 <= hAnimEnd then
            local tag = word(data, hAnim + 4)
            if tag == 5 then head = index elseif tag == 8 then jaw = index end
        end
        extensions = finish
    end
    if not head or not jaw then return end
    local frame = frameData + 4 + jaw * 56
    if word(data, frame + 48) ~= head then return end
    -- Only apply to the measured converted jaw basis. Future rigs that use
    -- the SA basis can use native facial playback directly.
    local expected = {0, 0, -1, 0, 1, 0, 1, 0, 0}
    for index, value in ipairs(expected) do
        local current = float(data, frame + (index - 1) * 4)
        if not current or math.abs(current - value) > 0.01 then return end
    end
    local x, y, z = float(data, frame + 36), float(data, frame + 40), float(data, frame + 44)
    if x and y and z and math.abs(x) + math.abs(y) + math.abs(z) < 0.5 then return {x, y, z} end
end

function trackTrafficJaw(ped, model, pivot)
    if pivot then tracked[ped] = {model, pivot} end
end

local function vector(a, b, fa, fb)
    return Vector3(a[1] * fa + b[1] * fb, a[2] * fa + b[2] * fb, a[3] * fa + b[3] * fb)
end

local function correctJaw(ped, pivot)
    local head, jaw = getElementBoneMatrix(ped, 5), getElementBoneMatrix(ped, 8)
    if not head or not jaw then return end
    -- SA facial clips place the jaw's third axis along the head's third axis.
    -- A jaw already in its converted bind basis needs no correction.
    local a, b = jaw[3], head[3]
    if a[1] * b[1] + a[2] * b[2] + a[3] * b[3] < 0.7 then return end
    correction = correction or Matrix()
    -- Apply the change of rest basis while preserving the animation delta.
    local c, s = -0.3547, 0.935
    correction.right = vector(jaw[3], jaw[3], -1, 0)
    correction.forward = vector(jaw[1], jaw[2], s, c)
    correction.up = vector(jaw[1], jaw[2], c, -s)
    local x, y, z = unpack(pivot)
    correction.position = Vector3(
        head[4][1] + x * head[1][1] + y * head[2][1] + z * head[3][1],
        head[4][2] + x * head[1][2] + y * head[2][2] + z * head[3][2],
        head[4][3] + x * head[1][3] + y * head[2][3] + z * head[3][3])
    setElementBoneMatrix(ped, 8, correction)
end

if type(setElementBoneMatrix) == "function" and type(getElementBoneMatrix) == "function" then
    addEventHandler("onClientPedsProcessed", root, function()
        if not next(tracked) then return end
        local x, y, z = getCameraMatrix()
        for ped, entry in pairs(tracked) do
            if getElementModel(ped) == entry[1] and isElementOnScreen(ped) then
                local px, py, pz = getElementPosition(ped)
                if (px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2 <= 35 ^ 2 then correctJaw(ped, entry[2]) end
            end
        end
    end)
end

local function untrack()
    tracked[source] = nil
end
addEventHandler("onClientElementStreamOut", root, untrack)
addEventHandler("onClientElementDestroy", root, untrack)
