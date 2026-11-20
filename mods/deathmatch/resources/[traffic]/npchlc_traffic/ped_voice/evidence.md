# Original pedestrian speech

The assets come from the USA PS2 release of Vice City Stories (SLUS-21590). The executable names bank 2 `SFX_BANK_PED_COMMENTS` in the bank-name table at 0x004B6588. Its index is `AUDIO/SET0/SFX2_PS.SDT`, with a 12-byte offset, length and sample-rate record for each entry in `SFX2_PS.RAW`. The preceding banks contain 292 and one sample respectively. Subtract 293 from a game sample ID to obtain its local index. File names use this local index with four decimal digits.

## From stimulus to voice

| Native event | Source and selection |
| --- | --- |
| Gun panic, 0x77 | The event-4 query at 0x0020C198 searches for a nearby shot. The threat branch at 0x001EFFB0 leads to the fleeing path, with 0x00210228 submitting speech. Generic male selector 0x001C2D08 requests 23 samples from 0xA38. Generic female selector 0x001C2DE0 requests 13 from 0x61A. These local ranges start at `2323.wav` and `1269.wav`, labelled MALE_PANIC_01 and FEMALE_PANIC_01 in the VAG headers. Some models have overrides. For example, 0x00158DE0 requests three samples starting at global ID 299, labelled GUNPANIC1 through GUNPANIC3. |
| Injury, 0x6A and 0x8A | The hitscan impact path at 0x002C7AC8 submits 0x6A on the hit ped. The generic male selector takes 51 samples from 0x9F0, the generic female selector 34 from 0x5ED. These start at local indices 2251 and 1224. Both events return the same ranges for every mapped non-player model. Fire and death use separate events and ranges. |
| Victim of carjacking, 0x7A | The victim paths at 0x00300B24 and 0x002FDDD8 submit this event. Many original model handlers select their own spoken reactions. Some models return the silent sentinel for this event. The catalog preserves those omissions. |
| Vehicle evade, 0x8D | Ordinary accepted reactions at 0x00209908 and 0x00209CD0 submit this event. The forced horn mode skips it. For example, model 23 selects bank-local 1861 or 1862, while model 9 has no evade voice. |
| Occupied vehicle collision, 0x8F | VehicleDamage at 0x00136C10 requests driver speech when both vehicles have drivers and calculated damage exceeds 5. Model 23 selects bank-local 1859 or 1860. Model 9 returns the silent sentinel. |

0x001C2448 first tries the per-model switch at 0x00157FC0, then evaluates its fallback cases. It passes the selected range and per-ped previous sample at offset 0x6BC into 0x001C87D8. The latter chooses a random offset modulo the range length. If it picks the previous clip, it advances one entry and wraps at the end. Original speech cooldown records begin at 0x00485AA8.

## Rebuilding

Run `python tools/ped_voice_import.py "<extracted disc directory>"` with Unicorn 2 available. The importer verifies the executable, compressed GAME.DTZ and both audio bank hashes. It reads the ped type from original model data and executes only the original model/event selection routine in a MIPS emulator with a synthetic ordinary, speech-eligible ped. It stops at the range picker or the silent return. The 20 counter residues cover the selector's 2-, 4- and 5-way alternate voice choices. The emitted Lua pools combine each model's possible clips for an event. The MTA host selects a shared playback variant from that pool.

The generated package covers 146 non-player models with at least one supported response, 95 with a carjacking response, 97 with an evade response and 122 with a driver collision response. Its 942 mono WAV files contain 101 original panic samples, 85 injury samples, 282 carjacking samples, 205 evade samples and 269 driver collision samples.
