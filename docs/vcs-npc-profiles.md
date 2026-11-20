# Look up an NPC by model, personality or type

The US PS2 model record has class byte 7 for peds, ped type at +34h and personality ID at +38h. The 42 personality records below come from the pointer table at offset 4CC250h of the **decompressed** GAME.DTZ. Both tables list the complete set of matching original model IDs in decimal. A dash indicates a record with no associated model in this model table. Use the VCS model ID before conversion to an MTA skin.

## Personality by situation

F, T and L are fear (+16h), temper (+17h) and lawfulness (+18h). D is the float at +04h named fleeDistance by the importer. +19h is a signed value compared between actors in one social interaction. The carjack column tests only T > F. The civilian gunshot column takes the first satisfied test in order: F > L, then T > F, otherwise Other. Use that column only after confirming the listener's role and event path. Evasion shows flag 10h, which can select a step instead of a dive for a near miss or a hands-up response in the ordinary vehicle dive path. Flag 80h also matters when [held at gunpoint](vcs-npc-special.md).

| ID | Personality (STAT_ prefix) | D | +08h / +0Ch / +10h | F/T/L | +19h | Flags | Carjack | Civilian gunshot | Evasion bit | VCS model IDs |
|---:|---|---:|---|---|---:|---:|---|---|---|---|
| 0 | PLAYER | 0 | 15 / 3 / 0.4 | 50/50/50 | 50 | 0x06 | Skip | Other | Clear | 0, 15, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167 |
| 1 | COP | 20 | 7.5 / 1 / 1 | 10/30/100 | 50 | 0x02 | Pass | Temper | Clear | 8, 9, 10, 11, 115, 116, 117, 118, 119 |
| 2 | MEDIC | 20 | 7.5 / 0.8 / 1.4 | 70/30/60 | 40 | 0x80 | Skip | Fear | Clear | 12 |
| 3 | FIREMAN | 20 | 7.5 / 1.2 / 0.8 | 10/20/60 | 80 | 0x02 | Pass | Temper | Clear | 13, 72 |
| 4 | GANG1 | 17 | 7.5 / 1 / 1 | 20/65/10 | 40 | 0x06 | Pass | Fear | Clear | 91, 92 |
| 5 | GANG2 | 17 | 7.5 / 1 / 1 | 20/65/10 | 40 | 0x0E | Pass | Fear | Clear | 93, 94 |
| 6 | GANG3 | 17 | 7.5 / 1 / 1 | 20/65/10 | 40 | 0x06 | Pass | Fear | Clear | 95, 96 |
| 7 | GANG4 | 17 | 7.5 / 1 / 1 | 0/65/10 | 40 | 0x06 | Pass | Temper | Clear | 97, 98 |
| 8 | GANG5 | 20 | 7.5 / 1 / 1 | 20/65/90 | 40 | 0x12 | Pass | Temper | Set | 99, 100 |
| 9 | GANG6 | 17 | 7.5 / 1 / 1 | 20/65/10 | 40 | 0x06 | Pass | Fear | Clear | 101, 102, 144, 145 |
| 10 | GANG7 | 17 | 7.5 / 1 / 1 | 20/65/10 | 40 | 0x06 | Pass | Fear | Clear | 89, 90, 103, 104 |
| 11 | GANG8 | 17 | 7.5 / 1 / 1 | 20/65/10 | 40 | 0x06 | Pass | Fear | Clear | — |
| 12 | GANG9 | 17 | 7.5 / 1 / 1 | 20/65/10 | 40 | 0x06 | Pass | Fear | Clear | 107, 108 |
| 13 | STREET_GUY | 17 | 7.5 / 1 / 1 | 45/30/30 | 60 | 0x06 | Skip | Fear | Clear | 40, 53, 59 |
| 14 | SUIT_GUY | 17 | 7.5 / 0.8 / 1.2 | 35/60/60 | 30 | 0x82 | Pass | Temper | Clear | 22, 70, 105, 106 |
| 15 | SENSIBLE_GUY | 17 | 7.5 / 0.7 / 1.1 | 65/30/70 | 20 | 0x80 | Skip | Other | Clear | 14, 23, 34, 36, 49, 63 |
| 16 | GEEK_GUY | 17 | 7.5 / 0.5 / 1.7 | 56/10/40 | 5 | 0x81 | Skip | Fear | Clear | 18, 44, 58, 62, 74, 82 |
| 17 | OLD_GUY | 17 | 7.5 / 0.4 / 2.5 | 40/10/40 | 5 | 0x13 | Skip | Other | Set | 19, 78 |
| 18 | TOUGH_GUY | 17 | 7.5 / 1.1 / 1.5 | 30/70/50 | 60 | 0x82 | Pass | Temper | Clear | 26, 48, 68 |
| 19 | STREET_GIRL | 17 | 7.5 / 0.9 / 1 | 45/30/30 | 60 | 0x06 | Skip | Fear | Clear | 16, 56 |
| 20 | SUIT_GIRL | 17 | 7.5 / 0.6 / 1.6 | 30/60/60 | 30 | 0x82 | Pass | Temper | Clear | 28, 29, 69 |
| 21 | SENSIBLE_GIRL | 17 | 7.5 / 0.5 / 1.1 | 65/30/70 | 20 | 0x80 | Skip | Other | Clear | 30, 38, 57, 73, 81 |
| 22 | GEEK_GIRL | 17 | 7.5 / 0.4 / 1.9 | 80/10/40 | 5 | 0x81 | Skip | Fear | Clear | 20, 24, 42, 60 |
| 23 | OLD_GIRL | 17 | 7.5 / 0.3 / 3 | 80/10/40 | 5 | 0xD1 | Skip | Fear | Set | 21, 25, 39, 43, 66 |
| 24 | TOUGH_GIRL | 17 | 7.5 / 1.1 / 1.5 | 30/70/50 | 60 | 0x02 | Pass | Temper | Clear | 17, 71 |
| 25 | TRAMP_MALE | 17 | 7.5 / 0.9 / 1.6 | 60/50/20 | 10 | 0x12 | Skip | Fear | Set | 33, 52 |
| 26 | TRAMP_FEMALE | 17 | 7.5 / 0.9 / 1.6 | 30/30/20 | 10 | 0x12 | Skip | Fear | Set | 32 |
| 27 | TOURIST | 17 | 7.5 / 0.8 / 1.8 | 100/20/70 | 30 | 0x84 | Skip | Fear | Clear | 27, 47, 64, 87, 88 |
| 28 | PROSTITUTE | 17 | 7.5 / 0.7 / 1 | 40/20/40 | 100 | 0x02 | Skip | Other | Clear | 31, 50, 76 |
| 29 | CRIMINAL | 17 | 7.5 / 1.2 / 1.3 | 30/55/10 | 60 | 0x12 | Pass | Fear | Set | 37, 55, 79 |
| 30 | BUSKER | 17 | 7.5 / 1 / 1 | 49/20/40 | 90 | 0x11 | Skip | Fear | Set | 54 |
| 31 | TAXIDRIVER | 17 | 7.5 / 0.8 / 1.5 | 16/80/30 | 30 | 0x82 | Pass | Temper | Clear | 35, 80 |
| 32 | PSYCHO | 17 | 7.5 / 1 / 1 | 0/100/0 | 50 | 0x86 | Pass | Temper | Clear | 41, 75 |
| 33 | STEWARD | 17 | 7.5 / 0.7 / 1.1 | 40/30/70 | 20 | 0x80 | Skip | Other | Clear | — |
| 34 | SPORTSFAN | 17 | 7.5 / 0.7 / 1.1 | 40/50/70 | 20 | 0x8E | Pass | Temper | Clear | — |
| 35 | SHOPPER | 17 | 7.5 / 1.5 / 1.5 | 30/75/50 | 40 | 0xAA | Pass | Temper | Clear | 61 |
| 36 | OLDSHOPPER | 17 | 7.5 / 1 / 2.5 | 45/65/70 | 20 | 0x72 | Pass | Temper | Set | 51 |
| 37 | BEACH_GUY | 17 | 7.5 / 0.8 / 1.2 | 52/60/60 | 30 | 0x82 | Pass | Temper | Clear | 46, 65, 67 |
| 38 | BEACH_GIRL | 17 | 7.5 / 0.9 / 1 | 59/30/30 | 60 | 0x06 | Skip | Fear | Clear | 45, 77, 85, 86 |
| 39 | SKATER | 20 | 6 / 0.7 / 1 | 40/40/60 | 80 | 0xB1 | Skip | Other | Set | 83, 84 |
| 40 | STD_MISSION | 20 | 15 / 1 / 1 | 50/50/50 | 50 | 0x06 | Skip | Other | Clear | 109, 110, 111, 112, 113, 114, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 146, 147, 148, 149, 150, 151, 152, 153, 154 |
| 41 | COWARD | 17 | 7.5 / 0.7 / 1.1 | 65/30/70 | 20 | 0x80 | Skip | Other | Clear | — |

### Passing another pedestrian

00206CE8 reads the same fear and temper fields when steering around a nearby person. The global must be zero and 00204830 must return zero. The personality gate is **T ≤ F or T < 51**. TAXIDRIVER (T 80, F 16) skips this path, while TRAMP_FEMALE (30, 30) can proceed.

1. Require +81C < now, movement above 1, a first nearby ped whose state differs from 3Ah, and a candidate distinct from the associated entity returned by 00218990 and the current target. Intersect the actor's **type-record mask at +8** with the candidate's identity.
2. Center a horizontal circle 1.25 units ahead of the actor. If the candidate is within radius 1 inclusive and 001EF4C0 succeeds, turn the desired heading by π/4. Set +81C to now plus 500 and a stagger derived from actor seed and frame number. If bit 10h of +1C8 is clear, also look toward the candidate and sample a short hold time.
3. A separate interaction in 0020D7F0 permits type 4 when actionable or in state 37h and +6C8 < now. Select the first nearby actor passing 002FCE00 with 3D distance < 10, type 5, and a strictly higher signed +19h value. Look at that person, request speech 99h and wait 4000 ms before looking again. A scan with no match waits 10000 ms. Test equal +19h values, a difference of one, and distance exactly 10. This helper is also called while riding as a passenger in state 37h.

The float at +08h is read at 001F6B3C and 00210774. At 001D97C4 and 001D97DC a collision branch compares the two actors' +10h values. It takes the same side if the second value is ≤ 1.5 or the first is ≤ the second. The behavioral meaning of +0Ch remains unresolved.

The table lists disc defaults. 00237FF8 writes through the actor's personality pointer. It increments temper at values ≤ 51. Above 51 a zero second argument preserves the value; a nonzero argument increments 52–54 and resets values ≥ 55 to 46. Check the caller and whether the record is shared before modeling this as an individual actor's change.

## Initial type masks

Root slot 1Ah points to the type table. Identity is the externally visible type bit. Threats is the initial mask, which can change at runtime. The +08h mask applies to passing encounters. Look up the stored identity explicitly: several records have zero or a bit different from the type ID shifted left.

| Type | Identity | Threats | +08h passing mask | VCS model IDs |
|---:|---:|---:|---:|---|
| 0 | 0x1 | 0x0 | 0x0 | 0, 15, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167 |
| 1 | 0x2 | 0x0 | 0x0 | — |
| 2 | 0x4 | 0x0 | 0x0 | — |
| 3 | 0x8 | 0x0 | 0x0 | — |
| 4 | 0x10 | 0x2900000 | 0xCFFFF | 14, 18, 19, 22, 23, 26, 27, 33, 34, 35, 36, 37, 40, 41, 44, 46, 48, 49, 52, 53, 54, 58, 59, 62, 63, 65, 67, 68, 70, 72, 74, 75, 78, 80, 82, 84, 88, 105, 106, 109, 110, 111, 112, 113, 114, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 139, 142, 143, 146, 147, 148, 149, 150, 151, 152, 153, 154 |
| 5 | 0x20 | 0x2900000 | 0xCFFFF | 16, 17, 20, 21, 24, 25, 28, 29, 30, 32, 38, 39, 42, 43, 45, 47, 51, 56, 57, 60, 61, 64, 66, 69, 71, 73, 77, 81, 83, 85, 86, 87, 138, 140, 141 |
| 6 | 0x40 | 0x2900000 | 0xC70 | 8, 9, 10, 11, 115, 116, 117, 118, 119 |
| 7 | 0x80 | 0x900000 | 0x80 | 91, 92 |
| 8 | 0x100 | 0x900000 | 0x100 | 93, 94 |
| 9 | 0x200 | 0x900000 | 0x200 | 95, 96 |
| 10 | 0x400 | 0x900000 | 0x440 | 97, 98 |
| 11 | 0x800 | 0x900000 | 0x840 | 99, 100 |
| 12 | 0x1000 | 0x900000 | 0x1000 | 101, 102, 144, 145 |
| 13 | 0x2000 | 0x900000 | 0xA001 | 89, 90, 103, 104 |
| 14 | 0x4000 | 0x900000 | 0x4000 | — |
| 15 | 0x8000 | 0x900000 | 0xA001 | 107, 108 |
| 16 | 0x10000 | 0x800000 | 0x70 | 12 |
| 17 | 0x0 | 0x0 | 0x0 | 13 |
| 18 | 0x40000 | 0xB00040 | 0xFFC0 | 55, 79 |
| 19 | 0x0 | 0x0 | 0x0 | — |
| 20 | 0x20000 | 0x2900000 | 0xFFC0 | 31, 50, 76 |
| 21 | 0x80000 | 0x0 | 0x0 | — |
| 22 | 0x0 | 0x0 | 0x0 | — |

**Boundary test.** Hold all other carjack conditions fixed and compare TAXIDRIVER (80 > 16), TRAMP_FEMALE (30 = 30) and SENSIBLE_GUY (30 < 65). Only the first passes the temper check. For direct damage, compare the victim's fear with 100 minus the **attacker's** temper. Changing who struck the blow can change the victim's decision. For a gunshot, also fix both roles, current threat masks and distance. [Disc importer](../tools/ped_ai_profiles.py) · [Data reproduction and field tests](vcs-street-ai.md)
