# Parking height correction

The former fixed 1 m lift could leave a converted hull embedded in late-loaded
map collision. Placement now waits for the converted model and a local surface,
using wheel contacts where available and the model bounding-box base otherwise.
Surface queries stay near the authored Z to retain the intended floor. Land
vehicles never substitute sea level for missing road collision. Boats retain
buoyancy. Unused land vehicles stay anchored until entry or damage; occupied
vehicles are also released after warp/seat transfers. Respawn repeats placement
and retains the original interior/dimension. Pending hulls are hidden.

## Verification on 2026-11-25

A real MTA 1.7 client connected to an isolated loopback server with the VCS map,
model provider, vehicle controllers, ENEX and production placement resources.
Temporary QA scripts recorded client-ready, measurements and screenshot results.
Original screenshots were opened for visual review and retained under
`screens/placement-height-2026-11-25` with both logs.

- Huey and hospital helicopter: model base approximately 0.020 m above the
  sampled surface, with landing skids visible and no road penetration.
- Admiral: wheel-based placement; bounding-box base -0.018 m relative to the
  centre surface (the wheel supports, rather than that box, determine height).
- Mall BMX: remained below the map in dimension 3090; base-to-centre-surface
  difference approximately 0.038 m.
- Dinghy: water level 6.0 m, floating at origin Z approximately 5.766 m.
- Huey respawn: repeated the 0.020 m base clearance. A server seat transfer
  confirmed an occupied vehicle was released within the occupancy-check period.
- Lua checks covered all 186 active parking records, stale reports, height bounds,
  occupied-report rejection, respawn generations and water fallback restrictions.

These are representative live scenes, not a visual inspection of every parking
point. Normal manual entry controls and driving/audio were not acceptance-tested
in this height-focused run. The final land-versus-water fallback restriction was
checked with a Lua test; it did not alter the successful live scene branches.
