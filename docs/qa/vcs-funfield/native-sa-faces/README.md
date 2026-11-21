# Native SA seated mouth and jaw regression

Verified on 21 November 2026 in a real MTA 1.7 client connected to an isolated
loopback server on port 61632. The production client script matched the
workspace. Temporary scripts controlled the close-up camera, switched test
skins and measured the final processed bones. Anode was not used.

## Cause and correction

The previous workaround only restored a cached jaw quaternion for CJ/model 0.
Other SA player skins still received the incompatible original VCS jaw track.
Skipping a manual jaw write alone was insufficient because the VCS IFP task
also animated that bone before the manual body pose.

Players now retain their native facial animation: the resource applies its
sampled seated/greeting body pose without writing jaw bone 8 or running the
VCS IFP task on players. No cached facial quaternion or model-0 exception is
needed. Original VCS NPC rider animation remains unchanged.

## Live results

| Skin | Scenarios | Native jaw quaternion agreement | Maximum head-relative jaw position error |
| --- | --- | ---: | ---: |
| 7, matching the reported hoodie skin | Seated idle, front/three-quarter greeting, stand and reseat | 1.0 | < 0.00004 world units |
| 0 / CJ, with blue hoodie clothing | Seated idle and greeting | 1.0 | < 0.00004 world units |
| 21 | Seated idle, front and three-quarter | 1.0 | < 0.00004 world units |
| 105 | Seated idle, front and three-quarter | 1.0 | < 0.00004 world units |

A high-priority `onClientPedsProcessed` observer sampled the native jaw
quaternion and its position relative to the native head. A lower-priority
observer ran after the production pose handler and compared the resulting jaw
against the transformed head basis. The final model-7 run accumulated 567
processed seated frames across idle, greeting and reseating. The screenshot
captures were visually reviewed, not accepted from measurements alone.

The fixture was rerun after an early capture was missing and after a probe
restart raced its own respawn. Those incomplete captures were excluded.
The accepted model-7 run started with that skin, waited for client-ready and
normal gameplay seating, and verified occupied seats in every recorded case.

- [User-reported distortion](user-reported-before.png)
- [Corrected skin 7, front](wheel-face-sa-7-idle-front.jpg)
- [Corrected skin 7, three-quarter](wheel-face-sa-7-idle-threequarter.jpg)
- [Skin 7 greeting](wheel-face-sa-7-greeting-front.jpg)
- [Skin 7 greeting, three-quarter](wheel-face-sa-7-greeting-threequarter.jpg)
- [Skin 7 after standing and reseating](wheel-face-sa-7-reseated-front.jpg)
- [CJ with a hoodie](wheel-face-sa-0-idle-front.jpg)
- [CJ greeting](wheel-face-sa-0-greeting-front.jpg)
- [Skin 21](wheel-face-sa-21-idle-front.jpg)
- [Skin 105](wheel-face-sa-105-idle-front.jpg)

[Bone measurements and source hash](measurements.json) retain the observations.
[Automated regression output](checks.txt) covers the existing wheel, seating,
asset and cinematic checks. No production test controls were added. Not every
SA/custom player skin was visually tested; the fix applies to all player
records and preserves each current model's native facial basis.
