function testGenerateFile() 
    local nodes_block = {
        {0,0,10,0,0},
        {5,5,10,0,0},
        {10,10,10,0,0},
    }

    local connection_block = {
        {1,2,-1,2,1+1*4,50,1,1,1000}
    }

    local forbidden_block = {}
    -- write header
    local f = fileCreate("testpath")
    fileWrite(f,dataToBytes("3i",#nodes_block,#connection_block,#forbidden_block))

    -- write nodes
    for node_index,node in ipairs(nodes_block) do 
        local x,y,z,rx,ry = unpack(node)
        x,y,z = math.floor(x*1000),math.floor(y*1000),math.floor(z*1000)
		rx,ry = math.floor(rx*1000),math.floor(ry*1000)
        fileWrite(f,dataToBytes("3i2s",x,y,z,rx,ry))

    end
 
    -- write connections
    for node_index,conn in ipairs(connection_block) do 
        local n1,n2,nb,trtype,lights,speed,ll,rl,density = unpack(conn)
        fileWrite(f,dataToBytes("3i2ubus2ubus",n1,n2,nb,trtype,lights,speed,ll,rl,density))
        iprint(conn)

    end


    fileClose(f)
    print("path wroted")
end

testGenerateFile()