# VCS map streaming and mission interiors

Tested on November 28, 2026, with MTA 1.7.0 build 27005 on an isolated loopback server. A temporary Lua resource observed the production map loader and ENEX handlers, drove the player and camera, and requested the original 960 × 600 screenshots below.

## Model visibility

The subsequent Downtown pass also checks previously unlinked models, sign geometry and the rotation of every loaded placement. [Downtown skyline and map rotations](../vcs-downtown-towers/README.md)

The client created 7,650 buildings and 3,630 objects from 165 zone maps. For all 1,159 native LOD pairs, the probe resolved both placements by model and unique ID, including pairs split across zones, and compared the engine's actual low-LOD element with the intended target. All 1,159 matched.

| Location | Near | Transition or middle distance | Far |
| --- | --- | --- | --- |
| Fort Baxter | [Barracks frontage](final-army-bounds.jpg) | [Base perimeter](final-army-mid.jpg) | [Base skyline](final-army-far.jpg) |
| Ocean Beach | [Hotel frontage](final-beach-near.jpg) | [Hotel block](final-beach-mid.jpg) | [Coastline](final-beach-far.jpg) |
| Offshore jetties | [Walkway and railings](jetty-near.jpg) | | [Jetty group](jetty-far.jpg) |

At fixed near and far camera positions, the probe temporarily hid just the barracks or Ocean Beach hotel LOD, captured a frame and restored it. In the central 580 × 350 image region, zero pixels changed by 20 or more grayscale levels at either near position. The far views changed by that amount at 2,283 and 970 pixels respectively. Repeat captures with the LOD enabled gave 0 and 170 pixels respectively at those far positions.

The airport aggregate mesh `vcs_model_1523` returned alpha 0, 195, 255 and 0 on the near, transition, far and return passes. Both offshore `lodlojetty` pairs used matching object types. Downtown `dt_nitelites8` and its LOD were active at 23:00. At 06:00 only the coarse layer was active. At noon both were hidden.

## Fort Baxter lighting

At 23:00 the camera stood 18 units south of a lamp owned by `jm_mess`. With identical camera settings, expanding the entity bounds restored the corona and illumination on the pavement. The mean grayscale level in the central 11 × 11 lamp pixels rose from 47.9 to 253.8 with the lamp centered, and from 51.2 to 254.1 in the turned view. The pavement sample at x=465–495, y=535–544 rose from 48.3 to 68.9 in the centered view. Measurements use the original JPEGs in the table.

| Camera | Before | After |
| --- | --- | --- |
| Centered on the lamp | [Centered baseline](before-lamp-center.jpg) | [Restored corona](after-lamp-center.jpg) |
| Turned in place | [Turned baseline](before-lamp-edge.jpg) | [Restored lamps](after-lamp-edge.jpg) |

The same view showed an unlit fixture at noon. The back wall occluded the lamp when viewed from the opposite side. A separate two-lamp floodlight stayed visible from eight camera positions spaced at 45 degrees. [Daylight](after-lamp-daylight.jpg) · [Back wall](after-lamp-reverse.jpg) · [Floodlight from the north](tower-orbit-0.jpg) · [Floodlight from the south](tower-orbit-180.jpg) · [Final map at night](final-lamp-edge.jpg)

## Free-roam access

The client entered and exited the four dimension-based mission interiors through the production ENEX triggers and walked on each interior floor. The existing barracks route also passed in both directions.

| Place | Interior scope | In-game evidence |
| --- | --- | --- |
| White Stallionz Bar | Interior 1, dimension 1154 | [Dance floor and bar](final-bar-walk.jpg) |
| Fort Baxter administration building | Interior 1, dimension 1106 | [Office corridor](final-admin-walk.jpg) |
| Freighter | Interior 1, dimension 66 | [Stairs below deck](final-ship-enter.jpg) |
| Mendez Mansion | Interior 1, dimension 162 | [Basement](final-mansion-walk.jpg) |
| Fort Baxter barracks | Interior 1, dimension 1282 | [Existing quarters](barracks-enter.jpg) |

Phil's warehouse is a walk-through building in the main world. From the same starting point and with the same forward input, the closed frontage stopped the player at X=-1225.87. The open building allowed movement to X=-1213.88 inside and back to X=-1231.41 outside. The player stayed on the ground throughout. [Closed frontage](warehouse-before.jpg) · [Open frontage](warehouse-open.jpg) · [Walk in](warehouse-walk-in.jpg) · [Walk out](warehouse-walk-out.jpg)

At the Mendez Building, the client descended from the roof to the upper and lower offices and returned by both stairways. Both office floors reported interior 0, dimension 0, extra-colours weather 6 and row 1. The rooftop restored outdoor lighting. [Lower office](tower-lower-walk.jpg) · [Upper office](tower-return-upper.jpg) · [Return to the roof](tower-return-roof.jpg)

The catalog verification separately exercises all 58 bidirectional routes and checks 116 landing points against source collision. The full-map asset checks cover 802 native lights in 236 mesh/collision pairs. Compared with the preceding map archive, all changed COL bytes belong to the minimum/maximum bounds or radius fields of 1,115 headers. Collision primitives and bounding-sphere centers are byte-identical.
