
print("Writing Meta")
local file = fileCreate (MapName..'/meta.xml' )
for i,v in pairs(meta) do
    fileWrite(file,"\n"..v)
end

fileWrite(file,"\n</meta>")

fileClose(file) -- done



