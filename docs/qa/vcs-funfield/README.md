# Ferris wheel acceptance

Latest facial compatibility fix: [Native SA seated mouth and jaw](native-sa-faces/README.md).

Latest camera refinement: [Ten-shot path planning and acceptance](ten-shot-camera/README.md).

Tested on 21 November 2026 using a real MTA 1.7 client connected to an isolated
loopback server on port 61626. The temporary server contains the current map,
SkyGfx, frontend, marker, model and production traffic resources. Anode was not
used. The production resource contains no test-only remote controls.

## Closed gameplay loop

The final complete run at 18:38–18:40 exercised walking from the entrance into
carriage 7, taking seat 3, riding at client limits of 60, 30 and 120 FPS,
requesting an exit stop, waiting for that carriage to align, standing and
walking onto the platform. The client caps the requested 144 FPS limit at 120.
These are configured limits, not an independently measured rendering rate.

The player finished with health 100.144, collision enabled, movement/jump
controls enabled, no occupied seat, no contact carriage and no pending stop.
Normal exit used no fade or teleport. The live wheel retained its original
0.05 rad/s running speed; a stop for an occupied carriage can require a full
revolution. The server accepted repeated rides and the opposite seat row.

- [Boarding](full-cycle/wheel-player-boarding-side.jpg)
- [Seated ride](full-cycle/wheel-player-riding-side.jpg)
- [Aligned exit stop and stand prompt](full-cycle/wheel-player-exit-platform.jpg)
- [Walked back outside](full-cycle/wheel-player-exited-front.jpg)
- [Recorded full-cycle events](full-cycle/server.log)

## Posture and rendering

The corrected player pose is verified separately in a close view and in final
bone matrices sampled in `onClientPedsProcessed` at `low-100`, after the
production pose handler at `low`.

In the corrected sample, the left hip and knee are at carriage-local Z
−2.5573 and −2.5590, with the knee approximately 0.451 units forward of the hip.
The pelvis is below the attachment origin by the original clip's root offset,
so the player sits on the bench rather than standing at the attachment origin.
Before correction, the hip and knee differed by roughly 0.44 units vertically
and the player visibly stood despite the animation task reporting `seat_idle`.

- [Corrected player seated pose](poses/wheel-player-pose-final.jpg)
- [Original civilian seated pose](poses/wheel-npc-pose-front.jpg)
- [Before/after final bone measurements](poses/measurements.json)

The seat transform uses the original attachment Z directly, without the
incorrect extra metre. Both rows face the centre aisle. Player bones are
sampled from the original four-second animation after native ped processing;
the hands-up variant preserves the seated pelvis and leg pose.

The outdoor hub and distant model now have compatible object LOD types. The
live client reports `lodris_wheel` as the hub's actual LOD partner, and current
map loads produce no failed wheel-LOD-link warning. The near scene contains
one animated wheel and twelve original carriages.

## Edge cases

| Scenario | Result |
| --- | --- |
| Seated jump followed by movement through the doorway | Passed through the gameplay `jumpferris` handler shared with the Jump binding and native forward control. The player fell without recapture or teleport, took normal lethal fall damage, and remained unseated with controls/collision restored. |
| Abandoned exit request after jumping | Cleared; the wheel returned to running rather than stopping for the departed player. |
| Death and subsequent respawn | Seat and request were released; the next run boarded and seated normally. |
| Vehicle-entry handlers while seated | Both live client/server native-event handlers returned cancellation. The same probes returned allowed outside the wheel interaction. These event probes complement the shared F-handler tests; they do not represent a second human pressing F. |
| Dimension change while seated | Dimension 7 was preserved, the seat cleared, collision and movement/jump controls were restored, and all local carriage presentation was released. |
| Resource restart during an elevated seated ride | Ownership released and the player recovered safely, with health retained and controls/collision enabled. |
| Disconnect and reconnect | A new JOIN and client-ready handshake rebuilt the twelve carriages from the continuing shared wheel phase; the player boarded and seated again without a stale reservation. |
| Exclusive reservations, duplicate requests and invalid event source | Passed in the two-player Lua server harness. |
| Damage, death, respawn and world-change release | Passed in the server harness. |
| Motion and braking | All twelve carriage targets align; fixed-step simulations match at 20/30/60/144 FPS. A thirty-minute simulation remains finite and fully relaxes swing. |

- [Jump and fall events](edges/run.log)
- [Fall outcome](edges/wheel-player-jump-landed-front.jpg)
- [World-change events](edges/world-change.log)
- [Restart and vehicle-entry events](edges/restart.log)
- [Reconnect events](edges/reconnect.log)

## Limits and reproduction

Run `py -B tools/check_vcs_funfield.py` for Lua syntax, assets, motion, seat
ownership and cleanup checks. `--stage-live` creates the isolated acceptance
fixture. Test scripts and their local control file remain inside the temporary
server, outside production resources.

One real client was available. Simultaneous two-client rendering and network
latency behavior remain unverified; the server's two-player reservation and
event-ownership cases were exercised with a Lua harness. No listening
assessment of game audio was made. Textbox rendering and normal frontend help
cue dispatch use the existing shared frontend implementation.

The current full-cycle and edge runs have no new funfield Lua errors or
warnings. Earlier matrix-shape, static-pose and very-small swing errors were
found during development and fixed before the final runs. Historical entries
remain in the local client's cumulative log; the evidence windows above keep
the accepted runs separate from those superseded iterations.
