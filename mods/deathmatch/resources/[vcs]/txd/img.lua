local fileHandle = fileCreate("img.png") 
if fileHandle then          
    local img = engineLoadIMGContainer("./data/raw.img")   
    local raw = img:getFile("247sign2.png")                      
    fileWrite(fileHandle,raw) 
    fileClose(fileHandle)
end