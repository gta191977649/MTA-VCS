# VCS world markers

The `marker` resource provides server and client exports backed by ordinary MTA marker elements. It uses original US PS2 VCS geometry and textures; `frontend` owns presentation, and `skygfx` supplies material effects and VCS lighting. Add `<include resource="marker" />` to a calling resource's `meta.xml`.

```lua
local entrance = exports.marker:createMarker(x, y, z + 2, "arrow", 1.5)
-- Minimap blips are OFF by default. Opt in explicitly:
exports.marker:setMarkerBlipVisible(entrance, true)
exports.marker:setMarkerBlipVisible(entrance, false)

addEventHandler("onMarkerHit", entrance, function(player, matchingDimension)
    if matchingDimension and getElementType(player) == "player" then
        -- Enter the building here.
    end
end)
```

## Creation

Server:

```lua
marker createMarker(x, y, z, type="checkpoint", size=4,
    r=237, g=130, b=180, a=228, visibleTo=root, ignoreAlphaLimits=true)
```

Client:

```lua
marker createMarker(x, y, z, type="checkpoint", size=4,
    r=237, g=130, b=180, a=228, ignoreAlphaLimits=true)
```

Call these through `exports.marker`. Invalid arguments return `false`. Color channels must be integers in 0–255, size must be positive, and coordinates must be finite. The compatibility argument `ignoreAlphaLimits` accepts a boolean; all custom visuals honor the requested alpha, including arrows and checkpoints. VCS mission pink is the default color.

| API type | Original native type | Presentation |
| --- | --- | --- |
| `arrow` | 1 | Rotating down arrow, 1024 ms size pulse and vertical bob, proximity scaling |
| `arrow2` | 2 | Alternate down-arrow entry, size pulse and proximity scaling without vertical bob |
| `pointer` | 3 | Horizontal pointer arrow, constant-phase script-pointer preset |
| `cylinder` | 6 | Ground-snapped translucent cylinder, two counter-rotating layers at 1 and 0.93 scale, proximity alpha |
| `checkpoint` | 6 | Tall race cylinder, original height multiplier 100 and proximity alpha |
| `cylinder2` | 7 | Single cylinder with original 0.7-unit lift and vertical oscillation |
| `ring` | 8 | Original blurred hoop, optionally oriented toward a target |
| `corona` | Separate corona renderer | Camera-facing, occluded mission `coronaringa` sprite |

Numeric types `1`, `2`, `3`, `6`, `7`, and `8` are also accepted. `getMarkerTypes()` returns the eight names in API order. Size follows the MTA diameter convention; the original hoop mesh is normalized from its 4.6846-unit diameter. Other meshes retain their original proportions.

Attaching an `arrow` or `arrow2` directly to a vehicle, ped or player enables VCS entity-arrow placement. The renderer takes the visual size and vertical clearance from the target type. A seated ped's arrow follows the vehicle roof. The supplied marker size and attachment offset still position and size the backing trigger.

## Updating and removing markers

Use native MTA `setElementPosition`, `attachElements`, `setElementDimension`, `setElementInterior`, `setMarkerSize`, and `destroyElement`. The native element retains its collision behavior and server/client marker hit and leave events. Bobbing changes only the visual transform, keeping the trigger stationary. Native arrow placement and cylinder collision caveats still apply to the backing trigger.

Use these exports for visual properties:

| Export | Result |
| --- | --- |
| `getMarkerType(marker)` | Custom style name, or `false` |
| `setMarkerType(marker, type)` | Changes style and native collision type |
| `getMarkerColor(marker)` | Four color channels |
| `setMarkerColor(marker, r, g, b, a)` | Changes visual color and any enabled blip |
| `setMarkerTarget(marker, x, y, z)` | Orients arrows/hoops toward a world point |
| `setMarkerTarget(marker, false)` | Clears the target |
| `setMarkerAnimation(marker, options)` | Replaces animation overrides; `{}` restores defaults |
| `setMarkerBlipVisible(marker, boolean)` | Creates/removes an attached minimap blip; default `false` |
| `isMarkerBlipVisible(marker)` | Whether a blip is requested |
| `getMarkerBlip(marker)` | Blip element, or `false` |
| `setMarkerVisibleTo(marker, element, boolean)` | Server-only viewer visibility rule |
| `isMarkerVisibleTo(marker, player)` | Server-only effective viewer visibility |

Animation options are `period` (a power of two from 1 to 32768 milliseconds), `pulse` (0–1), `rotation` (degrees/second, −3600 to 3600), and `height` (positive vertical scale, at most 1000). Native types 7 and 8 do not pulse in size. A target replaces the free-spinning orientation, as in the original placement path.

Server-created markers must be changed on the server. Client setters operate on client-created markers. Blips follow the marker's position, color, dimension, interior, and viewer rules, and are destroyed when disabled or when their marker is destroyed. Creating a world marker never creates a minimap blip implicitly.

Visibility accepts a player, root, or an ancestor element; the nearest rule in the player's element ancestry wins. Use the exported visibility setter/query. Native visibility/color queries describe the transparent MTA trigger, whose alpha is deliberately zero. Calling native color or type setters can expose the backing SA visual; use the corresponding exports instead.

Markers are parented to the caller's dynamic element root and cleaned up when the caller stops. Late client starts receive a snapshot. Frontend restarts reload assets and active presentation state. Up to 32 nearest mesh markers and 32 nearest coronas are drawn per frame, with original mesh distance limits.

## Source and fidelity

See [the reverse-engineering evidence](../../../../../docs/vcs-markers.md) and `assets/manifest.json`. Rebuild assets with:

```powershell
py tools/import_vcs_markers.py "D:/ps2_game/Grand Theft Auto - Vice City Stories (USA)" "<path-to-vcsconv.exe>"
```

The original meshes, texture alpha, placement formulas, and timing constants are preserved. SkyGfx owns normal/additive blending, depth state, and the recovered ambient/directional color rules with its VCS timecycle and sun direction. Frontend applies those light values to the recovered mesh normals. This is a port of the original lighting rules onto MTA primitives, rather than PS2 hardware rendering. Native arrows 1/2 include their original star-corona overlays, using SkyGfx's original VCS raster. The mission corona uses the original sprite with world occlusion; the general-purpose corona lens-flare pipeline is outside this marker API. Collision shapes remain MTA's native shapes.
