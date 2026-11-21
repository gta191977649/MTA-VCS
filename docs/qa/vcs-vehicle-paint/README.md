# PS2 vehicle paint verification

An isolated loopback server and one real MTA client ran with the VCS map, model resources and minimap enabled. A temporary Lua resource compared native MTA RGB values to values decoded independently from the US PS2 `GAME.DTZ`. Each screenshot is the original 960 × 600 client capture.

## Mission and parked vehicles

| Vehicle | Primary RGB | Secondary RGB | Live check |
| --- | --- | --- | --- |
| Downtown Fire Copter | 255, 255, 255 | 36, 57, 100 | The old build supplied 245, 245, 245 to both channels. The updated station helicopter showed the navy nose, cowling and tail while parked, after the pilot started Fire Copter, and after respawn. [Before](fire-copter-before.jpg) · [Parked](fire-copter-parked.jpg) · [Mission active](fire-copter-mission.jpg) |
| Downtown Air Ambulance | 255, 255, 255 | 176, 0, 0 | The parked and respawned helicopter retained its white body and red upper fuselage. [Hospital helipad](air-rescue-parked.jpg) |
| Beach Patrol BF Injection | 255, 25, 0 | 255, 25, 0 | The lifeguard station uses alternate variation zero. The parked vehicle and its respawn reproduced that pair. [Beach Patrol](beach-patrol-parked.jpg) |
| VCPD car | 54, 122, 73 | 188, 188, 180 | Both paint channels matched on the client and server before and after respawn. [VCPD parking lot](vcpd-parked.jpg) |

Before each respawn the fixture changed both channels to magenta to distinguish restoration from simply retaining the old RGB. Pay ’n’ Spray garage 916 charged $100 to repair a damaged Admiral. Its paired RGB values changed from (81, 84, 89) to (66, 31, 33), both authored Admiral variations.

## PS2 palette and material checks

The US PS2 model table contains 111 vehicle records, 552 factory paint pairs and 11 alternate pairs. Each pair may refer to the shared vehicle palette or to RGB entries in the model itself. The parked generator selects a normal or alternate pair. Turismo's 0150 instruction sets both channels directly from the shared palette. These paths produce different colors for the same numeric argument.

Mesh comparisons against the PS2 models identified lost or incorrectly assigned paint on the Hermes, Landstalker, Moonbeam, Yankee, Sabre Turbo and Mop50. The repaired faces retain their positions and winding. A clean rebuild from the loose model assets reproduced all five repaired archive meshes byte-for-byte and the same individual texture rasters. The legacy Mop50 loads its repaired loose assets directly.

## Model coverage

The factory and native-hull binding checks exercised each of the 103 vehicles in the converted catalog. Both creation paths selected legal PS2 paint for every model. Every bound hull then received scripted shared palette entries 23 and 42. All 103 returned (150, 145, 140) and (124, 38, 52), preserved those values across a second bind and reported successful binding. The client agreed with the server on all 206 factory and override readbacks.

The test also spawned 6WEELAT, SPEED2, IDAHO, MOPED, BOBO, CHOLO and GANGBUR through the legacy vehicle spawn event. All seven streamed on the real client, retained the legacy model identifier and matched one of their PS2 paint pairs on the server and client.

All 186 original parked generator rows matched separate live vehicles and their PS2 color selection. Thirteen ambient road vehicles also matched their own model's paint table. Entering the Escobar Turismo race produced three opponents with shared palette entries 0, 1 and 2 on both channels. Their RGB values were (15, 15, 15), (188, 188, 180) and (42, 119, 161).

Of the 206 converted-model client readings, 204 came from streamed native hulls. AIRTRAIN uses separate render objects. The client read its native hull's synchronized colors on both passes while that hull reported unstreamed. Three active AIRTRAIN traffic records used (5, 5, 5) on both channels. CHOPPER (279) has a PS2 paint record but no identified spawnable asset in this checkout.

## Taxi roof signs

The original Taxi fixture reproduced a bare roof with both extras disabled. After the fix, both original Taxi extras rendered a sign. The vehicle factory supplied one automatically, as did the freeroam command `/createvehicle 420`. The Cabbie kept its built-in sign. For both vehicles the driver started Taxi Driver at noon and at 23:00. The client and server agreed on the on-duty light, the nighttime captures showed its yellow glow, and cancellation restored the off-duty state. The VCS minimap and right-hand fare count are visible during dispatch.

| Vehicle | Before | Off duty by day | On duty at night |
| --- | --- | --- | --- |
| Taxi (226) | [Bare roof](taxi-before.jpg) | [Visible TAXI sign](taxi-off.jpg) | [Illuminated sign and fare objective](taxi-on.jpg) |
| Cabbie (183) | | [Built-in TAXI sign](cabbie-off.jpg) | [Illuminated sign](cabbie-on.jpg) |

## Two-tone material delivery

The connected client hashed the entire 27,969,536-byte vehicle archive while `vcs_model` was running. Its SHA-256 matched the staged resource and HTTP download, `24713ca5aaa2f54af8030f6c7b2eb05b9aeef9039fdf7829bd34d2cbf2751d6c`. An earlier same-endpoint reload had left the old archive open on the client. A fresh isolated loopback connection delivered the updated archive.

Changing the same Landstalker's first and second colors in place swapped both its painted body and the tint on its textured door panels. In the same 24 × 18 pixel panel area, mean RGB changed from (14.2, 14.2, 12.2) to (10.1, 2.4, 2.1). [Red body](landstalker-red-body.jpg) · [Red door trim](landstalker-red-trim.jpg)
