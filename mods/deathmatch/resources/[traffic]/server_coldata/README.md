# Server collisions documentation

Server collisions resource is a way to do simple collision checking between elements server-side, eliminating the need to rely on the client in some cases. It uses bounding boxes with Z rotations only. Its initial purpose was preventing NPC HLC traffic cars from getting stuck in each other.

## Exported functions

When Server collisions resource is running, other resources can call its functions in this way:
```
exports.server_coldata:functionName(arguments)
```

The list of all functions exported by Server collisions:
```
getModelBoundingBox (model, part)

Server-only function

Gets the bounding box or one of its components of the model. x1, y1, z1 are the lower coordinates, x2, y2, z2 are the higher ones.

    model: ID of the model whose data you want to get
    part: Component of the bounding box. Can be one of these values: "x1", "y1", "z1", "x2", "y2", "z2" or false. Default value: false

Returns the specified bounding box component. If none specified, returns all coordinates in order: x1, y1, z1, x2, y2, z2. false if invalid arguments were given.
```

```
generateColData (startelement)

Server-only function

Generates the collision data map of all peds, players and vehicles which are children or sub-children of the specified element. Calls clearColData before doing so.

    startelement: The element whose children you want to get. Default value: root

Returns true if data has been generated, false if invalid startelement specified.
```

```
clearColData ()

Server-only function

Clears all collision data to free memory. Done automatically by generateColData. When this is done, results returned before by createModelIntersectionBox and getElementIntersectionBox are no longer valid.

Returns true.
```

```
createModelIntersectionBox (model, x, y, z, r)

Server-only function

Creates a bounding box of the model in the specified coordinates.

    model: ID of the model whose bounding box you want to create
    x, y, z: Position of the bounding box
    r: Z Rotation of the bounding box

Returns the ID of the created bounding box, false if invalid arguments were given.
```

```
getElementIntersectionBox (element)

Server-only function

Gets a bounding box of the specified element.

    element: The element whose bounding box you want to get

Returns the ID of the created bounding box, false if invalid arguments were given.
```

```
updateElementColData (element)

Server-only function

Updates the collision data of the element in the collision data map. Needed if you want to check collisions when you create or move the element after generating the collision data map.

    element: The element whose collision data you want to update

Returns true if collision data was updated, false if invalid arguments were given.
```

```
doesModelBoxIntersect (box, dim, excluded)

Server-only function

Checks if the given bounding box intersects with any other bounding box in the collision data map.

    box: Bounding box which you want to check
    dim: Dimension whose collision data map you want to check the box against
    excluded: Box in the collision data map which you want to be ignored

Returns true if the box intersects, false if it does not or if invalid arguments were given.
```

```
doModelBoxesIntersect (b1, b2)

Server-only function

Checks if two bounding boxes intersect.

    b1, b2: Bounding boxes which you want to check

Returns true if boxes intersect, false if they do not or if invalid arguments were given.
```

### Example

The following example creates many cars at random positions at the center of the map without getting them stuck inside each other:
```
exports.server_coldata:generateColData(root) --prevent the cars from intersecting elements which are already there
for num = 1, 300 do
    local x, y, z = math.random()*20, -math.random()*20, 3.5 --get the random position
    local r = math.random()*360 --get the random rotation
    local box = exports.server_coldata:createModelIntersectionBox(492, x, y, z, r) --create the bounding box for checking
    if not exports.server_coldata:doesModelBoxIntersect(box) then --check if the box intersects any element
        local car = createVehicle(492, x, y, z, 0, 0, r) --if there is no intersecting element, create the car
        exports.server_coldata:updateElementColData(car) --store the bounding box of created car to the collision data map for the following cars
    end
end
exports.server_coldata:clearColData() --free the memory if we do not use the functions again soon
```

*Original page for this resource available via web archive: https://web.archive.org/web/20161127100905/http://crystalmv.net84.net:80/pages/scripts/server_coldata.php*
