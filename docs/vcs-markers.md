# VCS marker evidence

Analysis used Ghidra MCP against the open program `SLUS_215.90 (VCS)`, the US PS2 VCS ELF. SHA-256: `3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547`. The associated `PS2/GAME.DTZ` SHA-256 is `570a7504048e8a0187b04b20fec63fc57c404c74b84e7d3ee19df8daab1a365b`. Code addresses below are ELF virtual addresses; asset offsets are in the inflated container before relocation.

## Recovered paths

| Location | Observed behavior |
| --- | --- |
| `003321F0 → 0016BF08` | Installs the marker model table from GAME.DTZ root slot `0x2A`, pointing to `0x3B2DBC`; initializes 32 marker entries of stride `0x90` |
| `0016C4B0` | Placement gate accepts exactly native types 1, 2, 3, 6, 7, 8; other IDs return null, despite residual unreachable branches for 0 and 4 |
| `00113D50 → 001142C0` | Radar entity arrows use vehicle size 2.5 and origin Z plus 1.2 times the collision-box top plus size. The ordinary ped arrow uses size 1.5 at ped Z plus 2.5. The alternate type 2 ped arrow uses size 0.5 at ped Z plus 1.3. A seated ped uses the vehicle roof calculation with the ped arrow size. The placement call passes pulse 0.2 and period 1024. |
| `0016B9A8 → 0016B9B8` | Traverses clump atomics and clones the final atomic; this matters for native type 7, which has three atomics |
| `0016BC58 → 0042C0B8` | Replaces material RGBA each render, scales XY and Z separately, renders the cloned atomic; native material RGB is not an extra tint |
| `001A6DF0` | Marker lighting uses 0.6 ambient RGB and light color `source + (1-source)*0.4` |
| `0016C020` | Renders submitted entries, removes unused entries, normal range 150; type 6 extends range by `size*10`, type 8 has a special range exception; types 1/2 also submit corona overlays |
| `00256338` | Persistent mission spheres: type 6 pink `(237,130,180)`, type 7 cyan `(30,255,255)`, other yellow `(255,255,128)`; alpha 228, pulse fraction 0.1; periods 2048/1024/2048 ms |
| `0016EB38` | Type 6 double placement at scales 1 and 0.93, with opposite rotation directions |
| `00405C18`, SCM `03D2` | Race cylinder uses native 6, radius input multiplied by 0.7, Z scale 100, alpha 255, period 128 |
| `00405E10`, SCM `03E2` | Deprecated race arrow uses native 3, size 3.2, constant-phase period 1, alpha 200, Z plus caller offset plus 7 |
| `004063B8` | Oriented hoop placement uses native 8, alpha 100, period 1 |
| `0017C4F0` | Pointer has separate near-camera native 3 and world-position native 1 paths; pink RGB and alpha 200 |
| `00405250`, SCM `0165` | Script corona submits to `0027DD10`, outside the six mesh types; ground sentinel handling adds 0.1 |

Ghidra initially treated `00405250` as data. Creating `VCS_Script_DrawCorona` at that entry enabled decompilation; the recovered handler reads nine parameters and calls the corona submission path. Script handler pointers were independently read at ELF file offset `0x3BFCE4 + (opcode − 0x3E)*8`.

## Animation formulas

In `0016C4B0`, phase is `sin(((time-created) & (period-1))*2*pi/period)`. Period 1 produces a constant zero phase. For arrows 1–3, proximity scale is 70% within 5 horizontal units, rises linearly to 100% at 25 units, and stays full-size beyond that. Pulsed size is `base - pulse*base*phase`; native 7 and 8 skip size pulsing. Types 1 and 3 bob by `base*phase*0.25`; type 7 places Z at `z+0.7+base*phase*0.6`.

Type 6 alpha is 30% within `size+1`, rises linearly to 100% at `size+12`, and remains full beyond that. Ground placement uses ground Z minus `size*0.05`. Rotation uses the short at marker `+0x80`, multiplied by the timestep and degrees-to-radians. Call-site assembly supplies 5 for normal arrows, ±1 for the double cylinder, and 0 for persistent type 7. Timer `002F4Axx` derives the timestep from hardware elapsed ticks; the normalized time unit is 50 steps/second. The port expresses those values as degrees/second.

Target orientation for native 8 uses the complete 3D direction. Other arrow target paths use horizontal direction; native 1/3 also apply an approximately −20-degree tilt. Target alignment replaces the accumulated free-spin matrix.

## Asset provenance and coverage

`tools/import_vcs_markers.py` verifies both input hashes, reads the model table, follows each clump's atomic list, converts the selected original VIF mesh with the existing local `vcsconv`, and decodes original palette textures. It preserves vertices, UVs, normals and triangle winding. None of the six native geometries has prelit vertex colors. Cylinder alpha gradients are in the original `zonewhite64` raster.

| Texture | Inflated GAME.DTZ texture offset |
| --- | --- |
| `xv_white_sl` | `0x578C0` |
| `zonewhite64` | `0xA8AD0` |
| `ringborderblur` | `0x63960` |
| `coronaringa` | `0x82D70` |

The generated manifest records each model's clump, final atomic and geometry offsets, counts, bounds, original material color, texture dimensions and output hashes. This covers every mesh ID admitted by the recovered placement gate, plus the script mission corona presentation. It does not claim to recover every effect of the general corona system or unavailable native types.

The API maps the familiar MTA names onto these recovered paths and exposes the additional VCS variants. Defaults use mission pink consistently; callers can select any RGBA. The API diameter convention, MTA trigger shapes, and bounded hoop distance are explicit port decisions. SkyGfx owns the marker shader and supplies the recovered 0.6 ambient, brightened timecycle directional color, and its VCS sun direction; frontend applies that lighting to the original normals. Native 1/2 include star-corona overlays at the recovered 2.2/1.2 radius multipliers and alpha132, additionally scaled by API opacity. `0027DC40` initializes corona texture0 from `coronastar` at `00487780`; the port reuses SkyGfx's verified original raster. The complete PS2 hardware pipeline remains outside this immediate-mode port. Static decompilation establishes formulas and assets; the live-client report establishes which port behaviors were exercised.

## Resource boundaries

`marker` owns the exported creation/lifecycle API, MTA trigger elements, synchronized visual definitions, viewer rules, and optional minimap blips. A new marker creates no blip; `setMarkerBlipVisible(marker, true)` is the explicit opt-in. `frontend` owns animation, camera-facing orientation, presentation filtering and draw submission. `skygfx` owns `createVcsMarkerMaterial(texture, additive)` and `getVcsMarkerLighting()`, including alpha/additive blend state, depth state and timecycle lighting. No gameplay resource draws marker UI directly.
