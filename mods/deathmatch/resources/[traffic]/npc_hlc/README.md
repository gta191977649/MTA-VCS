# NPC high-level control documentation

NPC HLC allows you to control peds from your scripts easily. It does the lower level job for you. You can assign the task to the ped and NPC HLC will use control states, camera rotations and other client-side stuff to do the rest. Another good thing NPC HLC can do is server-side syncing. When ped has no syncer, the server becomes the one. It will use setElementPosition and a few other functions to simulate the ped movement, so even peds which are far away from any player will move. This syncing is less accurate and does not work with all tasks, though.

Keep in mind that resource is in the beta stage and some settings, functions and events are very likely to change in the future versions.

How the ped controlling works: you create the ped, enable the HLC functionality and assign a few tasks. The ped completes the first task, then another, in the same order they were added, and stops when all tasks are completed.

## Resource settings

`meta.xml` has a setting called `server_colchecking`. It allows you to choose whether to use collision detection when peds move without the syncing player. `"true"` enables it, preventing the peds from getting stuck inside each other, but increasing CPU and memory usage. Any other value disables it. Server coldata is needed for this setting to be effective. If it is not running, the collision detection will be disabled.

`control_npc_s.lua` has `UPDATE_INTERVAL_MS` variable. It is the time in milliseconds. It determines how often peds with no syncers are updated server-side. Default value is `2000`.

## Exported functions

When NPC HLC resource is running, other resources can call its functions in this way:
```
exports.npc_hlc:functionName(arguments)
```

The list of all functions exported by NPC HLC:
```
enableHLCForNPC (npc, walkspeed, accuracy, drivespeed)

Server-only function

Enables high-level control functionality for the specified ped. This is the first function which must be called before using other functions on the ped.

    npc: The ped you want to enable the HLC for
    walkspeed: Walking speed of the ped. Can be "walk", "run", "sprint" and "sprintfast". Default value: "run"
    accuracy: Weapon accuracy of the ped. Can range from 0 (worst) to 1 (best). Default value: 1
    drivespeed: Maximum driving speed of the ped. Measured in GTA velocity units. Default value: 40/180

Returns true if HLC was enabled for the ped, false if it is already enabled or invalid arguments were given.
```

```
disableHLCForNPC (npc)

Server-only function

Disables high-level control functionality for specified ped. After doing so, you cannot use other HLC functions on the ped unless you re-enable it using enableHLCForNPC.

    npc: The ped you want to disable HLC for

Returns true if HLC was disabled for the ped, false if it was not enabled before the function was called or invalid arguments were given.
```

```
isHLCEnabled (npc)

Server and client function

Checks if high-level control functionality is enabled for specified ped.

    npc: The ped you want to check

Returns true if HLC is enabled for the ped, false if it is not or invalid arguments were given.
```

```
setNPCWalkSpeed (npc, speed)

Server-only function

Sets the ped's on-foot speed.

    npc: The ped whose speed you want to change
    speed: Ped's walking speed. Can be "walk", "run", "sprint" or "sprintfast"

Returns true if walking speed was set successfully, false if invalid arguments were given.
```

```
getNPCWalkSpeed (npc)

Server and client function

Gets the ped's on-foot speed.

    npc: The ped whose speed you want to get

Returns walking speed of the ped or false if invalid arguments were given.
```

```
setNPCWeaponAccuracy (npc, accuracy)

Server-only function

Sets the ped's weapon accuracy.

    npc: The ped whose accuracy you want to change
    accuracy: Ped's accuracy. Can range from 0 to 1

Returns true if accuracy was set, false if invalid arguments were given.
```

```
getNPCWeaponAccuracy (npc)

Server and client function

Gets the ped's weapon accuracy.

    npc: The ped whose accuracy you want to get

Returns accuracy of the ped or false if invalid arguments were given.
```

```
setNPCDriveSpeed (npc, speed)

Server-only function

Sets the ped's maximum driving speed.

    npc: The ped whose speed you want to change
    speed: Ped's driving speed in GTA velocity units

Returns true if driving speed was set, false if invalid arguments were given.
```

```
getNPCDriveSpeed (npc)

Server and client function

Gets the ped's maximum driving speed.

    npc: The ped whose speed you want to get

Returns driving speed of the ped or false if invalid arguments were given.
```

```
addNPCTask (npc, task)

Server-only function

Adds a task to the ped's task sequence.

    npc: The ped which you want to add the task for
    task: A table containing the task data

Returns true if the task was added, false if invalid arguments were given.
```

```
clearNPCTasks (npc)

Server-only function

Clears all tasks from the ped's task sequence, therefore stopping all actions.

    npc: The ped whose task sequence you want to clear

Returns true if sequence was cleared, false if invalid arguments were given.
```

```
setNPCTask (npc, task)

Server-only function

Clears the ped's task sequence and adds the specified task, therefore making the ped perform it instantly.

    npc: The ped which you want to set the task for
    task: A table containing the task data

Returns true if the task was set, false if invalid arguments were given.
```

## Events
```
"npc_hlc:onNPCTaskDone" (task)

Server-side event

Gets triggered when the ped completes the task.

    source: The ped which completed the task
    task: The task which was completed
```

## Task data format

The task is a table which stores the task name on the first index and a few parameters on the following indices.

Tasks list:
```
{"walkToPos", x, y, z, distance}

Walk straight towards the specified point until the distance is short enough.

    x, y, z: Walking destination
    distance: The distance at which the task is completed
```

```
{"walkAlongLine", x1, y1, z1, x2, y2, z2, offset, enddistance}

Walk along the line until the ped is near enough to the ending point.

    x1, y1, z1: Starting position of the line
    x2, y2, z2: Ending position of the line
    offset: The distance which the ped pushes the nearest point of the line towards the ending point to get the actual destination point. The smaller it is, the more the ped tries to stay near the line.
    enddistance: The distance to the end of the line at which the task is completed
```

```
{"walkAroundBend", x0, y0, x1, y1, z1, x2, y2, z2, offset, enddistance}

Walk along the arc until the ped is near enough to the ending point.

    x0, y0: The point which the arc is bent around
    x1, y1, z1: Starting position of the arc
    x2, y2, z2: Ending position of the arc
    offset: The distance which the ped pushes the nearest point of the arc towards the ending point to get the actual destination point. The smaller it is, the more the ped tries to stay near the arc.
    enddistance: The distance to the end of the arc at which the task is completed
```

```
{"driveToPos", x, y, z, distance}

Drive straight towards the specified point until the distance is short enough.

    x, y, z: Driving destination
    distance: The distance at which the task is completed
```

```
{"driveAlongLine", x1, y1, z1, x2, y2, z2, offset, enddistance}

Drive along the line until the ped is near enough to the ending point.

    x1, y1, z1: Starting position of the line
    x2, y2, z2: Ending position of the line
    offset: The distance which the ped pushes the nearest point of the line towards the ending point to get the actual destination point. The smaller it is, the more the ped tries to stay near the line.
    enddistance: The distance to the end of the line at which the task is completed
```

```
{"driveAroundBend", x0, y0, x1, y1, z1, x2, y2, z2, offset, enddistance}

Drive along the arc until the ped is near enough to the ending point.

    x0, y0: The point which the arc is bent around
    x1, y1, z1: Starting position of the arc
    x2, y2, z2: Ending position of the arc
    offset: The distance which the ped pushes the nearest point of the arc towards the ending point to get the actual destination point. The smaller it is, the more the ped tries to stay near the arc.
    enddistance: The distance to the end of the arc at which the task is completed
```

```
{"walkFollowElement", followed, distance}

Try to stay in the range of the specified element.

    followed: The element to follow
    distance: The maximum distance to the element
```

```
{"shootPoint", x, y, z}

Shoot at the specified point.

    x, y, z: The point to shoot at
```

```
{"shootElement", target}

Shoot at the specified element.

    target: The element to shoot at
```

```
{"killPed", target, shootdist, followdist}

Shoot at the ped and try to stay in range.

    target: The ped to shoot at
    shootdist: Maximum shooting distance
    followdist: The distance at which to start walking towards the target
```

```
{"waitForGreenLight", direction}

Do nothing until a certain traffic light state. In addition to what direction parameter sets, the task will also be completed if all lights are yellow or turned off.

    direction: A parameter determining which traffic lights should be green. "NS" is for north-south, "WE" is for west-east and "ped" is for red states of all vehicle traffic lights.
```

## Example

The following example creates a ped at the center of the map. The ped walks to the north and then to the east.
```
local ped = createPed(0, 0, 0, 3) --create the ped
exports.npc_hlc:enableNPCForHLC(ped) --make HLC functions work on the ped
exports.npc_hlc:addNPCTask(ped, {"walkAlongLine", 0, 0, 3, 0, 20, 3, 2, 4}) --walk 20 units to the north
exports.npc_hlc:addNPCTask(ped, {"walkAlongLine", 0, 20, 3, 20, 20, 3, 2, 4}) --walk 20 units to the east
```

*Original page for this resource available via web archive: https://web.archive.org/web/20161129144418/http://crystalmv.net84.net:80/pages/scripts/npc_hlc.php*
