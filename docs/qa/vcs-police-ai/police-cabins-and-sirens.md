# Police cabins and emergency lights

A real MTA 1.7 client joined an isolated VCS server on loopback. The test used native emergency vehicle bases, the production model tagger and SkyGfx. A second FBI car came from the public `createVcsVehicle(193, ...)` export. The temporary fixture placed the player in seat zero, opened the passenger door for the interior view and captured the scene in sunlight and at night. Each linked image is an original 960 × 600 client screenshot accepted by the server.

| Vehicle | Native base | Visible result |
| --- | --- | --- |
| FBI Washington (193) | 598 | The white seat backs in the original test are dark in the corrected view. The driver remains visible through the windscreen. [Before](fbi-cabin-before.jpg) · [Windscreen](fbi-cabin-windshield-after.jpg) · [Interior](fbi-cabin-dashboard-after.jpg) · [Dashboard beacon at night](fbi-beacon-night-after.jpg) |
| Vice Cheetah (204) | 597 | The dashboard top is dark and the console and steering wheel retain their original low-resolution detail. [Before](vice-cabin-before.jpg) · [After](vice-cabin-dashboard-after.jpg) · [Dashboard beacon at night](vice-beacon-night-after.jpg) |
| Marked cruiser (207) | 596 | The roof bar has separate left and right lens materials. Both were bound when the siren was on and removed when it was off. [Night view](cruiser-lenses-night-after.jpg) |
| Enforcer (234) | 427 | [Roof lamps at night](enforcer-lenses-night-after.jpg) |
| VCPD Electra (191) | 523 | [Motorcycle lamps at night](electra-lights-night-after.jpg) |
| FBI Rancher (268) | 490 | [Emergency lights at night](rancher-lights-night-after.jpg) |

The FBI and Vice dashboard beacons each produced a visible red flash. In the traffic FBI, the 11 × 11 pixel sample around the beacon had zero red-dominant pixels after the night off state settled. All 121 pixels became red-dominant when lit. Native world-sound event group 17, index 10 played when each undercover car switched on. Audio evidence comes from the client's native sound event. No recording or listening assessment was made.

## Player horn input

The key test initialized each car with its siren off and left it in the driver's control. The Windows automation pressed the configured H key in the game window. For each press the fixture recorded the client key event, seat-zero ownership and the native siren flag on the server and the client after 550 ms. Before the correction, a key down and up could land inside one game frame and leave the siren off on both undercover cars and the standard cruiser base.

The final run began with a fresh game process. The client cache and server archive both had MD5 `859DCCB923CCE240DFC93EA5920CF53D`. A previous reconnect had retained an open, outdated vehicle archive. Its captures were excluded from the final input check.

All six traffic-tagged vehicles in the table and a separately spawned FBI Washington passed both H presses. The client's key clock measured 0–1 ms per press in this run. All 14 transitions matched between the native siren flag on the server and the flag on the driving client. The fixture recorded native siren event 17/10 on all six traffic models. [FBI after first H](horn-193-traffic-on.jpg) · [FBI after second H](horn-193-traffic-off.jpg) · [Cruiser after first H](horn-207-traffic-on.jpg) · [Cruiser after second H](horn-207-traffic-off.jpg)

The observer triggered a full Lua garbage collection inside SkyGfx before reading each vehicle's applied materials. One initial cruiser read preceded streaming. All 168 subsequent reads reported active vehicle bindings, including all 102 FBI and 11 Vice samples. Both undercover cars kept their glass and three reflection materials while their dashboard beacons switched on and off. The standalone FBI retained its binding for approximately one minute.

The final visual sweep received all 56 requested screenshots. The client script and server logs showed no script warnings or errors during the scenes. The fixture released the horn control and restored the camera before the isolated game client and server were closed.
