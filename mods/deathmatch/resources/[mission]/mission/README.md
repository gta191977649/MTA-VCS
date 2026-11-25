# Vehicle missions

Enter an eligible vehicle as the driver and press the bound **sub-mission** control (normally **2**). The entry prompt shows the current binding. Press the control twice within 2.5 seconds to cancel an active run. Pressing the control in another eligible mission vehicle ends the current run and starts the new activity. The server also accepts `/vehiclemission`.

| Mission | Eligible VCS vehicles and start | Completion reward |
| --- | --- | --- |
| Taxi Driver | Taxi and Cabbie | Use the horn on the ground to boost jump after earning $5,000 or completing 50 fares across runs. |
| Vigilante | Police car, FBI car, Enforcer, FBI Rancher, police motorcycle, Rhino, Hunter and undercover Vice Cheetah | Complete level 15 for 50 additional points of armour capacity. |
| Paramedic | Ambulance | Complete level 15 for unlimited sprint. |
| Air Rescue | Air Ambulance | Complete level 15 for $500 and 50 additional points of maximum health. |
| Fire Fighter | Firetruck | Complete level 15 for fireproofing. |
| Beach Patrol | BF Injection | Complete level 15 for $1,500 and unlimited swimming endurance. |
| Fire Copter | Huey at the Downtown fire station | Complete five runs for an additional $500 on first completion. |
| Vice Sights | Maverick at the airport tour stand | Complete five tours for an additional $500 on first completion. |

## Races, trials and stunts

The US PS2 version has 20 named activities in 15 scripts. Vehicle activities start at their original parked vehicles. Turismo starts when the player enters either organizer marker on foot. Use the left and right arrows to browse available courses and Enter to select.

| Activities | Start and objective |
| --- | --- |
| Watersports | Take the Jet Ski at Prawn Island and race eight water circuits. |
| Quad Bike Time Trials, BMX Time Trials, Sanchez Time Trials | Use the designated Downtown Quad, BMX or Sanchez. The three series contain four, eight and twelve circuits respectively. |
| Caddy Daddy | Take the Leaf Links Caddy for the golf course trial. |
| Mashin' Up the Mall | Use the BMX inside the mall. Collect all 50 coronas. Green requires a wheelie, blue requires a stoppie, and red accepts either wheel posture or normal riding. |
| When Funday Comes | Enter the trailer-park organizer on foot for the standalone two-lap quad race. |
| Turismo | Enter the Little Havana or Vice Point organizer marker. Choose from five or four races respectively, pay the entry fee, then take an eligible vehicle to the marked starting grid. |
| Crash! and Rush! | Take the studio Coach on Prawn Island or the Linerunner in Viceport. Cause $2,000 or $1,700 of destruction respectively in three minutes. |
| Skywolf, Crims on Wings, Crims on Water Wings | Use the designated Hunter, biplane or Skimmer. Skywolf alternates flying checkpoints with drone targets. |
| Land, Sea and Air Ace; Hyman Memorial O.D.T. | Start on the Ocean Beach Sanchez or airport biplane. Switch to the marked vehicles as each leg ends. |
| Playground on the Town, Point, Dock and Park | Use the PCJ-600 at the corresponding site. The first pickup starts the timer and remaining checkpoints can be collected in any order. |
| Haiti Hover Race and Harbor Hover Race | Take the hovercraft at Little Haiti or the harbor and follow the course. |

The server keeps course wins, fastest times, lap records, best finishing positions and scores under the same account or guest profile as the service missions. Each course has its own record. Times are stored in milliseconds. A player can race another independent session on the same course. A starting grid reservation covers staging, and mission markers, countdowns, scores and payouts belong to the individual run.

Both islands are available. Vigilante, Paramedic, Air Rescue and Fire Fighter save after levels 5, 10 and 15. Beach Patrol saves every five levels. These missions continue after the reward. Fire Copter and Vice Sights end after level five and a new session starts at level one.

On Beach Patrol swimmer duties, approach in the Coastguard and put the swimmer on either side of the boat. Hold the corresponding vehicle look control and press vehicle fire. The lifeguard throws the preserver to that side. A control hint appears within 30 metres of a swimmer.

The server keeps taxi totals, checkpoints and unlocks in the resource's `vehicle_missions.db` SQLite database. Logged-in accounts and guests have separate profiles. Guests use their MTA serial. Logging in or out ends the current run and loads the selected profile.

## Integration

`leeds_engine` starts the resource after traffic and stops it before traffic during a reload. Each mission registers its original vehicle models and its start, tick and cleanup callbacks with the server lifecycle. The server checks the driver and vehicle, awards money, and removes mission-owned elements or releases borrowed traffic actors when a run ends.

Passenger entry is a traffic objective. The server reserves the requested seat, the syncer performs the native entry, and mission scripts observe actual seat occupancy. Taxi drivers and Vigilante vehicles use the traffic road graph. World markers use the shared marker resource.

Each run has a server-issued token, a participating driver, and its own objective actors, marker audience and payouts. Modules resolve client reports with `Mission.forParticipant(player, token, id)` before checking the current objective and vehicle. `Mission.participants(run)` and `Mission.notify(run, event, ...)` support participant lookup and targeted delivery. Site reservations are scoped by interior and dimension. Vehicle reservations also protect the driver seat while the driver is away. The current release supports independent drivers in the shared world.

Finishing, failing, cancelling, switching profiles, disconnecting or stopping the resource releases the run's vehicles, NPCs, markers, minimap blips and reservations. Ambient traffic actors return to traffic ownership. Client teardown removes attachments, model allocations, effects and mission HUD entries. A completion banner or result caption has its own finite display time. Garage services own their doors, bays and cameras independently. Taxi stopovers restore the camera they replaced and the driver's previous control and roof-light states.

The frontend draws the mission timer, counters and tip meter on the right. In the US PS2 executable, the HUD calls the timer at `0x00320C08` before the counter pass at `0x00320F28`. Both align values to logical X 456 on the 480 Ãƒâ€” 272 screen. Labels end at X 405, shifting farther left if the value needs more room. The first active row starts at Y 100 and each subsequent row advances by 20. Mission instructions use bottom subtitles, and the completion banner fades at screen center.

The traffic export `assignTrafficPedObjective(ped, "enterVehicle", vehicle, seat)` requests boarding for an acquired actor. Use `isMissionPedSeated(ped, vehicle, seat)` to check a completed entry. MTA can report a vehicle as occupied while its door animation is still running.

The Air Rescue hook and Fire Copter bucket swing on a 5.8125 m spring simulated every frame on each client. The pilot sends the endpoint up to eight times per second. The server checks the driver, run, reach and age of the sample and forwards it to nearby observers, who smoothly correct their local swing. Patient pickup, delivery and the spray footprint follow the moving attachment. MTA caps native armour at 100 points. To support the Vigilante reward, the server holds the additional 50 points in reserve and the frontend displays the effective total.

The frontend asset importer includes the original mission-passed tune. To update an existing generated frontend asset pack, run `python tools/import_vcs_frontend.py --mission-passed-only "<extracted US PS2 disc directory>"`.

Ghidra inspection of `SLUS_215.90` located the Paramedic never-tired flag at handler `0x002D36E0`. The health and armour reward handlers at `0x002D4AC0` and `0x002D4B70` update both the maximum and the current value. The Air Rescue rope creation and hook lookup handlers are `0x003D8A00` and `0x003D8E88`.

The PS2 source scripts are `TAXI` (19), `VIG` (15), `PARAMED` (14) and `CHOPLIF` (17). The implementation uses their original location tables and checks the original VCS model ID independently of the MTA parent model.

The additional SCM scripts are `FIRETRK` (16), `BEACHPL` (33), `TOURVCS` (34) and `FIREHEL` (35). Fire Copter uses the 79 authored fires across five dispatches and the original type-3 bucket, model 7350. The Coastguard lifeguard throws model 7375. The prop importer accepts `--bucket` or `--lifesaver` to rebuild these meshes and textures.

In the US executable, fireproof opcode 04D4 sets the player's fireproof flag at `0x002D5B50`. Swimming opcode 0532 writes player-info offset +0x164 at `0x002D6058`. The swimming update at `0x001F3060` checks this flag before deducting endurance based on horizontal velocity. MTA uses this endurance budget to limit fast swimming and displays it through the frontend stamina bar. Underwater breathing continues to use MTA oxygen.

### Air Rescue rig

In `MAIN.txt`, `CHOPLIF_13450` creates a type-4 rope and stores its end object in `$5407`. The VCS PS2 executable's object constructor at `0x00227560` reads this type's model ID from `ModelIndices + 0x8E` and places the object at the last rope node. In the US disc's `GAME.DTZ`, that field contains 7353, whose model-name hash `0xD7BD7ED2` resolves to `ndc_helirescuerig`. The adjacent fields select the helicopter bucket (7350) and the cargo magnet (7392). `CHOPLIF_10278` attaches each patient to the rescue rig at a radius of 1.2 m and local Z of -1.4 m.

The synchronized, collisionless end object owns the patients. Each streamed client displays the original rig mesh at its native scale, including while empty. Its bounds measure 1.94 m across and 2.15 m high. Streaming out or ending the mission removes the visual. The frontend draws the cable between the helicopter and the end object. The fixed attachment reproduces the deployed reach without simulating the PS2 rope segments.

To rebuild the mesh and its four-material texture dictionary, run `py tools/import_vcs_rescue_rig.py "<extracted US PS2 disc>" --converter "<mta_map_tools checkout>"`.

## Race drivers

The mission resource owns grid slots, steering targets, scoring checkpoints, laps and results. The traffic resource owns vehicle controls and carries the current order across changes in network ownership. Turismo accepts another vehicle of the selected class during the return timer. The trailer-park race requires the supplied quad. A weapon hit by the participant on an AI driver in their own race causes immediate disqualification, even if the driver survives. Hits by other players or NPCs, vehicle collisions, and shots into the rival vehicle body do not count as attacks on the driver.

Server resources can call the following exports on `npchlc_traffic`. The driver and density exports return a boolean. The resource that starts a driver owns its orders until release.

- `startMissionRaceDriver(ped, vehicle, 2)` acquires a traffic ped seated in the driver seat of a supported road vehicle.
- `setMissionRaceTarget(ped, x, y, z, cruiseSpeed, nextX, nextY, straight, arrivalRadius)` supplies the current target and the SCM cruise command. The optional next coordinate supplies the outgoing direction. A true `straight` selects direct steering. The optional arrival radius is in world units. Updating speed at the same target retains route progress.
- `stopMissionRaceDriver(ped)` clears the assignment and releases driver control.
- `clearAreaOfCars(x, y, z, radius, interior, dimension, keep)` retires eligible ambient road vehicles and their occupants, returning the number cleared. Turismo uses a 20-unit radius before rival creation and a 100-unit radius at each occupied grid slot before countdown (RACEHUB_8763 and RACEHUB_10485).
- `setMissionTrafficDensity(player, multiplier)` adjusts the participant's ambient road population budget. Pass `false` to release it.

Streamed racers use the projected lane target, speed-dependent steering limit and proportional pedals from reVC's `CCarCtrl::SteerAICarWithPhysicsFollowPath` in `src/control/CarCtrl.cpp`. The MTA controller also checks upcoming curvature and the available turning radius when selecting its approach speed. Streamed and off-screen racers share the vehicle branch of `FindAngleToWeaveThroughTraffic`. Its `WeaveForOtherCar` calculation uses closing velocity, vehicle dimensions and bearing to find a passing angle. On road links MTA clips candidate headings to the carriageway and checks the turn, lateral movement and return to parallel travel against moving vehicles and the local road surface.

### PS2 behavior references

In SLUS-215.90 the SCM handler at `003D0910` retains a matching coordinate objective within a squared XYZ distance of 0.01. Otherwise it calls `0043B858` and selects autopilot mission 8 for a road route or 9 for direct approach. The corresponding steering routines are `00438A80` and `00439580`. Opcode 0050 at `003D1128` truncates cruise speed and caps it at the handling maximum times 60. Opcode 0051 at `003D1240` writes the driving style byte at vehicle offset 0x214. The mission repeatedly selects style 2. The San Andreas source counterpart for road joining, physics status, cruise command and style ownership is `CTaskComplexCarDriveMission::SetUpCar`.

`RACEHUB_4213` applies tagged corner limits, the leader distance cap and the adjustment for a nearby rival directly ahead. `RACEHUB_4749` gates recovery on visibility and proximity to the driver, usable vehicle and destination. `RACEHUB_5209` finds an off-screen catch-up point among the three rings behind the player. The normal recovery uses a forward speed of 10 SCM units and catch-up uses 15. At the finish, RACEHUB_6469 assigns temporary car action 5 to the first three finishers for three, two and one seconds respectively. MTA uses the participant's camera for the visibility sample and rechecks eligibility on the server before moving a vehicle. The player-attack disqualification extends the SCM racer-death condition.

## Swinger's Club

Press **E** at the Leaf Links driving-range marker on foot, or use `/golf`. A lone golfer starts immediately. With another eligible player nearby, choose solo or send a challenge. The invited golfer presses **E** at the range to respond. Golf uses the shared per-player mission reservation.

Press **Space** to begin, then press it once for power and once for aim. The green sections give maximum power and straight aim. Hold **Space** during flight to fast-forward. **Backspace** leaves the round or withdraws a pending challenge. In a match, players alternate five shots each. The remaining player can finish their personal round if the other leaves.

Each whole metre scores one point. Striking the buoy adds 50 points and pays $50. Beat 500 for the first pass and $1,000 reward. Later passes require beating the personal best. The profile stores the best round and furthest drive. Match standings use total score and allow a draw.

The US PS2 script is mission 18, `DRIVERA`. MTA uses the original tee, shot meter thresholds, launch heading and speed conversion, animation group 75, club, ball and buoy. A fixed-step ball simulation uses a water-height cutoff and buoy contact volume. The server owns turns, shot timing, contact and scoring. Each participant's client groups the golfer, props, model assets, animation bank and positional sounds under a round element. Cleanup destroys that hierarchy, frees the model IDs and restores the camera and controls.

`tools/import_vcs_golf_audio.py` resolves `SX_GFSW`, `SX_GFHT`, `SX_GFIW` and `SX_GFHM` through `AUDIO/M_LOOKUP.BIN` and decodes the original mono VAG samples from bank 67. These play at the tee, ball, water entry and buoy contact respectively. The meter confirmation uses the frontend cue for SCM sound 1. Run `python -B tools/check_vcs_golf.py` for the two-player server regression scenarios.
