# VCS police AI client acceptance

The [prompt driver-door arrest and Busted camera checks](quick-door-arrest-20261125/README.md) cover fast seated arrests, lock interruption, corrected PS2 camera selection and normal camera restoration.

A Windows MTA 1.7 client connected to an isolated loopback server with the VCS map, models, frontend, route graph, SkyGfx and production traffic resources. A temporary resource drove the wanted export, player position and inputs. Production traffic selected and spawned the responding units. The driver-seat and spike-strip sections identify where QA arranged an officer or a vehicle.

The [pursuit acceptance runs](chase-update.md) record a wanted increase on the same patrol, a moving ram, a block, and the handoff from pursuit to seated arrest. The [roadblock and spike-strip runs](hazard-update.md) cover the two-star control, barrier selection through six stars, and wheel contact with a strip assigned by the ambient population.

The [armed-driver pursuit tests](armed-driver-pursuit.md) follow an armed specialist from firing at a stationary driver's vehicle through an interrupted reach, a successful retry and seated custody.

The [siren source comparison](siren-yield.md) covers VCS and San Andreas. The [make-way clearance tests](make-way-clearance.md) measure civilian movement, the gap between both vehicles at passing, and route resumption on the MTA client.

The [driving style and chase tests](driving-style-acceptance.md) show civilian and police debug labels, the same civilian changing seats, a two-junction pursuit, a moving rear-quarter ram and a separate block.

## Downtown wanted display and frame times

The fixed-camera screenshots are from the HUD integration pass. Each shows the frontend for the requested level. The server verified the native wanted integer immediately after each export call. An initial three-second warm-up per level preceded approximately 10.5 seconds of client frame samples. The mean, p95 and p99 columns are milliseconds between rendered frames. The entity columns are sampled mean counts of streamed vehicles and NPCs. Packets are received transport packets during the sample, including MTA synchronization and screenshot traffic. Runs used one real player. Multiplayer capacity requires a separate concurrent-player test.

| Stars and candidate screenshot | Frames before / after | Mean ms | p95 ms | p99 ms | Vehicles | NPCs | Packets |
|---|---:|---:|---:|---:|---:|---:|---:|
| [0](after-level-0-foot-front.jpg) | 694 / 642 | 15.1 / 16.4 | 19.8 / 20.8 | 24.2 / 27.6 | 41.8 / 42.1 | 14.2 / 12.0 | 397 / 380 |
| [1](after-level-1-foot-front.jpg) | 584 / 605 | 18.0 / 17.3 | 23.4 / 21.8 | 26.2 / 27.0 | 45.3 / 47.2 | 23.6 / 18.9 | 397 / 335 |
| [2](after-level-2-foot-front.jpg) | 601 / 556 | 17.5 / 18.9 | 21.9 / 24.4 | 24.6 / 27.5 | 44.6 / 46.7 | 20.9 / 21.7 | 273 / 361 |
| [3](after-level-3-foot-front.jpg) | 601 / 616 | 17.5 / 17.1 | 22.6 / 21.4 | 25.0 / 25.2 | 45.2 / 42.2 | 25.5 / 16.3 | 272 / 468 |
| [4](after-level-4-foot-front.jpg) | 595 / 621 | 17.6 / 16.9 | 22.0 / 22.6 | 25.6 / 25.9 | 45.6 / 41.5 | 25.7 / 12.5 | 252 / 337 |
| [5](after-level-5-foot-front.jpg) | 608 / 778 | 17.3 / 13.5 | 21.5 / 17.7 | 25.3 / 25.3 | 45.8 / 33.0 | 26.2 / 3.0 | 278 / 312 |
| [6](after-level-6-foot-front.jpg) | 596 / 823 | 17.6 / 12.8 | 22.1 / 16.1 | 24.8 / 18.5 | 44.8 / 33.0 | 28.1 / 6.2 | 272 / 207 |

The baseline ran all seven levels without interruption. The candidate resumed at three stars after another local task used the client. At four stars the stationary player went down. At five and six stars the HUD and server showed the requested level, while the player had respawned approximately 200 units away. Those last two rows have different streaming loads. The two-star candidate p95 rose while the three-star p95 fell. Population varied across runs.

The one-star frame shows a uniformed officer beside the player and an open marked cruiser. At two and three stars, more marked units and dismounted officers were visible. At four stars, several cruisers and dismounted officers surrounded the stationary player's position. Baseline frames are retained for [zero](before-level-0-foot-front.jpg), [two](before-level-2-foot-front.jpg) and [six stars](before-level-6-foot-front.jpg).

## Custody

A production patrol arrived with two occupants and its siren active. The probe repositioned the player beside a dismounted original-model-8 officer and used the traffic resource's restrained-player export. The arrest event reported a live two-star suspect. The client displayed the green Busted message above the player, the two-star HUD and a marked patrol with its door open. [Arrest screenshot](after-arrest-busted-officer-front.jpg)

After the restart, cash had fallen from $2,850 to $2,650, wanted had returned to zero, health was 100, armour was zero and the previously issued pistol was gone. The server reported the player unfrozen with the fire control enabled.

The driver-seat test used a model-8 officer from a production patrol. The probe placed the officer at the driver's door of an unlocked, stationary car on a supported rooftop, enrolled the officer in the production pursuit roster, selected the baton slot and capped the target at one star. The real client executed native vehicle entry. The server observed a non-forced driver's exit with that officer as jacker, followed by a live one-star arrest. The Busted screenshot shows the open door, officer, ejected player and single star. Cash fell from $2,000 to $1,900. The player regained fire control and returned to the downtown station with zero wanted. A previous street trial also completed a non-forced exit with the wanted level rising to two before arrest. [One-star driver arrest](one-star-native-driver-jack-busted.jpg) and [two-star street arrest](two-star-native-driver-jack-busted.jpg)

## Driving and water response

The temporary resource gave the player an ordinary car on the downtown road and used the client's accelerate control for about five seconds. The car travelled 136.2 units from its start. At two stars, an occupied patrol car (original model 207) had its siren on with two occupants. The player remained in the driving seat during the capture. [Player driving at two stars](after-drive2-player-accelerating-rear.jpg)

At three stars, the player occupied a dinghy near waterway node 1163. The traffic resource assigned an occupied Predator (original model 219) to the player's boat mission. The first observation was at 59.4 units. The screenshot shows the police livery, driver and hull under the bridge. [Predator responding at three stars](after-sea3-predator-three-quarter.jpg)

## Gameplay frame samples

The temporary probe captured client frame intervals after a three-second warm-up. NPCs retained normal damage and dispatch logic. The driving case applied the accelerator over the same interval in both builds. The six-star on-foot case includes the candidate player's death and subsequent respawn. Each row is a single pass with ambient population randomness. CPU values, where available, are the mean process CPU seconds per wall-clock second expressed as a percentage of one logical core. Packet counts cover each whole scene, including its warm-up.

| Scene | Build | Frames | Median ms | Mean ms | p95 ms | p99 ms | Process CPU | Packets |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| Zero-star pedestrian | baseline | 1087 | 13.5 | 14.2 | 19.2 | 22.6 | 4.0% | 556 |
| Zero-star pedestrian | candidate | 1065 | 13.8 | 14.4 | 19.1 | 22.5 | 4.9% | 554 |
| Two-star player car | baseline | 1471 | 14.9 | 15.9 | 22.0 | 24.9 | 4.1% | 797 |
| Two-star player car | candidate | 1307 | 17.0 | 18.0 | 24.5 | 27.9 | 4.8% | 1000 |
| Six-star pedestrian | baseline | 2594 | 16.0 | 16.9 | 22.7 | 25.4 | 3.4% | 823 |
| Six-star pedestrian | candidate | 2733 | 15.5 | 16.0 | 23.0 | 29.5 | 3.8% | 836 |
| Two-star custody | earlier candidate | 2107 | 14.8 | 16.3 | 23.4 | 29.0 | — | 704 |
| Five-star pedestrian | earlier candidate | 1600 | 17.7 | 18.6 | 25.2 | 30.2 | — | 710 |
| Three-star player boat | earlier candidate | 3155 | 15.7 | 16.8 | 22.7 | 26.0 | 3.3% | 1237 |
| Four-star specialist response | candidate | 2158 | 16.6 | 17.6 | 23.8 | 27.9 | 4.2% | 995 |
| Five-star specialist response | candidate | 1501 | 24.5 | 25.0 | 31.4 | 35.9 | 4.0% | 1969 |
| Six-star specialist response | candidate | 1717 | 21.3 | 21.9 | 27.1 | 31.6 | 5.9% | 2168 |

Server Lua timing reported 0.18%–0.74% for the traffic resource in the rolling 60-second windows ending during the sampled high-star and boat scenes. During the three-star boat scene the client received 222 police volley events, with both the occupied Predator and a helicopter assigned. These are issued volley events, independent of visual impacts or damage.

## Specialist response

In a separate pass the temporary probe protected the player from damage so each 40-second specialist scene retained its wanted level. The server recorded original vehicle and occupant IDs separately from the client's streamed MTA model IDs.

| Stars | Production units observed | Client evidence |
|---|---|---|
| 4 | Enforcer 234 with SWAT model 9 in all four seats and the siren active. A Vice car 204 carried a pair of model-117 officers. | Four streamed SWAT skins in the Enforcer and 4 rope attachment updates. [Enforcer](final-special4-enforcer-three-quarter.jpg) |
| 5 | FBI sedan 193 arrived with original-model-10 officers in each of its four seats. An Enforcer from the previous scene remained present. | The four seats were sampled before the officers started getting out. [FBI sedan](five-star-fbi-sedan.jpg) |
| 6 | Rhino 246 with a model-11 driver and Barracks 218 with two model-11 soldiers. Both responded with active sirens. | The client independently reported each vehicle streamed and the same occupied seats. [Rhino](final-special6-rhino-three-quarter.jpg) and [Barracks](final-special6-barracks-three-quarter.jpg) |

## Helicopter and Predator

The four-star Police Maverick approached a protected rooftop target at (−657.34, 724.18, 48.00), settled about 15 units away and recorded a pitch near one degree. By the last air sample it had emitted 45 helicopter volleys, 3 callout events and 2 distinct rappelling officers. The screenshot shows the VCPD helicopter upright over downtown. [Police Maverick](airsea-air.jpg)

A second four-star run followed one original-model-9 SWAT officer from deployment to combat. The real MTA client recorded the traffic resource calling `createSWATRope` at the helicopter door with an 8,499 ms hold. The officer played `ped/abseil`, descended from 16.50 units above the roof to a last airborne sample of 2.48 units, and released at 1.00 unit. The same ped immediately aimed and fired weapon 28 from 1.54 units away. Its ground task remained `killPed` for the next ten seconds. Both captures returned status `ok`. [Native rope descent](swat-rappel-air-three-quarter.jpg) · [Ground engagement](swat-rappel-ground-three-quarter.jpg) · [Half-second samples and native calls](swat-rappel-observations.txt)

Two additional four-star runs interrupted officers already descending from naturally dispatched helicopters. Destroying the aircraft at officer Z = 57.61 preserved the officer. At 419 ms, it was unfrozen, detached and controlled by HLC. At 1,234 ms it reached the roof at Z = 48.00. Clearing wanted during a different descent at Z = 81.98 removed that officer before the wanted setter returned. The first client sample at 409 ms confirmed its removal with zero stars. All four before/after screenshots returned `ok`. [Aircraft before link loss](swat-loss-before-side.jpg) · [Landing after link loss](swat-loss-after-side.jpg) · [Rooftop after wanted reset](swat-clear-after-side.jpg) · [Client and server samples](swat-rappel-interruptions.txt)

The three-star Predator closed from 50.4 to 1.9 units from the player boat. The probe recorded 7 twin-gun boat volleys and 5 boat callouts. Callout counts measure playback requests. Audible volume and sound quality require a listening assessment. [Predator](airsea-boat.jpg) and [emitter telemetry](airsea-observations.txt)

## Native scheduler load

A native server stress run used 600 synthetic tasks to exercise the server scheduling deadline. Before the final deadline checks, the measured p95 was 4 ms and p99 was 5 ms against a 3 ms p95 target. With the revised checks, 109 samples measured p95 at 2 ms and p99 at 3 ms, with 63 budget yields. This measures the native server's synthetic scheduler workload. The client frame measurements above include the renderer, map, population, AI and network synchronization.

## Client resource update

The first expanded-skin build attempted to replace an archive the connected client still had open. MTA rejected it with a checksum mismatch. That run was discarded. The next benchmark used a versioned path for the same skin payload in the isolated test copy. The shipping build keeps the original street archive byte-identical and mounts the six officer skins from a separate police archive. On a subsequent reconnect, the client loaded the shipping files and streamed the FBI sedan and Vice car as distinct custom model IDs. Their model-10 and model-117 occupants also resolved to distinct custom skins.

A repeat three-star boat scene on the shipping build sampled 3,363 frames, with a 15.0 ms median, 21.5 ms p95 and 24.4 ms p99. The client streamed an occupied original-model-219 Predator at 61.0 units and received 283 combined police volleys during 55 seconds. The emitter-specific counts above are from the separate targeted probe.

## Roadblock and spike strip

The [roadblock grounding regression](roadblock-grounding.md) reproduces buried Enforcers on a graded street and shows the corrected four- and six-star roadblocks.

At four stars the test moved the occupied player car from outside the 160-unit activation radius to the approach of original flagged road node 88 near (−653.125, 747.5). The production scheduler accepted its own random draw on the second crossing in both runs. As the car approached within 51 units, the sampled Enforcer (234) gained two guards on foot, both original model 9 and carrying MTA weapon 28. In the repeat capture, two Enforcers blocked the street and four officers were visible beside them. [Street view](police-roadblock-enforcers-along-road.jpg) and [overhead view](police-roadblock-enforcers-overhead.jpg)

The spike-strip probe arranged a model-8 officer beside the eastbound lane, supplied the production stinger candidate and gave the player a test SUV. The deployment and wheel-contact checks ran in the traffic resource. The client's ground query returned z=10.384, and the strip became visible at (−626, 748.5, 10.534), pointing north across the player's path. After an initial velocity and actual accelerator input carried the SUV across it, the server's four wheel states changed from (0, 0, 0, 0) to (0, 1, 0, 1). The deployment frame shows the spikes and officer. The crossing frame shows the vehicle past the strip. The wheel-state reading records the punctures. [Deployment](police-stinger-deployed.jpg) and [crossing](police-stinger-wheel-contact.jpg)

## Busted camera, animation and input

The isolated client ran a one-star driver arrest followed by a two-star arrest on foot. For the vehicle trial, the probe enrolled a model-8 officer beside an occupied, unlocked car. An initial native exit reported seat 255 and did not trigger Busted. A subsequent native exit reported driver seat 0, a ped jacker and no forced removal. For the on-foot trial, the probe placed a model-8 officer next to a restrained player by the downtown station. Both trials used the production arrest, camera, animation, fade and release handlers.

The game's client reported `PED/handsup` on the player and `PED/ARRESTgun` on the officer. The camera held a 45° shot through 3.9 seconds. The probe issued action and change-camera presses at 0.7 seconds. Both synthetic button states were present at 0.8 seconds while their bindings and the fire binding were disabled. In both trials the follow camera returned to the player by 4.32 seconds at the downtown station, with a measured FOV of 90°. Both resources observed the wanted transition to zero. The player paid $100 then $200. The three bindings were enabled again by the 8.2-second sample. [Both actors during the arrest](foot-busted-camera-late.jpg), [station during the fade-in](foot-busted-camera-fading-in.jpg) and [normal player camera after release](seat-busted-camera-restored.jpg)

A final rooftop driver-arrest trial checked collision clearance around the test vehicle and roof edge. The camera initially sampled about eight units from its focus and moved as the player raised his hands and the officer climbed out of the car. It showed both actors and the opened door. An earlier build had placed the camera less than one unit from the player here. Native vehicle exit and door tasks continued briefly on the officer before the named arrest animation took over. [Driver arrest on the roof](seat-busted-presentation.jpg)

## MTA 1.7 reconnect crash

Build 1.7.0-7.27005.0 reported a native access violation at 23:57:52 on November 20. The departing client's last Lua message was the map loader's streaming-limit restoration check at 23:57:50. The client console logged a new loopback connection attempt at 23:57:51. The next server connection had not reached JOIN when the exception occurred. The San Andreas reference maps the fault address to `CTxdStore::GetNumRefs`, called through `CStreaming::RemoveLeastUsedModel` and `MakeSpaceFor`. This identifies the failing subsystem. The logs do not identify the particular texture or its owner.

The map loader now skips streaming-limit restoration while map archives, requested texture slots or pending unloads remain. It also checks current memory usage before lowering the budget after an orderly unload. A Lua 5.1 check covered an active map, an idle loader and an idle loader with usage above the previous budget. A fresh client joined afterward. The crash had occurred on reconnect, and a fresh launch alone cannot demonstrate a fix for that sequence.

## Prior driver-ejection build

On a clean server population, the temporary resource parked an unlocked Infernus downtown, seated the player, applied the handbrake and set the requested star level. Production traffic spawned, allocated and equipped every officer. The fixture observed the arresting ped leave an original-model-207 marked unit in each trial.

| Wanted | Client and server observations | Result |
| --- | --- | --- |
| Two stars | A model-8 officer with weapon slot 2 requested the occupied driver's seat from 2.81 units. The client reported native door opening and slow driver drag tasks. | Native seat-0 exit, live Busted event, wanted zero and $200 fee. [Door opened](ordinary-2-patrol-native-door.jpg) and [Busted](ordinary-2-patrol-driver-busted.jpg) |
| One star | A model-8 officer using slot 1 requested the occupied driver's seat from 1.50 units. The screenshot shows the officer beside the open door and the one-star HUD. | Native seat-0 exit, live Busted event, wanted zero and $100 fee. [Door opened](ordinary-1-patrol-native-door.jpg) |

The two-star native sequence took about six seconds from start-enter to driver exit. One run also showed two nearby officers independently requesting the same door. These measurements describe the driver-ejection build. The subsequent seated-arrest implementation replaces that interaction.

## Native door arrest with the driver seated

The test client parked an occupied Infernus at one and two stars. Production selected the marked cruiser (original model 207), assigned its uniformed officer (model 8) and controlled the dismount and approach. The two-star fixture moved the suspect vehicle beside an existing dispatched cruiser. The one-star officer reached the suspect at the starting location. The probe never moved an officer or changed their weapons.

| Case | Observed result |
| --- | --- |
| Locked before the two-star approach | A uniformed officer reached 3.48 units. The lock remained set, the hinge read zero and two stars remained. |
| Lock applied during native entry | The probe locked the suspect's car 80 ms after the ordinary driver-seat start event. After 1.8 seconds the driver still occupied seat zero, the car was locked, its hinge remained at zero and two stars remained. |
| Unlocked two-star retry | The officer began native entry from 1.55 units. The native door-opening task gave way to the on-foot task. The server read a front-left hinge ratio of 0.823 at Busted. |
| One-star approach | The officer requested the driver door from 1.58 units. The server accepted the opening at 0.772. The syncer observed 0.837 with the officer on foot. The officer faced the seated driver, with heading error staying below 0.3° during the sampled hold. |

In both arrests the driver remained in seat zero and the officer stayed outside until the station transfer. From 0.96 through 3.9 seconds the officer held pistol 22 with aim enabled and firing disabled. The native targeting ray passed within 0.12 units of the driver's neck. The station removed the driver under blackout. By 4.51 seconds the camera again followed the local player at 90° FOV. At release, the police resource restored movement, released the car and reset wanted to zero. The $2,500 starting balance fell to $2,400 with one star and $2,300 with two.

[Native door-opening motion](seated-2-door-opening.jpg) · [One-star pistol hold](seated-1-officer-aim.jpg) · [Two-star open door and seated driver in a second run](seated-2-officer-aim.jpg) · [Timestamped measurements](seated-driver-observations.txt)

An earlier one-star run left the officer stationary at client vehicle-local coordinates (−1.84, 1.36) with forward input off. That run did not record the same officer's server-local coordinates. The current walking task and server reach check share a collision-box-based position. The accepted one-star run recorded server-local coordinates (−1.69, −0.28) during native entry. Wrong syncers, stale attempts, denied native entry, wrong doors, moving cars and changing seat occupants are covered in the Lua regression.

## Native emergency vehicle sirens

The real MTA 1.7 client and server agreed on the original emergency model ID for each test vehicle. The driver used VCS bike 191 on SA 523, marked car 207 on SA 596, FBI sedan 193 on SA 598 and Vice Cheetah 204 on SA 597. Each vehicle streamed with its VCS skin, reported its siren on during the four-second activation, and reported it off afterward. The client received sound group 17, sample 10 from each individual vehicle during activation. In the San Andreas audio reference those are the horn/siren bank slot and long police siren sample. The next sample after switching off contained no new vehicle sound event. The front of the bike and the marked car's roof bar showed illuminated emergency lights. Special-unit driving handling comes from the VCS FBICAR and CHEETAH records.

WASAPI loopback also recorded mixed game audio. During the siren intervals the median dominant frequency between 350 and 1800 Hz was 870 Hz for the bike, 935 Hz for the marked car, 878 Hz for the FBI and 925 Hz for Vice. Traffic contributed to the audio mix. The per-vehicle sound events identify the siren independently of that background.

The rooftop repeat kept other cars clear of the camera and confirmed native sound 17/10 on all four streamed vehicles. These earlier photographs exposed the SA roof-bar lamp floating above the undercover bodies. [Electra](siren-191-on.jpg), [marked cruiser](siren-207-on.jpg), [FBI sedan](siren-193-on.jpg) and [Vice Cheetah](siren-204-on.jpg).

The final build keeps the native siren sound and locates each undercover beacon behind the windshield. A fixed-camera client sampled a 132 × 88 pixel region every 125 ms. Before activation, the FBI frame contained zero saturated red pixels and the Vice frame contained 3–4. During activation the peaks were 358 and 366, with 13 local extrema in each sequence. Both emitted the native long siren. The bike and cruiser also showed repeated red or blue pulses. The frontend resolved the VCS display names on entry. The undercover lamp coordinates are fitted to the converted meshes. [Frame samples](siren-flash-samples.csv), [FBI Washington](native-flash-193.jpg), [VCPD Cheetah](native-flash-204.jpg), [VCPD WinterGreen](native-flash-191.jpg) and [VCPD Cruiser](native-flash-207.jpg).

## Routed ground pursuits

### Dispatch handling and model bindings

The loopback server tagged nine vehicles through the traffic model binding. A second, untagged vehicle of each native model retained its original handling. After the tagged vehicles streamed, the client and server agreed on all 30 sampled values, including mass, drivetrain, acceleration, suspension, damage multiplier and both flag words. Passenger counts below exclude the driver and scripted truck-bed attachments. [Vehicles during the handling readback](police-dispatch-models-native-handling.jpg)

| Dispatch vehicle | VCS ID | SA base | Native passenger seats | Mass | Max velocity | MTA acceleration |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Electra | 191 | 523 | 1 | 800 | 190 | 16 |
| FBI sedan | 193 | 598 | 3 | 1800.7 | 200 | 10 |
| Vice Cheetah | 204 | 597 | 3 | 1400 | 200 | 13.2 |
| Marked cruiser | 207 | 596 | 3 | 1750 | 160 | 9.6 |
| Barracks | 218 | 433 | 1 | 10500 | 180 | 8 |
| Predator | 219 | 430 | 0 | 2200 | 190 | 0.68 |
| Enforcer | 234 | 427 | 3 | 2600 | 155 | 9.6 |
| Rhino | 246 | 432 | 0 | 25000 | 80 | 16 |
| Police Maverick | 261 | 497 | 3 | 4500 | 200 | 6.4 |

The FBI and Vice client meshes came from the traffic variant archive. The converted model provider supplied the other seven, and allocated a client model derived from 433 for the Barracks. The PC Edition handling rows matched the bundled file for all nine. San Andreas scales acceleration by 0.4 in `tHandlingData::InitFromData` before converting to simulation units. The shared handling loader applies this factor once. Traffic writes changed properties to tagged instances only. [Bundled handling records](../../../mods/deathmatch/resources/%5Bmodel%5D/vcs_vehicle/data/handling.dat)

The client kept the Electra's native suspension force when the server tried overriding it. The released binding therefore preserves native motorcycle suspension on both sides. MTA disables boat suspension changes. The Predator's native 0.05 brake already matches its source value and is below the setter minimum. The helicopter uses the native hull and the VCS flight controller. [MTA handling properties and restrictions](https://wiki.multitheftauto.com/wiki/SetVehicleHandling)

With these values, the marked car recovered from a curb obstruction and reached close pursuit of the parked SUV. The Electra initially ran wide on a right turn into a building. Reducing the emergency controller's target speed on sharp bends brought it through both turns on a single graph search. The real client recorded mission 5 fourteen seconds after dispatch. The rider stopped 7.2 units from the SUV, dismounted and approached the driver door. [Marked car interception](vcs-handling-cruiser-intercept.jpg) and [Electra interception](vcs-handling-electra-intercept.jpg)

A second fixture parked the occupied SUV seven units beside the dispatched Electra on its approach. The rider dismounted and ran to the driver-side handle. Before the correction, the native sync owner saw the rider at the door while the server retained a pedestrian position over ten units away for more than twenty seconds. With the correction, the owner reported reaching the handle after the ordinary native sync had time to arrive. The server reconciled an 8.08-unit discrepancy 3.58 seconds into the assigned approach and verified native door opening. The production arrest callback identified the same rider, one wanted star and the player still in driver seat zero. The client screenshot shows the open door, driver and helmeted officer, with a passing taxi in the foreground. [Electra rider opening the driver door](electra-rider-seated-arrest.jpg)

At four stars the production Police Maverick settled into a hover 16.9 units from the rooftop target. The client recorded three rope drops and 58 gun volleys by the end of the hover observation. The marine phase moved the player aboard a speedboat and set three stars. The Predator closed to 3.3 units and the client counted 33 gun volleys before the scene ended. [Four-star Police Maverick](vcs-handling-maverick.jpg) and [three-star Predator](vcs-handling-predator.jpg)

### Road routing

The fixture parked the player at (−761, 203), held one wanted star and placed a traffic-owned marked cruiser on the approach from node 389 to 342. The real client measured pavement heights of 9.88 at the approach and 10.06 at the destination. Its initial line-of-sight check between the vehicles was blocked. The production planner selected links through nodes 342, 340, 341, 310, 336 and 337. The lane change on the two-lane avenue allowed the second right turn. The server recorded the assigned suspect, driver-seat occupant and client sync owner throughout the first approach. [First junction](police-route-first-corner.jpg) and [second junction](police-route-second-corner.jpg)

The cruiser overshot the second junction, obtained a connected alternate route, and returned on the destination street. It switched from road mission 2 to close mission 3 at a sampled separation of 16.3 units, then stopped at 12.9. The probe recorded the marked unit's officer dismounting and the seated arrest callback five seconds later. The repeated test with an Electra streamed original model 191 on base 523. Client telemetry confirmed the rider occupied the driver seat, received acceleration and steering, and reached a native velocity magnitude of 0.20 on the approach. [Electra at the first junction](police-bike-route-first-corner.jpg)

In the final Electra run the planner found the complete route with one search. The client briefly reported an obstacle during the first turn, resumed driving and reached the suspect's SUV on the destination street. The server switched the bike from mission 4 to 5, ordered a stop at 8.9 units and recorded the rider leaving the saddle. The same client remained the bike's sync owner. [Electra approaching the suspect's SUV](police-bike-route-close.jpg)

The deterministic Lua traffic check exercises changes during an active drive. It moves the suspect onto another street and verifies that the replacement task ends on that street. A turn of less than six units updates the target road within one second. With two patrols sharing the search budget, closing the upcoming turn stops the affected driver before another search slot is available. Reopening it allows the driver to resume after the retry delay. The check also verifies that waypoint progress postpones recovery, a four-second stall triggers a fresh plan, and a cruiser displaced beyond the road network stops until it can rejoin.

## PHI_A3 Barracks riders

A server-side test mission created three original-model-37 BMYCR actors through `createTrafficScriptPed`, provided the Uzi loadout, and mounted them using the PHI_A3 export. The connected player drove the Barracks. All three actors streamed with the same custom BMYCR skin and weapon 28. The client reported each ped attached at the recovered offset, outside the native seats, before accelerator input and at speed 0.185. The driver remained in seat 0. A repeat mount was idempotent, duplicate riders were rejected, and explicit unmount and truck destruction both released all three actors. This fixture exercises the mission export independently of the six-star army patrol. [Truck bed](barracks-mission-bed-riders.jpg) and [client and server measurements](barracks-mission-bed-riders.txt)

## SWAT descent cadence and Police Maverick paint

On 21 November 2026 a four-star rooftop test followed a production SWAT officer in a real MTA client on an isolated loopback server. A low-priority pre-render probe measured height after the traffic controller. Height changed on **287 of 287 consecutive airborne frame intervals**, with a maximum absolute vertical step of **0.094 game units**. Half-second samples reported `ped/abseil` throughout descent. The last airborne sample was 3.06 units above the roof. The first grounded sample was 1.00 unit above it, with collisions released to normal control and the same officer executing `killPed` with weapon 28. [Officer on the rope](swat-frame-descent.jpg)

A separate daylight run read back model 261's primary RGB (157, 152, 114) and secondary RGB (188, 188, 180) on both client and server. The side view shows the khaki fuselage, light upper cowling and VCPD markings. [Police Maverick side view](polmav-ps2-paint.jpg) · [PS2 palette and deployment references](../../police-ai/vehicle-and-special-response.md)
