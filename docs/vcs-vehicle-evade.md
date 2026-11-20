# A player vehicle approaches a pedestrian

All addresses refer to the US PS2 VCS executable `SLUS_215.90`. A vehicle's scan can cause a ped to stop and gesture, raise their hands, sidestep, dive or keep walking.

## Detecting the approach

Vehicle update at `0x0033CA7C` calls `0x00433EB0`, searching 11 world units in each direction along X and Y around the vehicle. A second traffic-control entry at `0x00433AE8` uses 16. Candidate handling at `0x004342D8` uses a scan marker to avoid processing the same entity twice in one scan. For ordinary vehicles:

- Absolute vertical separation must be below 4. Let v be velocity projected on vehicle forward, gap the forward projection of the ped relative to the car center minus the front of the collision box, and side the absolute lateral projection. Require 0 < gap < 200v and side ≤ W+0.5. W uses the lateral maximum of the collision box, multiplied by 1.6 for vehicle class 6. Speed thresholds use internal units.
- Urgent reactions require gap < 50v. For v > 0.3, use the step handler if side > W+0.1 and the dive handler otherwise. For 0.1 < v ≤ 0.3 and ped state other than 0x11, use dive if side ≤ W−0.5, otherwise step. Low speed, reverse travel and movement outside the corridor fail the ordinary urgent branch. Skip a ped already in 0x1F or 0x30.
- At 50v ≤ gap < 200v, require a player vehicle, ambient ped outside state 9 and the facing-half-plane check or an active horn. Call `0x00205C20(ped,vehicle,2000)` and set movement 4 to flee the vehicle temporarily.

## Action choice and completion

| Handler | Ordinary-mode behavior |
|---|---|
| Step `0x00209908` | Check control flags, state and facing angle. An ordinary vehicle approaching from behind can be ignored. Once accepted, half of the random choices use the idle_taxi gesture. Others choose a left/right normal of vehicle velocity according to relative position, turn and play EV_step. Enter state 0x1F. |
| Dive `0x00209CD0` | After control and state checks, a front approach has a one-half hands-up branch. A rear approach is ignored seven times out of eight. Stats flags +0x14 & 0x10 can require hands up. A dive chooses one of the normals to the ped-to-car line, plays EV_dive and enters 0x30. Hands up plays handsup and enters 0x1F. |
| Horn | A regular car's horn can force mode 1, changing directional/random selection and suppressing the ordinary shout request. Vehicle+0x2B4 holds the horn counter. Input near `0x0033C0FC` sets it, `0x00336CA0` decays it and `0x001BAB90` uses it to select the model's horn sound. |
| End `0x0020A260` | A completed dive writes now+1 ms and enters fall state 0x2D; the following state machinery handles getting up. Other reactions can restore saved state through `0x00392F10`. The 1 ms write marks a transition rather than the total time on the ground. |

Ped animation group 0 uses clips 145 and 146 for EV_step and EV_dive, with association flags 0x58 and 0x1050. The step lasts about 1.133 s and local root Y travels from −0.036 to −1.210. The dive lasts about 2.333 s; Y travels 0.021 to 6.758 and Z −0.235 to −0.938. idle_taxi lasts about 0.833 s, handsup 1.133 s, and the front and back get-up clips about 1.367 s each. These are original clip samples. Multiplayer synchronization and collision movement use MTA adaptations.

## Shouts

Both handlers call `0x00174A90(ped,0x8D)` after accepting ordinary mode; forced mode 1 skips this request. At `0x00485AA8+(0x8D−0x66)*24` the next speech delay is 1000–1499 ms, same-ped repeat delay 3000–3999 ms and global category delay 3000 ms. MTA applies the last gate per receiving player.

The importer runs original event selector `0x001C2448` and reads bank-2 sample ranges at `0x001C87D8`. It found 97 eligible models and 205 unique WAVs. Model 23 uses samples 1861 and 1862; model 9 has no line for this event. The former's indices can be checked in `AUDIO/SET0/SFX2_PS.SDT`. The importer retains the latter's original silent result.

For architecture compare SA's `source/game_sa/Tasks/TaskTypes/TaskComplexEvasiveStep.cpp` and `TaskComplexEvasiveDiveAndGetUp.cpp`. The latter separates turning, diving, pausing and standing into subtasks. The thresholds, probabilities and sound and animation values above come from PS2 VCS.

## Original and port observations

In PCSX2 with the US disc, the player entered a parked car with a controller. A fixture set pedestrian position and initial car speed for a repeatable approach; state, health and both positions were sampled frame by frame. Model 16 transitioned from state 5 to dive state 0x30 at 0.30 s while roughly 9.7 m from the car and at health 100. By 0.67 s it had moved laterally about 0.9 m; the car still hit it at 0.73 s. Collision remained active during evasion.

In the MTA 1.7 client a real player drove a Landstalker from (282, −1100) toward positive Y, with model 23 near (282.4, −1082). Without using the horn, that approach triggered original voice 1862 and ev_dive_root. Ped X moved continuously from 282.39 to 284.09 as the car passed, reaching 289.27 at the end of the dive. The client played getup_front_root and resumed walking at the landing point with health 100. Moving the ped roughly 6 m aside, or reversing away from the same start, did not trigger evasion. Repeated ordinary approaches may instead produce hands up or a sidestep. [MTA recording](street-ai-evidence/mta-vehicle-evade.webp)

The resource uses `ped_evasion.lua` for trajectories and choice, `ped_evasion_c.lua` for landing checks and skeletal animation, and `ped_evasion_s.lua` for interruption, synchronization and recovery. Run `py -B tools/ped_evasion_check.py` to exercise geometry, landing, syncer handover and get-up. Handover has automated coverage; the recorded MTA trial used one real client.
