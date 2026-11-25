local resourceColumns, selectedRows, serverInfo = {}, {}, {}
local sortBy = {what="__NONE__", dir=-1}
local scoreboardForced, held, visible = false, false, false
local nextUpdate = 0
scoreboardColumns = {}
local function iif(cond, yes, no) if cond then return yes end return no end

-- addColumn
function scoreboardAddColumn(name, width, friendlyName, priority, textFunction, fromResource, isImage, imageW, imageH)
	if type(name) ~= "string" then
		return false
	end

	width = math.max(1,tonumber(width) or 70)
	friendlyName = friendlyName or name
	priority = tonumber( priority ) or getNextFreePrioritySlot( scoreboardGetColumnPriority( "name" ) )
	textFunction = textFunction or nil
	fromResource = fromResource or sourceResource

	if not (priority > MAX_PRIORITY_SLOT or priority < 1) then

		for key = 1, #scoreboardColumns do
			local value = scoreboardColumns[key]

			if name == value.name then
				return false
			end
		end

        fixPrioritySlot(priority)
		table.insert( scoreboardColumns, { ["name"] = name, ["width"] = width, ["friendlyName"] = friendlyName, ["priority"] = priority, ["textFunction"] = textFunction, ["isImage"] = isImage, ["imageW"] = imageW, ["imageH"] = imageH } )
		table.sort( scoreboardColumns, function ( a, b ) return a.priority < b.priority end )

		if fromResource then
			if not resourceColumns[fromResource] then resourceColumns[fromResource] = {} end
			table.insert ( resourceColumns[fromResource], name )
		end

		return true
	end

	return false
end

addEvent( "doScoreboardAddColumn", true )
addEventHandler( "doScoreboardAddColumn", root,
	function ( name, width, friendlyName, priority, fromResource, isImage, imageW, imageH )
		scoreboardAddColumn( name, width, friendlyName, priority, nil, fromResource, isImage, imageW, imageH )
	end
)

function onClientScoreboardCreateColumns(columnsToAdd)
	for columnID = 1, #columnsToAdd do
		local columnData = columnsToAdd[columnID]

		scoreboardAddColumn(columnData.name, columnData.width, columnData.friendlyName, columnData.priority, nil, nil, columnData.isImage, columnData.imageW, columnData.imageH)
	end
end
addEvent("onClientScoreboardCreateColumns", true)
addEventHandler("onClientScoreboardCreateColumns", root, onClientScoreboardCreateColumns)

-- removeColumn
function scoreboardRemoveColumn(name)
	if type(name) ~= "string" then
		return false
	end

	for key = 1, #scoreboardColumns do
		local value = scoreboardColumns[key]

		if name == value.name then
			table.remove(scoreboardColumns, key)

			for resource, content in pairs(resourceColumns) do
				table.removevalue(content, name)
			end

			return true
		end
	end

	return false
end

addEvent( "doScoreboardRemoveColumn", true )
addEventHandler( "doScoreboardRemoveColumn", resourceRoot,
	function ( name )
		scoreboardRemoveColumn( name )
	end
)

-- clearColumns
function scoreboardClearColumns()
	while ( scoreboardColumns[1] ) do
		table.remove( scoreboardColumns, 1 )
		resourceColumns = {}
	end
	return true
end

addEvent( "doScoreboardClearColumns", true )
addEventHandler( "doScoreboardClearColumns", resourceRoot,
	function ()
		scoreboardClearColumns()
	end
)

-- resetColumns
function scoreboardResetColumns( fromServer )
	while ( scoreboardColumns[1] ) do
		table.remove( scoreboardColumns, 1 )
		resourceColumns = {}
	end
	if not fromServer then
        scoreboardColumns = defaultColumns(serverInfo.countries ~= false)
	end
	return true
end

addEvent( "doScoreboardResetColumns", true )
addEventHandler( "doScoreboardResetColumns", resourceRoot,
	function ( fromServer )
		scoreboardResetColumns( iif( fromServer == nil, true, fromServer ) )
	end
)

-- setForced
function scoreboardSetForced( forced )
	scoreboardForced = forced
end

addEvent( "doScoreboardSetForced", true )
addEventHandler( "doScoreboardSetForced", resourceRoot,
	function ( forced )
		scoreboardSetForced( forced )
	end
)

--Compatibility
setScoreboardForced = scoreboardSetForced

--setSortBy
function scoreboardSetSortBy(name, desc)
	if not name then
		sortBy.what = "__NONE__"
		sortBy.dir = -1

		return true
	end

	if type(name) ~= "string" then
		return false
	end

	local exists = false

	for key = 1, #scoreboardColumns do
		local value = scoreboardColumns[key]

		if name == value.name then
			exists = true
		end
	end

	if exists then
		desc = desc == true and 1 or -1
		sortBy.what = name
		sortBy.dir = desc
        nextUpdate=0
        return true
	end
end

addEvent( "doScoreboardSetSortBy", true )
addEventHandler( "doScoreboardSetSortBy", resourceRoot,
	function ( name, desc )
		scoreboardSetSortBy( name, desc )
	end
)

--getColumnPriority
function scoreboardGetColumnPriority(name)
	if type(name) ~= "string" then
		return false
	end

	for key = 1, #scoreboardColumns do
		local value = scoreboardColumns[key]

		if name == value.name then
			return value.priority
		end
	end

	return false
end

--setColumnPriority
function scoreboardSetColumnPriority(name, priority)
	if type(name) ~= "string" or type(priority) ~= "number" then
		return false
	end

	if not (priority > MAX_PRIORITY_SLOT or priority < 1) then
		local columnIndex = false

		for key = 1, #scoreboardColumns do
			local value = scoreboardColumns[key]

			if name == value.name then
				columnIndex = key
			end
		end

		if columnIndex then
			scoreboardColumns[columnIndex].priority = -1 -- To empty out the current priority
			fixPrioritySlot(priority)
			scoreboardColumns[columnIndex].priority = priority
			table.sort(scoreboardColumns, function(a, b) return a.priority < b.priority end)

			return true
		end
	end

	return false
end

addEvent( "doScoreboardSetColumnPriority", true )
addEventHandler( "doScoreboardSetColumnPriority", resourceRoot,
	function ( name, priority )
		scoreboardSetColumnPriority( name, priority )
	end
)

--getColumnCount
function scoreboardGetColumnCount()
	return #scoreboardColumns
end

--setColumnTextFunction
function scoreboardSetColumnTextFunction(name, func)
	if type(name) ~= "string" then
		return false
	end

	for key = 1, #scoreboardColumns do
		local value = scoreboardColumns[key]

		if name == value.name then
			scoreboardColumns[key].textFunction = func

			return true
		end
	end

	return false
end


function removeResourceScoreboardColumns( resource )
	if resourceColumns[resource] then
		while resourceColumns[resource][1] do
			local success = scoreboardRemoveColumn( resourceColumns[resource][1] )
			if not success then break end
		end
		resourceColumns[resource] = nil
	end
end
addEventHandler( "onClientResourceStop", root, removeResourceScoreboardColumns )


function scoreboardForceUpdate()
    nextUpdate=0
    return true
end

function scoreboardGetTopCornerPosition()
    local x,y=exports.frontend:getScoreboardBounds()
    return x,y
end
function scoreboardGetSize()
    local x,y,w,h=exports.frontend:getScoreboardBounds()
    if not x then return false end
    return w,h
end
function scoreboardGetSelectedRows()
    local rows={}
    for e in pairs(selectedRows) do rows[#rows+1]=e end
    return rows
end
addEventHandler("onClientPlayerQuit",root,function() selectedRows[source]=nil end)
addEvent("onClientPlayerScoreboardClick",false)
addEvent("onScoreboardCellClick",false)
addEventHandler("onScoreboardCellClick",resourceRoot,function(element,column,x,y)
    if element then
        if triggerEvent("onClientPlayerScoreboardClick",element,not selectedRows[element],x,y,column) then
            selectedRows[element]=not selectedRows[element] or nil
        end
    elseif sortBy.what~=column then
        sortBy.what,sortBy.dir=column,-1
    elseif sortBy.dir==-1 then sortBy.dir=1
    else sortBy.what,sortBy.dir="__NONE__",-1 end
    nextUpdate=0
end,false)

addEvent("sendServerInfo",true)
addEventHandler("sendServerInfo",localPlayer,function(info) serverInfo=info; nextUpdate=0 end)
local function toggleScoreboard()
    if not exports.frontend:isPlayerDialogVisible() then held=not held end
end
addCommandHandler("scoreboard",toggleScoreboard)
addCommandHandler("Toggle scoreboard",toggleScoreboard)
bindKey("tab","down","Toggle scoreboard")
addEventHandler("onClientResourceStart",resourceRoot,function()
    triggerServerEvent("requestServerInfo",localPlayer)
end)
addEventHandler("onClientRender",root,function()
    local open=(held or scoreboardForced) and #scoreboardColumns>0 and not exports.frontend:isPlayerDialogVisible()
    if open~=visible then
        visible=open
        if not open then exports.frontend:setScoreboardContent(false); return end
        nextUpdate=0
        triggerServerEvent("requestServerInfo",localPlayer)
    end
    if not visible or getTickCount()<nextUpdate then return end
    nextUpdate=getTickCount()+500
    local columns={}
    for i,c in ipairs(scoreboardColumns) do
        columns[i]={name=c.name,friendlyName=c.friendlyName,width=c.width,imageW=c.imageW,imageH=c.imageH}
    end
    exports.frontend:setScoreboardContent({
        title=serverInfo.server or "", population="Players: "..#getElementsByType("player"),
        columns=columns, rows=buildScoreboardRows(scoreboardColumns,selectedRows,sortBy,not serverInfo.forcehideteams),
        colorcodes=serverInfo.allowcolorcodes, step=serverInfo.scrollStep
    })
end)
