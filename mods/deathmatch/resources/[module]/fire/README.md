# VCS fire

The server manages 40 fire slots per game dimension. A client joining partway through a fire receives its elapsed time, strength, type and world. SkyGfx owns particle rendering, lights and positional sounds. Fire Fighter and Fire Copter retain their mission timers, target ownership and rescue conditions.

## Server exports

| Call | Result and ownership |
| --- | --- |
| `StartScriptFire(owner, host, viewer, size)` | Returns a fire ID or `false`. The owner is an element. Destroying it extinguishes the fire. An optional host supplies a moving source. A ground fire uses the owner's position at creation. The player supplied as viewer receives the mission effect. Repeating the call on the same owner returns the active ID. The default size is 0.8. |
| `ExtinguishPointWithWater(x, y, z, radius, interior, dimension, elapsedMs)` | Wet the first ordinary fire in range and return whether water reached it. Pass the time represented by the input sample in milliseconds. The fire emits steam until its strength falls below zero. Mission scripts remove their own fires. |
| `SetObjectHealth(object, health, damageMultiplier)` | Implements the positive object health assigned by script opcode 0490. The signed-byte health range is 0–127. A positive value enables ignition by flame weapons. Zero clears this state. The optional multiplier represents the original object-data damage multiplier and defaults to 1. An opted-in object is destroyed when its fire damage exhausts this health. |

## US PS2 evidence

| Original code or data | Behavior used in the port |
| --- | --- |
| `002BD340`, `002BD438`, `002BD478` | Initialize strength to 1. Scan 40 records of 64 bytes in slot order. |
| `002BD6F0`, `002BD7C8` | Ground fire lasts 10 seconds. Attached car fires last 4–5 seconds, NPC fires 10–11 seconds and player fire 3333 ms. |
| `002BDDC8`, `001D7940` | Recover 0.002 strength per 20 ms. Emit CARFLAME and CARFLAME_SMOKE at 400, 200 or 80 ms according to the 0.3 and 0.7 thresholds. Fire inflicts 1.2 damage per 20 ms. Player damage carries a 0.33 multiplier. Armour absorbs damage first. Ground contact tests squared distance against 2. |
| `002BEAB8`, `00186AA8` | Water suppresses strength by 0.012 per 20 ms and emits three steam puffs. Cannon points use a radius of 4 and vertical acceleration of −0.009 per 20 ms step. |
| `0013ECA4–0013EED8` | A damaged automobile below 250 health emits types 27, 57 and 56 each PS2 frame. The burning clock reaches 5000 ms before the explosion. Repairing above the threshold cancels it. |
| `002E16C0`, `002E23A0` | A Molotov creates a size-0.7 ground fire, a three-second hot area and expanding rings. Car wrecks run a 4250 ms sequence. |
| `002CA078`, `002C9D70` | One stationary type-74 muzzle particle lasts 100 ms. Five more begin a direction vector ahead, each runs at 0.9 times the preceding velocity and lasts 600 ms. |
| `00179708`, `00179B58`, inflated `PS2/GAME.DTZ` at `0x3D7530 + 33 × 0x70` | Weapon 33 uses the 100-slot area-shot pool. Its recorded shot speed is 0.65, initial squared hit radius is 1.2, rate is 100 ms and lifetime is 1000 ms. |
| `003113E0`, `00197068`, `00132F30` | Script command 0490 assigns object health. Flame weapons test nearby objects for a positive value. The object's damage multiplier is applied before integer truncation. |

MTA supplies weapon aim, vehicle transforms, damage notifications and explosion positions. The server reconstructs a player's flame shot from the reported aim direction and server-side player position. Exact PS2 muzzle-bone offsets, random spread, some object destruction effects and the original water cannon nozzle geometry remain approximations. The client uses native ped fire reactions and filters native continuous burn damage during a managed fire. Engine damage from unrelated gameplay resources continues to apply.
