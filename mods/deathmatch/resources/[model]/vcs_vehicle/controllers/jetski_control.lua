CJetSki = CVehicle.derive("CJetSki", CBoat)
CJetSki.baseModel = 473
-- 0019C200 halves the handling file's turn mass when constructing CBoat.
CJetSki.turnMass = 2000.0293*0.5
CVehicle.register(233, CJetSki)

-- The SA CBoat pad already implements the VCS brake filter, -0.3 reverse
-- and signed-square steering. The subtype adds two independent balance axes.
function CJetSki:New(hull)
    local ski = CVehicle.New(self, hull)
    ski.lateral, ski.longitudinal = 0, 0
    return ski
end

function CJetSki:ProcessControlInputs(accelerate, reverse, side, fore, handbrake, step)
    CBoat.ProcessControlInputs(self, accelerate, reverse, side, handbrake, step)
    local blend = math.min(1, 0.2 * step)
    self.lateral = self.lateral + (side-self.lateral)*blend
    self.longitudinal = self.longitudinal + (fore-self.longitudinal)*blend
end

-- SLUS_215.90 001A3150, handling subtype 2. The neutral mass centre is zero.
function CJetSki:GetCentreOfMass()
    return {-0.49*self.lateral, 0.01*self.longitudinal, 0}
end
