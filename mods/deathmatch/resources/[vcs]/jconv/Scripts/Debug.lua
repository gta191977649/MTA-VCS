print("Writing Debug")

local file = fileCreate ('debug.txt' )
for i,v in pairs(Debug) do
    fileWrite(file,"\n"..v)
end

fileClose(file) -- done



