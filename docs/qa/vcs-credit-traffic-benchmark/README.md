# Traffic frame cost during the VCS credits

## Test setup

A real MTA 1.7 client ran the VCS map, credits, SkyGfx world shaders, full post-processing, and bloom on an isolated loopback server at 1280 × 720 with a server limit of 100 FPS. The host reported an Intel Core Ultra X7 358H and Intel Arc B390 graphics. The 21:00 credits scene keeps the daytime sun optics out of the comparison.

The test recorded 460 camera and player-position samples from the production credits director following ambient traffic. Each pass replayed the same camera, field of view, player path, and credit text for that experiment. Each measurement followed a 12-second settling period. Screenshots were taken on a separate replay after frame sampling. Actors spawned and drove normally, so the camera path was repeatable while actor counts and behavior varied.

## Traffic resource on and off

Only `npchlc_traffic` was stopped for the two middle passes. Its dependencies, the credits, parked vehicles from other resources, and SkyGfx stayed active. Each measurement covered 20.5 seconds. Streamed counts include actors outside the camera view.

| Pass | Traffic | Mean streamed vehicles / peds | Average FPS | Mean frame | P95 frame | P99 frame |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | On | 17.9 / 13.0 | 45.3 | 22.1 ms | 41.3 ms | 54.3 ms |
| 2 | Off | 7.2 / 0 | 64.7 | 15.4 ms | 24.2 ms | 35.1 ms |
| 3 | Off | 7.2 / 0 | 63.8 | 15.7 ms | 25.7 ms | 34.7 ms |
| 4 | On | 15.6 / 12.3 | 48.4 | 20.6 ms | 29.7 ms | 33.0 ms |

Pooled across the two passes per condition, traffic increased mean frame time from 15.56 to 21.33 ms. The share of frames over the 16.67 ms budget for 60 FPS rose from 29.4% to 80.0%. P95 rose from 25.2 to 32.6 ms. The size of the tail varied between traffic-enabled passes.

PresentMon independently measured average present intervals of 22.25, 15.16, 15.67, and 20.66 ms across the four passes. Average GPU-busy times were 6.48, 5.26, 5.43, and 6.48 ms respectively. These measurements use the interior of each pass, discarding one second at each boundary. The additional GPU work accounts for only part of the observed interval increase. CPU and GPU work can overlap.

[Traffic on](traffic-on.jpg) · [Traffic off](traffic-off.jpg) · [Per-frame measurements](frame-times.csv)

## Traffic still running, actor models hidden

A second recorded clip lasted 21.6 seconds. All four passes kept traffic running. The middle two set client-side alpha to zero on traffic-owned peds and vehicles, including newly streamed actors. At the end of each hidden pass, every streamed traffic-owned actor reported zero alpha (10 peds and 8 vehicles, then 11 peds and 8 vehicles). Collision, synchronization, audio, and vehicle effects continued. The parked cars owned by other resources stayed visible.

| Traffic models | Average FPS | Mean frame | P95 frame | P99 frame |
| --- | ---: | ---: | ---: | ---: |
| Visible, two passes | 43.0 | 23.26 ms | 36.0 ms | 42.4 ms |
| Hidden, two passes | 43.5 | 22.98 ms | 35.9 ms | 56.7 ms |

Hiding the models saved 0.28 ms on average and did not consistently improve the slowest frames. PresentMon GPU-busy time ranged from 7.05 to 7.54 ms across the four passes. Actor transparency leaves engine processing and some effects active, so this comparison cannot apportion the remaining time between physics, synchronization, animation, or audio.

In the two visible passes, MTA's five-second Lua timing samples measured the NPC task executor `cycleNPCs` at 79 ms over 228 calls and 77 ms over 221 calls, about 0.35 ms per frame in both. The traffic impact-sampling callback took about 0.03 ms per frame and traffic visibility about 0.04 ms per frame in those windows. These are callback timings and cannot account for native engine work that runs later.

[Models visible](actors-visible.jpg) · [Models hidden](actors-hidden.jpg) · [Recorded camera path for this clip](camera-path.csv)

## Which traffic population costs time

Seven more passes used the second camera recording. Each restarted the traffic resource, set its road-car and ambient pedestrian densities before graph loading finished, and allowed the population to build. Boat density was zero throughout. The production road-vehicle population includes drivers and passengers. The order was both, pedestrians, cars, neither, cars, pedestrians, both.

| Enabled populations | Pass averages | Pooled FPS | Mean frame | P95 frame |
| --- | --- | ---: | ---: | ---: |
| Both | 40.8 and 49.0 FPS | 44.9 | 22.27 ms | 34.3 ms |
| Road cars and occupants | 49.8 and 56.3 FPS | 53.1 | 18.85 ms | 29.8 ms |
| Ambient pedestrians | 54.4 and 58.0 FPS | 56.2 | 17.80 ms | 29.4 ms |
| Neither | 60.1 FPS | 60.1 | 16.63 ms | 26.7 ms |

The car-only passes ended with seven to nine streamed traffic vehicles and eight to nine occupants. The pedestrian-only passes averaged 0.3 to 1.0 streamed peds. This route measures a lightly populated sidewalk. The differences between these conditions cannot be added to predict full-density performance.

Prioritize road cars and occupants. A useful first experiment is to keep the same cars and drivers on the same path and vary the update rate for distant vehicles following rails. Measure the client frame-time change and verify that nearby steering, collisions, and network handoffs still work. The existing per-frame path runs through `cycleNPCs`, `performTask.driveTrafficRail`, and `advanceNPCTrafficRail`. Its measured Lua time leaves a substantial part of the gap unattributed. Separate native vehicle physics, synchronization, and occupant processing before selecting a permanent change.

[Road cars and occupants](road-cars.jpg) · [Road cars and walkers disabled](no-road-cars-or-walkers.jpg)

## Road-traffic optimization results

The implemented changes cache the 21 horizontal samples of each route segment and skip redundant velocity writes and look-ahead work when a vehicle is already stopped. Comparing 900 repeated route lookups took 65.8 ms before and 37.7 ms after. Across 1,200 positions the original and optimized implementations returned identical segment selections, projections, and look-ahead coordinates. The traffic regression suite passed, including braking a stopped vehicle after a lateral impulse.

The final live comparison replayed the same camera with production traffic. Across two passes per condition, the original averaged 45.95 FPS with a 33.80 ms P95 frame time. The optimized version averaged 42.49 FPS with a 36.52 ms P95. The optimized passes avoided 7,339 stationary velocity writes during settling and measurement. Actor counts varied, and these runs did not demonstrate an overall FPS gain. An earlier experiment lowering distant steering frequency also failed to improve frame time and was removed. Production uses its existing steering frequency and traffic density.

[Per-pass measurements](rail-optimization.csv) · [Optimized road traffic in the live client](rail-optimized.jpg)
