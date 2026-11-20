# Ambient traffic behind an abandoned car

A real MTA 1.7 client connected to an isolated VCS server with its normal road graph, model resources and ambient traffic. The temporary fixture placed a red unoccupied Premier in the path of a moving production NPC on a divided city street. The car had no driver, no running engine and no position lock. The observer remained on the sidewalk. Production traffic selected its own models and routes and controlled every NPC from spawn onward.

Progress was measured along the original lane, with signed lateral distance measured perpendicular to it. Each vehicle kept its server-assigned road order across the transition from route-following to native physics. Positions and input came from the driving client. The observer tracked the parked car separately so moving it forward could be distinguished from passing it.

## Before the fix

The lead taxi approached at 10.2 game units per second and stopped 7.8 units behind the Premier. Two following vehicles stopped at 15.8 and 22.7 units. All three stayed on their route, at zero speed and zero lateral offset, through the 32.1-second sample. A second run captured four NPCs queued behind the empty car, with the rearmost center 29.9 units behind it. [Original queue screenshot](abandoned-queue-before.jpg)

## Final run

The parked car was at (−34.0, −1444.25). A light-blue sports car, road order 3, approached at 16.0 units/s. A red sedan, road order 4, formed the queue behind it. The front car stopped 12.1 units behind the center of the Premier. The following car stopped 19.4 units behind it. Both retained their original drivers and road-order IDs. [Queue at rest](abandoned-queue-waiting.jpg)

| Seconds after placement | Observed behavior |
| --- | --- |
| 32.42 | The lead car switched from rail style 0 to physics style 2 after the server had observed over 30 seconds stationary. The brief reverse request reached the client. Its rear sensor measured the follower at 1.83 units and reported `rear blocked`. The lead held at zero longitudinal speed. |
| 36.8 | The lead passed on the median side, with its center 3.6 units laterally from the original lane center. Its wheels briefly rode the curb. [Lead car beside the obstacle](abandoned-queue-lead-passing.jpg) |
| 38.5 | The lead was 17.3 units beyond the Premier, traveling at 16.5 units/s. The original red follower advanced from −19.4 to −11.6, then waited behind the same obstruction. |
| 66.56–67.0 | The follower received its own recovery request and physically backed from −11.6 to −12.2 units. It then steered toward the median. |
| 71.1–73.6 | The follower passed with 3.5 units of lateral offset, then reached 13.1 units beyond the Premier at 10.0 units/s. The recorded pass was at 73.02 seconds. [Follower beyond the Premier](abandoned-queue-follower-cleared.jpg) |

The parked Premier stayed empty and at its original sampled position throughout both passes. The collision observer recorded no contact between the lead and the Premier. This run used an ordinary divided street with available space at the median. There was no closed traffic signal during the measured wait. The screenshot supplied with the bug had no map coordinates.
