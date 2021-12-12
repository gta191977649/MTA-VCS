function genFileStream()
	return {
		--Variable
		usingRaw = false;
		file = false;
		cacheSize = 1024*1024;	--1MB
		cachedString = ""; 
		cachedIndex	= false;
		--Function
		loadFile = function(self,fname)
			if fileExists(fname) then
				self.file = fname
			else
				self.file = fname
				self.usingRaw = true
			end
		end;
		clearCache = function(self)
			self.cachedIndex = false
			self.cachedString = ""
			collectgarbage()
		end;
		cache = function(self,offset)
			local filePath = self.file
			if filePath then
				local f = fileOpen(self.file)
				fileSetPos(f,offset)
				self.cachedString = fileRead(f,self.cacheSize)
				self.cachedIndex = offset
				fileClose(f)
			end
			return false
		end;
		get = function(self,offset,bytes,direct)
			if self.usingRaw then
				return self.file:sub(offset+1,offset+bytes)
			else
				local filePath = self.file
				if filePath then
					if direct then
						local f = fileOpen(filePath)
						fileSetPos(f,offset)
						local str = fileRead(f,bytes)
						fileClose(f)
						return str
					else
						if not self.cachedIndex then self:cache(offset) end
						local cacheStart,cacheEnd = self.cachedIndex,self.cachedIndex+self.cacheSize
						local readStart,readEnd = offset,offset+bytes
						local str = ""
						if readStart >= cacheStart then
							if readStart >= cacheEnd then
								self:cache(readStart)
								return self:get(offset,bytes)
							end
							if readEnd <= cacheEnd then
								return self.cachedString:sub(readStart-cacheStart+1,readEnd-cacheStart)
							else
								str = self.cachedString:sub(readStart-cacheStart+1)
								while true do
									self:cache(self.cachedIndex+self.cacheSize)
									local _cacheEnd = self.cachedIndex+self.cacheSize
									if self.cachedIndex+self.cacheSize >= readEnd then
										str = str..self.cachedString:sub(1,readEnd-self.cachedIndex)
										break
									else
										str = str..self.cachedString
									end
								end
								return str
							end
						else
							self:cache(readStart)
							return self:get(offset,bytes)
						end
					end
				end
			end
		end;
		readChar = function(self,offset,bytes)
			local str = self:get(offset,bytes)
			local zero = str:find("%z")
			if zero then
				return str:sub(1,zero-1)
			end
			return str
		end;
		readNumber = function(self,offset,bytes)
			local str = self:get(offset,bytes)
			local num = 0
			for i=1,bytes do
				num = num+str:sub(i,i):byte()*0x100^(i-1)
			end
			return num
		end;
	}
end

function engineLoadIMGContainer(file)
	assert(type(file) == "string","Bad argument @'engineLoadIMGContainer' at argument 1, expected a string got "..type(file))
	--assert(fileExists(file),"Bad argument @'engineLoadIMGContainer' at argument 1, file "..file.." doesn't exist")
	local fs = genFileStream()
	fs:loadFile(file)
	local imgFile = {
		files = {},
		directory = {},
		directoryNameToIndex = {},
	}
	--Read Head
	local readIndex = 0
	local IMGVer = fs:readChar(readIndex,4)
	readIndex = readIndex+4
	imgFile.version = IMGVer
	local entriesCount = fs:readNumber(readIndex,4)
	readIndex = readIndex+4
	imgFile.entriesCount = entriesCount
	--Read Directory
	for index=1,entriesCount do
		local i = index-1
		local offset,streamingSize,sizeInArchive,name
		offset = fs:readNumber(readIndex,4)
		readIndex = readIndex+4
		streamingSize = fs:readNumber(readIndex,2)
		readIndex = readIndex+2
		sizeInArchive = fs:readNumber(readIndex,2)
		readIndex = readIndex+2
		name = fs:readChar(readIndex,24)
		readIndex = readIndex+24
		imgFile.directory[index] = {name=name,streamingSize=streamingSize*2048,sizeInArchive=sizeInArchive*2048,offset=offset*2048}
		imgFile.directoryNameToIndex[name] = index
	end
	fs:clearCache()
	imgFile.getFile = function(self,name)
		if self then
			local index = imgFile.directoryNameToIndex[name]
			if index then
				local dirData = imgFile.directory[index]
				return fs:get(dirData.offset,dirData.streamingSize,true)
			end
			return false
		end
	end
	imgFile.fileExists = function(self,name)
		return imgFile.directoryNameToIndex[name] or false
	end
	imgFile.listFiles = function(self)
		local fileList = {}
		for i=1,#imgFile.directory do
			fileList[i] = imgFile.directory[i].name
		end
		return fileList
	end
	return imgFile
end