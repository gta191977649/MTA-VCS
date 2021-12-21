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

function setElementFlagProperty(element,flag)
    local breakableFlags = {
        0x200,0x400,0x1000,0x400000,32900
    }
    for i,mask in ipairs(breakableFlags) do
        if bitAnd(flag,mask) ~= 0 then 
            setObjectBreakable(element,true)
            return
        end
    end
end