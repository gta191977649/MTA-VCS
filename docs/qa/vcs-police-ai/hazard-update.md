# Roadblock and spike-strip acceptance

## Roadblock approach

A Windows MTA 1.7 client joined an isolated loopback server running the VCS map, models, SkyGfx, wanted and production traffic resources. A temporary Lua resource placed the player in an SUV outside the 160-unit activation radius of VCS road node 88 and held the accelerator. After a rejected attempt, the fixture returned the SUV outside the radius. The production scheduler chose every roll, vehicle position and guard.

At two stars the SUV crossed the boundary without a barrier. At three through six stars the line formed on the same downtown street. The distance column gives the horizontal separation when the observer first counted two guards beside the sampled vehicle.

| Stars | Masked roll | VCS vehicle | VCS guard skin | Guards | Distance | Client capture |
| --- | --- | --- | --- | --- | --- | --- |
| 3 | 0 | 207, patrol | 8 | 2 | 45.45 | [Patrol line](hazard-road-3-guards-street.jpg) |
| 4 | 4 | 234, Enforcer | 9 | 2 | 48.70 | [SWAT line](hazard-road-4-guards-street.jpg) |
| 5 | 0 | 193, FBI | 10 | 2 | 47.09 | [FBI line](hazard-road-5-guards-street.jpg) |
| 6 | 4 | 218, Barracks | 11 | 2 | 45.84 | [Army line](hazard-road-6-guards-street.jpg) |

All four original 960 × 600 JPEGs show the corresponding vehicles across the road and officers alongside them. The isolated server recorded successful captures from the test player and resource. In the US PS2 executable, the pool pass at `00433008` compares only the X and Y differences before calling guard creation at `0040ADA0`. A Lua regression covers a player inside 51 horizontal units whose 3D distance exceeds 51.

## Wheel-contact geometry

VCS tests individual nearby wheel contacts against its twelve strip objects at `0039D9A8`. Each pair of slats shares a center. The contact distance uses the crossing vehicle's model scale at +0x58 plus 0.1. For example, the PS2 data gives 0.70 for the marked patrol car, 0.654 for its bike and 0.90 for the Enforcer. Untagged MTA vehicles use the common 0.70 scale.

The pre-fix MTA regression moved a front axle across the strip between adjacent 100 ms samples. Both sampled positions missed and the tyre remained intact. The server now sweeps each nearby wheel relative to the six moving pair centers. Regressions exercise contact after the slats reach a wheel, a wheel ahead of the opening tip, front and rear crossings, a pass beyond the end, elevated wheels, discontinuous or stale transforms, and preservation of previous damage. The server derives wheel positions from chassis bounds and uses the curb's elevation. The client samples the pavement under each pair.

## Spike-strip deployment

At three stars, the ordinary ambient population assigned an officer on the corner sidewalk near (−665.46, 735.15). The temporary fixture positioned the player's SUV back along the approach. Two seconds stationary left the strip undeployed. The client then held accelerate. The officer began the underhand throw when the approaching SUV reached (−669.42, 721.70). [Officer starting the throw](final-hazard-suv-windup.jpg)

The animation request for `weapon_throwu` returned true. MTA reported the internal animation name `ped/run_wuzi`. A low-priority `onClientPedsProcessed` observer measured the actual elbow angles from both shoulders, elbows and wrists. Right/left flexion at 63, 113, 320, 402 and 514 ms was 14.0°/49.1°, 15.3°/59.2°, 79.5°/75.9°, 96.0°/62.7° and 61.8°/30.4°. The rise and release follow the converted VCS clip. The right elbow returned to 10.0° by 650 ms.

The fixture held the SUV back to photograph the slats opening along the selected road axis (−1.00, 0.05). The farthest pair advanced from 2.43 units at 536 ms to 9.26 units at full extension. The SUV resumed accelerating and reached (−668.80, 734.00). Both server and client recorded wheel states changing from (0, 0, 0, 0) to (1, 0, 1, 0) in front-left, rear-left, front-right, rear-right order. [Strip across SUV lane](final-hazard-suv-curb-to-lane.jpg) · [SUV front wheel contact](final-hazard-suv-driver-crossing.jpg)

### Extending strip beside a junction

The final bike run used a naturally assigned officer on the sidewalk near (−665.36, 726.00). The fixture positioned the rider for repeatable approaches. Two seconds stationary and a subsequent ride away from the officer produced no deployment. On the return, ordinary acceleration put the rider at (−669.29, 713.15) when deployment began. The server selected the road-facing direction (−0.99, 0.12). A temporary observer held the bike short of the curb so the client could record the whole opening sequence.

| Client observation after the trigger | Rendered slats | Farthest pair center along the road-facing axis |
| --- | --- | --- |
| 143 ms | 0 | — |
| 535 ms | 12 | 2.61 |
| 1,065 ms | 12 | 4.90 |
| 2,002 ms | 12 | 8.15 |
| 2,862 ms | 12 | 9.26 |

At full extension the six measured pair centers were 1.54, 3.09, 4.63, 6.17, 7.71 and 9.26 units from the origin. Each pair had headings of 112.9° and 232.9°. The early frame shows the slats opening beside the officer. The full frame shows the strip running from the corner sidewalk across the yellow center line. [Slats opening](final-hazard-bike-curb-throw.jpg) · [Open strip and junction](final-hazard-bike-curb-to-lane.jpg)

The rider resumed accelerating. The server recorded (1, 0, 1, 0) at first front contact. The client independently reported that tuple, followed by (1, 1, 1, 1) as its rear axle crossed. MTA exposes four wheel-state slots for this bike. [Rider crossing](final-hazard-bike-driver-crossing.jpg)

A second SUV with a temporary NPC driver crossed the same fully extended strip after the rider had stopped away from it. The fixture supplied the second vehicle's initial velocity and used client accelerator input to follow the sampled approach. Its intact wheels changed to (1, 0, 1, 0) at (−670.04, 725.70). Clearing wanted removed the strip metadata on both server and client. [Second vehicle crossing](final-hazard-secondary-driver-crossing.jpg)
