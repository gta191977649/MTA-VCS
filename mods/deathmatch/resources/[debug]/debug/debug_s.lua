function isTransparentFlag(flag) 
    local transparentFlags = {
        0x4,0x8
    }

    for i,mask in ipairs(transparentFlags) do
        if bitAnd(flag,mask) ~= 0 then 
            return true
        end
    end

    return false
end
print(isTransparentFlag(450))