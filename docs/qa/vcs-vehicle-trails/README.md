# Vehicle light trail acceptance

## Result

The PS2-derived VCS vehicle trail component is enabled by default. Lua 5.1 behavioral checks passed, and real-client rendering passed on an isolated MTA 1.7 server at loopback port 60376. Production test resources, configuration, and test toggles stayed in the temporary server. The server was stopped after matching its PID and executable path. The original JPEG screenshots and current-run logs are retained in `verified/`.

Binary addresses, recovered formulas, and deliberate MTA differences are recorded in [the reverse-engineering notes](../../vcs-vehicle-trails.md). A Ghidra plate comment documenting the streak renderer was saved at `0027C418`.

## Live run

- Started the current map, models, SkyGfx, water, route graph, and production NPC traffic. A new server-ready message, player JOIN, and client-ready event confirmed the connection.
- Waited for map collision before releasing the player-driven taxi. Applied real accelerate input and used an oscillating camera aim to expose screen-space trails. Reset the controlled scene between cases.
- Reviewed all ten original screenshots. Headlight streaks are bright rather than dark; rear streaks are red. The damaged lamp no longer emits a streak. Disabling the feature removes streaks while preserving the normal lamps. Re-enabling and changing the vehicle model work.
- Confirmed trails with full, reduced, and off post-processing. The controlled front/full case submitted a maximum of ten segments, matching two lamps with five segments each. Ambient traffic contributes to aggregate counters in the other scenes, so those totals are not per-car measurements.
- Observed production-spawned NPCs separately after removing the player from the controlled car. Server-side records identified a Pony (original model 224, native slot 440) with a ped in the driver seat and `driveTrafficRail` assignment, followed by a Stallion (206/439) under `driveTrafficPhysics`. The NPC observation covered 750 client frames; its final aggregate draw-failure count was zero.
- Current-run client logs contain no errors or warnings. The server reports the pre-existing deprecated rotor API and missing owner-email setting. Inputs were released and the prior camera/FPS limit restored at completion.

| Evidence | Original screenshot |
| --- | --- |
| Player headlights, full post-processing | [Headlights](verified/run4-player-front-full-orbit.jpg) |
| Player rear lamps | [Rear lights](verified/run4-player-rear-full-orbit.jpg) |
| Reduced post-processing | [Reduced](verified/run4-player-front-reduced-orbit.jpg) |
| Post-processing off | [Off](verified/run4-player-front-off-orbit.jpg) |
| Damaged front-left lamp | [Damaged lamp](verified/run4-player-damaged-orbit.jpg) |
| Vehicle lights switched off | [Lights off](verified/run4-player-lights-off-orbit.jpg) |
| Trail component disabled | [Trails disabled](verified/run4-player-disabled-orbit.jpg) |
| Trail component re-enabled | [Trails restored](verified/run4-player-reenabled-orbit.jpg) |
| Taxi changed to police car | [Model change](verified/run4-player-model-orbit.jpg) |
| Production NPC Pony | [NPC rear lamps](verified/run4-npc-npc-orbit.jpg) |

## Logic checks and limits

`python tools/check_vcs_vehicle_trails.py` passes syntax, resource ordering, RGB/endpoint fading, two-sample startup, independent damage states, occlusion gaps, 50-pixel discontinuity rejection, light-off expiry, rear color, brake brightening, reverse gray, daytime reverse RGB, resolution reset, visibility/dimension filtering, disable/re-enable, model/stream lifecycle, blend restoration, and shader-allocation failure checks.

Brake/reverse color and occlusion/reset edge cases were checked through the Lua harness, not a complete set of connected-client maneuvers. This acceptance run used 30 FPS and 960x600 screenshots. It does not establish pixel-identical original PS2 rasterization, other frame-rate/resolution appearances, or a listening assessment of engine audio. No audio implementation changed.

Initial evidence was rejected: the first scene fell before collision loaded, the next scene started in a palm-tree median, and the untextured primitive path inherited rendering state and produced dark lines. The accepted run uses a clear traffic lane, delayed screenshot transitions, and an explicit additive material shader. Rejected runs are not visual acceptance evidence.
