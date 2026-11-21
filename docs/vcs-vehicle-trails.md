# PS2 VCS vehicle light trails

## Binary evidence

Reference: Ghidra MCP program `SLUS_215.90 (VCS)`, US PS2 VCS ELF, MIPS R5900 little-endian. Original path: `D:/ps2_game/Grand Theft Auto - Vice City Stories (USA)/SLUS_215.90`. ELF SHA-256: `3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547`. Addresses below are virtual addresses. Decompiler parameter lists omit some R5900 register/stack arguments; call-site assembly was checked separately.

| Evidence | Address | Observed behavior |
| --- | --- | --- |
| E1 | `0027DD10` | Corona wrapper resolves the texture index, forwards five stack arguments unchanged to `0027DD80`. |
| E2 | `0027DD80` | Registry of 56 corona records, stride `0x90`; horizontal camera-distance rejection; argument 15 becomes streak flag bit 3 at record offset `0x48`. |
| E3 | `0027C4A8–0027C764` | Shift six XY/RGB/validity samples, clear current validity, project each corona independently, require on-screen coordinates and clear-LOS flag; reject current validity when either screen-axis displacement exceeds 50 pixels. LOS queries are cached for 2000 ms in the original. |
| E4 | `0027CCDC–0027CFB0` | Untextured additive line pass, depth test off, five segments per flagged corona. Endpoint RGB is `historicalRGB * floor((6-age)*21.333334) >> 8`, with ages 0–5; alpha remains 255. Render state is restored afterwards. |
| E5 | `0014566C–00145DA0` | Normalize camera-to-vehicle direction and dot with vehicle forward. Headlight intensity is `0.3 - dot*0.5`, RGB `(210,210,195)` or halogen `(190,190,255)`. Registration distance is 200 times camera LOD multiplier. Main headlights have streak flag 1; the separate large flare has flag 0. |
| E6 | `00146268–001465DC` | Rear-facing lamps use intensity `0.4 + dot*0.4`, base red 128. Brake/reverse input adds 0.4; reversing uses gray `(128,128,128)`. Registration distance is 50 times camera LOD multiplier. Damaged lamps are skipped independently; rear submissions enable streaks. |
| E7 | `00147228–001475E8` | Lights-off branch can submit rear lamps under brake/reverse input, with fixed RGB 120 (red tail/brake or gray reverse), distance 50. |

The registry/renderer correspondence and arithmetic are high-confidence static observations. This investigation does not claim original-console frame-by-frame visual equivalence. Camera-mode special cases and unrelated sun, weapon, and world-light corona callers are outside the vehicle-trail implementation.

## SkyGfx implementation

`pipeline/vcsVehicleTrails.lua` owns the VCS-only lamp histories and additive line submission. `VCSGraphics` starts/stops it and renders it immediately before its scene capture, so full, reduced, and off post-processing modes all support trails. It does not start the legacy classic-corona renderer. The existing legacy trail settings continue to control the legacy pipeline.

`shader/vcsVehicleTrails.fx` explicitly sets vertex/pixel shaders, ONE/ONE blending, and disabled depth writes/tests. The first real-client screenshots exposed dark lines with untextured `dxDrawPrimitive` despite successful submission counters. The material primitive path prevents inherited shader state from changing the recovered RGB output. MTA's [untextured primitive batcher](https://github.com/multitheftauto/mtasa-blue/blob/master/Client/core/Graphics/CPrimitiveBatcher.cpp) sets texture-stage arguments but does not explicitly clear vertex/pixel shaders in its flush.

`SKYGFX.vehicleLightTrails` defaults to `true`. Set it to `false` in `config.lua` to disable this effect. `getVcsGraphicsStats().vehicleTrails` returns `active`, `lamps`, `samples`, `segments`, and cumulative draw `failures`. These are read-only diagnostic counters; production exposes no test-control API.

Each valid model dummy produces its own lamp; a centered dummy produces one lamp. MTA light indexes are front-left 0, front-right 1, rear-right 2, rear-left 3. The original all-four-projections gate and arbitrary 20-unit cutoff are not used. Six samples are advanced once per rendered frame, matching the original frame-based history rather than adding a time-based long-exposure effect.

The following are explicit MTA adaptations:

- The camera LOD multiplier is unavailable through this scripting interface, so front/rear registration limits use its baseline value 1 (200/50 world units).
- Current MTA light activation, damage state, dummy transforms, gear, velocity, and driver controls stand in for native vehicle fields. Current model handling flags select halogen color; custom VCS handling flags are not assumed to share every SA bit.
- Visibility uses a current ray per projected eligible lamp instead of the original two-second cache. It checks buildings/objects and ignores the emitting vehicle and pedestrians. This avoids trails persisting through newly occluding geometry.
- Graphics restore, camera cuts, changed resolution/interior/dimension, model changes, stream-out, and resource stop reset history. Invalid samples age as gaps, preventing connections across invisible intervals.
- MTA renders the recovered integer screen positions at the current output resolution. The 50-pixel discontinuity threshold and one-pixel line rasterization remain literal; original PS2 raster/antialiasing behavior is not emulated.
- The 56-slot original registry is shared with nonvehicle coronas. This implementation tracks streamed vehicle lamps without displacing unrelated MTA coronas and batches line submissions to stay below Lua argument limits.

## Verification

Run `python tools/check_vcs_vehicle_trails.py` for Lua 5.1 syntax and behavioral checks. Run with `--live` on Windows to stage the current production resources, map, models, water, and traffic on an isolated loopback server and connect a real MTA client. The only test toggle is injected into the isolated SkyGfx copy. Screenshots are saved from authenticated `onPlayerScreenShot` callbacks, with original JPEG bytes and logs retained under `docs/qa/vcs-vehicle-trails`.

Live results and remaining limitations are recorded after visual review in the evidence directory. Logic checks alone do not establish rendering fidelity.
