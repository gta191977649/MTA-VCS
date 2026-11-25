# Building rendering

SkyGfx replaces building color lighting and fog while retaining GTA SA's
per-draw visibility and material render states. This applies to converted world
sectors, static props, foliage, glass, shop furniture and floor decals.

## Native opacity and render states

`vcsWorld.fx` uses the alpha returned by `MTACalcGTABuildingDiffuse`, then
multiplies it by texture alpha. This follows the current lighting and material
source states. Unlit geometry must not consume stale material opacity; native
distance fades must not discard the opacity supplied by `RenderAtomicWithAlpha`.
VCS RGB555 and expanded prop prelight calculations remain unchanged.

All building variants use a single-pass technique that overrides fog and the
vertex/pixel shaders only. GTA retains ownership of alpha testing, blending,
additive blending, depth testing, depth writes and backface culling. There are
no texture-specific PS2 coverage thresholds or extra fringe passes. The old
`vcsAlphaTextures.txt` classification is no longer loaded or downloaded.
The `alphaTextures` diagnostics field remains available and reports zero
separate alpha overrides.

Model draw-last, additive, depth and culling flags remain eagleLoader model
settings. SkyGfx does not replace them with texture-name-based state overrides.
Draw distances, native LOD links and streaming residency remain unchanged.

## Aggregate range LODs

Some converted placements have a `lodNear` distance and XY `lodBounds` instead
of a native high-detail parent. eagleLoader fades those aggregate LODs in each
frame using distance to the bounds. The near fade reverses SA's unlinked-model
far-fade band: its end is `lodNear + 20`; its width is 20 units through a near
distance of 150, otherwise `lodNear / 15 + 10`.

The fade multiplies the stored placement alpha. Timed visibility can still
force zero and restore the original alpha. Moving the camera back through the
band reverses the transition without visibility hysteresis. Native rendering
continues to own the far fade. The separate 100 ms residency checks retain
their existing hysteresis and do not set visual opacity.

These aggregate bounds do not encode native model bounding radii or the
camera's LOD multiplier. Their transition is a compatibility adaptation of the
SA fade band, rather than a reconstruction of native parent/child ownership.

## Verification

Run `python tools/check_building_visibility.py` with `lupa.lua51` installed to
check reversible range fades, placement opacity, timed visibility, destruction
cleanup and Lua 5.1 syntax. Rendering acceptance additionally requires a real
MTA client connected to an isolated loopback server; Lua checks cannot validate
GPU material state or streaming transitions.
