# Wanted score, crime reporting and dispatch

In the US PS2 executable, the player owns a wanted object at player +0x900. The player update calls its periodic tick at `0x0023087C`. A score change can take effect earlier through a crime report or direct setter. The score determines the star count, the pursuit budgets and a roadblock threshold. Individual dispatchers then decide whether an actual unit can enter the world.

## The six response levels

All scores and thresholds below are decimal. Range endpoints are inclusive. The ranges assume the initial six-star, 9600-point cap and ordinary unit flags. The **road roll** column gives the promotion of a normal traffic-generation attempt to a police vehicle at `0x00430464–0x00430520`, after the shared traffic, officer, vehicle and area gates. Ambient and scripted vehicles have their own entry points.

| Stars | Live score | Direct-set score | Officer limit | Vehicle limit | Roadblock threshold | Road roll | Additional eligible units |
|---:|---:|---:|---:|---:|---:|---|---|
| 0 | 0–39 | 0 | 0 | 0 | 0 | Inactive | None |
| 1 | 40–179 | 60 | 2 | 1 | 0 | Inactive | Ordinary officers can pursue |
| 2 | 180–549 | 200 | 3 | 2 | 0 | Low 16 RNG bits modulo 31 must be 16–30 | Dedicated road response |
| 3 | 550–1199 | 570 | 4 | 3 | 12 | Pass | Vice, one helicopter, roadblocks, targeted foot population |
| 4 | 1200–2399 | 1220 | 6 | 3 | 18 | Pass | Vice, one helicopter, roadblocks, SWAT |
| 5 | 2400–4799 | 2420 | 8 | 4 | 24 | Pass | Vice, one helicopter, roadblocks, FBI |
| 6 | 4800–9600 | 4820 | 10 | 4 | 30 | Pass | Vice, one helicopter, roadblocks, army |

The same targeted foot population path remains eligible at levels 4–6. The SWAT, FBI and army predicates each test **equality** with their level. Vice tests `stars > 2`. At five stars, the FBI condition becomes true and the ordinary four-star SWAT condition becomes false. Existing entities follow their own update and removal rules.

**Evidence.** `0x003AA918` clamps the score to the global point ceiling, then compares it to 4800, 2400, 1200, 550, 180 and 40 in that order. Each branch writes the complete response row. Instructions `0x003AAAB8–0x003AAAC8` stamp the level-change time only when the resulting star count differs. `0x003AAB80` supplies the direct-set scores. `0x003AADA0–0x003AAEA8` implement the five unit queries.

## Wanted state and ways to change it

| Wanted offset | Meaning and consumers |
|---|---|
| +0x00, +0x04 | Live score and saved respray score. Crime resolution at `0x003AB458` takes the larger of the newly accumulated live score and saved score. |
| +0x08, +0x0C, +0x10 | Tick gate timestamp, last star transition timestamp and respray suspension timestamp. Clock source `0x004CD104` is in milliseconds. |
| +0x14 | Floating-point crime multiplier. `0x003AA608` initializes it to 1.0. Script handler `0x002D3880` writes its argument. |
| +0x18, +0x19, +0x1A | Registered pursuing officer count, officer limit and traffic duty vehicle limit. Duty vehicles share the counter at `0x0048A970`, including the Predator through `0x003EA0E0`. The ten officer pointers start at +0x330. |
| +0x1C, +0x1E | Unsigned 16-bit roadblock threshold, then a flag byte. Byte masks 0x01 and 0x02 suppress the helicopter request. Masks 0x04, 0x08 and 0x10 independently force the SWAT, FBI and army predicates. |
| +0x20, +0x24 | Live and saved stars. The initializer clears both. |
| +0x30 | Sixteen crime records of 0x30 bytes each. Each holds the type, incident identity, registration time, position, processed flag and reduced-weight flag. |

- **Direct set.** `0x003AAB80` bounds the requested level by the global maximum, empties the pending queue, writes the corresponding seed score and recomputes the row. Script handlers `0x002D2A90` and `0x002D2C48` call it through the player wrapper `0x002379C0` with the supplied level and zero respectively. The bribe pickup branch at `0x001E1FA8` (model table +0xA6, call at `0x001E2110`) sets the level to `max(0, currentStars - 1)`. Picking one up at three stars therefore seeds 200 points even when the previous score was 1199.
- **Raise minimum.** `0x003AAC80` first restores the saved star level through the direct setter when it exceeds live stars. It then applies the direct setter if the resulting live level is below the requested minimum. A call already at or above both floors keeps the current score and queue. Script handler `0x002D2AF8` and the event reporter both reach this path through `0x002379E0`. The MIPS load of the saved level into the argument register is at `0x003AAC98`.
- **Story cap.** The image at `0x00489EE8` contains little-endian words 6 and 9600. Script handler `0x002D3138` calls `0x003AACE0`, which writes maximum level and point ceiling as a pair. For levels 0 through 6 the respective ceilings are **0, 110, 365, 875, 1800, 3600, 7200**. Explicitly setting cap six therefore changes the initial ceiling. The cap setter writes globals. The next score recomputation clamps the live score. A separate helper at `0x003AAC38` sets both cap and live level immediately.
- **Low-level decay.** In `0x003AA760`, elapsed time must be strictly greater than 1000 ms. Under two stars, a zero-result presence query within 18 units subtracts one point, floors it at zero, advances +0x08 and recomputes the row. With police present the decay branch leaves +0x08 in place, allowing subsequent updates to retry. At two or more stars the tick advances +0x08 without subtracting. The queue and officer roster maintenance run after this branch whenever the gate was open. A single delayed tick subtracts at most one point.
- **Presence.** `0x003AAFB0` tests strict three-dimensional distance from the player or current player vehicle, selected by `0x0024A150`. It counts occupied pool entries with ped model 8, 9, 10, 11, 117, 118 or 119. It also counts vehicles marked by bit 40 of the 64-bit flags at vehicle +0x260 or matching model 261, 219, 207 or 234. The vehicle loop excludes the player's current vehicle and status codes 4 and 5. The ped loop has no health or line-of-sight test.
- **Respray.** On a successful garage transition with live stars, `0x0041EA90` saves the current score and stars, records the time, zeros the live score and stars, and releases the pursuing officers via `0x003AAED8`. It performs direct field writes here. `0x003AA760` clears the saved values when `savedTime + 20000 < now`. At the equality boundary they are still eligible. A report while they are present can restore the saved score even if the report itself adds zero. A minimum-level request can instead restore the saved star level with its direct-set seed.
- **Player reset.** New player construction reaches `0x003AA608` at `0x0022F920`. Player recovery routines `0x0024CF50` and `0x0024D350` call `0x003AA730` at `0x0024D0A4` and `0x0024D458`. This releases officers and reinitializes the wanted object, including pending crimes, score multiplier, overrides and saved score.

## From a crime event to stars

**Game event registration.** `0x002792C0` first searches a separate 64-entry world-event list. Event type, entity class and entity pool reference form its key. A repeat refreshes the expiry and returns. A new event reaches the wanted translator only when its responsible entity is the active player. Even if the world-event list has no free slot, this attribution check still runs for an unseen key. Gunfire at `0x002C3E48` registers event 4 with a 1000 ms repeat window. Repeated shots can therefore extend one world event before the wanted object's own queue sees another report.

**Event translation.** `0x00279768` maps world events to crime IDs. All IDs and base points in the table are decimal. For paired ped cases, the victim's type at +0x550 selects the second result when it equals 6 (police).

| Crime | World event | Base points | Trigger and PS2 evidence |
|---|---|---|---|
| 1 | 4 | 0 | Gunfire, including player-ped and player-driven-vehicle paths in `0x002C3E48`. |
| 2 / 3 | 1 / 3 | 5 / 45 | Ordinary damage to a pedestrian / officer. The general reporter at `0x001D8B30` checks the attacker against the active player and diverts five damage IDs into crimes 18/19. |
| 4 / 5 | 11 / 12 | 30 / 80 | Projectile hit on a pedestrian / officer. Impact branches at `0x002C6EB0–0x002C6EE0` and `0x002C8810–0x002C882C` emit the corresponding ped event. |
| 6 | 8 | 15 | Vehicle taking. The entry path at `0x001FEDC8` tests the player, vehicle classification, creation byte and bit 58 at vehicle +0x260 before the event at `0x001FFA28`. It sets that bit afterward. |
| 7 | 2 | 10 | Translator case confirmed. No event-2 producer identified among the direct world-event registration calls in this ELF. |
| 8 / 9 | Direct | 5 / 10 | After an officer's evasive reaction to a vehicle driven by the player, `0x00209CD0` reports **both** crimes at `0x0020A208` and `0x0020A230`, using that officer as the incident identity. Both reports share the same branch. [Vehicle evasion](../vcs-vehicle-evade.md) |
| 10 / 11 | 9 / 10 | 18 / 80 | Vehicle impact on an ordinary pedestrian / officer. The collision routine `0x001DA320` tests the contacting vehicle and its driver, then reports at `0x001DAEC0` / `0x001DAEA8` before applying damage. |
| 12 | — | 400 | Score-switch case present. No producer found in the direct report paths below. |
| 13 / 14 / 15 | 14 / 15 / 16 | 20 / 80 / 20 | Setting a pedestrian, officer or vehicle on fire. The fire allocator `0x002BD7C8` selects events by entity type and ped type, then submits the non-null fire source at `0x002BDB84`. |
| 16 | Direct | 500 | Projectile type 0x12's update at `0x00181734` can reach the special target check `0x0022F4B8`. It skips model 0x118, requires signed model ID −962 (0xFC3E), a clear target byte +0x3C0, and squared distance <25. It sets the byte, timestamps the target with the frame counter, and submits the crime at `0x0022F618`. The model's normal gameplay availability remains unverified. |
| 17 | 13 | 25 | Vehicle explosion/destruction event. The player-controlled Rhino contact branch at `0x00151A30` reports against the struck vehicle. The explosion manager at `0x002E1924` also issues the vehicle event with its source. |
| 18 / 19 | 17 / 18 | 35 / 100 | Special damage to a pedestrian / officer. `0x001D8B30` selects these events when the player inflicted damage with ID 5, 9, 10, 11 or 53. |

**Scope of crime 12.** Ghidra references and a direct MIPS jump/call scan of the ELF text identify two entry paths to the score switch at `0x003AB458` (immediate report and queue processing), two callers of the queue inserter and one caller of the deferred wrapper. The direct submitters outside the event translator supply 8, 9 and 16. The translator has no crime-12 result. This supports including the numeric weight while leaving its gameplay trigger unassigned.

An unmatched event translates to zero and skips reporting. For ordinary assault, the early branch also consumes a flagged victim at zero stars if `0x0020C348` succeeds. It clears bit 42 at victim +0x1C8 and returns, awarding 50 through the player-info field only when the victim is outside states 0x39/0x3A.

**Report timing and star floors.** A matching police presence within 14 units makes the report immediate. With no presence, a nonzero `0x00489F84` also makes crimes 4, 5, 14 and 15 immediate. The remaining events enter the deferred path. Each immediate translated event calls the minimum-level helper with one star after reporting. Event 3 then requests at least one star and events 12 and 18 request at least two, regardless of immediate versus deferred selection. MIPS call sites are `0x002799B0`, `0x002799F8` and `0x00279A20`. Thus witnessed gunfire can produce a first star despite its zero base weight. A deferred zero-weight gunfire report alone, absent saved score, leaves the player at zero.

**Queue.** `0x003AB2A8` matches on both crime ID and incident identity. A matching processed record returns one. An unprocessed match returns zero. A new entry uses the first empty slot. The full queue also returns zero, with no insertion. Deferred reporting at `0x003AAAD8` just attempts insertion. The immediate path at `0x003AAB08` attempts insertion with the processed flag clear, then scores whenever insertion returned zero. An unprocessed immediate entry can therefore score again at a later tick if a direct setter has not cleared the queue. Full queues drop new deferred reports but still allow new immediate scores. Queue processing at `0x003AB388` scores once at `start + 500 < now`, marks the entry and expires its ID at `start + 10000 < now`. On a late first visit it scores before expiring.

**Score arithmetic.** `0x003AB458` starts with the player's multiplier, applies an additional ×0.3 when `0x004CD4CA == 1`, multiplies by `1 - min(globalReduction,100) × 0.01`, and applies ×0.333 when the report's reduced flag is set. `0x0040D4A8` reads the percentage from `0x004CD688`. The addition to the live score uses floating-point multiplication followed by integer truncation. Resolution then takes the maximum of that score and the saved score, forwards the crime/position to `0x002FA6A8`, and recomputes the wanted row. Crime 1 skips the addition and still performs these last steps.

## From eligibility to a unit in the world

**Land vehicles.** `0x00430290` first applies shared traffic limits. Its targeted police branch at `0x00430464` requires at least two stars, global area/mode `0x00489F7C == 0`, a police vehicle count below the vehicle limit, and a registered officer count below the officer limit. `0x003EA0E0` adjusts the vehicle count at `0x0048A970` when the duty flag changes. At level two the RNG gate in the table also applies. A failed gate continues into the normal traffic selection branch. It does not remove a patrol already in the world. A successful gate reaches vehicle selection at `0x00430520` and still needs placement.

**Targeted foot population.** `0x002B17A8` enables the targeted ped branch above two stars. In ordinary mode it compares the count of type-6 peds (`0x004CD514`, maintained by `0x002B4210`) with the officer limit. In nonzero area/mode it compares against the integer part of 1.6 times that limit. In the ordinary branch, the player must also be outside the vehicle-associated states tested by `0x00219D50`, and at least one of the police-vehicle, density or total-vehicle ceilings must have been reached. In mode zero, `(rng & 31) == 0` with a current player vehicle enables a special draw that bypasses both comparisons. The targeted selection bypasses the normal pedestrian density veto, requests a candidate within scaled placement bounds of 35 and 60, and selects type 6. The subtype helper at `0x002B3590` advances the RNG and returns zero. A successful special draw writes +0x92C = 1 on a newly created type-6 ped. See [officer behavior](officer-behavior.md) for its separate update path. Ordinary placement can also select a police ped through the zone's population weight.

**Specialists and air support.** `0x003C90E8` consumes the wanted queries to request models. Its strings at `0x004BDA28` identify PoliceBike/BikeCop (191/119), Enforcer/Swat (234/9), FbiCar/FbiPed (193/10), Rhino/Barracks/ArmyPed (246/218/11), PoliceHeli (261) and Vice (117/118). At three or more stars it requests the Vice car (204) and requests the two Vice peds when `0x0048800C == 0` and the index at `0x0048A9AC` is 0–3. The streaming routine itself returns early for area states selected by the unsigned expression `(uint)(word[0x004CD444] - 1) < 2`. The helicopter query gives zero when either low flag bit at wanted +0x1E is set. Script handlers `0x002D3178` and `0x002D37D0` independently toggle those bits. Details of model availability, selection priority, crew and flight are in [vehicle and special response](vehicle-and-special-response.md).

**Roadblocks.** `0x0040A9E0` processes a slice of the road-node list each frame. Crossing within a horizontal distance strictly below 160 sets the node latch. An attempt requires a newly set latch, a current player vehicle, and `(rng & 0x64) < threshold` at `0x0040ABA8–0x0040ABC8`. Leaving the radius resets the latch. The masked values are 0, 4, 32, 36, 64, 68, 96 and 100. The four nonzero thresholds **all accept exactly 0 and 4**. Treating 12/18/24/30 as percentages would change the level comparison. A second pending-segment branch in the same routine consumes a slot when its midpoint is strictly within 170 in three dimensions and calls `0x0040B348` independently of this roll.

## Boundary checks

| Starting state and event | Expected PS2 branch outcome |
|---|---|
| Fresh player fires, presence at 13.9 units, report proceeds | Immediate zero-point crime followed by the one-star floor. The setter seeds 60 and clears the queue. Without another report, 21 qualifying one-point decay steps reach 39 and clear the star. |
| Score reaches 180, 550, 1200, 2400 or 4800 exactly | Enter the next row immediately. One point below each value remains in the preceding row. At 1200 and 4800 the vehicle limit stays the same as in the preceding row. |
| Score 180 with no police within 18 | The timed gate advances. Two stars suppress one-point decay. |
| Two stars, two duty vehicles, zero enrolled officers | Vehicle count equals its limit. The targeted traffic branch falls through before checking RNG. |
| At four stars, a free road node produces RNG mask 32 | The check fails against threshold 18. It also fails at six stars against 30. A mask of 4 would pass at either level if the player were in a vehicle and the node latch were newly set. |
| Respray at 1199 points, then zero-weight report before expiry | The score resolver restores 1199 and the three-star row. After the periodic expiry clears saved fields, the same score operation with live score zero yields zero. A minimum-level call can independently raise it. |

These are static branch traces. The role names of global mode values and script bits beyond their observed consumers require additional caller evidence when attributing a named mission or game mode.

## MTA checks against the PS2 build

The server regression drives the production scorer from zero through 4,800 points in five-point increments. It checks both sides of every star threshold while a second simulated player remains at three stars. It also queries all seven levels with all 32 combinations of response flags, checks a two-step parole restoration, and exercises an immediate firearm hit that follows an earlier hit on the same victim. Run `py -B tools/check_vcs_wanted.py` from the repository root.

The module keeps each player's world-event identity list separate from their pending crime queue. The PS2 repeat windows at the producer call sites are 1,000 ms for gunfire and vehicle impacts, 1,500 ms for taking a vehicle, 2,000 ms for ordinary or special pedestrian damage, and 10,000 ms for bullet strikes and ignition. Repeated world events extend the expiry. Direct star assignments clear the crime queue and preserve these event identities. In multiplayer, two players striking the same victim have independent event lists.

The damage classifier at `001D8B30` distinguishes ordinary assault from special damage. Reading the US GAME.DTZ weapon records (stride 0x70, model at +0x60) identifies original IDs 5, 9, 10 and 11 as KNIFECUR, MACHETE, KATANA and CHNSAW. MTA's combat knife, katana and chainsaw map to this branch. Managed NPCs report nonfatal hits after server health-loss corroboration and fatal hits through the native death event. The vehicle bomb shop can report a destroyed car using its server-owned planter and armed-vehicle records.

The area-based percentage reduction uses the maximum signed halfword at +0x0E among matching 16-byte cull boxes (`0040CFF0`, accessor `0040D4A8`). All 631 boxes in the US GAME.DTZ table at file offset 0x3436A4 have zero in that field. The ordinary map therefore introduces no area percentage reduction to crime points.
