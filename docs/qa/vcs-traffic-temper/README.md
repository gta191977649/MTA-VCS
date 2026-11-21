# Traffic temperament on a real MTA client

On November 21, 2026, an MTA 1.7 client joined an isolated loopback server running the workspace traffic resources. Each run required a fresh server-ready log entry, player join and temporary-resource client-ready event. Production traffic supplied and controlled the civilian and police drivers. The fixture positioned the player and applied player inputs.

## One driver from impact to melee

Run `hot-500359` followed ped `0x1B7` (VCS model 37, `CIVMALE`, temper 55, fear 30), its original traffic car `0x1B6`, and player `0x1A4`. Times are measured from selection of that driver.

| Elapsed | Observation |
| --- | --- |
| 1.154 s | The player SUV hit the selected car. Client horizontal velocity magnitudes were 0.480 for the player and 0.270 for the NPC in MTA velocity units. |
| 1.498–1.779 s | The server recorded committed road rage and assigned `driveAtPed` revision 58. The two cars made another physical contact during this assignment, with NPC speed 0.328 and player speed 0.289. [Moving contact and style 2](hot-500359-return-contact-side.jpg) |
| 3.314–4.790 s | The server assigned `stopVehicle` revision 71. The NPC left seat zero at 4.748 s and received `approachDriverDoor` revision 82. |
| 6.378–11.409 s | Native start-enter identified the tracked player as the occupant of seat zero in the player SUV. The client recorded `TASK_SIMPLE_CAR_SLOW_DRAG_PED_OUT` from 8.138 s. The server confirmed the player's exit with the tracked NPC as jacker at 11.409 s. |
| 11.716–18.188 s | The server assigned `killPed` revision 126. Six subsequent server player-damage events named the same NPC and weapon 0. Their recorded losses were 1, 1, 3, 1, 2 and 2. |

The fixture placed the SUV seven units behind the traffic vehicle, set its initial forward velocity to 0.65 and applied the accelerator. After the impact, it placed the SUV fourteen units ahead, applied throttle for another 550 ms, then used the handbrake. The NPC exited before the optional close-placement retry in this run. Production code controlled its steering, braking, exit, door approach, extraction and attacks throughout.

## Native extraction and sync display

A repeat on the final native-executor code, run `hot-351426`, tracked model 37 in car `0x1DB`. The fixture placed the SUV alongside at 7.615 s. The driver exited at 9.513 s and reached the verified left driver door. At 11.465 s the server accepted its native executor acknowledgement. The mid-drag capture shows **Road rage > Pull driver out** with **Sync: native executor** in green. The body of the SUV partially obscures the seated player in this view. The client recorded the native slow drag at 12.974 and 14.824 s. The server confirmed that the same NPC removed the player at 16.794 s, left the SUV itself at 18.799 s and inflicted unarmed player damage at 19.738 s. [Door approach](hot-351426-door-approach-side.jpg) · [Native pull-out in progress](hot-351426-drag-side.jpg) · [Melee after extraction](hot-351426-melee-side.jpg)

Run `hot-504983` photographed the same sequence from the driver's side. The model 41 driver (temper 100, fear 0) reached into the open SUV door with the green native-executor label visible. The client recorded the slow drag at 10.209 and 12.018 s. The server confirmed the player's exit with this NPC as jacker at 13.957 s and the first unarmed hit from the NPC at 16.808 s. [Pulling the player out](hot-504983-drag-late-side.jpg) · [Punching the player after extraction](hot-504983-melee-side.jpg)

## Comparison runs

| Scene | Measured result |
| --- | --- |
| Two civilian drivers in the same group | Model 41 (`CIVMALE`, temper 100, fear 0) committed to `driveAtPed` after a player collision. Model 19 (`CIVMALE`, temper 10, fear 40) received the same rear-impact fixture and selected `crashFlee`. Its distance from the parked player reached 23.6 units by 5.7 s. [Hot-tempered driver](hot-586811-driving-side.jpg) |
| Attacking the car from the street | Run `body-498339` struck a civilian car with a bat. The fixture briefly held it in place to land the blow. Its driver committed at 1.798 s, left the car at 3.130 s and inflicted the first confirmed unarmed damage at 3.363 s. [On-foot confrontation](body-498339-encounter-foot-side.jpg) |
| Police | The selected production cruiser driver (model 8, `COP`) exited after a bat hit on the car. The HUD showed one wanted star. The same officer inflicted baton damage (weapon 3). [Officer responding](cop-628213-melee-side.jpg) |
| Emergency and gang groups | Separate fixtures created original models 12, 13 and 90 through the traffic script API and released ownership before the player swung the bat. The medic (`EMERGENCY`), firefighter (`FIREMAN`) and gang member (`GANG7`) each entered the damage event and received `killPed`. The gang test recorded repeated unarmed player damage from model 90. These fixtures exercised personal reactions while off duty. [Medic](footmedic-535946-melee-side.jpg) · [Firefighter](footfire-541848-melee-side.jpg) |
| Controlled server wait | The fixture held server completion of a finished walk for a single test ped in the isolated copy. The owner reported `walkToPos` revision 2, complete and waiting. The rendered sync line was red. The driving and combat scenes above show green execution status. [Waiting for server](wait-487883-manual-side.jpg) |

The server and client script logs contained no Lua errors during the acceptance window. Startup emitted existing placement and deprecated-resource warnings. The server validated the source resource, scene tag, player and successful JPEG status for each linked image. Single-client runs exercised owner execution and server reconciliation. A transfer between two real clients was outside these live measurements.



## Walking queue and vehicle-hit handoff

A real MTA client connected to an isolated loopback server on 21 November 2026. A temporary Lua resource recorded server queue depth, task revision, sync owner, client walking input, seat exit, and attributed damage.

| Case | Observation |
| --- | --- |
| Walking queue | A model 23 civilian walked eight alternating three-unit legs. Server queue depth fell from 8 to 0 in 17 seconds. The seven intermediate heads had depths 7 through 1 and distinct revisions. The executor continued through each turn. |
| Ambient pedestrian | A production-spawned civilian (model 69) walked 20.66 units from its initial observation through multiple walking assignments. The live overlay displayed a walking goal and an active owner. [Golf course](walking-queue-golf.jpg) |
| Attack on an occupied vehicle | A bat strike registered 7.5 vehicle damage on the server. The same model 17 driver (temper 70, fear 30) received a brake order 129 ms later. The seat exit followed 980 ms after the observed brake order. The next combat assignment was observed 109 ms after exit and the first attributed melee damage 395 ms after exit. Task assignments were sampled and these timings describe this encounter. [At the driver's door](vehicle-hit-queue-exit.jpg) |
| Scheduler load | The isolated native regression exercised 600 tasks over 114 scheduler samples. The 95th percentile tick was 3 ms and the 99th percentile was 5 ms. The scheduler hit its budget 71 times. |

The fix addresses delayed queue refills, walking waypoints passed between server samples, and confirmed path obstructions. The screenshot from the original report has no queue revision trace or clearance sample to identify which condition applied at that location.
