function main() 
    print("Start Skygfx")
    fx_toogleRadiosity(true)
    fx_setRadiosityConfig(21,103) 
end
addEventHandler( "onClientResourceStart", resourceRoot,main);