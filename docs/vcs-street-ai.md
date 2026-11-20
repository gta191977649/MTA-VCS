# Finding street NPC behavior in PS2 Vice City Stories

Use this index when working on `npchlc_traffic`. All virtual addresses refer to the US PS2 executable `SLUS_215.90`. Start with an observable question, such as “Which branch assigns the carjacker as the displaced driver's target?” Follow the actor, event and state writes. Look up a situation, original model and personality, objective, ped state, or occupation in the [NPC behavior handbook](vcs-npc-behavior.md).

## Source material

| Material | Local location or entry point | Verification |
| --- | --- | --- |
| PS2 code | `D:\ps2_game\Grand Theft Auto - Vice City Stories (USA)\SLUS_215.90`, open as `SLUS_215.90 (VCS)` in Ghidra | Use `Get-FileHash` to verify SHA-256 `3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547`. Pass virtual addresses directly to Ghidra MCP `inspect`. |
| Model, personality, population and animation indexes | `PS2/GAME.DTZ` on the same disc | Inflate with zlib and check the GATG header. Python importer offsets address the inflated image. Root slot 7 holds the model table. Model info +0x34 is ped type and +0x38 is personality ID. |
| Models, textures and external animation blocks | `GTA3PS2.IMG` | Read offsets and lengths from the streaming table in 2,048-byte sectors. The extractor checks disc hashes and converted RenderWare chunk types and lengths. |
| Story and ambient scripts | `MAIN.SCM` and the searchable local `MAIN.txt` | Find a command and its surrounding conditions in the disassembly, then confirm the bytes and the PS2 opcode handler. Both a mission and freeroam logic can trigger the same action. |
| Placed map objects | `mods/deathmatch/resources/[vcs]/vcs/zones` | Trace a definition's model name to its map position, orientation, interior, dimension and uniqueID. A model may have many placements. |
| Comparison projects | `D:\dev\VCSPC\VCS PC`, `D:\Game\vcs_pc_edition\data`, `D:\dev\gta-reversed\source\game_sa` | Cross-check model names, personality names, animations and layouts in VCSPC. The Events, Tasks and Attractors code in gta-reversed helps identify responsibilities. Verify branch conditions and constants on PS2. |

## Trace a behavior

1. **Carjacking.** Decompile 0x002FDCB0. Identify the ejected ped, carjacker, personality pointer and comparison direction. Follow the objective setter and check its target argument. On MTA, follow `onVehicleStartEnter`, `onVehicleExit` and `onVehicleEnter` in `traffic_road.lua` to `TrafficAmbient.adoptDriver`. Record attempt, exit and takeover separately and compare the same ped element across those events.
2. **Taking damage.** Start with damage at 0x001D7940 and reaction selection at 0x002201A0 and 0x00220458. Record both participants' types, personality fields, weapon conditions, active task and branch destination. MTA's server-side `onPedDamage` gives health loss. Establish attribution before selecting the reaction.
3. **Helping a teammate.** Follow 0x00220160 to 0x0030A520 for nearby followers selecting a target after an attack on the player. See 0x00307550 for propagation among gang members. For the distinctions between bystanders, followers and the port's sight reports, see [threat responses](vcs-npc-reactions.md). See the resource's `wanted-evidence.md` for crime types and wanted points.
4. **Population and gangs.** At 0x002B17A8, inspect the police threshold, nine cumulative gang thresholds and civilian branch. 0x002B45C8 requests a group of two or three, and 0x002B3B90 handles the type 11 singleton. Search `MAIN.txt` for `set_gang_ped_models` to check initial model pairs and subsequent script overrides. This resource uses initial freeroam settings.
5. **Beach.** The string `PED_SUNBATHE` at 0x004AB578 identifies a state label. At the end of 0x002B17A8 inspect surfaces 0x22/0x12, hours 10–18, rain, clearance and the preceding call to 0x002B4588. That function returns 0 in this build. Other entry points and map attractors require their own traces.
6. **Seating and jobs.** Trace the placed object, animation block and script assignment for the scene. Transform the model-local point and orientation to world coordinates. Observe approach side, alignment, occupation, interruption and release. A state or clip name establishes asset presence.
7. **Road passengers.** 0x00430290 creates the driver, then samples independently for each passenger place using a strict threshold of 0.125. Successful samples fill seats from the front. 0x00395868 derives capacity from PS2 model class, doors and handling flags. 0x003E6998 writes vehicle+0x235. Cars using the `van` animation block spawn at most one passenger. 0x003E91B0 skips the first passenger position for certain models. During carjacking, 0x003EF018 iterates passengers separately. Ordinary exit objectives start with 1,800 ms and add 300–599 ms per subsequent passenger. Another car-passenger branch uses 10,000 ms. The port caps capacity at the replacement vehicle's available seats. The current sync client requests native exit with `setPedExitVehicle`. On receipt of the exit event, the server transfers that ped to the walking AI. Post-exit passenger fleeing is an MTA adaptation. Story and externally created passengers have their own controlling resources.

For example, call `inspect(action="decompile", file_name="SLUS_215.90 (VCS)", address="0x002FDCB0")` and use `references_to` to find callers. For a label with no direct xrefs, trace the state dispatch and its writers. Distinguish ELF virtual addresses, ELF file offsets, inflated GAME.DTZ offsets and IMG sectors. Record the build, address, operand or data record, result and test scenario for each new rule.

## Resources and regeneration

Run these commands from the repository root. Normal startup uses the converted data shipped in the traffic resource. For skin regeneration, point `$converter` to the Win32 D3D9 build of vcsconv produced by `tools/build_vcs_model_converter.py`.

```powershell
$disc = 'D:/ps2_game/Grand Theft Auto - Vice City Stories (USA)'
$converter = Join-Path $env:TEMP 'vcs-model-build-tools/vcsconv-rebuilt-d3d9.exe'
py -B tools/ped_ai_profiles.py $disc --check
py -B tools/import_vcs_traffic.py $disc --street-peds $converter
py -B tools/ped_activity_import.py $disc
py -B tools/ped_voice_import.py $disc  # Requires Python Unicorn 2
py -B tools/ped_ai_check.py
py -B tools/ped_activity_check.py
py -B tools/ped_voice_check.py
py -B tools/check_vcs_traffic.py --disc $disc --vcs-pc-dir 'D:/Game/vcs_pc_edition' --native
py -B tools/check_vcs_wanted.py
```

Omit `--check` to rebuild personality data from the disc. Skins, textures and locomotion animations go in `npchlc_traffic/ped_models/`. The catalog uses original model IDs. Look up personality by that ID even when the base MTA skin or dynamically allocated client-side model ID differs.

To locate seats, follow the count and table pointer at inflated GAME.DTZ header offset 0x54, the model's effect span, the 64-byte type-3/subtype-1 record, its local coordinates and direction, then the placed map entity. Trace ambient scanning at 0x002D9210 to capacity at 0x00401338, approach checks at 0x00401458 and registration at 0x003FFDB0. Stone bench model 484 has effects 17/18 and park bench model 513 has effects 48/49. The generated catalog has 138 seats, four table work positions and 18 beach bounds. Use `rg --files --no-ignore` to inspect the resource and converted map. Use PowerShell `-LiteralPath` for paths containing `[traffic]` or `[vcs]`.

The original `emp` block supplies `emp_bar_clean`. Assigning it to an outdoor `chairsntable` is a port decision. Beach eligibility combines original zones and personalities with MTA surface probes and scheduling. The resource ships ten original clips and two beach-entry clips derived by reversing the original rising motion in `ped_activity/activities.ifp`. The converted models, profiles, sites and animations run independently of a local game installation.

## In-game regression

Use a dedicated test-server port and load the VCS map, npc_hlc and npchlc_traffic. Launch the MTA client. Preserve other users' active sessions.

Record location, time and weather, original model ID, participants, NPC element, adjacent events, selected response and recovery. With two observers, let the sync owner leave and verify that task, reservation and threat target still belong to the same actor. Record Lua simulation, native MTA server checks, MTA client runs and original PS2 observations separately.

| Scene | Recorded observation |
| --- | --- |
| PS2 carjacking | A PCSX2 fixture positioned the vehicle. Controller input triggered the carjacking. Driver model 35 changed from state 60 to 8, lost the vehicle pointer and retained 100 health. The player entered driving state 55. The driver moved over 20 m away in about four seconds. |
| MTA carjacking | Actual input transferred the driver's seat to the player. Comparing elements before and after entry showed the original driver alive and outside the vehicle. |
| Unarmed strike | In US PS2 VCS on PCSX2, model 26 took two hits, fell from 100 health to 91 then 82, and continued fighting in state 17. MTA model 23, STAT_SENSIBLE_GUY, fell from 100 to 98.68 and fled roughly 16 m in five seconds. These are two personality samples. |
| MTA stone bench | Two actors walked, turned and took separate slots on a bench at (353.88, −1085.52). Server phases were seat_down, seat_idle, seat_up and release. The four-second seating animation started after the sync client confirmed heading. The activity module performed no actor coordinate writes. |
| MTA table work | A ped approached the chairsntable at (298.93, 710.81), and the client played emp_bar_clean. |
| MTA beach | Near (642, −374), material 33 passed the sand probe and the ped lowered, lay down and sunbathed. Materials 43 and 9 failed nearby. The original PS2 game spawned beach pedestrians in the same area, although the field sample did not show a wandering ped choosing to lie down. |

[20-second bench recording](street-ai-evidence/mta-bench.webp) · [Two occupied seats](street-ai-evidence/mta-bench.jpg)

Fixtures select sites, place actors initially and hold the camera. Normal resource code handles walking, turning and animation thereafter. Carjacking and strikes use game input. Lua regression covers sync handoff, stale replies and catch-up for late observers. The in-game run used one MTA client. See the [activity evidence](../mods/deathmatch/resources/%5Btraffic%5D/npchlc_traffic/ped_activity/evidence.md) for bench bone movement, beach gating and work-site ownership.

## Gunfire and voice

Trace hearing, ped-type masks, near misses and personality branches in [gunfire perception](vcs-gunfire.md). Identify voice requests for driver exits, fleeing listeners and wounded actors in [PS2 voice call sites](vcs-voice-calls.md). Start voice identification at disc files `AUDIO/SET0/SFX2_PS.SDT` and `SFX2_PS.RAW`, replay the selector for the original model and voice event, then look up the bank-relative ID in `ped_voice/catalog.lua`. See [voice-bank extraction](../mods/deathmatch/resources/%5Btraffic%5D/npchlc_traffic/ped_voice/evidence.md).

Gunshots, panic shouts and injury cries have distinct ranges. PS2 0x001C21D8 processes ordinary ped speech when squared listener distance is below 1,600. 0x002A7120 preserves full volume for 8 m, then attenuates quadratically to 40 m. Building occlusion lowers the volume to 31/127. MTA selects one original model voice-bank variant on the server for nearby listeners. The port tracks the original same-class global interval per listener so distant groups can shout independently. Clients play spatialized mono audio at the actor.

A pistol fired near the bench made five pedestrians flee with 100 health. Both seated NPCs released their slots. Model 83 played panic variant 1280.wav, lasting 0.880 s on the client. Direct hits on model 72 produced client bullet-hit reports and server health changes of 100 → 91.75 → 83.50. The first hit produced injury variant 2279.wav. These checks used actual firing input on an MTA 1.7 background client and its sync server.

The hit recording captures Anode Remote Audio game output with leading and trailing silence removed. In this run, a bullet hit model 23. The server recorded damage and the client recorded the playback position and nonzero level for original injury variant 2277.wav. [Nearby gunshot and injury voice](street-ai-evidence/mta-gunfire.wav)

In the miss recording, model 82 fled the sound and played 2325.wav. After downmixing both recordings to mono and resampling the source material to 48 kHz, normalized cross-correlation peaks were 0.9962 for panic and 0.9956 for injury. A separate vehicle hit produced 25 bodywork damage on the client. The server confirmed damage to the same car, and its driver accelerated from cruise speed 12 to target speed 18. [Near-miss panic voice](street-ai-evidence/mta-gunfire-fear.wav)

For player-vehicle approach scans, personality and horn branches, evasion speech, animation import and reproduction, see [vehicle evasion](vcs-vehicle-evade.md). The client recording shows the dive, passing vehicle and get-up. [Evasion recording](street-ai-evidence/mta-vehicle-evade.webp)

For anger, fleeing and pursuit after a vehicle collision, see the [collision decision tree](vcs-vehicle-impact.md). For a displaced driver's escape, retaliation, recovery of the driver's seat and subsequent departure, see the [carjacking decision tree](vcs-carjack.md).
