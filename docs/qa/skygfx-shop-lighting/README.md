# SkyGfx shop furniture lighting verification

Date: 2026-11-20. Client: MTA:SA 1.7.0-7.27005.0, Windows x64.

Shop furniture references streamed GTA3PS2 materials with bare content-hash
texture names. These names matched neither `vcsw_*` nor SkyGfx's existing
specialized prop lists. The furniture therefore retained SA's lighting while
the surrounding room used the VCS shader.

`tools/vcs_shop_materials.py` reads production shop placements, their intact and
damaged model definitions, and the deployed IMG/DFF material references. It
generates 22 exact texture bindings covering 18 meshes and 801 placements.
Run `python tools/vcs_shop_materials.py --check` after changing map assets.
Existing specialized prop bindings retain precedence through exclusion from
the generated manifest.

The furniture shader uses expanded prop prelight and the active VCS room
timecycle. Cabinet atlases contain opaque metal and translucent glass together.
Only fully opaque pixels write depth; the translucent pass blends without
writing depth, keeping food behind the glass visible. This variant is limited
to the shop manifest and does not change the existing foliage or world alpha
thresholds. No additional screen capture or fullscreen postprocessing pass is
introduced. GPU frame time was not benchmarked.

## Connected-client test

An isolated loopback server used the production Eagle loader, current IMG assets,
SkyGfx, interior, custom_coronas and DGS. Its map selection was restricted to the
unchanged `int_1581` Gorilla Salad room. A temporary Lua resource spawned the test
player in interior 1, dimension 1581, at midnight, then fixed the camera at
(-1734.7, 636.9, 152.3), looking at (-1735.2, 640.2, 151.0).

The server logged a fresh JOIN and client-ready event. Nine production map
objects streamed in. The client reported `shopProps=true`, `shopTextures=22`,
and all three visible hashed prop textures were present in the manifest.
Removing and reapplying all 22 bindings succeeded. Server screenshot events
reported success; both original 960x600 JPEG captures were reviewed.

- [Before: furniture bindings disabled](shop-before.jpg)
- [After: furniture bindings enabled](shop-after.jpg)

The after image shows the cabinet receiving the room's warmer lighting with
food visible through its transparent areas. Surrounding room rendering remains
consistent. The final run logged no client script or shader errors. Camera and
player freeze were released before the owned test server was stopped.

Coverage across all shop placements was checked statically. Other rooms,
in-game furniture breakage, and restart behavior were not visually exercised.
This test establishes shader coverage and the observed room result; it is not
a pixel-exact comparison against a running PS2 original.
