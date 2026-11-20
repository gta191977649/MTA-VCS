# Five-star specialist fire and driver-door custody

On 21 November 2026, a real MTA 1.7.0 client joined an isolated loopback server on port 29571. The temporary probe selected a passenger from a car spawned by the five-star traffic response. The probe moved the crew vehicle into view, requested the specialist's native exit and positioned that officer at measured distances from the seated driver. Production AI selected the weapon action, approach, native entry and custody. The test used no drive-away input.

## FBI officer

Run `specialist-950526` selected original model 10 in seat 1 at 39.11 units. The officer carried MTA weapon 29. The test fixed the player's Landstalker in place and moved competing foot officers away from the handle to isolate this officer. The client observed the following sequence.

| Scene | Observation |
| --- | --- |
| Stationary driver | The client counted one weapon-fire event at 11.0399 units. The muzzle flash is visible. Its last fire input came from the NPC controller 198 ms earlier, and the assigned task had already changed to door approach when the event arrived. [Original image](five-star-fbi-fire-stationary-side.jpg) |
| Moving the officer across the 3-unit boundary | The probe alternated the specialist's position to either side of the boundary ten times with the car locked. A client function hook recorded 21 positive fire inputs. The smallest distance at a positive input was 3.5211 units. Across 154 rendered frames within 3 units, fire was held in zero frames. Exact boundary equality and weapon-range equality are covered by the Lua regression. |
| Lock during native entry | The first seat-0, door-0 entry started at server tick 964826. The probe locked the car 98 ms later. At tick 968235 the door remained closed, wanted level was five and the driver remained seated. The client observed zero fire inputs through the reach and locked interval. [Original image](five-star-fbi-interrupted-door-side.jpg) |
| Unlock and retry | The second seat-0, door-0 entry started at tick 969683. The client observed `TASK_SIMPLE_CAR_OPEN_DOOR_FROM_OUTSIDE` with the hinge at 0.185. Server custody followed 1,190 ms after the entry began, with the original driver seated, wanted level five and the replicated hinge at 0.805. The client observed zero fire inputs during this reach. [Door opening](five-star-fbi-driver-door-open-side.jpg) · [Busted camera](five-star-fbi-seated-custody-side.jpg) |

## Vice officer and competing actors

Run `specialist-576651` selected original model 117 in seat 1 at 40.16 units. The same officer fired three times with MTA weapon 28 between 11.016 and 11.018 units, then entered a native door reach after the probe moved the officer to 2.45 units. Locking the door during that reach preserved the seated driver, closed hinge and five stars for 3.2 seconds. Two officers stood beside the handle. [Initial gunfire](five-star-vice-stationary-fire.jpg) · [Contested handle](five-star-vice-locked-door.jpg)

The Vice run did not complete the unlocked retry. The fixture vetoed competing officers' entry requests and the selected officer drifted beyond 3 units. It also observed a weapon-fire event at 2.707 units. This run did not record control inputs, so that individual event cannot be attributed to a particular input distance. The FBI run independently measured the delay between a valid input and the native fire event and exercised the threshold under instrumentation.

All six original 960 × 600 JPEGs returned screenshot status `ok` and were visually reviewed. The fixture released its camera, controls and parked officers after the run. At resource restart the client logged one stale fixture event. An inactive PIT fixture also logged two vehicle-argument warnings while observing the unrelated FBI arrest. The FBI custody event and hinge readings came from the active probe.
