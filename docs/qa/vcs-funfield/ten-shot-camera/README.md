# Ten-shot camera acceptance

Tested on 21 November 2026 using a real MTA 1.7 client connected to an isolated
loopback server on port 56666. Production scripts in the test copy match the
workspace. No Anode or production test controls were used.

## Resulting behavior

- Ten themed shots repeat every 80 seconds, with independently authored FOV,
  yaw and pitch movement. Intentional cuts remain between shots.
- Each shot locks one path before it begins. No per-frame alternative-angle
  selection remains. The next path is planned during the preceding shot.
- Forecasts use the production fixed-step simulation, including acceleration,
  aligned braking and carriage swing. Every candidate receives 65 pose/mesh
  samples, lens-clearance checks and swept lens checks.
- Player framing and sight lines remain required throughout scenic shots.
  Neighboring riders are checked during the discovery emphasis and reply.
  The greeting also reserves vertical space for the raised hands.
- Some wheel phases prevent a clear two-cabin view. Those phases deliberately
  use a planned sheltered composition; neighboring-rider visibility is not
  guaranteed at every phase. These paths are chosen at the cut, never as
  mid-shot jumps. SkyGfx time and weather remain unchanged by production code.

## Automated checks

`py -B tools/check_vcs_funfield_camera.py` passes:

- Path bounds and authored FOV/yaw/pitch variation at 20, 30, 60 and 144 FPS.
- Both seating directions, moving wheel heights, and head/upper-body framing
  at 4:3, 16:9 and 21:9. Sheltered greeting checks cover both lateral seat
  offsets and the top of the raised-hands envelope.
- Motion forecasts agree with production simulation for starting, running,
  stopping and stopped states, without mutating the input state.
- Whole-shot rejection of paths obstructed later in their course; selection
  among existing neighboring riders; locked path identity within a shot.
- Position, yaw, pitch and FOV rate limits through obstruction/recovery,
  plus camera ownership, menu pause, stand release and the arrival override.

## Gameplay evidence

Two complete daytime loops were followed by an E stop request, the arrival
composition, continued cinema while seated, F stand and a normal walk onto the
platform. Camera target, HUD, collision and movement controls were restored.
The daytime trace recorded no blocked lens movement or within-shot variant
changes; every selected active-camera path passed planning validation.

- [Interior introduction](wheel-cinema-clearance-day-0-seated-introduction-middle.jpg)
- [Vice Point reveal](wheel-cinema-clearance-day-0-vice-point-reveal-middle.jpg)
- [City foreground composition](wheel-cinema-clearance-day-1-city-lookout-middle.jpg)
- [Player gesture](wheel-cinema-clearance-day-0-greeting-player.jpg)
- [Skyline composition](wheel-cinema-clearance-day-0-skyline-light-middle.jpg)
- [Height composition](wheel-cinema-clearance-day-0-height-middle.jpg)
- [Waterfront composition](wheel-cinema-clearance-day-0-waterfront-middle.jpg)
- [Wheel scale composition](wheel-cinema-clearance-day-1-wheel-scale-middle.jpg)
- [Pullback composition](wheel-cinema-clearance-day-1-quiet-farewell-middle.jpg)
- [Platform arrival](wheel-cinema-exit-arrival.jpg)
- [Still seated at the platform](wheel-cinema-exit-still-seated.jpg)
- [Normal walk off with camera/HUD restored](wheel-cinema-exited-platform.jpg)

The daytime screenshots precede the final sheltered-greeting framing change.
Final-build lighting screenshots and measured frame-rate results are recorded
below. Screenshots are original 960 by 600 server captures, checked for the
originating resource, player, scene tag and successful capture status.

## Final lighting and motion checks

| Run | Active-camera trace samples | Uncertified paths | Blocked lens samples | In-shot variant changes |
| --- | ---: | ---: | ---: | ---: |
| Daytime loops and exit | 209 | 0 | 0 | 0 |
| Sunset | 123 | 0 | 0 | 0 |
| Final night build | 80 | 0 | 0 | 0 |
| Final VCS rain build | 83 | 0 | 0 | 0 |

The night and final rain runs each covered all ten shots. Per-frame probes
recorded 4,242 night frames and 4,392 rain frames. Maximum measured rates were:

| Run | Yaw (degrees/s) | Pitch (degrees/s) | FOV (degrees/s) | Cabin-relative lens (m/s) |
| --- | ---: | ---: | ---: | ---: |
| Night | 5.59 | 3.13 | 3.90 | 2.08 |
| Rain | 4.56 | 2.27 | 4.65 | 2.09 |

Rate measurements exclude deliberate cuts, ownership handoffs and the first
100 ms at either endpoint of a cut, since MTA applies the FOV component after
the matrix update. The early sunset probe did not filter these transients;
its FOV maximum is retained in the raw measurements but is not an acceptance
measurement. Unit checks additionally exercise obstruction and recovery at
20/30/60/144 FPS.

The first native-weather setup was rejected after visual review showed a
clear sky. The accepted rain run used `exports.skygfx:setVcsWeather(2)` in the
temporary probe and recorded VCS weather 2 with `getRainLevel() == 0.5`.
Original captures show rain particles, cloudy light and wet surfaces.

- [Sunset skyline](wheel-cinema-verified-sunset-0-skyline-light-middle.jpg)
- [Night wheel reveal](wheel-cinema-final-night-0-vice-point-reveal-middle.jpg)
- [Final sheltered greeting with raised hands visible](wheel-cinema-final-night-0-greeting-player.jpg)
- [Rain wheel reveal](wheel-cinema-vcs-rain-6-vice-point-reveal-middle.jpg)
- [Rain high-angle composition](wheel-cinema-vcs-rain-6-height-middle.jpg)
- [Rain sheltered composition](wheel-cinema-vcs-rain-6-neighboring-riders-middle.jpg)

[Measurements and production hashes](measurements.json) and
[sanitized camera traces](trace.jsonl) retain the observations without player
identifiers. [Automated check output](checks.txt) records the final command.
Current-session client/server logs contained no script errors from these
resources; the existing unrelated rotor deprecation warning remains.

Limits: sample validation forecasts the current shared simulation and scenery;
it is not a proof against arbitrary future server changes or dynamic objects.
Neighboring-cabin motifs may use a sheltered view when their sight lines fail.
Nighttime lighting and other occupants can obscure parts of the rider despite
a clear head sight line. No listening assessment was needed for this camera-only
change; audio behavior was unchanged.
