local overrides={}
local function updateCountry(player)
    if overrides[player] then return end
    local provider=getResourceFromName("ip2c")
    local code=provider and getResourceState(provider)=="running" and exports.ip2c:getPlayerCountry(player)
    code=code or "N/A"
    local current=getElementData(player,"Country")
    if type(current)~="table" or current[2]~=code then
        setElementData(player,"Country",{code~="N/A" and ":ip2c/client/images/flags/"..code:lower()..".png" or false,code})
    end
end
local function refresh()
    for _,player in ipairs(getElementsByType("player")) do updateCountry(player) end
end
addEventHandler("onPlayerJoin",root,function() updateCountry(source) end)
addEventHandler("onPlayerQuit",root,function() overrides[source]=nil end)
addEventHandler("onResourceStart",resourceRoot,refresh)
-- IP2C finishes loading its database asynchronously.
addEventHandler("onCountryDatabaseReady",root,refresh)
addEventHandler("onResourceStop",root,function(res)
    if getResourceName(res)=="ip2c" then setTimer(refresh,50,1) end
end)
addCommandHandler("setcountry",function(player,_,code)
    code=type(code)=="string" and code:upper()
    if not code or not code:match("^[A-Z][A-Z]$") then return end
    local path=":ip2c/client/images/flags/"..code:lower()..".png"
    if not fileExists(path) then return end
    overrides[player]=true
    setElementData(player,"Country",{path,code})
end)
