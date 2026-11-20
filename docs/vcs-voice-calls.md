# PS2 VCS street voice call sites

The addresses below are Ghidra virtual addresses in the US PS2 executable `SLUS_215.90`. World events, voice requests and bank-relative audio samples have separate numbering systems.

| Situation | PS2 call path |
| --- | --- |
| A pedestrian hears gunfire | Weapon logic at 0x002C3E48 registers world event 4 through 0x002792C0 for 1,000 ms. The ped query at 0x0020C198 calls 0x002796A0 to scan 64 event slots, selecting the nearest match at a 3D distance strictly below 60. It retrieves a shooter of entity type 1. Vehicle gunfire has a separate registration path using type 2. |
| A frightened pedestrian shouts | 0x001EFFB0 checks threat mask 0x100000, both ped types and the listener's conditions, then records the threat source. One interruption path at 0x00210110 accepts the threat, stores it at ped+0x55C and sets bit 0x80000 at +0x1D0. The branch at 0x00210228 calls 0x00205C20 on the target, entering PED_FLEE_ENTITY with a 10,000 ms limit and requesting voice 0x77. The actor's current activity gates this path. |
| A bullet hits a pedestrian | The entity-hit branch of 0x002C6460 requests voice 0x6A on the victim at 0x002C7AC8 and also emits impact sound event 0x3D. Several physical-impact branches at 0x001DA320 request voice 0x8A. Each voice has its own timing limits. |
| A driver is carjacked | The automobile branch at 0x00300B24 requests 0x7A on the ejected driver. 0x002FDDD8 also requests it on the original occupant of the driver's seat. |
| Two driven vehicles collide | Vehicle collision damage at 0x00136C10 requests driver voice 0x8F when both vehicles have drivers and computed damage exceeds 5. For example, model 23 selects bank 2 sample 1859 or 1860. Model 9 returns silence for this event. |
| Player gunfire damages traffic | Nonfatal vehicle health loss at 0x003E85BC calls 0x003EF910. An ordinary cruising car randomly accelerates or is abandoned. The first acceleration multiplies cruise speed by 1.5 and takes the integer result. The abandonment branch requests 0x77 on the driver and passengers, staggering passenger actions by 200 ms per seat. A driver of gang type 7–15 attacked by the player directs the vehicle's members to perform objective 8 on the attacker. MTA correlates sync-client vehicle-hit reports, actual server health loss and firing records for the same attacker. When a shot merely passes nearby, an ordinary driver in PED_DRIVING (0x37) fails the pedestrian threat gate before 0x002D9108. The predicate at 0x001FD9E0 requires state <0x29. |

## Arbitration when multiple actors speak

0x00174A90 accepts voice events 0x66–0x9F and retains the lower-numbered pending event. It checks the actor's last voice event and its time. 0x00174858 reads the pending event from ped+0x7B2 and checks the actor and global event-class playback times before submitting to the audio system. Actor elevation, global state and current animation can also gate playback. The executable's `SFX_BANK_PED_COMMENTS` string at 0x004B65B0 identifies bank 2.

The timing table at 0x00485AA8 contains 24 bytes per event. All times below are milliseconds. The original derives jitter from the high bits of a random sample multiplied by a range.

| Voice event | Delay before this actor can speak again | Minimum interval for this actor to repeat this class | Global interval for the class |
| --- | --- | --- | --- |
| 0x6A | 100 + [0, 1] | 100 + [0, 1] | 1000 |
| 0x77 | 1700 + [0, 999] | 3000 + [0, 999] | 3000 |
| 0x7A | 800 + [0, 399] | 2000 + [0, 999] | 2600 |
| 0x8A | 200 + [0, 199] | 200 + [0, 199] | 1000 |
| 0x8D | 1000 + [0, 499] | 3000 + [0, 999] | 3000 |
| 0x8E | 1000 + [0, 499] | 1000 + [0, 999] | 3000 |
| 0x8F | 3000 + [0, 1999] | 5000 + [0, 999] | 3000 |

After a quick drag-out, 0x00306520 can request 0x8E. The importer ran the original sample selector for every mapped non-player model in the resource. Each returned silence for that event.

To verify a selection, decompile its caller and timing checks in Ghidra. Inspect 0x001C2D08 and 0x001C2DE0 for default male and female voice selection. Model-specific selectors can override those defaults. Cross-check the selected model, voice event, global sample ID and bank-relative index when exporting audio.


## Rebuilding and checking positional voices

Open `SLUS_215.90 (VCS)` in Ghidra and follow `001C21D8 → 001C2448 → 00157FC0`. The selector reads the original pedestrian model at +0x56. At the fallback switch, model 8 (police) uses audio-manager field +0x30 modulo 5 and model 12 (paramedic) uses it modulo 2. Each branch has its own event table and may return silence. For generic pain the male and female selection routines pass different first samples and counts to 001C87D8. For gang dialogue, model 90 and model 91 start at bank-relative WAV 2201 and 0992 respectively. Some groups share pain recordings while having separate dialogue.

Run `python -B tools/ped_voice_import.py "<unpacked US disc>"`. It executes the selector with each model's GAME.DTZ ped type and all 20 counter residues, deduplicates periodic tables and converts bank 2 into the resource's mono WAV files. The MTA server picks one eligible variant for the speaker and retains it across events. This per-actor assignment substitutes for the PS2 audio-manager field. Inspect `ped_voice/catalog.lua` by original model, variant, then event.

On the client `ped_voice_c.lua` calls `playSound3D` once per utterance and attaches the sound to the speaker. The 40-unit radius and the 127/31 clear/obstructed levels come from 001C21D8. The near plateau and quadratic falloff come from 002A7120. MTA recalculates gain and building occlusion every 100 ms while the sound plays. Run `python -B tools/ped_voice_check.py` to check catalog coverage, role selection and moving source/listener gain.
