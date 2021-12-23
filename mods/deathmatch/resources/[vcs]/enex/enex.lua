HUD = exports.hud
local readingFlag = false
local HIT_COOLDOWN_TIME = 3000
local lastHit = getTickCount()
Enex = {}
local enexElement = createElement("enex")
function createEnex(x1,y1,z1,rot,w1,w2,x2,y2,z2,rot2,int,flag,name) 

    local nwx, nwy = getPositionFromOffsetByPosRot(x1, y1, z1, 0.0, 0.0, rot, w1/2, w2/2, 0.0)
    local sex, sey = getPositionFromOffsetByPosRot(x1, y1, z1, 0.0, 0.0, rot, -w1/2, -w2/2, 0.0)
    local nex, ney = getPositionFromOffsetByPosRot(x1, y1, z1, 0.0, 0.0, rot, -w1/2, w2/2, 0.0)
    local swx, swy = getPositionFromOffsetByPosRot(x1, y1, z1, 0.0, 0.0, rot, w1/2, -w2/2, 0.0)

    --[[
    createMarker(nwx, nwy, z1, "cylinder", 0.4)
    createMarker(sex, sey, z1, "cylinder", 0.4)
    createMarker(nex, ney, z1, "cylinder", 0.4)
    createMarker(swx, swy, z1, "cylinder", 0.4)
    --]]

    local colshape = createColPolygon (x1,y1, nwx, nwy,sex, sey, nex, ney,swx, swy)
    setColPolygonHeight(colshape,z1,z1+5)  
    Enex[colshape] = {
        pos_entry = {x1,y1,z1,rot},
        pos_exit = {x2,y2,z2,rot2},
        int = int,
        flag = tonumber(flag),
        name = name,
    }
    local marker = createMarker(x1,y1,z1+2,"arrow",1.5,0,255,255,100)
    setElementParent(marker,enexElement)
    setElementInterior(marker,int)
    setElementInterior(colshape,int)
end

function teleportPlayerToLinkedInterior(source,link) 
    fadeCamera(true,0.5)
    print("hit "..Enex[source].name.." flag "..Enex[source].flag)
    local x,y,z = unpack(Enex[link].pos_exit)
    lastHit = getTickCount()
    setElementInterior(localPlayer,Enex[link].int)
    setElementPosition(localPlayer,x,y,z+0.5)
end
function loadEnex(path) 
    -- step 1 load enex
    local f = readFileInLines(path)
    for _,line in ipairs(f) do 
        if not isComment(line) then 
            if string.find(line, "end") then
                readingFlag = false 
            end

            if readingFlag then 
                local l = split(line:gsub("%s+", ""),",")
                iprint(l)
                local x,y,z,rot,w1,w2,w3,x2,y2,z2,rot2,int,flag,name = unpack(l)
                createEnex(x,y,z,rot,w1,w2,x2,y2,z2,rot2,int,flag,name)
            end

            if string.find(line, "enex") then
                readingFlag = true 
            end
        end
    end
    -- step 2 find linked pairs
    for colshape,enex in pairs(Enex) do 
        print(enex.name)
        -- check if is linked pair
        if enex.flag == 6 then 
            print(enex.name.." is linked pair, find the coresponding pair...")
            for link,find in pairs(Enex) do 
                if find.name == enex.name and find.flag == 2 then 
                    print("find linked pair for "..enex.name)
                    enex.link = link 
                    find.link = colshape 
                    break
                end
            end
        end
    end
    -- step 3 register event callback
    addEventHandler("onClientColShapeHit", root, function(theElement, matchingDimension) 
        if Enex[source] ~= nil and theElement == localPlayer and matchingDimension then 
            -- prevent hit loop (cooldown)
            if getTickCount() - lastHit < HIT_COOLDOWN_TIME then return end
            local link = Enex[source].link
            if link ~= nil and Enex[link] ~= nil then 
                if Enex[source].flag == 6 then -- only show at entry
                    HUD:showGameText(Enex[source].name,"LOCATION_NAME",3000)
                end
                --fade camera
                fadeCamera(false,0.5)
                setTimer(teleportPlayerToLinkedInterior,500,1,source,link)
                --teleportPlayerToLinkedInterior() 
            else
                HUD:showGameText("Enex Pair Missing!","LOCATION_NAME",3000)
                print(Enex[source].name.." link not found!")
            end
        end
    end)
end


-- animation
addEventHandler( "onClientResourceStart", resourceRoot,function()
    fadeCamera(true)
    loadEnex("enex.ipl")
end)