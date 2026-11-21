# Placement coverage

Source: US PS2 MAIN.txt. `car_park/spawns.lua` retains all 199 INITCG
records and the first INITCG switch state. Placement spawns initially enabled
generators plus the studio Coach ($995) for Crash! in the standalone world.
The original SAFEHOU script enables this Coach as the story progresses.
Vehicle names resolve through the live vcs_model catalog and all vehicles use
the vcs_vehicle factory. The 17 additional parked-car models are packaged with
private client IDs to avoid replacing models sharing the same native hull.
Run tools/extend_placement_models.py after regenerating the traffic model resource.
SA physics settles vehicles from a 1 m
lift; original generator ground queries and per-model offsets are not yet
reproduced. The hospital Air Ambulance generators use the model's default
white primary paint (255, 255, 255) and dark red secondary paint (176, 0, 0).
The vehicle factory resolves this default when creating original model 189.
Placement retains the remaining generator colour, alarm and lock fields as data.

`pickups/weapons.lua` contains the 52 fixed INITPU weapon locations. Compatible
SA weapons are used as approximations; unsupported VCS-only weapons are logged.
Mission, shop and unlockable weapon pickups are not included. Respawn is 30 s.

`collectables/balloons.lua` contains all 99 coordinates from 99RED. It is data
only: object rendering, shooting, persistent per-player progress and rewards
are not implemented. The original NDC_REDBALLOON is model 18264 in the map
IDE, but the current loader does not export its dynamically allocated model ID.

Ghidra US SLUS_215.90, FUN_003d9480: car-generator creation checks model
availability, resolves ground height for land vehicles, adds a vehicle-derived
height, and applies the stored angle. This implementation is an approximation.

Indoor parking points carry explicit interior/dimension metadata. Generator
$1020 (mall BMX) uses interior 0, dimension 3090, matching the ENEX mall
portals. Spawn and respawn both apply the recorded room; outdoor rows default
to interior 0, dimension 0.
