# VCS vehicle mission acceptance

[PS2 race, trial and stunt acceptance](races/README.md) covers the 20 additional activities, native source checks, multiplayer regressions and live client screenshots.

The expanded acceptance run covers all eight vehicles, the VCS minimap, parked hospital helicopter paint and mission cleanup. [Service mission results and screenshots](service-missions/README.md)

The isolated loopback server ran the workspace resources with a real MTA client and a temporary Lua resource. The fixture positioned vehicles, prepared saved profiles for checkpoint tests, and recorded server events and client screenshots. Taxi pickup used a production traffic pedestrian. A physical press of the bound sub-mission control started Taxi Driver.

## Current mission HUD and rescue rig

The connected client showed pink time and silver counters on the right. The labels shared a right edge, with the values aligned in a second column. The taxi tip meter occupied the value column under Fares. The US PS2 HUD timer and counter passes at `0x00320C08` and `0x00320F28` place the value edge at X 456 in their 480 × 272 coordinate space. The label edge is X 405 and moves left for longer values. Active rows start at Y 100 and advance by 20. [Taxi Driver](taxi-onboard.jpg) · [Vigilante](vigilante-hud.jpg) · [Paramedic](paramedic-hud.jpg) · [Air Rescue](air-rescue-rig-empty.jpg)

The previous client streamed stock object 16332 at scale 0.22. The replacement displayed the VCS `ndc_helirescuerig` (model 7353) at scale 1, with the suspension wires, net and lower frame visible while it was empty. [Prior fitting](air-rescue-rig-before.jpg) · [Replacement close-up](air-rescue-rig-detail.jpg)

In a level-15 dispatch, the helicopter moved 8 m sideways with the rig and four patients attached. At the hospital the client reported zero patients attached, the mission awarded $6,500 and the HUD advanced to 16. Ending the mission removed both the visual rig and its synchronized attachment point. The fixture positioned the helicopter and supplied the saved checkpoint. [Four patients in transit](air-rescue-winch.jpg) · [Hospital payout](air-rescue-level-15.jpg)

## Gameplay acceptance

The taxi fare, horn jump, Vigilante encounter, Paramedic multi-trip and payout-animation captures below are historical. They document the gameplay checks from the first run and show its earlier HUD. The Air Rescue images were replaced with captures from the corrected build.

| Check | Observation |
| --- | --- |
| Sub-mission input | The default binding showed [Press 2 to start Taxi Driver](taxi-start-prompt.jpg). A second press during the cancellation window ended the run. The corrected build cleared all three right-side rows. [Cancellation](taxi-hud-cleared.jpg) |
| Special taxi fares | The connected client completed [shopping](taxi-shopping.jpg) for $871 and the [robbery getaway](taxi-getaway.jpg) for $589. The isolated fixture selected the fare type and positioned the cab. The mission controlled the passenger, return trip, two wanted stars and payout. |
| Tailing | The [target sedan](taxi-tail.jpg) drove to Ammu-Nation in Downtown over 140 seconds. The fixture positioned the cab at following distance and took it to the final curb. After the passenger exited, cash increased from $20,780 to $20,801. All four fare types paid out on the client. |
| Taxi reward | Completing fare 50 on a prepared guest profile unlocked the [horn jump](taxi-horn-jump.jpg). The vehicle rose from Z 15.95 to 18.51. A new account on the same client had its own progression, and logging out restored the guest unlock. |
| Vigilante dispatch | The client encountered [cars](vigilante-car.jpg), [motorcycles](vigilante-motorbikes.jpg) and [on-foot suspects](vigilante-on-foot.jpg) on successive waves. In the first eight seconds the lead car traveled 34.06 m and the lead bike traveled 34.05 m. |
| Vigilante reward | A prepared level-15 run awarded 150 armour capacity and continued to [level 16](vigilante-on-foot.jpg). A controlled 30-point armour loss reduced the effective total from 150 to 120. The test fixture used scripted suspect deaths for the payout check. |
| Paramedic | Level 6 required [two ambulance trips](paramedic-multi-trip.jpg). The test confirmed three occupied passenger seats per trip, six hospital discharges, a $600 payout and continuation to level 7. Level 15 required five ambulance loads and paid $1,500. After the unlock the player sprinted 131.45 m across open ground in 20 seconds. The client reported native sprint on 1,143 of 1,159 frames. |
| Air Rescue reward | The [winch pickup](air-rescue-winch.jpg) kept the patient attached as the helicopter moved 8 m horizontally. Delivering four patients on [level 15](air-rescue-level-15.jpg) awarded $6,500, raised player health to 150 and advanced the HUD to level 16. |
| Presentation | The same payout label stayed centered at [200 ms](payout-200ms.jpg), [1,000 ms](payout-1000ms.jpg) and [2,800 ms](payout-2800ms.jpg). These three captures sampled the frontend payout API directly. The client reported the 4.032-second stereo completion tune playing, with nonzero levels in both channels. |

Restarting the traffic and mission resources together produced two early client event-registration warnings for npc_hlc:control. The subsequent mission runs produced no mission runtime warnings.

## Regression checks

Run the four Python scripts `tools/check_vcs_mission.py`, `tools/check_vcs_taxi.py`, `tools/check_vcs_vigilante.py` and `tools/check_vcs_rescue.py` with Lupa's Lua 5.1 runtime. They exercise the production modules with controlled time, actors, seat confirmations and encounter selection. The shared lifecycle test uses SQLite and exercises duplicate payouts, profile changes and reconnects.

`tools/check_vcs_font_layout.py --output <png>` renders the production font code at four resolutions. It checks constant subtitle opacity until expiry and samples the centered completion banner through fade-in, hold and fade-out.

## Helicopter slings and mission switching

The pilot and nearby observers now simulate the sling each frame. During a five-second real-client run with the VCS minimap enabled, the fixture moved the helicopter three metres sideways. The client rendered 298 frames and measured 237 changes in lateral attachment offset. The server received 37 pilot samples during that interval. The rig swung from 2.62 m behind the mount to 2.28 m ahead. Lua regressions exercised observer smoothing, stream-out, rejected senders and stale samples with a simulated second client.

The fixture positioned the helicopter for a level-one winch pickup and helipad delivery. The server confirmed the patient was attached and awarded $100 on delivery. After a mission switch the player activated the Fire Copter spray, and the server retired the targeted rooftop fire. [Air Rescue pickup](air-rescue-client-pickup.jpg) · [Fire Copter spray](fire-copter-client-spray.jpg)

The driver used the sub-mission action to switch from Air Rescue to Fire Copter and then to Taxi Driver. Each old attachment had already been destroyed when the next run started. After cancellation the client counted zero attachment visuals, the server counted zero mission fire objects, and only the two permanent Turismo organizer markers remained. The multiplayer regression repeated a switch with a second simulated player and checked that the other run kept its bucket and vehicle reservation.
