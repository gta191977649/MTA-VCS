# Chunder Wheel

The shared outdoor Ferris wheel uses the original VCS carriage, collision,
seated animation and civilian population. `leeds_engine` starts this resource
after traffic and its model provider.

## Playing

Approach the pink entrance marker and wait for the wheel to stop. Walk through
the doorway of the lowest carriage. Movement remains normal while standing.

- **F:** take the nearest available seat, or stand up from an occupied seat.
- **E:** request an exit stop for the current carriage. The wheel brakes when
  that carriage next reaches the platform. Other players share its movement.
- Stand with **F** to regain free movement, then use normal jumping to leave
  through the carriage doorway. Falling is normal gameplay, including damage.
  Jump does not toggle seating and has no special ride binding.

At an exit stop, stand with F and walk onto the platform. There is no exit fade
or teleport. All required controls and waiting states use frontend textboxes.
F is consumed by the seating interaction: client and server vehicle-entry
events are cancelled while seated and during that key's short action window.
The same interactions are available as `sitferris` and `exitferris` commands.

Sitting and the per-player exit request are multiplayer adaptations. The
original script stops the wheel near the boarding area and lets the player
walk aboard; it does not sell tickets or assign the player a seat.

## Integration

Dependencies are `vcs`, `eagleLoader`, `frontend`, `marker` and
`npchlc_traffic`, including traffic's usual model and controller dependencies.
The map's existing outdoor hub and distant wheel are compatible object LODs.
The resource rotates that hub and creates exactly twelve carriage objects per
observing client. It restores the hub when inactive or stopped.

The server owns the phase, boarding visits, stop requests, NPC population and
seat reservations. Every seat is exclusive across NPCs and players. A sampled original bone pose is reapplied after GTA processes player peds so CJ visibly sits even when the native primary animation task reports a clip without displaying it. Observing
clients interpolate the shared fixed-step simulation. Native contact physics
carries standing players; no extra displacement or automatic recapture is
applied to someone who walks or jumps out.

`getFerrisWheelState()` is a read-only export on both sides. Common fields
include `angle`, `speed`, `phase`, `swing` and simulation `time`. Server results
also contain `active`, `riders`, `spectators` and seated `players`. Client
results expose `carriages`, `hub`, `lod`, `riding`, `seated`, `exitQueued`,
`exitReady`, `ready`, `npcCount` and `spectatorCount` for observation.

Death, respawning, damage, external displacement, vehicle occupancy, world
changes and disconnects release a player's seat. A departed rider's pending
stop is discarded. Resource/dependency shutdown releases borrowed spectators,
restores controls, collision and the prior frozen state and recovers remaining riders to the
entrance before their supporting objects disappear. That recovery applies to
shutdown only, not a normal exit or voluntary fall.

## Seated cinematic

Sitting starts a repeating 80-second, ten-shot sequence. Every shot includes
the player except the nine-second Vice Point reveal. Each path independently
animates horizontal viewing angle (yaw), vertical viewing angle (pitch) and
FOV, even when the wheel is stationary. Roll stays zero.

| Shot | Seconds | Emphasis and movement | FOV |
| --- | ---: | --- | --- |
| Seated introduction | 7 | Opposite interior seat, face and upper body; slide toward frontal framing and rise. | 64 to 56 |
| Vice Point reveal | 9 | Whole wheel, fairground, canal and buildings; lateral ascending dolly with a level horizon. | 74 to 68 |
| City lookout | 8 | Player's shoulder and city beyond; diagonal outward track and descent. | 62 to 54 |
| Neighboring riders | 8 | Player foreground and another occupied cabin; slide across the opening and rise. | 66 to 58 |
| Greeting | 8 | Player hands-up and NPC response in one continuous composition; opposite-side arc and descent. | 60 to 54 |
| Skyline and light | 8 | Player profile against available light; lateral rising track. | 58 to 64 |
| Height | 7 | Oblique view of the seated player and ground below; outward descending high track. | 60 to 70 |
| Waterfront | 8 | Lateral portrait with passing shoreline; counter-track and lower. | 56 to 50 |
| Wheel scale | 8 | Low three-quarter view, rider beneath rim and spokes; inward rising track. | 68 to 60 |
| Quiet farewell | 9 | Return attention to the rider; diagonal rising pullback from medium portrait to cabin. | 52 to 62 |

Position, aim and FOV use eased curves, with editorial cuts between shots.
Within a shot, the rendered lens follows its locked path with eased motion. Yaw and pitch use the shortest angular path,
limited to 42 and 28 degrees per second; FOV changes are limited to 8 degrees
per second, with cabin-relative lens movement limited to 3.5 metres per
second. These limits reset at intentional shot cuts. The selected full-shot
path stays unchanged until the next cut.
Scenic compositions balance viewing directions so distant scenery cannot pull
the player out of the letterbox. The greeting uses an opposite-side two-subject
path when both subjects have a clear full-shot view, and a player portrait
when the cabin geometry prevents that composition. The sheltered greeting
widens FOV from 100 to 90 degrees and reserves space above the head for the
raised hands, rather than cropping the gesture inside a close portrait.
The neighboring NPC is selected from up to eight ranked existing wheel riders
by full-shot visibility and retained through
the greeting. The server schedules the player's 1.2-second gesture and the
NPC's response on the shared wheel clock, limits requests to one per 45 seconds,
and validates the player's occupied seat and the NPC's other carriage on the
same wheel. Selection favors a clear view at a similar height over a closer
carriage hidden above the roof or below the floor.
The sampled original gesture blends with the seated pose while retaining each
player skin's native facial basis. No new pedestrians are created for these shots.
The sunlight composition reads SkyGfx's original sun direction and adapts to
the current weather and time without changing either.

The camera stays within 80 metres of the wheel. Collision probes check the
lens and player sight lines, including direct tests against the visible wheel
and cabin meshes. Framing checks retain the player's head inside the letterbox.
Exterior paths use the cabin's open side on the rider's side of the wheel
plane, avoiding the rotating spokes between the camera and player. Distinct
heights, distances, tracking directions and framing retain each shot's theme.
Before each shot, `camera_plan.lua` forecasts the shared wheel simulation,
including acceleration, braking and carriage swing. It checks 65 samples of
each candidate path against static scenery and the predicted wheel/cabin
meshes, with lens-clearance probes, swept lens segments, player framing and
subject sight lines. The neighboring rider must be visible during the middle
of the discovery shot and during the greeting response; the player remains
visible throughout. The next plan is prepared during the previous shot's
last two seconds. Predicted mesh queries transform rays back into each
object's current space; they never move live world elements.

One certified path is locked for the whole shot. The camera does not switch
angles in response to individual frame probes. If a scenic path cannot fit,
the planner tries a side view of both riders or a distinct sheltered cabin
path before the cut. The read-only state reports `planned`, `alternate`,
`emergency`, `motionBlocked` and shot `progress`. `planned=false` means no
candidate passed every probe. An unexpected obstruction holds lens movement
instead of cutting or wandering to another angle.

Menus pause the shot clock. Another script taking camera control temporarily
suspends this scene without overwriting the new camera; it resumes when the
camera follows the player again. Standing releases the camera before the
gameplay request. Jumping remains a native action after standing.

The loop continues for as long as the player stays seated, including at an
exit stop. When a requested carriage reaches the platform, an eight-second
arrival shot frames the seated player, open doorway and landing together.
It returns to the regular loop and repeats every 24 seconds while the player
remains seated at that stop. The shared textbox reminds them to press F again
to stand up from the seat. A requested stop with seated riders allows at least
12 seconds at the platform for the arrival shot and a normal exit. Player skins retain their native jaw animation and bind basis. Players use
the sampled body/greeting pose without running the VCS IFP task or writing its
jaw track. This applies to all SA player skins, including model changes while
seated and players first observed after boarding; it does not depend on a
cached CJ-only quaternion. Original VCS NPC riders keep their original IFP.

Presentation belongs to `frontend`: `setCinematicPresentation(boolean)` claims
or releases a resource-scoped cinematic mode. Multiple callers can overlap;
one caller releasing or stopping does not clear another caller's claim. This
mode hides the gameplay HUD, radar and chat, draws an animated 2.20:1
letterbox, and keeps the shared interaction help below its top edge. Stronger
gameplay UI hides and menus retain precedence. `getCinematicPresentation()`
returns read-only `active`, `aspect` and `inset` observations. The funfield
client state includes `cinematic` observations (`active`, `shot`, `elapsed`,
`fov`, `subject`, `neighbor`, `greeting`, `fallback`, `reason`). Neither export provides test controls.

Run `py -B tools/check_vcs_funfield_camera.py` for path, presentation ownership
and camera handoff regressions. `--stage-live` prepares a separate loopback
server with a temporary real-client probe that boards through normal gameplay
and captures the production camera without overriding it.

## Original sources

Source edition: US PS2 SLUS-21590 v1.00. Asset hashes are recorded in
`assets/manifest.json`.

| Source | Restored behavior |
| --- | --- |
| `00175620` | Twelve carriages, 23-unit radius, 0.05 rad/s cruise, acceleration, aligned braking and spring-damped swing. |
| `00176310`, `GAME.DTZ` root slot 15 + `0x132` | Hub model 5499 and carriage model 7069. |
| `001763E0`, `00176680` | Carriage creation inside 275 units and removal beyond 300 units. |
| `MAIN.txt`, `FERRIS` | Random civilian riders, up to 20 occupants, up to five borrowed spectators and 13â€“18-second watching periods. |
| `GLOBMON_633..803`, `00419BA8`, `00213738`, `00213FB8` | Four seat offsets, facing orientations 0/2 and full carriage-relative ped matrices. Attachment Z is used directly; adding a ground-coordinate origin correction makes riders float. |
| Animation group 0, associations 156/164 | `handsup` and `SEAT_idle`, converted to ANP3 with the existing VCS skeleton conversion. The hands-up variant retains the seated lower body. |
| `0041DA30` | Rider collision is enabled near the player or when observed through a sniper scope. |

Spectators use the production traffic ownership APIs and return to ambient
control when their viewing period ends. The implementation processes every
allocated rider rather than reproducing the original script's twelve-index
animation scan over its twenty-element rider array.

## Regeneration and checks

From the repository root:

```powershell
py -B tools/import_vcs_funfield.py 'D:/ps2_game/Grand Theft Auto - Vice City Stories (USA)' "$env:TEMP/vcs-model-build-tools/vcsconv-rebuilt-d3d9.exe"
py -B tools/check_vcs_funfield.py
py -B tools/check_vcs_funfield.py --stage-live
```

Asset regeneration also uses the sibling `mta_map_tools` collision converter;
override its location with `--map-tools`. The live fixture is created entirely
in an isolated temporary server. Its test-only controls are not part of this
production resource. Start that server hidden, wait for its ready log, connect
the real MTA client to its loopback port, and review the recorded measurements,
logs and original screenshots before accepting the run.
