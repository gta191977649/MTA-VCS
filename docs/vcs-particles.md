# VCS particles and fire

SkyGfx loads 90 particle definitions from the USA PS2 disc. Each 0x84-byte record in the inflated `PS2/GAME.DTZ` table at `0x3B3660` supplies a particle's initial size, lifetime, colour and simulation parameters. In `SLUS_215.90`, `001E81C8` binds rasters, `001E9040` and `001E9078` allocate particles, `001E9C90` advances the simulation and `001EAD88` draws them. SkyGfx shares the 750 slots across emitters and simulates at 30 steps per game second.

Screen-space particles use the same explicit alpha, soft-additive or additive blend states as world particles. Their shader keeps the screen-space vertex transform and disables depth testing. MTA's `dxSetBlendMode("add")` uses `ONE/INVSRCALPHA`, so it cannot replace the original `ONE/ONE` particle blend: the opaque black background of `raindrop4` would darken the scene into rectangles. Preserve the disc raster and select the screen material when drawing `RAINDROP_2D`.

Rain blending was checked on 2026-11-25 with a real MTA client on an isolated loopback server. A temporary resource held rain at 1.0 through the shared weather API and switched between the old and fixed screen draw paths. The old path reproduced dark rectangles; the fixed path retained visible streaks without the rectangles at 17:47 and 23:00. All three server-requested screenshots returned `ok`, and the client log contained no errors during the run. The disc importer check also passed for all 90 particle definitions and the unchanged atlas.

## Gameplay integration

- The fire resource owns script fires, damaged vehicles, wrecks, burning pedestrians and flame-weapon ignition. The server synchronizes active fires with clients. Each client simulates particles and plays positional fire sounds in its current dimension and interior. Firefighter missions attach a fire to the mission target and release it when their cannon or bucket conditions are met. Free-roam water cannon hits reduce the strength of nearby fires.
- Engine flames, smoke, wreck explosions and flamethrower shots use the VCS atlas. Fire and explosion lights feed the world and vehicle material passes before bloom. Those passes approximate illumination using distance to the nearest two submitted lights. Large sprites retain depth testing against the world, so a low explosion can visibly intersect the road.
- San Andreas can start secondary fires without reporting their positions to Lua. SkyGfx checks the vertex colour against the fire colour track for each native raster before layering the original `flame1` sprite. SkyGfx leaves `bullethitsmoke` under native rendering because sand spray and a secondary fire layer share that raster. The primary ground-fire billboard uses `wjet6`. The layers accumulate the `CARFLAME` colour at the base and taper to separate red tips. This approximates the overlap of newly emitted VCS particles using the host billboard's motion, lifetime and depth test. Near a managed emitter the shader suppresses overlapping native flames and tracks the four nearest active source clusters. Native-only fires retain host simulation and audio.
- Weapon fire, projectile trails, boat wakes, vehicle wheel and exhaust effects, swimming, footsteps, weather, breakable objects and placed map emitters feed the particle pool. The generated placement list contains eight tiki torches and one fountain. Script integrations include Pay 'n' Spray, Fire Copter bucket drops and concert flashes.

## Resource API and asset generation

Use `exports.skygfx:AreParticlesEnabled()` before choosing a fallback. On the client, call `exports.skygfx:AddParticle(id, x, y, z, vx, vy, vz, size, r, g, b, a, spin, angle, frame, life, visibility)`. The ID can be numeric or an original particle name. Arguments after position are optional. A false result can indicate a disabled pipeline, an invalid input, a camera-distance rejection or a full pool. For synchronized persistent fires use the server exports `StartScriptFire`, `ExtinguishPointWithWater` and `SetObjectHealth` from the fire resource.

From the repository root, pass the unpacked USA disc directory to each importer.

```powershell
python -B tools/import_vcs_particles.py "<disc>"
python -B tools/check_vcs_particles.py "<disc>"
python -B tools/import_vcs_particle_objects.py "<disc>"
python -B tools/import_vcs_fire_audio.py "<disc>"
```

The audio sample indices, gains, pitch and distance curves are documented in [VCS fire audio](vcs-fire-audio.md).

## Disc inventory

Each row is available through the SkyGfx particle API. The address is one recovered immediate-ID call instruction in the USA executable. A dash means the literal-call scan found none. Dynamic selectors, internal particle transitions, object data and script opcodes can also select a particle. The script column records literal particle IDs found in `MAIN.SCM` opcode `029F`. A definition or an original caller alone does not establish gameplay or visual parity for its mission.

| ID | Disc name | Example PS2 call | Script 029F |
| ---: | --- | --- | --- |
| 0 | `SPARK` | `002C3778` | Yes |
| 1 | `SPARK_SMALL` | `001369A4` | Yes |
| 2 | `WATER_SPARK` | — | — |
| 3 | `WHEEL_DIRT` | `00141B2C` | — |
| 4 | `SAND` | `00141E78` | — |
| 5 | `WHEEL_WATER` | — | — |
| 6 | `BLOOD` | `001D60AC` | — |
| 7 | `BLOOD_SMALL` | `00125E00` | — |
| 8 | `BLOOD_SPURT` | `001D60D4` | — |
| 9 | `DEBRIS` | `00291A18` | — |
| 10 | `DEBRIS2` | `00125EA0` | — |
| 11 | `FLYERS` | — | — |
| 12 | `WATER` | — | — |
| 13 | `FLAME` | `002296F4` | Yes |
| 14 | `FIREBALL` | — | — |
| 15 | `GUNFLASH` | `001515F4` | — |
| 16 | `GUNFLASH_NOANIM` | — | — |
| 17 | `GUNSMOKE` | — | — |
| 18 | `GUNSMOKE2` | `00151520` | — |
| 19 | `CIGARETTE_SMOKE` | — | Yes |
| 20 | `SMOKE` | `002CE90C` | Yes |
| 21 | `SMOKE_SLOWMOTION` | — | — |
| 22 | `DRY_ICE` | — | — |
| 23 | `TEARGAS` | `001814C0` | Yes |
| 24 | `GARAGEPAINT_SPRAY` | — | Yes |
| 25 | `SHARD` | — | — |
| 26 | `SPLASH` | `0022B7E4` | — |
| 27 | `CARFLAME` | `0013ED5C` | — |
| 28 | `STEAM` | `001EABB4` | Yes |
| 29 | `STEAM2` | — | — |
| 30 | `STEAM_NY` | — | — |
| 31 | `STEAM_NY_SLOWMOTION` | `00187618` | — |
| 32 | `GROUND_STEAM` | `003E44C0` | — |
| 33 | `ENGINE_STEAM` | `001413A0` | — |
| 34 | `RAINDROP` | — | — |
| 35 | `RAINDROP_SMALL` | — | — |
| 36 | `RAIN_SPLASH` | `0022B19C` | — |
| 37 | `RAIN_SPLASH_BIGGROW` | `001398A4` | — |
| 38 | `RAIN_SPLASHUP` | `00143D8C` | — |
| 39 | `WATERSPRAY` | `00141FA0` | — |
| 40 | `EXPLOSION_MEDIUM` | `00229BBC` | — |
| 41 | `EXPLOSION_LARGE` | `002E3324` | — |
| 42 | `EXPLOSION_MFAST` | `001EBF20` | — |
| 43 | `EXPLOSION_LFAST` | `002E1810` | — |
| 44 | `CAR_SPLASH` | `0014819C` | — |
| 45 | `BOAT_SPLASH` | `001543AC` | — |
| 46 | `BOAT_THRUSTJET` | — | — |
| 47 | `WATER_HYDRANT` | — | — |
| 48 | `WATER_CANNON` | — | — |
| 49 | `EXTINGUISH_STEAM` | — | — |
| 50 | `PED_SPLASH` | `00139DB4` | — |
| 51 | `PEDFOOT_DUST` | `001FA704` | — |
| 52 | `CAR_DUST` | — | — |
| 53 | `HELI_DUST` | `003EF884` | — |
| 54 | `HELI_ATTACK` | — | Yes |
| 55 | `ENGINE_SMOKE` | `0013CB08` | — |
| 56 | `ENGINE_SMOKE2` | `0013EE40` | — |
| 57 | `CARFLAME_SMOKE` | `0013EE08` | — |
| 58 | `FIREBALL_SMOKE` | `00229B20` | Yes |
| 59 | `PAINT_SMOKE` | — | — |
| 60 | `TREE_LEAVES` | — | — |
| 61 | `CARCOLLISION_DUST` | `00136A9C` | — |
| 62 | `CAR_DEBRIS` | `0012C844` | — |
| 63 | `BIRD_DEBRIS` | `002C5FB0` | — |
| 64 | `HELI_DEBRIS` | `0022D798` | — |
| 65 | `EXHAUST_FUMES` | `00144150` | — |
| 66 | `RUBBER_SMOKE` | `001FB95C` | — |
| 67 | `BURNINGRUBBER_SMOKE` | `0039A504` | — |
| 68 | `BULLETHIT_SMOKE` | `002C6274` | — |
| 69 | `GUNSHELL_FIRST` | `002C5C24` | — |
| 70 | `GUNSHELL` | `002C5C54` | — |
| 71 | `GUNSHELL_BUMP1` | `001EAA48` | — |
| 72 | `GUNSHELL_BUMP2` | `001EAACC` | — |
| 73 | `ROCKET_SMOKE` | — | — |
| 74 | `THROWN_FLAME` | `002C9DE4` | — |
| 75 | `SWIM_SPLASH` | `001F41E0` | — |
| 76 | `SWIM_WAKE` | — | — |
| 77 | `SWIM_WAKE2` | — | — |
| 78 | `HELI_WATER_DROP` | — | Yes |
| 79 | `BALLOON_EXP` | `00292178` | — |
| 80 | `AUDIENCE_FLASH` | — | Yes |
| 81 | `TEST` | `00125CE0` | — |
| 82 | `BIRD_FRONT` | `00270270` | — |
| 83 | `SHIP_SIDE` | `00270504` | — |
| 84 | `BEASTIE` | `003E5C68` | — |
| 85 | `RAINDROP_2D` | `003E4A34` | — |
| 86 | `FERRY_CHIM_SMOKE` | — | — |
| 87 | `MULTIPLAYER_HIT` | — | — |
| 88 | `HYDRANT_STEAM` | — | — |
| 89 | `FLOOR_HIT` | `002C61DC` | — |
