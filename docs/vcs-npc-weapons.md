# Ambient pedestrian weapons

In the USA PS2 release, the main script sets two weapon IDs for each gang. Population creation makes one independent draw per new gang member. The first and second entries each have a 50% chance. A zero entry produces an unarmed ped. Temper comes from the model's PEDSTATS record and has no part in the draw.

| Ped type | First weapon | Second weapon |
| --- | --- | --- |
| GANG1 | Beretta (19) | Unarmed (0) |
| GANG2 | Beretta (19) | Baseball bat (6) |
| GANG3 | Silenced Ingram (26) | Uzi (25) |
| GANG4 | M16 (28) | M16 (28) |
| GANG5 | Unarmed (0) | Beretta (19) |
| GANG6 | Beretta (19) | Uzi (25) |
| GANG7 | Beretta (19) | Baseball bat (6) |
| GANG8 | Golf club (3) | Golf club (3) |
| GANG9 | Silenced Ingram (26) | AK-47 (29) |

## Other groups

The same population factory creates ordinary civilians, criminals and prostitutes unarmed in normal play. EMERGENCY and FIREMAN use the emergency constructor at `0x00408F90`, which grants no weapon. The armed-ped cheat is a separate branch. The traffic resource keeps these groups' default inventories when a confrontation begins.

Police use a subtype loadout. Patrol and motorcycle officers carry a baton and pistol and initially select fists. SWAT and armed undercover officers select a compact SMG, and FBI and army officers select the MPLNG. The PS2 constructor at `0x00324D08` requests 1,000 rounds for its weapon grants. [Police equipment and model mapping](vcs-npc-services.md)

## Population and inventory

The nine consecutive `0157` commands start at file offset `0xF6EA` in the US `MAIN.SCM`. Gang index zero corresponds to ped type 7. The native script handler calls `0x003659F8`, which stores the pair at `0x006F3CB8` and `0x006F3CBC` with a gang-record stride of `0x1C`.

The San Andreas comparison is `CPopulation::AddPed` in gta-reversed's `source/game_sa/Population.cpp`. It also selects weapons from the gang record, but uses a different probability. The values below come from VCS.

In Ghidra, the population function at `0x002B2908` sends ped types 7â€“15 through the gang branch. It scales the random value to a number from 0 to 99 and selects the first weapon below 50. At `0x002B2E10` and `0x002B2E28` it reads the corresponding gang entry. It requests the chosen weapon with ammunition argument `0x61A9` (25,001). The grant helper at `0x001FFE68` queues the weapon until its model is available. Slot selection uses the weapon-info field at +68h and the setter at `0x00200168`. For fresh gang members with a firearm this supplies the selected gun and its ammunition.

The street population path at `0x002B4680` calls that constructor separately for individuals in the formation. The driver's seat path at `0x003E911C` and passenger path at `0x003E9270` both call the occupant constructor at `0x002B3CA0`, which reaches the same grant. Afterward it removes the visible weapon model from the seated ped. The inventory and selected weapon slot survive the handoff. A change of seat or a transition to combat therefore preserves the original draw.

The constructor takes the population's requested ped type independently of the model's PEDSTATS. Golfers 105 and 106 have a CIVMALE model default. A GANG8 territory spawn gives either golfer a club while a civilian spawn keeps its empty inventory.

The occupant factory checks service vehicles first. For other cars, it scans the nine vehicle IDs installed by the preceding `0156` commands in MAIN.SCM, in order: 267, 265, 269, 209, 174, 231, 171, 184 and 171. The first match wins, so model 171 carries a GANG7 crew. Each seat gets its own gang model and loadout draw. A missing gang ped model falls back to street model 14.

In MTA, the Beretta uses weapon 22, the bat 5, the golf club 2, the M16 31 and the AK-47 30. The Uzi and silenced Ingram share the native Micro Uzi, weapon 28. The server returns the original VCS ID alongside the host weapon ID so decisions can use the original weapon-info record. The correspondence was checked through the PS2 weapon-info model ID at +60h and the model-name hash in GAME.DTZ. [Server weapon selection](../mods/deathmatch/resources/%5Btraffic%5D/npchlc_traffic/ped_weapons.lua)

## Rampage overrides

The Rampage script changes the pair used for new population members in particular mission branches. Its initialization and teardown have different effects on the resulting loadouts.

| MAIN.SCM offset | Ped type | Temporary pair in VCS IDs |
| --- | --- | --- |
| `0x35BC6` | GANG6 | 6, 19 |
| `0x35C3D` | GANG3 | 6, 19 |
| `0x35CE8` | GANG2 | 6, 19 |
| `0x35D25` | GANG2 | 19, 25 |
| `0x35DEA` | GANG2 | 0, 0 |
| `0x35FD1` | GANG3 | 0, 0 |

At `0x36863` the script restores all nine freeroam pairs. Ambient MTA population uses those freeroam defaults. Explicit mission-specific inventory remains the responsibility of its owning script.
