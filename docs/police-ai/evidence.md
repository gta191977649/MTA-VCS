# Evidence and verification

## Source build

The source is the US PS2 ELF `SLUS_215.90`, SHA-256 `3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547`. Ghidra MCP identified the open program as `SLUS_215.90 (VCS)`, little-endian MIPS R5900, image base `00100000`. Addresses below are virtual addresses in that ELF. SCM offsets are file offsets into the US `MAIN.SCM`, SHA-256 `3cd356b27e6abedbcc59422840d96d31685f9de6911f9b968e544d5ce1ffdb32`.

Labels such as “ram far” describe observed behavior. Model IDs, offsets, unsigned masks, timer comparisons and assignments can be checked independently of those names. For an ambiguous decompiler expression, inspect the MIPS branch and its delay slot. This matters for the roadblock bit mask, the signed Predator steering comparison, the crime-report minimum and the order of helicopter firing-delay overrides.

## Address crosswalk

| Question | Entry or caller | Decisive read, branch or write |
|---|---|---|
| What starts a wanted level? | `00279768` translates game events, `003AB458` resolves points | `002799B0 / 002799F8 / 00279A20` impose minimums. `003AA918` writes score-derived budgets and stars. [Wanted](wanted-and-dispatch.md) |
| How can stars disappear? | `003AA760` tick, `003AAFB0` presence, `0041EA90` respray | The tick decays only below two stars. `001E2110` routes a bribe through the direct setter. `0024CF50 → 003AA730` resets wanted on player recovery. [Wanted](wanted-and-dispatch.md) |
| Where do the units come from? | World update `003BA8D8` invokes air management and the vehicle population / roadblock / deferred deployment passes | `00430464` tests both capacity limits before the forced traffic pick. `002B17A8` has its own targeted-ped gates. `003C90E8` requests specialist models. [Ground](ground-response.md) |
| Which vehicle and which crew? | `00432BE8` chooses the moving model, `0042ABB0` requests seats, `002B3CA0` selects occupants | Moving selection checks undercover before SWAT/FBI/army. `0040B348` uses army/FBI/SWAT/patrol priority for barriers. [Ground](ground-response.md) |
| How does a car reach the player? | `0042B050` chooses the starting mission, `00428C48` changes it, `00438420` drives it | `00439928 / 00439A40` switch between approaching and holding a block. `0042AD80` gives the crew exit objectives. [Ground](ground-response.md) |
| Why are officers already outside a roadblock? | `0040A9E0 → 0040B348` places the line | `00433008 → 0040ADA0` later creates two stationary officers beside a qualifying barrier vehicle. [Ground](ground-response.md) |
| Which officer gets the chase? | Virtual slot `00490D10 → 00324FC8`, then `00325CD8` | `00326FD8` enrolls and assigns the objective. `003271E8` releases. `00327478 / 00327740` enter and maintain arrest. [Officers](officer-behavior.md) |
| What makes arrest final? | `002FD838` completes the pending vehicle-entry branch, `0024C428` examines player state | `0024A770` starts Busted. Phase 2 charges the level-dependent fee before restart clears wanted. [Officers](officer-behavior.md) |
| Who can deploy spikes? | Special population draw `002B17A8`, assignment at `002B2588` | `00327D98` tests the approaching player vehicle. `0039D340 / 0039D9A8` update the strip and test nearby wheels. [Officers](officer-behavior.md) |
| How many aircraft, and when can one act? | `003AAE58 → 002E9D00` gives demand and manager checks, `002EA060` spawns | `002E6A1C–002E6A98` selects the firing delay. `002EA700` deploys subtype 3. `0043C968 / 0043D8F8` control flight and retirement. [Air](vehicle-and-special-response.md) |
| What changes on water? | `00430290` converts the police class to model 219, `0042B1C0` selects its mission | `0042B670` sets the cruise byte, `0043A320` leads the target, `0043A620 / 0043A640` gate firing. [Water](vehicle-and-special-response.md) |

## Script evidence

The SCM handler pointers are eight bytes apart, beginning at `004BEAF4`. Opcode `0098` resolves to `002D2A90` (set wanted), `0128` to `002D3138` (set maximum), `012E` and `024A` to the two suppression handlers, and `024F` to `002D3880` (crime multiplier). `00254B90` decodes operand type 7 as a signed byte and type 9 as four immediate bytes. `00254FF8` resolves local operand `0D` using the current script frame.

In the US main script, the conditional chain at file offsets `21856–21887` compares a frame-local variable against 2 and then 1. The branches issue `0128` with 6 at `21862`, 5 at `21879`, or 4 at `21884`. The two successful comparisons jump over the remaining choices. This establishes a scripted 4/5/6 maximum selection independently of the ELF's initial cap. Another example at `174C10–174C1A` pairs a 0.1 crime multiplier with maximum level 3. Associating these bytecode blocks with named story missions requires their caller context.

## Checks performed

- Read the imported ELF from disk and matched its SHA-256. Rechecked the main entry points, unit predicates and branch constants with Ghidra MCP.
- Exercised the machine instructions at `003AA918` in an isolated little-endian MIPS64 emulator for every integer score from 0 through 9,601, with the original ELF data and a fresh synthetic wanted object. All **9,602** cases matched the documented star, officer, vehicle and roadblock columns and the 9,600-point clamp.
- Called all five unit queries at `003AADA0–003AAE58` for all seven star levels and all 32 combinations of the two suppression bits and three specialist override bits. All **1,120** return truth values matched the documented predicates. The helicopter count of exactly one at three through six is also explicit in the return instructions.
- Exercised `003AAB80`, including its queue-clear call and score recomputation, with each direct-set level 0–6. The seven resulting point values matched the direct-set column. The isolated calls used the ELF code with a synthetic stack and wanted object.
- Traced the boundary scenarios at the ends of the [wanted](wanted-and-dispatch.md), [ground](ground-response.md) and [officer](officer-behavior.md) chapters. For an air example, the 2→3 transition raises demand to one. An unavailable model defers creation. With a loaded model, a due timer and a free slot, the manager creates mission `0x1B`. At 3→2 the manager gives a tracked aircraft mission `0x1E`. At exactly 170 units that distance branch retains it. Beyond 170 it removes it.
- Checked the comparable `CWanted::NumOfHelisRequired` and specialist queries in the local San Andreas `source/game_sa/Wanted.cpp`. SA returns two helicopters at levels 4–6. VCS returns one. All VCS values in the response matrix come from the PS2 build.

## Coverage limits

This reference reconstructs the ordinary one- through six-star response and its documented overrides. The executable checks above exercise individual PS2 routines. For observed gameplay in the MTA implementation, including differences in host physics and model availability, see the [loopback client results](../qa/vcs-police-ai/README.md).

The seven location-specific encounter variants have a registration path and a handler at `0042C440`. Ghidra cross-references and a scan of aligned direct jumps and relative branches in ELF text found no direct control transfer to that entry. Their use in unrestricted free roam remains unverified. The strip retraction phase has a handler, but its upstream trigger is unconfirmed. Some shared ped flags and the external gate on starting Busted retain their raw conditions in the [officer chapter](officer-behavior.md). Those limits matter when reproducing exceptional transitions.

The separate [aircraft selector](vehicle-and-special-response.md) at `003F8FF0` also has no identified caller. For crime inputs, the [score table](wanted-and-dispatch.md) identifies the known producers and preserves numeric IDs where the upstream gameplay event remains unconfirmed.
