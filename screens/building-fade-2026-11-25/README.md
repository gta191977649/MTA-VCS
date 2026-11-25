# Native building rendering acceptance

Verified on 2026-11-25 with MTA 1.7.0-7.27005.0, Windows x64. The client
connected to a fresh isolated loopback server with eagleLoader, the complete
VCS map, SkyGfx, custom_coronas, interior and DGS. A temporary Lua resource
received a client-ready event, prepared the fixtures and requested 960x600
server screenshots. Accepted original JPEGs were opened and inspected.

## Distance fade

A stock city-hall building (model 4002) was placed at (0, 0, 1000). Cameras
looked horizontally from (0, -distance, 1030), with a fixed 70-degree FOV.
The model draw distance was 100. The existing client draw-distance multiplier
was retained. Each shader was bound globally to that model's texture names:
per-element shader targeting is not supported for buildings by the documented
MTA API. The comparison shader used the previous world-alpha/vertex-only
variant. Its color uniforms were held constant and post-processing was off.

At the same 185-unit camera offset:

- [Previous shader: facade remains opaque](final-before-185.jpg).
- [Restored shader: native distance opacity reaches the facade](final-restored-185.jpg).
- [Native reference: facade fades at the same boundary](final-native-185.jpg).

VCS color treatment remains, so this is an opacity/visibility comparison, not
a pixel-exact RGB comparison. Additional samples covered 180, 190, 195 and
200 units. Fixture opacity was explicitly reset before each final comparison.

A second pass set model LOD distance to 600 with extended LOD enabled and
sampled 250 through 330 units. Native SA ordinary-entity distance handling
beyond 300 units was retained. Both paths showed intermediate opacity at 310:

- [Native extended-distance reference](final-extended-native-310.jpg).
- [Restored extended-distance rendering](final-extended-restored-310.jpg).

## Aggregate LOD opacity

A real low-LOD object used near distance 100 and bounds (-1, -1, 1, 1).
Approaching and retreating camera offsets 101, 106, 111, 116 and 121 produced
element alpha 0, 63, 127, 191 and 255, respectively. The same values were
observed in reverse. At half fade, placement alpha 128 produced 64, zero
remained zero, and restoring 255 produced 127.

- [Hidden aggregate](object-range-101.jpg).
- [Intermediate aggregate opacity](object-range-111.jpg).
- [Fully visible aggregate](object-range-121.jpg).

The [observations](observations.log) retain the measured alpha values and
screenshot status events. Unit checks also cover timed visibility restoration,
re-registering bounds, explicit invisibility and destruction cleanup.

## Material coverage and limits

The VCS beach and Starlite scenes were inspected with the production shader,
including converted buildings and palm foliage. Runtime diagnostics reported
world, opaque/alpha props, foliage and all 22 shop bindings active. The shop
manifest check passed for 801 placements and 18 meshes. The shader now leaves
blend, alpha-test, depth and culling states to native rendering for every
variant; it contains no material-specific coverage or fringe passes.

- [Beach buildings](restored-map-beach.jpg).
- [Starlite buildings and palm foliage](restored-map-starlite.jpg).
- [Shop cabinet: food remains visible through glass](restored-shop-native-states.jpg).

Final comparison runs produced no new shader or client script errors. Early
test-setup failures (out-of-bounds coordinates, omitted camera fade and staged
resource restart events) were corrected; their captures are not acceptance
evidence. GPU timing, every individual material, additive-material overlap,
occlusion boundaries and all interior transitions were not exhaustively
benchmarked or visually exercised. Native alpha-test behavior for explicitly
translucent building elements is retained.

See [implementation behavior](../../docs/building-rendering.md). Test code and
temporary exports remain confined to the isolated server. The test restores
camera/player state before its owned server is stopped.
