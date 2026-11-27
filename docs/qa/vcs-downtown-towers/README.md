# Downtown skyline and map rotations

Tested on November 28, 2026 with MTA 1.7 build 27005, an isolated loopback server and a temporary Lua resource. The client mounted the four production IMG archives. All screenshots are the original 960 × 600 frames returned by the client.

## Rockstar roof signs

The original west and east signs stand vertically on their roof frames. The PS2 axes of the west sign are right (0, −1, 0), forward (0, 0, 1) and up (−1, 0, 0). At vertical pitch the previous exporter calculated roll and heading independently from nearly zero components. The converter now resolves the remaining angle from the right vector. It also selects MAINLA geometry 4959 for the west distant sign. The BEACH variant contained the east sign at a different world position.

| West before | West after | East after | Distant view | Noon |
| --- | --- | --- | --- | --- |
| [Edge-on letters](rot-base-west.jpg) | [Letters on the frame](rot-verified-near.jpg) | [East roof](rot-verified-east.jpg) | [West roof at night](rot-verified-far.jpg) | [Unlit frame](rot-verified-day.jpg) |

## Tower visibility

Two exterior placements displayed the DIAC5B cutscene skyline over the normal streets. The source streams the backdrop under slot 32, state 1. Removing those exterior placements exposes the original window recesses. The concert gantry in the mall retains its own geometry. [Facade before](dt-base-west-facade.jpg) · [Same camera after](dt-verified-west-facade.jpg)

Tower 56 now switches from `doontoon56` to `lodntoon56`. Its detail distance is 299 m. The coarse range uses 3,500 m, matching nearby Downtown towers. At each of two fixed cameras, the probe hid only the coarse building and then restored it. In the central 580 × 350 pixels, hiding the coarse building changed zero pixels by at least 20 grayscale levels at the near camera and 23,578 at the far camera. Restoring it reproduced the original frame in that region at both positions. [Near facade](switch56-near-on.jpg) · [Far tower](switch56-far-on.jpg) · [Far tower hidden](switch56-far-hidden.jpg)

## Night windows

### Tower 56 floating-window report

The two red lamp columns and the sequence of white window bands identify Tower 56. At the original camera position (−995, 790, 215), the probe hid only `lodntoon56`. This reproduced the floating windows at the left edge of the frame. Restoring the shell restored the facade. Comparing the restored and hidden frames changed 4,966 pixels by at least 12 grayscale levels inside the tower crop. Repeating the restored frame changed zero pixels at that threshold. [Shell hidden](reported-frame-hidden.jpg) · [Shell visible](reported-frame-on.jpg) · [Night view centered on the tower](reported-building-verified.jpg)

The two rooftop masts use a separate 84-triangle PS2 mesh, model 3003. Its former 100 m range left the red lights suspended above the roof at the same camera. A single native low-LOD object now draws the original mesh at the 3,500 m skyline range. The live client showed the masts from approximately 75 m and 730 m away, with the red lights aligned at night. This run loaded 7,647 buildings and 3,651 objects and verified all 1,181 engine LOD links. [Distant roof before](before56-mast-day.jpg) · [Distant roof after](after56-mast-day.jpg) · [Night lighting after](after56-mast-night.jpg)

### Other facades

Nineteen facades share their detail triangles between two complementary distant meshes. The detail partitions reproduce the original textured triangles, vertex colors, texture coordinates and winding. Each partition has its own native LOD link. North Beach West reuses its second original detail. The red Downtown sign retains its daytime far layer and uses a single copy of the overlapping night geometry. [Glass facade at 23:00](dt-verified-night-glass.jpg) · [Skyline at 23:00](dt-verified-night-bridge.jpg)

## Whole-map runtime checks

The probe read the engine matrices of all 7,648 buildings and 3,650 objects. All 11,298 positions matched the map within 1 cm. The largest absolute basis-component error was 0.00000136. The probe also resolved the actual engine LOD targets for all 1,181 links across the 165 zone maps. Every target matched its intended placement.

At 05:00 the detailed west window layers were inactive and the separately timed distant windows remained active. At noon all three were inactive. At 23:00 both detail partitions and the distant layer were active in their normal dimension, with native links controlling distance. The daytime red sign's distant layer was active at noon and inactive at 23:00.

The disc comparison covers every placement and 801 damage variants, totaling 4,110,638 DFF vertices. It reconstructs world positions from the shipped meshes and compares them with the original sector or prop mesh. The converter took the vertical-pitch path for 110 shipped placements. [Source comparison](../../../tools/check_vcs_map_rotations.py) · [Tower 56 from above](dt-verified-roof56.jpg)
