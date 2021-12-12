Timecycs = {
	["EXTRASUNNY_LA"] = {
		id = 0,
		data = {}
	},
	["SUNNY_LA"] = {
		id = 1,
		data = {}
	},
	["EXTRASUNNY_SMOG_LA"] = {
		id = 2,
		data = {}
	},
	["SUNNY_SMOG_LA"] = {
		id = 3,
		data = {}
	},
	["CLOUDY_LA"] = {
		id = 4,
		data = {}
	},
	["SUNNY_SF"] = {
		id = 5,
		data = {}
	},
	["EXTRASUNNY_SF"] = {
		id = 6,
		data = {}
	},
	["CLOUDY_SF"] = {
		id = 7,
		data = {}
	},
	["RAINY_SF"] = {
		id = 8,
		data = {}
	},
	["FOGGY_SF"] = {
		id = 9,
		data = {}
	},
	["SUNNY_VEGAS"] = {
		id = 10,
		data = {}
	},
	["EXTRASUNNY_VEGAS"] = {
		id = 11,
		data = {}
	},
	["CLOUDY_VEGAS"] = {
		id = 12,
		data = {}
	},
	["EXTRASUNNY_COUNTRYSIDE"] = {
		id = 13,
		data = {}
	},
	["SUNNY_COUNTRYSIDE"] = {
		id = 14,
		data = {}
	},
	["CLOUDY_COUNTRYSIDE"] = {
		id = 15,
		data = {}
	},
	["RAINY_COUNTRYSIDE"] = {
		id = 16,
		data = {}
	},
	["EXTRASUNNY_DESERT"] = {
		id = 17,
		data = {}
	},
	["SUNNY_DESERT"] = {
		id = 18,
		data = {}
	},
	["SANDSTORM_DESERT"] = {
		id = 19,
		data = {}
	},
	["UNDERWATER"] = {
		id = 20,
		data = {}
	},
	["EXTRACOLOURS_1"] = {
		id = 21,
		data = {}
	},
	["EXTRACOLOURS_2"] = {
		id = 22,
		data = {}
	},
}
function loadTimecycDat(path)
    local file = fileOpen(path,true)                           
    if not file then
        return false
    end
    local FullText = fileRead(file, 100)
    
    while not fileIsEOF(file) do
    FullText = FullText .. fileRead(file, 100)
    end
    fileClose(file)
    
    Lines = split(FullText,'\n' )
    for i = 1, #Lines do
    	if string.find(Lines[i],"////////////") then 
    		print(Lines[i])
    	end
   		local params = split(Lines[i],"\t")
   		if #params == 14 then 
   			local SKY_TOP = params[4]
   			local SKY_BOT = params[5]
   			--setSkyGradient( SKY_TOP[1],SKY_TOP[2],SKY_TOP[3],SKY_BOT[1],SKY_BOT[2],SKY_BOT[3])

   		end
    end
end
loadTimecycDat("timecyc/timecyc.dat")
--setSkyGradient(90, 205, 255,200, 144, 85)