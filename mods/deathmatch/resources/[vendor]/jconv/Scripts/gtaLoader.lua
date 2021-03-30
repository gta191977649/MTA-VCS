local File = fileOpen("data/gta.dat")
local Data = fileRead(File, fileGetSize(File))
local Proccessed = split(Data,10) -- Split the lines
fileClose (File)

IPLTable = {}
IDETable = {}
IMGTable = {}

function toTable()
	print(#Proccessed)
	for i=1,#Proccessed do
		local String = Proccessed[i]
		if gettok(String,2,' ') then
			local Type = string.gsub(gettok(String,1,' '),'%s',"")
			local Path = string.gsub(gettok(String,2,' '),'%s',"")
			if Path then
				local exits = fileExists(Path)
				if not exits then
					print("|"..Path..'|')
				else
					if Type == "IPL" then
						table.insert(IPLTable,Path) -- Load Ipls
					elseif Type == "IDE" then
						table.insert(IDETable,Path) -- Load Ides
					elseif Type == "IMG" then
						table.insert(IMGTable,Path) -- Load Imgs // Unused might be useable in the future
					end
				end
			end
		end
	end
end
toTable() -- Proccess Data, Sort the files


