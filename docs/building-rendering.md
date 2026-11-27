# Building rendering

SkyGfx replaces building color lighting and fog while retaining GTA SA's
per-draw visibility and material render states. This applies to converted world
sectors, static props, foliage, glass, shop furniture and floor decals.

## Native opacity and render states

`vcsWorld.fx` starts with the alpha returned by `MTACalcGTABuildingDiffuse`.
It also reproduces RenderWare's active second-stage `CURRENT * TFACTOR` alpha
modulation before multiplying by texture alpha. The unlit/prelit rendering
path uses this texture factor for distance fades on trees and street furniture;
lighting/material alpha alone does not contain those fades. Disabled texture
stages are ignored even if their registers retain a previous draw's factor.
VCS RGB555 and expanded prop prelight calculations remain unchanged.

Every model's far fade is based on its definition's `lodDistance`, applied by
eagleLoader through `engineSetModelLODDistance`. Existing loader distance
multipliers and GTA's camera LOD scaling remain effective. SkyGfx consumes
the engine-calculated opacity, including its bounds and far-clip decisions;
it has no global tree, lamp or building cutoff and no second distance timer.
Both building elements and object elements use this shared opacity path.

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

## Native LOD pairs

SA counts a high-detail building as rendered after its COL sphere passes the
camera test. Fort Baxter's `lodhan_open` covers several hangars, while its
native detail owner `jm_han_open` occupies one hangar. A camera looking at an
adjacent hangar can therefore expose the coarse mesh even at close range.
The map converter transforms each coarse mesh into its detail owner's local
coordinates and expands the owner's sector box and camera sphere to cover
it. Its collision shapes, sphere center and draw distance are preserved.

Each distinct placement uses its original native HD/LOD link. Repeated copies
of the same coarse model at the same transform and in the same scope share
one draw. When the same coarse model also serves as a standalone low-LOD
object, eagleLoader creates both ends of its native pairs as objects so all
instances use the same engine draw-distance multiplier. Co-located related
neon models with different lighting hours retain each layer's original hours
and switch through their native object link.

Downtown tower 56 has two co-located shells in the PS2 normal render pass.
The detail mesh (2970) uses its original 299-unit draw distance. The
simplified shell (3079) has a 100-unit source distance and no source link.
The converter links it to 2970 and assigns it the 3,500-unit skyline distance
used by the adjacent towers 22 and 39. Ordinary play displays the separate
building models at both street and skyline distances. The twin rooftop
antennae share one 84-triangle PS2 model (3003). The converter keeps
one instance at its original rotation and gives it the same 3,500-unit
range, so the red lamps have visible supports beyond the original 100 units.

MAINLA geometry 5967 combines several Downtown facades into a single
backdrop. Its two placements reference the same geometry and transform. All
22 copies of its sector overlay require swap slot 32, state 1. The original
`SAFEHOU_12249` routine activates this state for the `DIAC5B` cinematic
and clears it afterwards. Free-roam conversion excludes these two placements.
The North Point Mall gantry uses a different mesh in dimension 3090.

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

## Native 2DFX lights

The converted map stores lamp coronas, point lights and ground shadows in
native DFF 2DFX records. SA schedules these effects during the owning entity's
pre-render pass. Its sector lookup uses the COL bounding box, and its camera
test uses the COL sphere. The converter expands both bounds around each
light's local position and its corona, point-light or shadow extent. It
preserves the original sphere center and collision primitives. Mesh bounds
and LOD footprints still describe the geometry.

The Fort Baxter mess hall (`jm_mess`, source model 1514) owns 24 lights spread
across the base. Its entity sphere has a radius of 185.73 world units.

## Timed window LODs

The PS2 island streams use separate distant meshes for different portions of
some lit facades. The converter partitions each matching detail mesh by
triangle, preserving vertex color, UV, material, pivot and bounds. Each
portion then has its own native high/low link, draw distance and time window.
Downtown model 2694, for example, can remain lit from 05:00 to 06:00 after
its detailed model 2574 switches off. Run `python tools/vcs_window_lods.py`
to verify the triangle sets and links. The new geometry resides in the
existing `dff_1.img`.

Downtown's western Rockstar sign uses MAINLA geometry resource 4959 for
distant model 2664. Its facade aligns with detailed model 2659 at world
X −574.5. The corresponding BEACH resource 4303 repeats the eastern
sign geometry near X −493. The eastern pair uses models 2687 and 2688.

## Verification

Run `python tools/check_vcs_map_rotations.py` to compare each shipped
placement and its DFF vertices with the PS2 disc. The check reconstructs the
MTA object matrix independently, including for symmetric meshes. At a vertical
pitch the converter uses the source right axis to recover the remaining
heading. For the western Rockstar sign this gives ZXY angles of X = 90°,
Y = 0°, Z = −90°. The same rule applies to the sign's distant model.

Run `python tools/vcs_lod_bounds.py` to verify every native pair, detect
duplicate coarse placements and check the detail bounds against the placed
coarse geometry. The converter runs the same tool with `--fix` when staging
a fresh export.

Run `python tools/check_vcs_map_lights.py` to check the spatial bounds of every
2DFX light in the shipped map against its assigned COL.

Run `python tools/check_building_visibility.py` with `lupa.lua51` installed to
check reversible range fades, placement opacity, timed visibility, destruction
cleanup and Lua 5.1 syntax. Rendering acceptance additionally requires a real
MTA client connected to an isolated loopback server; Lua checks cannot validate
GPU material state or streaming transitions.
