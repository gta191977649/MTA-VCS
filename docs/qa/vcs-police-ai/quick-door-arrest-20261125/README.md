# Prompt driver-door arrest and Busted camera acceptance

Verified on 25 November 2026 with an isolated loopback MTA 1.7 server, a real client and temporary Lua resources. At the user's request, the accepted fixtures spawned a nearby marked patrol and officer directly. The officer used the production pursuit worker, native door task, hinge confirmation and custody controller. Test hooks remained in the isolated server copy.

## Driver-door arrests

| Scenario | Measured result |
| --- | --- |
| One star, stationary occupied car | Driver stayed in seat zero and officer stayed outside. Server hinge ratio 0.8074. Client Busted appeared 180 ms after the hinge-threshold observation. The successful native entry-to-arrest interval was about 1.45 seconds. Initial requests before the new officer finished streaming were rejected; total fixture start-to-arrest time was 10 seconds. |
| Two stars, lock during the first reach, then unlock | Lock cancelled the first attempt without arrest. The same officer retried after unlock and arrested the seated driver. Hinge ratio 0.8074; client Busted followed the threshold by 108 ms. The successful native entry-to-arrest interval was 1.27 seconds; total fixture time, including spawn delay and interruption, was 4.02 seconds. |
| Custody completion | Both runs reset wanted to zero, released player/vehicle freezes and charged $100/$200 from $2,500. Forced driver exits occurred at the station transfer after Busted. |

Original screenshots were opened and reviewed: [one-star custody](closed-one-busted.jpg), [two-star open door and seated driver](closed-two-interrupted-busted.jpg). The latter uses a temporary fixture camera to show the driver's door. [Accepted telemetry](observations.txt) records the native tasks and release. Ambient-patrol trials timed out and were excluded. An initial two-case fixture replaced its officer mid-test; the accepted two-star trial was rerun separately with the same officer throughout.

## Busted camera

Ghidra decompilation of US PS2 `0x0029A8F0` exposed reversed entity-type branches in the adapter: masked type 6 is a ped; type 4 is a vehicle. The correction gives ped targets a 50/50 officer/side ordering and occupied vehicles a 65% street-fixture-first ordering. `0x002A40E0` and `0x002A4538` confirm the existing officer-offset and low-side geometry. The field of view remains 45 degrees.

A separate live seated arrest and restrained on-foot arrest used the corrected production camera with no fixture camera override. From approximately 0.2 through 3.9 seconds both measured 45-degree FOV, zero roll and a look ray passing through spine bone 3 within floating-point precision. Seated view distance changed from 23.79 to 11.66 units; the on-foot view changed from 9.25 to 12.50 units. Both followed the player again at 90-degree FOV by the 4.5-second sample and remained correct at 5.4 and 8.2 seconds. Wanted reset, the $200 fee and release also completed in each run.

Reviewed evidence: [seated production shot](camera-seated-two-early.jpg), [seated fade](camera-seated-two-fade.jpg), [seated station return](camera-seated-two-station.jpg), [on-foot early shot](camera-foot-two-early.jpg), [on-foot later shot](camera-foot-two-late.jpg), [on-foot fade](camera-foot-two-fade.jpg), [on-foot station return](camera-foot-two-station.jpg). The seated street-anchor shot includes a foreground lamp arm but keeps the focus ray clear. The optional seated 1.5-second screenshot was not returned while the preceding capture was pending; the 3.9-second telemetry and fade capture verify the later seated camera state. [Camera telemetry](camera-observations.txt) contains all samples.

## Automated checks and limits

- Wanted tests passed, including 249/250 ms retry boundaries, stale expiry/cancellation, duplicate officers, entry veto, ownership/world/target rejection and client cleanup.
- Ped-service tests passed, including door priority over an active firearm burst. Custody and camera tests passed; camera tests now distinguish the strict 0.5/0.65 selection boundaries.
- HLC checks passed, including the 249/250 ms first-arrival boundary, 1,500 ms subsequent spacing and four-report cap. Changed production scripts compile under Lua 5.1; targeted whitespace checks passed.
- The broader ground-police test remains blocked by its renderer mock lacking `CPointLights`; executing its HEAD version reproduced the same failure.
- No arrest/camera controller errors appeared in the accepted live runs. Client startup reported existing missing raw textures from `txd/ps2rawtxd.lua`. Complete logs are retained in `D:/dev/MTA-VCS-qa/quick-door-arrest-20261125`.
- Quick live coverage uses stationary scripted patrol fixtures. Creeping vehicles, passenger-side approaches, open/missing doors and multiplayer ownership handoff were not rerun live. Deterministic tests cover eligibility and stale-owner rejection. Responsiveness and hinge thresholds are MTA implementation values, not recovered VCS constants.
