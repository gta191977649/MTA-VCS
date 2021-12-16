function isTransparentFlag(flag) 
    local transparentFlags = {
        0x8,2097388,204084,68,2097156,2097228
    }
    for i,mask in ipairs(transparentFlags) do
        if bitAnd(flag,mask) ~= 0 then 
            return true
        end
    end
    return false
end
