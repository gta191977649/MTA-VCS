# Little Haiti car crusher

Drive an automobile under the hanging magnet in the eastern part of the Little Haiti junkyard and get out. The pickup rectangle is centered at (-1267.255, 130.228). The crane collects one stationary empty car at a time, swings it into the crusher, releases it, and returns. The hinged lid closes and the delivering driver receives the scrap value. The San Andreas information pickup (model 1239) gives the original GTA III help through the VCS frontend and respawns after 30 seconds.

## Port references

GTA III's decoded main.txt line 412 activates the Harwood crane. The layout maps the original pickup rectangle, drop coordinates, heading, information pickup, and IPL placements together onto the junkyard floor. The crane legs, cab, magnet, crusher body, lid, and service equipment come from the original GTA III models. The crane travels along angular, radial and vertical axes using CCrane's native rates. CGarage waits three seconds before closing, records the crushed vehicle at full closure, and shakes for three seconds before reopening.

The machine uses positional WAVs from the GTA III PC sound bank. The crane magnet runs at 6000 Hz and the opening and closing press uses the fishing-boat idle sample at 6543 Hz. Magnet pickup and lid stops use the original car and panel impacts. The three-second shake mixes the five car and six panel impacts at approximately half pitch into one synchronized track. Playback follows the same server timestamps as the animation, including when a listener arrives mid-cycle.

The award is the integer part of min(125, 25 + monetaryValue × health / 500000), using the vehicle's active handling value. The server tracks the player who left the driver's seat inside the pickup rectangle. An unattended vehicle without a delivering player can be crushed without crediting a bystander.

## Multiplayer and mission integration

The server reserves the target, attaches it to a replicated hook, controls the drop, and issues the payment. It sends timestamped movement phases. Each client samples those phases every rendered frame for the crane cab, magnet, attached vehicle, lid, and crusher shake. A clock handshake gives late observers the current phase. If the resource stops during handling, the vehicle returns to its pickup position with its original collision, lock, and frozen state. The next driver can deliver it again.

Mission resources can call the server export `exports.car_crusher:setCrusherMissionVehicle(player, vehicle)`. Pass `false` to clear the assignment. The MEAT1 and JOEY5 help condition requires the designated vehicle inside the transformed 20-unit proximity check and shares one help flag per player session. A mission can listen for the server event `onCarCrusherCrushed` on `root`. Its source is the specific vehicle immediately before removal, and its arguments are the delivering player (if present) and calculated scrap value. A wreck or interrupted transfer does not emit the event.

Run the multiplayer regression from the repository root with `lua5.1 tools/check_vcs_car_crusher.lua`.
