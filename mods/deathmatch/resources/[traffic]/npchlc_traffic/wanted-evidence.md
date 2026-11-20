# PS2 wanted system evidence

USA PS2 `SLUS_215.90`, SHA-256 `3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547`. Addresses are virtual addresses in the Ghidra program `SLUS_215.90 (VCS)`.

| Behavior | Evidence |
| --- | --- |
| Score becomes 1–6 stars at 40, 180, 550, 1200, 2400 and 4800 points | `0x003AA918` compares against `0x28`, `0xB4`, `0x226`, `0x4B0`, `0x960` and `0x12C0`. Same branches write police ped and vehicle targets at wanted offsets `+0x19` and `+0x1A`, and the roadblock threshold at `+0x1C`. |
| Direct script changes use 0, 60, 200, 570, 1220, 2420 and 4820 points and clear the pending queue | `0x003AAB80` clears the queue at `0x003AB280` then assigns score from the switch. ELF data at `0x00489EE8` initializes the cap to six stars and 9600 points. `0x003AACE0` assigns different caps after an explicit story command. |
| Reported events contribute fixed points | `0x00279768` maps game event IDs to crime IDs. `0x003AB458` applies the amount, the per-player multiplier (default `1.0` in `0x003AA608`), the global reduction (default `0` in `0x0040CDF8`) and the optional report reduction `0.333`. The call then uses the larger of accumulated points and saved parole points. |
| Crime queue | `0x003AB2A8` scans 16 slots for matching crime ID and incident identity before inserting. `0x00279768` tests police presence at strictly less than 14 world units, with additional branches for scripted flags. `0x003AAB08` reports immediately when selected and passes zero in `t0` to `0x003AB2A8`, leaving queue processing eligible to report that record. `0x003AB388` applies queued reports after 500 ms and expires records after 10000 ms. `0x003AA760` gates this processing at an interval greater than 1000 ms. |
| Gunfire registers a zero-point crime | `0x002C3E48` emits event `4` with the shooter as incident identity and a 1000 ms repeat window. `0x002792C0` refreshes the expiry of an existing matching game event. `0x00279768` maps event `4` to crime `1`. `0x003AB458` skips the score addition for crime `1` and still compares the score against saved parole. MTA exposes only bullet-synced weapons through `onPlayerWeaponFire`. |
| Firearm strike on a pedestrian | `0x001D7940` calls `0x001D8B30` for the general damage report (civilian crime `2`, police crime `3`), and gun-hit paths `0x002C6460` and `0x002C7C28` additionally report crimes `4` and `5` respectively. For managed pedestrians, wanted.lua handles fatal incidents. ped_ai.lua correlates the client's attacker and weapon report with server-observed damage or synchronized health loss for nonfatal unarmed and firearm incidents. |
| Natural decay | `0x003AA760` subtracts one point after more than 1000 ms with fewer than two stars and no police presence. `0x003AAFB0` counts the listed original police models and police-classified vehicles strictly inside a three-dimensional radius of 18 world units. The foot and vehicle presence bridge queries server-managed police roles in the matching MTA dimension and interior. |
| Pay 'n' Spray suspends wanted points | `0x0041EA90` copies wanted points and stars to the saved fields, stamps the current time and zeros the live fields. `0x003AA760` drops the saved fields after 20000 ms. `0x003AB458` restores at least the saved score on a report during this window. The help branch `GAMHELP_2435` in `MAIN.SCM` describes the flashing stars. |
| Reset on respawn | Player reset at `0x0022F708` calls `0x003AA608` to reset the wanted fields and crime queue. |
| Police deployment requirements under normal flags | `0x003AADA0` requests undercover at 3+ stars. `0x003AADB0`, `0x003AADE8` and `0x003AAE20` test 4, 5 and 6 stars for SWAT, FBI and army respectively. `0x003AAE58` requests one police helicopter at 3–6 stars and checks override flags. The model requests and labels are in `0x003C90E8` and `0x004BDA28`. `0x0040A9E0` consumes the roadblock threshold. |

The multiplayer adapter uses the executable's defaults for unrestricted free roam. Story-specific caps, multiplier changes, overrides, or original mission scripts require the corresponding game-mode integration. The unit requirements describe dispatch policy. Scripts can send classified incidents through `reportWantedCrime`. MTA server `onPedDamage` reports health loss without attacker or cause and is insufficient for attributing original nonfatal assault crimes.

## Air support

- `0x002E9D00` requires an available POLMAV, normal open-world area and at least three stars. It schedules another spawn attempt after 15 seconds. Its retiring aircraft is removed outside 170 units.
- `0x002EA060` chooses an angle from the low random byte, spawns 250 units away, reverses the angle beyond the original XY bounds, and uses the greater of target altitude plus 50 or terrain plus 20. The ray at `0x00196778` scans from +1000 to −1000 and returns 20 on a miss.
- `0x003E90E8` calls `0x002B3CA0`, which assigns POLMAV's pilot to cop type 6, subtype 0. `0x002B2908` and `0x00324D08` resolve the subtype to original ped model 8. The verified POLMAV model is original ID 261.
- `0x00438420` dispatches pursuit and retreat to `0x0043C968` and `0x0043D8F8`. `0x0043CB10` calculates yaw, pitch, lateral input and collective using world rays and aircraft velocity. The shared Lua math covers the post-ray flight controls. The built-in syncer controller supplies ray samples and maps the control axes to MTA flight physics.

The built-in controller runs by default. An optional server resource can register itself with `registerTrafficPoliceProvider()` and implement `getPoliceTerrainHeight(x, y, player)` and `controlPoliceHelicopter(vehicle, pilot, target, retiring)`. The terrain function returns a height, true for a completed ray miss, or false when collision is unavailable. The control function returns true after assigning flight control. `getTrafficPoliceFlightIntent` and `getTrafficPoliceFlightControls` expose the verified math to the provider. Dispatch creates one authoritative aircraft and pilot pair per wanted target after matching VCS assets are bound. `getTrafficPoliceStatus()` reports active pairs and binding availability.

## MTA server API

Use `exports.wanted` for these calls. The traffic exports forward older callers to the same server authority. See the [full server and HUD interface](../../../../../docs/police-ai/resource-api.md).

- `getPlayerWanted(player)` reads the native level.
- `setPlayerWanted(player, level, reason)` applies a scripted level and returns success. `reason` defaults to `script`.
- `suspendPlayerWanted(player)` applies the original temporary respray suspension and updates the existing HUD's flashing stars.
- `reportWantedCrime(player, crimeType, incident, immediate, reduced)` submits a PS2 crime ID from the reporter's switch. The optional `incident` is an element or numeric identity. When `immediate` is omitted, the module uses nearby managed police. The optional `reduced` applies the original one-third multiplier.
- `onPlayerWanted(oldLevel, newLevel, reason)` is a local server event sourced by the affected player. An actual level transition through these exports emits it immediately. Native writes are observed once per 200 ms poll and have reason `native`.
