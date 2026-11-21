# PS2 vehicle race and stunt acceptance

The US PS2 mission table assigns these activities to scripts 26–32 and 36–43. The 20 activity titles include 33 selectable time-trial circuits, all nine Turismo events, two demolition challenges, 50 mall BMX coronas, two flight trials, Skywolf, two vehicle relays, four PCJ playgrounds and two hovercraft courses.

## Gameplay on the loopback server

One real MTA client drove against the server with the VCS minimap enabled. A temporary Lua resource arranged the scenes and captured the original 960 × 600 screenshots. All twenty launches used the production sub-mission command or an on-foot Turismo hub. The fixture supplied travel and contacts for selected checks.

| Check | Observed result |
| --- | --- |
| Mall BMX | The driver started inside the mall in dimension 3090 with underworld warp disabled. A flat pass through a green corona left it visible at 0/50. After the client measured rear-wheel contact with the front wheel clear, the green corona disappeared and the counter reached 1/50. The fixture positioned and pitched the bike for the wheel-contact check. [Flat crossing](../mall-bmx-stunt-rejected.jpg) · [Wheelie](../mall-bmx-stunt-crossing.jpg) |
| Watersports | Crossing the 24 gates of the first three-lap Jet Ski event under fixture positioning retired each objective and awarded $100. [Finish](../watersports-result.jpg) |
| Turismo | At the Little Havana organizer the driver paid $100, joined three NPC riders and completed Escobar Run-Way. The riders moved on the real client. Player checkpoint travel used fixture assistance. The server recorded 59.547 seconds, a best lap of 20.837 seconds, first place and a $500 prize. [Payout](../turismo-payout.jpg) · [All nine races and verification details](../motorsport.md) |
| Crash! and Rush! | The studio Coach struck weakened target vehicles in the live test. Eight destruction awards totaled $2,400. At the three-minute deadline the first success paid $1,000. Cancelling Rush! removed its temporary durability bonus, carrying 100 damage through to the original truck. [Rush! starting HUD](rush-linerunner.jpg) · [Collision and damage HUD](../crash-damage.jpg) · [Completion](../crash-complete.jpg) |
| Skywolf | The client launched a Hunter rocket and destroyed a full-health drone. The fixture destroyed the other drone in the wave and the next ring became active. [Hunter and drone](../skywolf-hunter-and-drone.jpg) |
| Land, Sea and Air Ace | After the sixteenth gate the rider switched to the spawned Jet Ski using the boarding command and advanced to checkpoint 18. The Jet Ski launch point is two metres east of the SCM coordinate to give the MTA hull enough depth. In a controlled comparison, full throttle moved the grounded craft 0.10 m in 5.4 seconds at the original coordinate and 152.76 m in the same interval at the adjusted point. On a fresh run the rider boarded normally and traveled 190.29 m in 6.4 seconds on native throttle. [Handoff](../relay-jet-ski-handoff.jpg) · [Mounted rider](../relay-jet-ski-next-leg.jpg) |

## Course captures

Each screenshot shows a live client at a course objective. The course fixture launched from the parked VCS model and positioned the vehicle for the shot.

| Course family | In-game captures |
| --- | --- |
| Circuit trials | [Watersports](trial-hud-watersports.jpg) · [Quad Bike](trial-hud-quadtrial.jpg) · [BMX](trial-hud-bmxtrial.jpg) · [Sanchez](trial-hud-sancheztrial.jpg) · [Caddy Daddy](trial-hud-caddydaddy.jpg) |
| Mall BMX | [Countdown, zero blips](trial-mall-countdown.jpg) · [Red corona collected](trial-mall-red.jpg) · [Flat crossing](trial-mall-flat.jpg) · [Green corona collected on a wheelie](trial-mall-wheelie.jpg) |
| Crims flight trials | [Crims on Wings](../course-crimsonwings.jpg) · [Crims on Water Wings](../course-crimsonwater.jpg) |
| Vehicle relays | [Ground checkpoint](../course-landseaair.jpg) · [Land, Sea and Air Ace handoff](../relay-jet-ski-handoff.jpg) · [Hyman Memorial O.D.T.](../course-hymanodt.jpg) |
| Playground | [Town](../course-playtown.jpg) · [Point](../course-playpoint.jpg) · [Dock](../course-playdock.jpg) · [Park](../course-playpark.jpg) |
| Hover races | [Haiti](../course-haitihover.jpg) · [Harbor](../course-harborhover.jpg) |

The final mall retest counted 50 world coronas during the countdown and zero blips. GO enabled 50 size-one blips. Collecting a red corona, crossing a green one flat, then performing a wheelie produced counts of 1, 1 and 2. Underworld warp stayed off. The loaned BMX returned to its original 648 health on cancellation. The four course selectors closed after the server accepted the selections. The client measured playback advancing on the left/right and center race audio files.

The ground leg of Land, Sea and Air Ace exposed a directed-checkpoint mesh pointing below the bridge. The renderer now orients it above terrain. The recapture uses the same fourth checkpoint and camera. A triangle-submission regression covers three directions.

## Source and multiplayer checks

- The course importers read the US PS2 script arrays. The regression suites exercise all 33 trial circuits, 50 mall coronas, 333 Turismo checkpoint crossings, both demolition score thresholds and all eleven flight, relay, playground and hover variants. They cover beat-the-record comparisons, independent profiles, the first-pickup timer, vehicle transfers, cancellation, stale messages and duplicate finishes.

- The native Turismo best-time routine at `0x0028A2F0` keeps the first result or the lower recorded time. The one-off sound handler at `0x00366500` routes countdown and checkpoint sounds to the frontend dispatcher at `0x001C55C0`. The port uses the recovered left, right and center samples for gate and start cues.

- Two simulated participants exercised overlapping runs, owner-scoped actors, marker visibility, grid reservations, course choices and records. The client collision regression also checked that releasing a race restores only collision pairs changed by that race. Only one real client was available.

- A live service regression cancelled Taxi Driver during a Pay ’n’ Spray repair. The garage completed two consecutive $100 repairs and released its camera. The two persistent Turismo organizer markers are part of the map while the mission resource is running.

## Final integration checks

Stopping the mission resource mid-run changed the mall totals from 50 coronas, 50 blips and one reserved vehicle to zero of each. The shared HUD became available immediately, the parked bike returned to its initial 720 health, and the garage provider stayed registered across the stop and restart. Underworld warp remained disabled. [Mall after resource stop](mall-after-resource-stop.jpg)

Running both water resources originally allocated 144 legacy polygons on top of the 80 streamed PS2 slots. The optional water shader now defers polygon creation to the active VCS map. On a fresh connection with both resources running, the client counted 80 PS2 slots and zero duplicate polygons. Harbor water measured Z 6 with the hovercraft floating at Z 6.73. The harbor and Haiti captures show the restored surface.

Three consecutive respawns into the mall and back to the exterior each parked and restored the same 80 PS2 water slots. Each return restored harbor water at Z 6. Three ordinary dimension changes and returns produced the same result. After both sets of checks the rider boarded the relay Jet Ski. The craft traveled 280.12 metres in 6.4 seconds on native throttle. The rider came off near the end of that sample.
