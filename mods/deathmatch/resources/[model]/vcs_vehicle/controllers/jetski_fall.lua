-- SLUS_215.90 001A4C50. The two comparisons use different scores.
-- 004864A4..004864C0 holds both thresholds and the six coefficients.
function CJetSki.ImpactScore(impulse, mass, matrix, nx, ny, nz, factor)
    local initial = impulse * 800 / mass * factor
    if initial <= 30 then return 0 end
    local function dot(axis)
        return nx*axis[1] + ny*axis[2] + nz*axis[3]
    end
    local forward = math.abs(dot(matrix[2]))
    local forwardWeight = 0.6
    if forward > 0.85 and nz >= 0.85 then forwardWeight = forwardWeight + 7*nz*nz end
    local up = dot(matrix[3])
    return initial * (forwardWeight*forward + 0.45*math.abs(dot(matrix[1]))
        + 0.05*math.max(0,up) - 1.5*math.min(0,up))
end
