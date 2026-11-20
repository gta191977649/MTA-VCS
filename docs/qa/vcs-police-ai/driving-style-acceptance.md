# Driver style labels and pursuit acceptance

On November 21, 2026, a real MTA 1.7 client joined a fresh loopback server. Temporary Lua resources enabled the production `/trafficdebug ped` command, observed the server's driver rows on the connected client, and captured the rendered labels and vehicle maneuvers.

## Driver, passenger and pedestrian

A civilian driving model 201 showed **Driving style 0 - Stop for cars** alongside the rail driving task. The reported vehicle matched the car and the observed seat was zero. The fixture moved the same NPC into seat one of the same car, then onto the street. In each case, the next two sampled rows contained no numerical style or associated vehicle. The passenger and pedestrian captions, temperament and health remained visible. On foot, the NPC received a walking task. [Civilian driver](driving-style-civilian.jpg) · [Passenger](driving-style-passenger.jpg) · [On foot](driving-style-on-foot.jpg)

A separate two-star scene showed **Driving style 2 - Avoid cars** over the driver of a production VCPD cruiser on its physics driving task. The same frame shows **Driving style 0 - Stop for cars** on the civilian van alongside it. The cruiser driver's synchronized row identified seat zero and the same vehicle. [Police and civilian styles together](driving-style-police.jpg)

## Pursuit

| Scene | Observation |
| --- | --- |
| Two junctions and wanted escalation | The fixture placed a dispatched cruiser once on the approach and parked the player SUV on the target street. The client held red signal state 2. The same cruiser took the first turn on mission 2, seed 2, at two stars. After escalation to three stars its cruise command rose from 34 to 43 while its mission and seed stayed the same. At the second junction its heading was 167.3°. It turned onto the target street, heading 128.8°, within 19 units of the SUV with its original driver still in the seat. [First turn](driving-style-first-corner.jpg) · [Second red light](driving-style-second-corner.jpg) · [Target street](driving-style-target-street.jpg) |
| Moving ram, three stars | Seed-1 cruiser 0x2B9 issued **Ram turn right** with the player and cruiser moving at 0.148 and 0.347 MTA velocity units. The first reported collision followed 11 ms later. At the next collision the cruiser was 2.20 units to the player's left and 3.74 units aft, with vehicle speeds 0.193 and 0.298. The client validated the measured rear-quarter contact 227 ms after the steering pulse. Across the following 350 ms sample the SUV heading changed from 85.91° to 89.15°, a 3.24° deflection. [Moving ram](driving-style-moving-ram.jpg) |
| Moving block, two stars | Seed-1 cruiser 0x2D9 began on mission 4. The client reported the close block at 9.59 units ahead of the SUV, with both vehicles moving at about 0.176. The server sampled mission 6 and the stop task. By first contact the SUV and cruiser had slowed to 0.086 and 0.077. [Block at contact](driving-style-block.jpg) |

For the two contact scenarios the fixture positioned the player SUV relative to an existing dispatched cruiser and applied accelerator and steering input to the SUV. Production AI drove the cruiser. The observed collision establishes a moving ram attempt and contact. The run did not establish a full spin.

The game audio session produced nonzero output on all 100 meter samples over five seconds in the block scene, with median peak 0.340 and maximum 0.582. These are measurements of the game mix. The server accepted each linked 960 × 600 image for the originating client, resource and tag. The originals were visually reviewed. The client script log contained no gameplay errors during the accepted runs. The fixture restored input, camera and traffic lights. The server was stopped after verifying its process ID and executable path.

## Civilian driving policies

A separate MTA 1.7 loopback session selected ordinary civilian drivers already following production routes. The fixture called the server export `setNPCTrafficDrivingStyle` and observed speed, pedal input, route position and the synchronized driver on the client. Production traffic supplied the cars and drivers and controlled the vehicles throughout. All distances below are in world units.

| Scene | Observed response |
| --- | --- |
| Styles 5 and 3 at the same red light | On road link 704, driver 0x1D7 in car 0x1D6 responded to red signal state 2 in style 5. The car settled 8.00 units before the route waypoint at 0.002 m/s. With the signal still red, the fixture switched the same seated driver to style 3. It crossed the waypoint at 11.78 m/s. The frames show the blue car before and during entry into the intersection. [Stopped at red](style5-red-stop.jpg) · [Crossing on the same red](style3-red-cross.jpg) |
| Style 6 approaching a standing pedestrian | The fixture placed a standing pedestrian 14 units ahead of an ordinary van on link 438. The van slowed from 9.93 to 4.43 to 2.44 m/s, then stopped with 5.38 units between its center and the pedestrian. After the fixture removed the pedestrian, the same driver resumed at full throttle and reached 10.32 m/s. [Van stopped short](style6-ped-stop.jpg) · [Van driving after clearance](style6-ped-resume.jpg) |
| Style 6 approaching a crossing pedestrian | The fixture placed a pedestrian to the side of the lane and applied the normal walk and forward controls. The driver's brake engaged while the pedestrian was walking at 1.76 m/s, 10.47 units ahead. The car slowed from 5.57 m/s to zero with the pedestrian still moving across the lane. It accelerated again when the pedestrian was 2.12 units left of its centerline. Both captures show the same driver and crossing pedestrian. [Braking on approach](style6-crossing-brake.jpg) · [Pedestrian clearing the lane](style6-crossing-clear.jpg) |

An initial standing-pedestrian run exposed a gap between the three collision rays. The final runs used a full-width check for on-foot pedestrians and players in style 6. Deterministic tests also covered an occupied vehicle seat, another dimension and a pedestrian on an overpass. The server accepted all six linked screenshots from the connected player and temporary resource. Both logs were checked. During the initial pedestrian scene, Windows Core Audio recorded nonzero output from the game in 80 of 80 samples, with a median peak of 0.023 across the game mix.
