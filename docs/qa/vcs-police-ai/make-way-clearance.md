# Emergency vehicle passing clearance

A real MTA client drove a marked VCPD cruiser on an isolated VCS server. A temporary fixture selected an automobile already spawned and driven by ambient traffic, placed the cruiser behind it once and then used throttle, braking and steering controls. It held a target line 0.60 game units off the NPC's original lane center and reduced closing speed while the measured hulls still overlapped laterally. The siren was off during the initial approach. Each pass retained the original civilian driver. No vehicle was repositioned during the passing interval.

The client projected both vehicles' local collision boxes onto the longitudinal and lateral axes of the approach. Yaw affects projected half-width. Abeam means the projected box centers cross longitudinally. The clearance margin is lateral center separation less both projected half-widths. The minimum overlap margin uses every rendered frame during longitudinal overlap. A separate collision event observer checked contact specifically between the cruiser and the selected civilian.

| Moving recipient | Time at abeam | Center separation | Cruiser + NPC half-widths | Margin at abeam | Minimum overlap margin |
| --- | ---: | ---: | ---: | ---: | ---: |
| Previous implementation, northbound model 171 | 9.30 s | 2.85 | 1.18 + 1.33 | 0.34 | 0.29 |
| Revised, matching northbound model 171 | 4.80 s | 3.56 | 1.19 + 1.56 | 0.82 | 0.77 |
| Revised, southbound model 175 entering from a curve | 6.57 s | 2.90 | 1.18 + 1.57 | 0.15 | 0.14 |

Time is measured from the start of the driven approach. In the previous implementation, the NPC moved 2.27 units sideways and the cruiser held its original line. The matched northbound tests began at (−37.9, −1489.0) with the same models, heading and scripted cruiser controls. On the revised pass the same model reached 3.04 units of lateral offset while the cruiser remained at −0.57. The driver resumed forward motion after the pass, reaching 10.29 units/s when the cruiser was 13.9 units ahead. The curved approach produced the narrowest revised pass. The NPC was already 2.32 units off its initial heading line when it reacted, so its total offset at abeam (3.50 units) includes road curvature. The cruiser was 0.61 units off lane center. The observer recorded no contact between the two vehicles on these passes. [Previous northbound pass](make-way-before-abeam.jpg) · [Matched revised northbound pass](make-way-after-abeam.jpg) · [Revised curved approach](make-way-curve-abeam.jpg)

## Stationary queue

For this run the fixture placed an empty red car ahead of a real traffic driver. It verified the driver had stopped before the cruiser approached. Before the change, with the siren active, the model 171 sedan held zero lateral offset at a 13.16-unit gap while the cruiser was traveling at 7.27 units/s. The pair never got abreast in the 28 seconds observed.

After the change, another production model 171 was stationary in the same lane when it received the rightward response at a 20.24-unit gap. The sedan moved 3.22 units sideways. At 4.77 s the cruiser drew abreast without contacting the sedan. The centers were 5.47 units apart, with projected half-widths of 1.49 and 1.55, giving a 2.43-unit margin. The minimum margin during longitudinal overlap was 1.90 units. The cruiser itself drifted from −0.60 to −2.33 as it passed the queue. The sedan's motion also cleared the cruiser's original aligned corridor by approximately 1.09 units. After the siren switched off, the sedan resumed its route at 9.2 units/s. [Stationary recipient after moving aside](make-way-stopped-abeam.jpg)

## Crossing traffic and siren-off control

With the cruiser approaching across its path, a production model 276 received the wait command at 0.195 s and stopped by 0.671 s. The wait cleared 4.05 seconds after it began. The civilian then traveled 4.76 units and reached 4.68 units/s by 6.20 s. The cruiser braked before crossing the civilian's lane, and the observer recorded no contact between them. [Civilian resuming across the cruiser's approach](make-way-crossing-release.jpg)

With the siren off at the start of the matched northbound pass, the marked cruiser approached from 27.9 units behind. The civilian kept driving at approximately 10 units/s and held its lane. By 0.63 s the cruiser had accelerated to 15.0 units/s and the gap had narrowed to 25.9 units. The civilian had moved only 0.02 units sideways and had no yield command.

## Signal-controlled junction

A supplemental test selected a stationary production driver near a signal. The observer decoded the driver's route assignment to identify the incoming signal group and stop waypoint. On a preliminary group 2 run, the cruiser accelerated for 1.3 seconds before braking and struck the rear of model 224. The civilian still stopped 3.02 units short and later crossed on green. This contact shows the limit of a driver yielding while constrained by a red light. In a second preliminary run with earlier braking, the server assigned the next route edge while the client displayed red. The normal server signal timer was still running during both preliminary trials, so client state alone could not establish when the server released the route.

For the final run the fixture held the same signal state on both peers and logged both at every sample. A stopped model 201 received a rightward response while approaching edge 702, signal group 1. At 1.38 s the cruiser had braked to a standstill behind it. The civilian crept from 7.06 to 4.75 units before the waypoint and stayed there through 6.9 s, including three seconds after the siren switched off. The next edge was assigned only after both peers went green at 7 s. At 8.28 s the civilian had crossed the waypoint by 1.68 units and reached 8.26 units/s. No contact occurred. The client also recorded native world sound group 17, index 10, from the cruiser during the siren-on interval. [Civilian holding at red](make-way-signal-red.jpg) · [Civilian advancing on green](make-way-signal-green.jpg)
