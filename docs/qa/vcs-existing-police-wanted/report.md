# Existing patrol response to wanted increases

Verified on 26 November 2026 with an isolated loopback MTA 1.7 server, a real connected client, and a temporary Lua fixture. No Anode was used.

## Cause and original behavior

An existing road patrol called `TrafficGroundPolice.assignVehicle`, which used `available`. That function checks both new-vehicle dispatch capacity and the on-foot officer roster. When either budget was full, an already-rendered patrol repeatedly rejected the wanted player and retained its driving task.

Ghidra MCP inspection of US PS2 VCS `SLUS_215.90` confirms that the existing on-duty car branch at `00429FEC–0042A154` checks positive wanted stars, the world ignore flag and the player's XY position without a dispatch-quota test. `0040D420` reads world flag `004CD684 & 0x10`. Outside the ±14-unit square the branch assigns a pursuit mission; inside it a cruising land vehicle calls `0042AD80`. Decompilation of that helper confirms driver objective `0x10` and staggered passenger exit objectives. The decisive [assembly listing](ghidra-00429fdc.txt) is retained. A comment was added at `0042A010` in the existing Ghidra program.

## Changes

- Existing cruising patrols can acquire a suspect despite full dispatch budgets. New-unit assignment retains both capacity checks. Ownership remains exclusive to one suspect, and existing units still count toward the roster.
- Wanted increases wake nearby patrol scans for the next budgeted visit. Visible retiring patrols are restored when their retirement can still be cancelled. Existing suppression, custody, world, pursuit and native exit rules remain in force.
- Optional `tracePolice` resource setting logs wanted-rise, acquisition, crew exit, pursuit exit and release, with vehicle, driver, suspect, stars and roster counts. It defaults to false. Status counters also record police wakeups, acquisitions and crew exits.

## Live observations

| Run | Observation |
|---|---|
| Before the fix, on-foot player | A production-spawned model-207 patrol and its officer were streamed before the 0→1 increase. With two enrolled officers filling the one-star officer budget, acquisition repeatedly returned false. The selected driver remained seated through the 20-second timeout. See [baseline trace](before-server.log) and [baseline scene](before-wanted.jpg). |
| Fixed, seated player, final clean run | Production traffic spawned the model-207 patrol and selected its route and driver. The fixture stopped the patrol, placed the player's stationary sedan beside it, and waited four seconds before raising wanted from zero to one. One reserved vehicle and two reserved officers filled both dispatch budgets. The selected patrol acquired the player in the same logged second as the rise. The client reported `TASK_SIMPLE_CAR_GET_OUT` before the first 417-ms server sample; the officer was on foot by the 1,447-ms sample. |
| Native arrest | The same selected officer approached the player's sedan, entered `TASK_SIMPLE_CAR_OPEN_DOOR_FROM_OUTSIDE`, and triggered the arrest at **5,588 ms** after the rise. The player remained in the driver's seat. Busted and the officer aiming through the opened door were verified in the original screenshot. |
| Cleanup | Screenshot callbacks returned `ok`. The client acknowledged camera and input restoration. The final run's server and client logs contained no Lua errors or bad-argument warnings. Only the isolated server was stopped after verifying its PID and executable path. |

[Final trace](after-server.log) · [Client log](after-client.log) · [Existing patrol before wanted](existing-patrol-before-wanted.jpg) · [Same officer arresting the seated player](existing-patrol-busted.jpg)

An additional police-bike run also reached native seated arrest in 5,336 ms. Its [arrest image](bike-existing-patrol-busted.jpg) was inspected. That exploratory run had an error in the temporary diagnostic print after it filled the roster; the print was corrected before the final clean car run. An earlier exploratory car run also reached arrest but its probe continued sampling a driver reference after custody cleanup. These fixture issues were corrected and are excluded from the final clean-run result.

The production population spawned and controlled the selected officer and patrol. Temporary instrumentation constrained the police population mix to obtain a patrol promptly. The fixture used stationary vehicles, reserved test officers and a reserved vehicle to reproduce full budgets; it did not force the selected officer's pursuit, exit, door opening or custody. Collisions with unrelated traffic were disabled for the selected actor and player. Temporary exports and probes remain only in the isolated server, outside production resources.

## Automated validation

Passed `python -B tools/check_vcs_ground_police.py`, `python -B tools/check_vcs_traffic.py`, `python -B tools/ped_ai_check.py`, `python -B tools/check_vcs_road_rage.py`, and `git diff --check`.

The police regression covers full roster acquisition, unchanged new-dispatch limits, response suppression, zero stars, ownership between players, wanted-rise scan wakeups, custody/world exclusions, fading-unit restoration, nearby exit versus distant pursuit, and opt-in trace output. The existing renderer mock was updated for its point-light registration dependency.

The live acceptance run proves the stopped-car, one-star acquisition and seated-arrest path. Higher-star acquisition transitions and distant-pursuit decisions were checked in Lua; all vehicle models, obstructed doors, moving chases and network latency combinations were not repeated in this task. Rendering and native client synchronization were observed; audio was not assessed by listening.
