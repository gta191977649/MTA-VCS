element_type = {}
element_id = {}
element_parent = {}
element_children = {}
element_data = {}

events = {}

stack_source = {}
stack_this = {}
event_source_stack_pos = 0

next_element_id = 1
next_event_id = 1

local dynamicElementRoot = getResourceDynamicElementRoot(getThisResource())

if not localPlayer then
	function createFakeElement(elmtype,id)
		--[[if type(elmtype) ~= "string" or id and type(id) ~= "string" then
			outputDebugString(debug.traceback())
			return
		end]]

		local this_id = next_element_id
		next_element_id = next_element_id+1
		element_type[this_id] = elmtype
		element_id[this_id] = id
		triggerClientEvent("traffic_edit:sync_createFakeElement",root,this_id,elmtype,id)
		setFakeElementParent(this_id,dynamicElementRoot)
		return this_id
	end

	function destroyFakeElement(element)
		--[[if not isFakeElement(element) then
			outputDebugString(debug.traceback())
			return
		end]]

		triggerFakeEvent("onElementDestroy",element)
		events[element] = nil
		local children = element_children[element]
		if children then
			for child in pairs(children) do
				destroyFakeElement(child)
			end
		end
		for dataname,data in pairs(element_data) do
			data[element] = nil
		end
		triggerClientEvent("traffic_edit:sync_destroyFakeElement",root,element)
		setFakeElementParent(element,nil)
		element_type[element] = nil
		element_id[element] = nil
	end

	function destroyElementLinkWithFakeElements()
		events[source] = nil
		local children = element_children[source]
		if children then
			for child in pairs(children) do
				destroyFakeElement(child)
			end
		end
	end
	addEventHandler("onElementDestroy",root,destroyElementLinkWithFakeElements)
end

function isFakeElement(element)
	return element_type[element] ~= nil
end

function setFakeElementParent(element,parent)
	--[[if not isFakeElement(element) then
		outputDebugString(debug.traceback())
		return
	end]]

	local prev_parent = element_parent[element]
	if prev_parent then
		element_children[prev_parent][element] = nil
		if not next(element_children[prev_parent]) then
			element_children[prev_parent] = nil
		end
	end
	if parent then
		if not element_children[parent] then
			element_children[parent] = {}
		end
		element_children[parent][element] = true
	end
	element_parent[element] = parent
	if not localPlayer then
		triggerClientEvent("traffic_edit:sync_setFakeElementParent",root,element,parent)
	end
end

function copyTable(table)
	local newtable = {}
	for key,value in pairs(table) do
		newtable[key] = type(value) == "table" and copyTable(value) or value
	end
	return newtable
end

function setFakeElementData(element,dataname,dataval,sync)
	--[[if not isFakeElement(element) or type(dataname) ~= "string" then
		outputDebugString(debug.traceback())
		return
	end]]

	if type(dataval) == "table" then dataval = copyTable(dataval) end
	if sync == nil then sync = true end
	if not element_data[dataname] then element_data[dataname] = {} end
	local prevval = element_data[dataname][element]
	if prevval == dataval then return end
	element_data[dataname][element] = dataval
	if not next(element_data[dataname]) then element_data[dataname] = nil end
	triggerFakeEvent(localPlayer and "onClientElementDataChange" or "onElementDataChange",element,dataname,prevval)
	if sync then
		if not localPlayer then
			triggerClientEvent("traffic_edit:sync_setFakeElementData",root,element,dataname,dataval)
		else
			triggerServerEvent("traffic_edit:sync_setFakeElementData",root,element,dataname,dataval)
		end
	end
end

function sync_setFakeElementData(element,dataname,dataval)
	setFakeElementData(element,dataname,dataval,false)
end

function removeFakeElementData(element,dataname)
	setFakeElementData(element,dataname,nil)
end

function getFakeElementData(element,dataname)
	--[[if not isFakeElement(element) or type(dataname) ~= "string" then
		outputDebugString(debug.traceback())
		return
	end]]

	local data = element_data[dataname] and element_data[dataname][element]
	return type(data) == "table" and copyTable(data) or data
end

function getFakeElementType(element)
	--[[if not isFakeElement(element) then
		outputDebugString(debug.traceback())
		return
	end]]

	return element_type[element]
end

function getFakeElementChildren(element)
	--[[if not isFakeElement(element) then
		outputDebugString(debug.traceback())
		return
	end]]

	local children = {}
	for child,parent in pairs(element_parent) do
		if parent == element then table.insert(children,child) end
	end
	return children
end

function addFakeEventHandler(event,attached,func,propagate)
	--[[if type(event) ~= "string" or not isElement(attached) and not isFakeElement(attached) or type(func) ~= "function" then
		outputDebugString(debug.traceback())
		return
	end]]

	if propagate == nil then propagate = true end
	local this_id = next_event_id
	next_event_id = next_event_id+1
	if not events[attached] then
		events[attached] = {}
	end
	if not events[attached][event] then
		events[attached][event] = {}
	end
	events[attached][event][func] = propagate
end

function removeFakeEventHandler(event,attached,func)
	--[[if type(event) ~= "string" or not isElement(attached) and not isFakeElement(attached) or type(func) ~= "function" then
		outputDebugString(debug.traceback())
		return
	end]]

	events[attached][event][func] = nil
	if next(events[attached][event]) then return end
	events[attached][event] = nil
	if next(events[attached]) then return end
	events[attached] = nil
end

function triggerFakeEvent(...)
	local arg = {...}
	local name,element = arg[1],arg[2]

	--[[if type(name) ~= "string" or not isElement(element) and not isFakeElement(element) then
		outputDebugString(debug.traceback())
		return
	end]]

	table.remove(arg,1)
	table.remove(arg,1)
	local attached = element

	while attached do
		local funclist = events[attached] and events[attached][name]

		if funclist then
			for func,propagate in pairs(funclist) do
				if propagate then
					stack_source[event_source_stack_pos] = fake_source
					stack_this[event_source_stack_pos] = fake_this

					event_source_stack_pos = event_source_stack_pos+1
					stack_source[event_source_stack_pos] = element
					stack_this[event_source_stack_pos] = attached

					fake_source,fake_this = element,attached
					func(unpack(arg))

					stack_source[event_source_stack_pos] = nil
					stack_this[event_source_stack_pos] = nil
					event_source_stack_pos = event_source_stack_pos-1

					fake_source = stack_source[event_source_stack_pos]
					fake_this = stack_this[event_source_stack_pos]
				end
			end
		end

		attached = element_parent[attached] or getElementParent(attached)
	end

	local children = element_children[element]
	if children then
		for child in pairs(children) do
			triggerFakeEvent(name,child,unpack(arg))
		end
	end
end

if not localPlayer then
	function triggerFakeClientEvent(...)
		local arg = {...}
		local player = arg[1]
		if type(player) == "string" then
			player = root
		else
			table.remove(arg,1)
		end
		triggerClientEvent(player,"traffic_edit:sync_triggerFakeClientEvent",root,unpack(arg))
	end

	function sync_triggerFakeServerEvent(...)
		local event,element = ...
		if isFakeElement(element) or isElement(element) then
			triggerFakeEvent(...)
		end
	end
end

if localPlayer then
	function sync_createFakeElement(element,elmtype,id)
		element_type[element] = elmtype
		element_id[element] = id
	end

	function sync_destroyFakeElement(element)
		triggerFakeEvent("onClientElementDestroy",element)
		element_type[element] = nil
		element_id[element] = nil
		for dataname,data in pairs(element_data) do
			data[element] = nil
		end
	end

	function sync_setFakeElementParent(element,parent)
		setFakeElementParent(element,parent)
	end

	function triggerFakeServerEvent(...)
		triggerServerEvent("traffic_edit:sync_triggerFakeServerEvent",root,...)
	end

	function sync_triggerFakeClientEvent(...)
		local event,element = ...
		if isFakeElement(element) or isElement(element) then
			triggerFakeEvent(...)
		end
	end

end

function getFakeElementByID(id)
	--[[if type(id) ~= "string" then
		outputDebugString(debug.traceback())
		return
	end]]

	for element,this_id in pairs(element_id) do
		if id == this_id then return element end
	end
end

if not localPlayer then
	addEvent("traffic_edit:sync_triggerFakeServerEvent",true)
	addEventHandler("traffic_edit:sync_triggerFakeServerEvent",root,sync_triggerFakeServerEvent)
else
	addEvent("traffic_edit:sync_triggerFakeClientEvent",true)
	addEventHandler("traffic_edit:sync_triggerFakeClientEvent",root,sync_triggerFakeClientEvent)
	addEvent("traffic_edit:sync_createFakeElement",true)
	addEvent("traffic_edit:sync_destroyFakeElement",true)
	addEvent("traffic_edit:sync_setFakeElementParent",true)
	addEventHandler("traffic_edit:sync_createFakeElement",root,sync_createFakeElement)
	addEventHandler("traffic_edit:sync_destroyFakeElement",root,sync_destroyFakeElement)
	addEventHandler("traffic_edit:sync_setFakeElementParent",root,sync_setFakeElementParent)
end

addEvent("traffic_edit:sync_setFakeElementData",true)
addEventHandler("traffic_edit:sync_setFakeElementData",root,sync_setFakeElementData)

if not localPlayer then
	function syncFakeElementList()
		triggerClientEvent(client,"traffic_edit:getElementList",root,element_type,element_id,element_parent,element_children,element_data)
	end
	addEvent("traffic_edit:requestElementList",true)
	addEventHandler("traffic_edit:requestElementList",root,syncFakeElementList)
else
	function getFakeElementList(types,ids,parents,children,data)
		element_type = types
		element_id = ids
		element_parent = parents
		element_children = children
		element_data = data

		initEditor()
	end
	addEvent("traffic_edit:getElementList",true)
	addEventHandler("traffic_edit:getElementList",root,getFakeElementList)

	function requestElementList()
		triggerServerEvent("traffic_edit:requestElementList",root)
	end
	addEventHandler("onClientResourceStart",resourceRoot,requestElementList)
end

