# State and objective dispatch in the PS2 executable

Look up the field first. In a carjacking, *objective* 08h directs the original driver to attack a target. *Ped state* 08h updates flight from a position. The numbers below come directly from the two US PS2 jump tables. Sample writers are direct JAL calls whose delay slot loads a literal ID into a1, limited to three examples per row. A dash leaves open other setters, register arguments, inline writes and script commands.

## Ped state on each frame

In the common update 001F4BF0, one path calls objective executor 003BC9A8, then reads ped+8C4 at 001F8A88. It indexes table 004AB870 with unsigned state minus one if the index is below 44h. 001F8FB4 rejoins common processing. Other code, including animation callbacks, can advance states that share this exit. The names are search hints paired by order with the contiguous debug strings starting at 004AB328. The call column lists distinct direct calls in decompiler text order. Individual paths execute subsets of these calls.

| State (hex) | Debug label | Frame destination | Example calls to 00219340 | Direct calls in the case |
|---:|---|---|---|---|
| 00 | PED_NONE | Outside table | — | — |
| 01 | PED_IDLE | 001F8E1C | 00102058, 001D0898, 001EE7D4 | 00201FD0 |
| 02 | PED_LOOK_ENTITY | 001F8E2C | 00203A38 | 00203E30 |
| 03 | PED_LOOK_HEADING | 001F8E2C | — | 00203E30 |
| 04 | PED_WANDER_RANGE | 001F8FB4 | — | — |
| 05 | PED_WANDER_PATH | 001F8E7C | 003930A4 | 00206878 |
| 06 | PED_SEEK_POSITION | 001F8FB4 | 00203FD8 | — |
| 07 | PED_SEEK_ENTITY | 001F8FB4 | — | — |
| 08 | PED_FLEE_POSITION | 001F8D18 | 00205B30 | 00218A98 → 00205DF8 |
| 09 | PED_FLEE_ENTITY | 001F8C90 | 00205CD0 | 00218A48 → 00201EF0 → 00205DF8 |
| 0A | PED_PURSUE | 001F8FB4 | — | — |
| 0B | PED_FOLLOW_PATH | 001F8E8C | 00207B74, 00209760 | 002097E8 |
| 0C | PED_SNIPER_MODE | 001F8FB4 | 00213924, 002360CC | — |
| 0D | PED_ROCKETLAUNCHER_MODE | 001F8FB4 | — | — |
| 0E | PED_DUMMY | 001F8FB4 | — | — |
| 0F | PED_PAUSE | 001F8E6C | — | 002021B8 |
| 10 | PED_ATTACK | 001F8D4C | 001D0CE8, 001D0D98, 001D13A0 | 001D26C8 |
| 11 | PED_FIGHT_NEW | 001F8D5C | 001D4370, 001D4484, 001D6468 | 001F4A60 → 001D5878 → 002201A0 |
| 12 | PED_FACE_PHONE | 001F8FB4 | — | — |
| 13 | PED_MAKE_PHONECALL | 001F8FB4 | 002D8F48 | — |
| 14 | PED_CHAT | 001F8DFC | 0020AAF0 | 0020AB58 |
| 15 | PED_MUG | 001F8FB4 | — | — |
| 16 | PED_AIMGUN | 001F8D98 | 001D03A0, 0023592C | 002FCE00 → 0021FB38 → 001D06A0 |
| 17 | PED_AI_CONTROL | 001F8FB4 | — | — |
| 18 | PED_SEEK_CAR | 001F8C80 | 00182808, 0020B538 | 0020B558 |
| 19 | PED_SEEK_BOAT_POSITION | 001F8B6C | 0030A7B0 | 0030A7D0 |
| 1A | PED_FOLLOW_ROUTE | 001F8FB4 | — | — |
| 1B | PED_CPR | 001F8FB4 | 00409A80 | — |
| 1C | PED_SOLICIT | 001F8FB4 | 00210A54 | — |
| 1D | PED_BUY_ICE_CREAM | 001F8E9C | 00210D3C | 00210D58 |
| 1E | PED_INVESTIGATE_EVENT | 001F8EAC | — | 001D6F20 |
| 1F | PED_EVADE_STEP | 001F8FB4 | 00209CA4, 0020A12C | — |
| 20 | PED_ON_FIRE | 001F8ECC | 002BDAD0, 002BEFC4 | 0020C310 → 002190C0 → 00206568 → 0020ED50 → 002BE8D0 → 00218A48 → 00218A98 → 00205DF8 |
| 21 | PED_SUNBATHE | 001F8FB4 | — | — |
| 22 | PED_FLASH | 001F8FB4 | — | — |
| 23 | PED_JOG | 001F8FB4 | — | — |
| 24 | PED_ANSWER_MOBILE | 001F8EBC | 0020B114 | 0020B280 |
| 25 | PED_HANG_OUT | 001F8FB4 | 002B2860, 002B286C, 002B5240 | — |
| 26 | PED_TAXI_PASSENGER | 001F8FB4 | — | — |
| 27 | PED_BACKOFF | 001F8B4C | — | 002044E0 → 002045B0 |
| 28 | PED_STATES_NO_AI | 001F8FB4 | — | — |
| 29 | PED_ABSEIL_FROM_HELI | 001F8FB4 | — | — |
| 2A | PED_SIT | 001F8FB4 | — | — |
| 2B | PED_JUMP | 001F8FB4 | 002124C0 | — |
| 2C | PED_LEDGE_JUMP | 001F8E0C | 00211EF8 | 00212030 |
| 2D | PED_FALL | 001F8E3C | 00202374 | 00202808 |
| 2E | PED_GETUP | 001F8B3C | 00203384 | 00203240 |
| 2F | PED_STAGGER | 001F8FB4 | — | — |
| 30 | PED_EVADE_DIVE | 001F8FB4 | 0020A158 | — |
| 31 | PED_STATES_CAN_SHOOT | 001F8FB4 | — | — |
| 32 | PED_PASSENGER_AIM | 001F8D98 | 001D0340, 001D2CCC, 0023132C | 002FCE00 → 0021FB38 → 001D06A0 |
| 33 | PED_PASSENGER | 001F8FB4 | 001FF874, 0020BE0C, 00213364 | — |
| 34 | PED_ENTER_TRAIN | 001F8FB4 | — | — |
| 35 | PED_EXIT_TRAIN | 001F8FB4 | — | — |
| 36 | PED_ARREST_PLAYER | 001F8FB4 | 0032767C | — |
| 37 | PED_DRIVING | 001F8B7C | 001FF26C, 001FF6A8, 001FF840 | 003021C0 → 00219CB8 → 00219340 → 001DD4B0 → 0020D7F0 → 0020D9B8 → 0020C310 → 0024A430 → 003BB670 |
| 38 | PED_OPEN_DOOR | 001F8FB4 | — | — |
| 39 | PED_DIE | 001F8FB4 | 0020A700 | — |
| 3A | PED_DEAD | 001F8FB4 | 0020A920, 0021087C | — |
| 3B | PED_CARJACK | 001F8FB4 | — | — |
| 3C | PED_DRAGGED_FROM_CAR | 001F8FB4 | 003009D8 | — |
| 3D | PED_ENTER_CAR | 001F8FB4 | 00301AD0 | — |
| 3E | PED_STEAL_CAR | 001F8FB4 | — | — |
| 3F | PED_EXIT_CAR | 001F8FB4 | 00303124 | — |
| 40 | PED_HANDS_UP | 001F8AB4 | — | 002159A8 → 00215928 → 00174A90 → 00214A90 |
| 41 | PED_ARRESTED | 001F8FB4 | 002FD928, 0032757C, 0032760C | — |
| 42 | PED_DEPLOY_STINGER | 001F8FB4 | 0039DF88 | — |
| 43 | PED_FOLLOW_ANIM | 001F8E5C | — | 00300B88 |
| 44 | PED_DROWN | 001F8E4C | 00202294 | 002026F0 |
| 45 | PED_ERROR | Outside table | 001FED80, 00201DE0, 00302370 | — |
| 46 | PED_HOLDING_STATE | Outside table | — | — |

### Examples from the state table

| Input | Update, guards and exit |
| --- | --- |
| 14h, chatting | 0020AB58 reads the partner at +6B4. An invalid reference or entity class ends the chat via 0020ADA8. If the partner has left chat, set a 30 s deadline. A partner attacking or fleeing a third person can trigger a response to that person. Otherwise participant flags govern speech 9Ch, gestures and turn-taking. A nonzero, strictly expired deadline ends the conversation. [Social interruptions](vcs-npc-reactions.md) |
| 24h, answering a mobile | 0020B280 requires 001FD9E0. With animation 9Fh present, time ≥ 0.35 and +304 empty, call 001FFB20 with 14Ah. Without 9Fh, when A0h crosses 0.5, call 001FFC90, restore via +68C and write 30h there. If all three animations are absent, start A1h. Test two consecutive samples after 0.5 to check that the restore happens only on crossing. |
| 37h, in a vehicle | 001F8B7C checks the vehicle reference. If absent, IDs 11h/12h get a call to 003021C0 before clearing occupancy and switching to state 0. If the actor occupies the driver's seat, call 001DD4B0 and recheck the car reference. Other occupants run 0020D7F0 and 0020D9B8. Another guarded branch can assign objective 32h against the player. [Vehicle decisions](vcs-npc-vehicles.md) |
| 40h, hands up | 001F8AB4 selects animation 9Dh when personality flag 80h is set, otherwise 9Ch. Request animation and speech only when the chosen animation is absent. The flag-set path passes an extra argument of 1500 to its speech helper. Gun threats also use a separate [wait slot](vcs-npc-special.md). |
| 44h, drowning | 002026F0 uses bit 40 of ped+E8, death state and animation 98h to start, reinforce or fade animation 8Eh. It then submits damage to 001D7940 with magnitude three times DAT_004CD110, null source and damage type 2Eh. Vary frame time and presence of 8Eh when testing the action and damage request. Water entry is handled upstream. |

## Objective on each frame

003BCC34 in 003BC9A8 reads ped+8A4 and indexes 004BD620 for unsigned IDs below 37h. Larger values jump to 003C0F78. Several IDs share an entry and can diverge later. “Common tail” describes what this dispatch does with the ID. The notes identify the first useful decision for tracing a branch.

| ID (hex) | Case VA | Behavior to trace | Example calls to entity setter 003BB670 |
|---:|---|---|---|
| 00 | 003C0F78 | Common tail. | — |
| 01 | 003BCF48 | When not driving, call 00201EF0 and check the activity point and deadline. | — |
| 02 | 003BCFB0 | Choose a wander direction without a target. Otherwise branch on the target's type. | — |
| 03 | 003BD514 | Check the timer and vehicle occupancy. May request an exit. | — |
| 04 | 003BE394 | Calculate displacement to the destination. Can turn toward the target entity. | — |
| 05 | 003C0F78 | Common tail. | — |
| 06 | 003BCF30 | Check occupancy and enter a waiting or driving path. | — |
| 07 | 003BD6A8 | Request driving state 37h. | — |
| 08 | 003BFAE8 | Leave the vehicle if necessary. On foot dispatch to the melee or ranged executor. | 0010BC38, 0011C2A8, 001823E0 |
| 09 | 003BF1CC | Validate the target and vehicle occupancy. Some paths join 08h. | 0010BCD0, 00326778, 003BFE00 |
| 0A | 003BE158 | Check vehicle occupancy and driving state. On foot handle the entity target. | 00120FC0, 0020FCB4, 0020FDBC |
| 0B | 003BE158 | Shares entry with 0Ah. | 0010BD68, 003BFED4 |
| 0C | 003BFEF8 | Clear the request if the target is missing. Select an approach radius by ID and distance. | 0010BE00, 0011C2D8, 00182530 |
| 0D | 003BFEF8 | Shares entry with 0Ch. | 0010C590 |
| 0E | 003BFEF8 | Shares entry with 0Ch. | — |
| 0F | 003C023C | Clear a missing target. Otherwise evaluate separation from the leader. | 0010C380, 002B49BC, 002B5C3C |
| 10 | 003BDE94 | Check vehicle exit conditions and deadline. | 0010BE98, 00247F2C, 0024DB40 |
| 11 | 003BD764 | Defer while fighting. Otherwise check passenger capacity of the target vehicle. | 0010BF28, 00182340, 002483B4 |
| 12 | 003BD9BC | Process driver entry based on the vehicle and actor state. | 0010BFB8, 001F18EC, 003064D8 |
| 13 | 003C0F78 | Common tail. | — |
| 14 | 003C0F78 | Common tail. | — |
| 15 | 003BCC5C | Test the target at +820 and the current attack state. | 0010C048 |
| 16 | 003C03D8 | Check the target vehicle, weapon and range. | 0010C0D8, 002DA89C |
| 17 | 003BE59C | Check occupancy before using the horizontal displacement to the destination. | — |
| 18 | 003BEF54 | Handle vehicle occupancy or the distance to the destination. | — |
| 19 | 003BEF54 | Shares entry with 18h. | — |
| 1A | 003C0F78 | Common tail. | — |
| 1B | 003C0F78 | Common tail. | — |
| 1C | 003BE260 | Face the target, register its reference and advance according to range. | — |
| 1D | 003C0F78 | Common tail. | 00414D3C |
| 1E | 003BD6BC | Test arrival. Otherwise call 00203E90 on the destination. | — |
| 1F | 003BD5D4 | Restore objective and state if the vehicle is missing. Otherwise check time and state. | 00239354 |
| 20 | 003BCECC | Check animation 0Fh and deadline. Request speech 88h and animation on expiry. | — |
| 21 | 003C0960 | Search nearby entities when there is no target car. | — |
| 22 | 003BD5AC | Call 0020B460 when the vehicle exists and current state allows it. | — |
| 23 | 003BCC84 | On foot check the clock and nearby entities. | — |
| 24 | 003BCC84 | Shares entry with 23h. | — |
| 25 | 003C0B6C | Check target existence, health and occupancy. Clean up a lost target. | 001F1A40 |
| 26 | 003BE054 | Check the delay, vehicle occupancy and reference. | 001D8928, 0025AFE4, 003BC83C |
| 27 | 003BE80C | Check the activity deadline. Handle approach, occupancy and action. | — |
| 28 | 003BE80C | Shares entry with 27h. | — |
| 29 | 003BDE48 | After exiting, a valid vehicle target can trigger 6000 ms of flight. | 0010C500 |
| 2A | 003C0F78 | Common tail. | — |
| 2B | 003BE80C | Shares entry with 27h. | — |
| 2C | 003BE80C | Shares entry with 27h. | — |
| 2D | 003BE80C | Shares entry with 27h. | — |
| 2E | 003C0AE4 | Clean up a missing target. Otherwise test flags and call 001D0198. | 0010C628 |
| 2F | 003C0F3C | Check occupancy after the deadline. Clean up on foot. | — |
| 30 | 003BD054 | Check the activity point and the global scalar against 0.2. | — |
| 31 | 003BEF54 | Shares entry with 18h. | — |
| 32 | 003BFBE4 | If riding in the same vehicle as the target, one path uses the common tail. | 001F8C70 |
| 33 | 003BD65C | Hold while the target is valid and the deadline has not passed. | — |
| 34 | 003BD200 | Search nearby grid cells when there is an activity point. | — |
| 35 | 003BE80C | Shares entry with 27h. | — |
| 36 | 003BD090 | Resolve the activity point and check its state. | — |

For objective 08h, inspect 003BFAE8 for the target and weapon. For state 08h, follow 001F8D18 to the position used by the flight update. Where the table provides only a debug name or an entry guard, use the setter and completion path to establish whether ambient actors reach it.
