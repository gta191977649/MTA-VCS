# VCS fire audio

The US PS2 executable selects the following mono voices from bank 0. Sample numbers index the 12-byte offset, size and frequency records in `AUDIO/SET0/SFX0_PS.SDT`. The matching `.RAW` entries contain VAG headers and SPU ADPCM frames. Rebuild the eight WAVs with `python -B tools/import_vcs_fire_audio.py "<unpacked disc>"`. The importer checks both bank hashes and decodes each loop through its end marker, trimming the silent frame before the loop-start marker.

| Emitter | Bank index | Base rate (Hz) | Playback rate (Hz) | Radius | Level / 127 |
| --- | ---: | ---: | --- | ---: | ---: |
| Ground fire | 68 | 16794 | Base + slot × 65 | 80 | 80 |
| Building fire | 68 | 16794 | 13435 + slot × 52 | 80 | 100 |
| Ped on fire | 227 | 22041 | Base + slot × 86 | 25 | 60 |
| Water extinguishing a fire | 188 | 22050 | 23000 + slot × 89 | Inherited from fire | Low byte of 400 × water countdown |
| Damaged vehicle below 250 health | 68 | 16794 | Base | 30 | 60 |
| Flamethrower start | 155 | 28000 | Base ± 1749 | 60 | 85 |
| Flamethrower loop | 153 | 11025 | Base + (entity index × 10 modulo 2048) | 60 | 105 |
| Car explosion | 137 | 20000 | 19500 ± 999 | 200 | 127 |
| Grenade, rocket, barrel or tank explosion | 137 | 20000 | 19000 ± 999 | 200 | 127 |
| Helicopter explosion | 137 | 20000 | 0.8 × (19500 ± 999) | 200 | 127 |
| Mine explosion | 246 | 23000 | 12347 ± 999 | 200 | 127 |
| Molotov impact | 139 | 20000 | 19000 ± 999 | 150 | 127 |

The fire dispatcher at `001C3810` iterates 40 slots and queues the first audible burning fire. The vehicle damage dispatcher at `001BB760` selects a separate loop below 250 health. Weapon dispatch at `001BFBC0` selects the start event at `001C0734` and the loop at `001C0A04`. Explosion dispatch at `001C35A8` distinguishes the Molotov and car cases. SkyGfx uses the original pitch range with Lua's random generator. The optional caller-supplied slot supplies the per-emitter pitch variation.

The vehicle selector uses sample 220 from 250 to 389 health. Its decoded PCM contains only zeros. VCS explosion type 11 shares sample 246 with type 8. The MTA explosion types `3`, `11` and `12` have SA-specific meanings and retain native sound pending an established VCS counterpart. [MTA explosion types](https://wiki.multitheftauto.com/wiki/Explosion_types)

Distance calculation at `001B56C0` multiplies the vertical separation by 0.65. At `002A7120` the first fifth of the radius maintains full volume. Beyond that point, gain is the square of the remaining distance divided by the square of the remaining radius, truncated to the original integer volume. SkyGfx applies this gain to positional MTA sounds and leaves stereo panning to the client.

Release dispatch at `002A8218` subtracts at least one integer volume unit per audio update for an unrequested loop. Ground, ped and building fires request ten release frames, vehicle damage requests three, and the flamethrower requests six. The client advances that release at 30 Hz and cuts the tail when leaving its world or stopping its owner resource.

Client callers use `PlayFireSound(kind,x,y,z,interior,dimension,slot,ageMs)`, `MoveFireSound(id,x,y,z)`, `ReportWaterExtinguish(id,strength)` and `StopFireSound(id)` through `exports.skygfx`. A live fire can resume at its current loop phase after entering range. Each handle belongs to its calling resource. One-shots expire automatically. Water reports refresh the secondary voice for the same fire. The PS2 uses the loop labeled `SFXJUMBOTAXI` for this event. The client approximates its 20-frame release with a linear fade at the 30 Hz reference rate.

Native sound cancellation checks the bank slot, sample, listener world and proximity to a registered replacement. For the flamethrower it also checks the emitting ped's weapon. The native explosion's listener-relative stereo tail lacks a world-space origin. Its overlap and the relative loudness after the client mixer require listening in the connected game.
