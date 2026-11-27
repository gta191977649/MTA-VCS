# NPC driver lifetime after body attacks

Verified on 2026-11-25 with the repository's MTA 1.7 build 27005, an isolated loopback server, a real MTA client, and a temporary Lua resource. No Anode was used.

## Cause and change

Population retirement unregisters a road car immediately, then deletes it and its occupants after the fade timer. The body-hit handler previously searched only registered cars. A real attack during this interval was ignored and the timer deleted the driver. Door interactions already cancelled the same retirement correctly.

The body-hit handler now accepts the pending road state, applies its existing owner, attacker, weapon, range and seat validation, and cancels retirement through `roadInteraction`. This restores the same vehicle, driver and passengers. The existing attack-response code then chooses its normal outcome. Health-loss events are retained for pending cars, without restarting their controllers, to support firearm damage arriving before its report.

## Original VCS evidence

Used the existing Ghidra MCP server and its open `SLUS_215.90 (VCS)` program, identified as the US PS2 ELF, MIPS R5900, image base `0x00100000`. SHA-256 of its input file: `3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547`.

- [`0x003EF910`](ghidra-003ef910.c) handles body attacks. Ordinary eligible occupants receive leave-car objective `0x10` and flee speech `0x77`, or the driver adopts style 3 with a first-transition cruise increase of 1.5. The random acceleration test is strictly greater than 0.5. Gang and law-enforcement branches precede this decision. This function does not delete the driver.
- Ghidra MCP's references query reports calls from `0x001D50C0` in the melee contact path and `0x003E85BC` in the vehicle-damage path. Automobile collision handling at `0x00136C10` is separate.
- [`0x002B0200`](ghidra-002b0200.c) performs population removal separately. Its pedestrian branch includes distance, visibility and retention checks; proximity within 20 scaled units refreshes a retention deadline.

These are static observations of the original executable. The cancellable fade timer is an MTA implementation detail. The existing port-specific civilian retaliation policy is outside this lifetime fix and remains documented in the [occupant behavior notes](../../vcs-npc-vehicles.md).

## Live verification

Production traffic created the vehicles, selected the drivers and assigned their routes. The temporary fixture stopped a selected car and drove real player fist/bat inputs through Lua. To exercise the narrow race deterministically, a high-priority observer requested retirement immediately before the production body-hit report, on the same client's ordered connection. The exit-branch random draw was fixed to 0.5 only in the isolated copy. This measures the cleanup race, not its natural frequency.

| Run | Original car / driver IDs | Measured outcome |
| --- | --- | --- |
| Baseline bat | 270 / 23 | Native weapon 5 hit, loss 9.3628. Driver and car deleted before any on-foot sample. First missing sample at 4472 ms after selection. Stack reaches the retirement callback and `finishRelease`. |
| Fixed bat | 211 / 43 | Native weapon 5 hit, loss 7.4071. Driver completed native exit by the 5956 ms sample, retained 11 HP and alpha 255, and remained alive through the 69-second observation. |
| Fixed fist | 276 / 63 | Native weapon 0 hit, loss 2.1476. Driver completed native exit by the 6821 ms sample, retained 30 HP and alpha 255, and remained alive through the 45-second observation. |

Original server-produced screenshots were opened and reviewed:

- Baseline: [before the bat hit](baseline-bat-before-body-side.jpg), [after deletion](baseline-bat-after-body-side.jpg). The gold target car is gone; the jeep in the second image is unrelated traffic.
- Fixed bat: [before](fixed-bat-before-body-side.jpg), [driver fleeing beside the retained car](fixed-bat-after-body-side.jpg).
- Fixed fist: [before](fixed-fist-before-body-side.jpg), [driver fleeing, viewed from the driver's side](fixed-fist-after-body-driver-side.jpg).

Selected-run samples and milestones: [baseline bat](baseline-bat.log), [fixed bat](fixed-bat.log), [fixed fist](fixed-fist.log). Earlier fixture attempts with missed strikes or an incidental non-weapon contact were discarded and rerun. A camera adjustment exposed the driver after the fist exit. Current server/client logs were reviewed; accepted runs did not introduce a production Lua error. Voice playback was not separately assessed by listening.

The fixture confirmed input release and camera restoration before stopping its resource. The isolated server was stopped after matching its PID and executable path. Test controls and scripts remain outside production resources.

## Regression checks

`python -B tools/check_vcs_traffic.py` passes. The new cases failed on the old implementation at `attacked car must cancel retirement`, then passed after the fix. They cover melee exit, firearm damage before/after the report, acceleration, invalid-owner and out-of-range reports, companion fade reset, and execution of the old retirement callback after cancellation.

Natural occurrence frequency, every vehicle model, and live multiplayer latency were not exhaustively sampled. Firearm ordering was checked in the Lua regression harness; live weapon contact used the bat.
