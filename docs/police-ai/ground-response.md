# Police cars, bikes and roadblocks

## When a moving unit appears

The world update calls the traffic scheduler, the roadblock update and the vehicle-pool pass consecutively at `003BAC88–003BAC98`. The scheduler `00430148` checks its global disable state and area mode, and calls the generator only below 30 ambient vehicles. It can make multiple attempts in one update. The traffic generator at `00430290` first checks zone density, the overall vehicle limit and at least `0x19000` available from the resource-space query. To force a police pick, stars must exceed one, the on-duty vehicle count must be below wanted `+0x1A`, the enrolled officer count must be below wanted `+0x19`, and area state `00489F7C` must equal zero. At two stars the additional test is `(random16 % 31) > 15`. At three through six the decision passes directly. These checks apply to this generator. An existing patrol can respond at one star.

Without a forced pick, the generator draws from the zone. While wanted, it retries police classes 13 and 24 up to a total of five draws. A police-car draw can become a police bike. Changing zones between the player and the proposed road position can trigger another selection. Candidate path, lane, space, model and surface checks still apply. The nearby-vehicle query uses radius 10 on land. A water node takes the [water branch](../vcs-water-air-traffic.md). Successful police classes 13, 23 and 24 acquire the on-duty flag. The idempotent setter increments or decrements `0048A970` on a flag transition. Evidence at `00430290`, `00431D34–00431DB0` and `003EA0E0`.

### Model selection and seats

Read this table top to bottom. The first matching branch in `00432BE8` wins. Model names for streaming requests are embedded at `004BDA28`. The seat column describes requests by the one-time crew initializer `0042ABB0`. A driver goes through `003E90E8`, passengers through `003E91B0`, and `002B3CA0 → 002B2908 → 00324D08` resolves officer subtype and ped model.

| Eligible moving unit | Loaded assets and selection | Requested seats and officer identity |
|---|---|---|
| Undercover, 3+ | Vehicle 204, peds 117 **and** 118, pair index 0–3, and `last + 120000 < now`. Takes priority at every eligible level. | Driver and front passenger, both subtype 5 on an on-duty 204. The pair arguments are twice the index and twice the index plus one. The constructor chooses model 117 for arguments 0–3 and 118 otherwise. Both officers get flag `+0x1D0 & 0x200000`. Creation increments the active count by two, timestamps the pair and advances the index modulo four. |
| SWAT, 4 or override | With Enforcer 234 and ped 9 loaded, the top third of a three-way draw selects the Enforcer. The other two outcomes return patrol 207 immediately. | Enforcer driver plus three passengers, subtype 2, ped 9. |
| FBI, 5 or override | With FBI car 193 and ped 10 loaded, return 193. | Driver plus three passengers, subtype 1, ped 10. |
| Army, 6 or override | Requires both Barracks 218 and Rhino 246 and ped 11 loaded. A two-way draw selects 218 for the lower half and 246 for the upper half. | Driver plus front passenger above one star, subtype 4, ped 11. |
| Ordinary patrol | Default 207. Below two stars, if bike 191 and ped 119 are loaded, the top third of a three-way draw selects the bike. | 207 has a subtype 0 driver, ped 8, plus a front passenger above one star. The bike has one subtype 6 rider, ped 119. |

Failure of an asset check continues to the next row. The general selector uses `floor(random * n / 2^31)` for the two- and three-way draws (`00408058`, `00443BC8`). `003C90E8` requests models independently of selection. Its undercover ped requests require the active count at `0048800C` to be zero as well as a valid pair index. The road selector itself tests residency and cooldown. An ordinary civilian model 204 has a separate occupant selection when its on-duty flag is clear.

## From patrol to pursuit

An officer on foot and a police automobile can independently report the same vehicle condition. At `0013A7BC → 0014E3E0`, the automobile checks an occupied player car of raw class 0, its halfword at `+0x22E` different from both zero and −1, status other than 5, and squared 3D separation <400. It then requests a minimum of one star. The calling model list includes patrol 207, FBI 193, Enforcer 234, Rhino 246 and Barracks 218. The corresponding on-foot observer is at `00326E18`.

On creation, a patrol car with zero stars receives mission 1 (cruise), style 0 and a cruise setting drawn from 12–16. A wanted patrol uses driving style 2, the speed selector `0042B210`, and the car mission selector `0042B050`. The latter first calls `0021A0D8` with the police vehicle's height. A player in vehicle class 4 or 5 over three units above that height can cause it to return cruise. A bike uses `0042B140` with the same height check. At one star it selects mission 4, at two through six mission 21. Evidence at `00430F48–004310F8`.

| Stars | Ordinary car mission 4 (block far) | Other eligible car outcome | Base cruise-speed command |
|---:|---|---|---|
| 1 | Random bit 1 clear (half) | Mission 2, ram far | 25 |
| 2 | Low three bits 0–2 | Mission 2 | 34 |
| 3 | Low three bits 0–1 | Mission 2 | Handling value × 1.10 × 60 |
| 4 | Low three bits equal 0 | Mission 2 | Handling value × 1.20 × 60 |
| 5 | Same as four | Mission 2 | Handling value × 1.25 × 60 |
| 6 | Same as four | Mission 2 | Handling value × 1.30 × 60 |

The default close-entry distance is 20. At `003E6610–003E6638` the vehicle initializer passes 0x14 to `002D1E68`, which stores it at autopilot +0x3E, vehicle +0x1BE. The SCM handler at `003D5A40` can replace this byte.

For an ordinary assigned pursuit, `00428C48` refreshes the cruise byte on missions 2–5. Changing stars during a ram or block keeps that mission. The probabilities above apply when choosing a mission for a new assignment. MTA sends a changed cruise command to the current road task with the same route sequence.

### Driving styles

San Andreas names these values in `source/game_sa/Enums/eCarDrivingStyle.h`. Its `CCarAI::UpdateCarAI` selects **Avoid cars** when an ordinary on-duty unit begins pursuit. VCS uses the same numeric style on acquisition. Its wanted-level mission draws and cruise commands follow the VCS table above. In particular, SA's one-star car selector always starts with a block and its three-star speed factor is 0.90.

| Style | SA name | VCS road-controller behavior |
|---|---|---|
| 0 | Stop for cars | Applies the full forward traffic speed limit and stops for red lights. Ordinary civilian traffic and cruising patrols start here. |
| 1 | Slow down for cars | Averages the traffic limit with the requested speed, and stops for red lights. |
| 2 | Avoid cars | Adjusts the steering bearing to pass obstacles and ignores red lights during ordinary pursuit. The separate bridge-stop condition still applies. |
| 3 | Plough through | Skips the forward traffic speed scan, bearing adjustment and red-light stop. The separate VCS vehicle damage reaction can select this style. |
| 4 | Stop for cars, ignore lights | Applies the full forward traffic speed limit and skips the red-light stop. |
| 5 | Avoid cars, obey lights | SA style supported for assigned routes. Steer around traffic and obey red lights. |
| 6 | Avoid cars, stop for pedestrians, obey lights | SA style supported for assigned routes. Steer around cars, stop for pedestrians in the path and obey red lights. |

The MTA traffic resource stores the style with each active road driver. A pursuit saves the previous cruise style, uses style 2 for both ram and block missions, and restores the saved value when the unit returns to cruising. Damage can send a civilian into style 3, and a flee response or a prolonged head-on obstruction can select style 2. Ordinary drivers keep their original spawn assignment.

Server scripts can call `exports.npchlc_traffic:setNPCTrafficDrivingStyle(ped, style)` on an ordinary managed road driver. It returns true on assignment and false for an invalid style, a passenger or a driver already occupied with an incident. Existing scripted HLC rail tasks can supply `task.style`; physics tasks accept the numeric style in slot 6. An omitted style uses the ordinary cruise behavior. With `/trafficdebug` enabled, the driver's overhead label shows the current number and name alongside the active task.

The VCS branches are at `00438A80` (route steering and traffic signals), `00433AE8` (forward speed limit) and `00435348` (bearing adjustment). In close pursuit, `00439580` also calls the bearing adjustment. Ram supplies the suspect vehicle as the exclusion, allowing contact, while `00439928` supplies no excluded vehicle for block. MTA approximates the native sector searches with cached collision sweeps and streamed vehicle footprints. Its far pursuit controller can brake for physical clearance or a junction while continuing through a red signal. The elevated-speed bend check uses the next turns present in the current route window, including turns beyond a collinear waypoint.

The handling value is a float at `vehicle[+0x160] + 0x54`. The selector converts the product to an integer. The four multiplier floats begin at `0048A950`. These are requested speeds in the game's control units. `0042B210` also converts any bike on missions 2/3 to 4/5. `0042B360` adjusts close-pursuit speed by **3D** range. At one star the on-foot bands below 20, below 40 and 40+ yield 5, 13 and 25. With a player vehicle the bands below 10, below 20 and 20+ yield 15, 22 and 25. At two stars the corresponding triples are 5/18/34 and 27/30/34. For a player on foot moving below 0.07 and within 30 units this routine caps the command at 10 at any wanted level.

### How civilian traffic yields to a siren

The San Andreas reference is `CCarAI::MakeWayForCarWithSiren` in `source/game_sa/CarAI.cpp`, called from `CAutomobile::ProcessControl`. The US PS2 VCS counterpart is `0042B718`. Its automobile and motorcycle callers at `0013EF68` and `0033C648` check the active siren, the model predicate at `003E9768`, and frame 5 of every eight. Either a player or an NPC can drive the emergency vehicle. The automobile caller excludes Mr. Whoopee.

VCS measures horizontal velocity in native units. The emergency vehicle must travel at least 0.1 and the civilian must travel faster than 0.05. Eligible traffic must be ahead of the emergency vehicle's actual direction of travel, within a horizontal distance strictly below `20 + 45 × emergency speed`, and less than five units apart vertically. The routine checks ordinary traffic cars and motorcycles. It skips law enforcement, active emergency crews and drivers using driving style 2.

| Civilian's position and motion | VCS action |
|---|---|
| Inside the approach cone (direction dot > 0.8), facing along the siren vehicle's travel (heading dot > 0.7) | Swerve right if on the right, otherwise left. Switch to physics, release the accelerator, steer 0.15 radians with light braking, then countersteer for the last second. |
| Elsewhere in the forward half-plane, moving toward the siren vehicle's position | Wait for two seconds. A driver using physics brakes. A driver following a rail slows on its existing route. |
| Behind the emitter, stationary, or outside the distance or height limits | Continue the current task. |

The PS2 temporary-action controller at `004380E0` owns the two-second deadline. The [SA and VCS source comparison](../qa/vcs-police-ai/siren-yield.md) records differences in side selection, timing and steering.

In MTA the server scans in the emitter's direction of travel, using the SA horizontal range of `40 + 45 × speed`. It compares the civilian's lateral offset with the combined half-widths of the two vehicles plus 0.65 units of clearance. A civilian already outside this corridor can continue. A same-direction civilian inside it can pull to either side, including from rest. Oncoming traffic uses its own heading to choose a swerve or wait. Crossing traffic approaching the emergency vehicle waits four seconds inside the forward cone or two seconds outside it.

For a swerve, the server assigns a lateral position and direction in world coordinates so the next sync owner can continue the same maneuver. The driver checks the space ahead, uses throttle to pull over, then straightens and holds the cleared line while the emergency vehicle passes. The base swerve lasts 2.5 seconds. The civilian resumes its existing route when the maneuver ends. Scans retain the VCS eight-frame cadence at the PS2's nominal 30 fps. If several sirens qualify in one scan, the nearest qualifying source supplies the decision.

### Mission transitions

At `004386BC–004386D0` the ram controller stores a turn and its 250 ms deadline. On subsequent updates, `004380E0` applies full throttle and inward steering until the deadline passes. The MTA syncer owns this timed input in the active driving task. Replacing the task or losing control releases the inputs.

| Current state | Condition and next action | PS2 evidence |
|---|---|---|
| Existing on-duty patrol, ordinary mission dispatch | With stars positive and world flag `004CD684 & 0x10` clear, if either absolute XY difference exceeds 14, set an active driving status, choose a car/bike/boat pursuit mission, clear the temporary action and set style 2. Inside that axis-aligned square, a cruising land patrol orders the crew out and clears speed and mission. | `00428C48`, default branch around `0042A078–0042A17C` |
| 2 ram far / 4 block far | Follow road nodes. If horizontal distance is strictly below the per-vehicle byte at `+0x1BE`, or flag `+0x218` bit 20 is set, switch to 3 ram close / 5 block close. The on-duty close retention distance is 50. Beyond 50 with the flag clear and road rejoin returning zero, restore 2/4 and clear the close-state fields. | `00428B10`, `00428B28`, `00428C48`, `00435FB8 → 004361A8` |
| 3 ram close | Steer toward the player. With a player vehicle the relative heading dot product and pursuer seed bits choose the lateral aim point. The aligned side approach uses the two collision extents minus 0.2 and can start temporary turn 6/7 for 250 ms inside `relativeSpeed × 12 + 2`. The other branch loads literal float bits `0x4BCCCCCD` for the lateral projection. The common point controller limits steering and derives throttle/brake from speed error. | `00438420`, `004384F4–00438748`, `00439580` |
| 5 block close | Aim ahead of the player. Cap horizontal target velocity magnitude at 0.13 and project it by 60. Within five horizontal units of that point, switch to mission 6 (hold the block). | `00438420 → 00439928` |
| 6 hold block | Brake and hold. More than ten horizontal units from the current player position restores mission 5. Inside ten, an on-duty crew exits if the player is on foot, the vehicle is upside down, or its 3D speed is below 0.05 with the slow counter above 2500. At exactly ten neither range branch fires. | `00439A40`, `003E9878` |
| 3/5 close, player becomes accessible | On-duty land vehicle, horizontal range **<14**. A player on foot or in an overturned vehicle qualifies immediately. Otherwise the player vehicle must be below 0.05 (ram) or 0.04 (block) and the accumulated slow counter must exceed 100. The accumulator adds frame step × 16.6667, resetting outside its speed gate. Request exit and clear mission and speed. Model 246 skips this particular dismount branch: the extracted byte is always less than the compiled comparison value 10001. | `00429110–00429194`, `00429488–0042950C`; upside-down predicate is vehicle up-Z ≤ −0.9 at `003E9878` |
| 21 bike pursuit | The steering handler leads the moving target by `min(2, 0.05 × distance) × 60 × playerVelocity`, then derives signed steering error and throttle from its own speed. An existing ram mission against a target in handling category 2 can also be changed to block far. | `00438420 → 0043A320`, `0042A3FC–0042A458` |
| Release / forced exit | Shared pursuit cleanup rejoins the roads, resets style to 0 and mission to 1, and clears the alert bit on zero stars or the checked ignore flags. World flag `004CD684 & 0x10` changes the resulting mission to 0. A separate test of world flag `0x100` while on duty and wanted orders crew exit and clears speed and mission. | `00428B70`, `0042A1A0`, `0040D420`, `0040D438` |

The two world flags in the table come from the player's position. `0040CE30 → 0040CFF0` tests all three coordinates strictly inside each zone's bounds and ORs the matching flags. Normally the player mask updates when the frame counter modulo eight equals six. A nonzero `006F4CF0` forces another update. Cars crossing a boundary can therefore react to the same stored mask until the player query runs again.

The initializer at `00332460–00332468` loads the attribute-zone count and table from inflated `GAME.DTZ` offsets 0x98 and 0x9C. Each of the 631 records is 16 bytes. Exactly two carry police bits. The box X (-165, -111), Y (44, 92), Z (-1, 17) has flag 0x10. The box X (-101, -67), Y (919, 945), Z (9, 23) has both 0x10 and 0x100. Every bound is exclusive. The full flag words are 52 and 312.

The exit order at `0042AD80` sends objective `0x10` to the driver, then to each occupied passenger slot. The first passenger's deadline is now + 100 ms. Each further occupied slot adds 200–399 ms. After leaving the vehicle the officer uses the normal [officer decisions](officer-behavior.md). Shared physics can temporarily override the pursuit controls for contact, reversing or an overturned vehicle. See [vehicle impact and recovery](../vcs-vehicle-impact.md).

An existing cruising patrol acquires a wanted suspect independently of the new-unit dispatch quotas. The original `00429FEC–0042A154` branch tests positive stars, the ignore flag and the suspect's position, without checking either roster count. New vehicle dispatch still uses the vehicle and officer limits. Existing units retain exclusive ownership by one suspect, count toward that suspect's roster, and obey response suppression and world checks. Officer enrollment retains its existing distance-based replacement policy.

A wanted-level increase wakes nearby patrol scans for the next budgeted vehicle visit, including visible patrols whose population retirement can still be cancelled. Close cruising land units request native crew exit inside the original ±14-unit XY square; more distant units start their normal driving pursuit. Enable the `npchlc_traffic` resource setting `tracePolice` to log wanted-rise, acquisition, crew-exit, pursuit-exit and release transitions with the target, stars and current roster counts. It defaults to false. [Regression evidence](../qa/vcs-existing-police-wanted/report.md).

The automobile physics update also reacts to a fast chase at three or more stars. The test at `0013A544` requires a player vehicle, a different pursuing vehicle on mission 2/3/4/5, and player 3D speed strictly above 0.3 in native units. The resulting branch writes vehicle `+0xC8` from `0.3 × float[vehicle+0x720] − float[vehicle+0x740]` at the path through `0013A9FC`. This changes the physics input while the same driving mission remains active.

### Specialist vehicles and crews

- **Rhino cannon.** An ordinary AI-driven army Rhino does not shoot the player with its cannon. Model 246 calls `00150C90` from `0013C3F4`. The turret routine compares the Rhino pointer with the current player vehicle and branches to the epilogue on mismatch at `00150D48–00150D50`. Only the player-vehicle branch processes the fire control and checks the strict 800 ms cooldown. Collision destruction has its own handler at `0013C404 → 00151928`. When vehicle speed is >0.1 and `+0x708` bit 47 is set, it walks recorded contacts and invokes the destruction method on qualifying vehicles other than model 246. Player ownership gates the additional crime report there.
- **FBI and army.** Both use the ordinary car mission selection. FBI subtype 1 and army subtype 4 receive weapon `0x1B` with 1000 rounds. The cop constructor sets `+0x78C / +0x78E / +0x4E8` to 1200/95/100.0 for FBI and 800/100/100.0 for army. Both pass the subtype filter into the same pursuit updater at `00324FC8 → 00325CD8`. Their car model's handling value can still produce different cruise commands. FBI requests four seats, army requests two at six stars. The Rhino has the two special close-mission exit checks above. No distinct FBI or army ram/block probability table appears in `0042B050`.
- **Bike and police boat mission 21.** The on-duty mission update calls `0042B670` and writes speed 10/15/20/25/30/40 for stars 1–6 (8 at zero). This is a later write than the initial speed assignment. Only model 219 takes the conditional weapon call in their shared intercept steering routine at `0043A320`.

### Soldiers in the Barracks

The moving six-star crew initializer at `0042ABB0` gives the Barracks (0xDA) a driver and front passenger. The roadblock routine at `0040ADA0` creates two army guards on foot alongside its Barracks. Neither call requests a truck-bed occupant.

The US main script contains four explicit Barracks creation sites. They use the following crew arrangements.

| Script path | Condition and occupants |
|---|---|
| `Noname_14_2775` through `3368` | The military-base sequence creates an army driver. It attaches the player and a model-0 stand-in at the truck origin and hides them. The soldier created outside the truck waits on foot. |
| `PHI_A3_12563 → 4981` | Phase 4 calls the truck escort setup. Once the Barracks and cargo assets load and the truck exists, the script loads BMYCR and Uzi, locks the vehicle, creates one BMYCR driver and attaches three armed BMYCR gang members in the bed. Cab passenger count is zero. The three attachments use opcode 02B6 with position 2, a 360-degree aiming limit and weapon 25. The setup gives them 9,999 rounds, with health 220, 220 and 80. The boxes and truck are created at `PHI_A3_4766`. |
| `LAN_B6_9137` and `9397` | Each convoy truck conditionally requests a driver and passenger index 0. A separate condition attaches three wooden boxes per truck. These cargo slots contain objects. |

A server-side mission can mount the three PHI_A3 riders using the [mission rider API](resource-api.md#phils-mission-truck).

## Roadblocks

1. **Enter a candidate area.** `0040A9E0` divides up to 300 road nodes into sixteen frame slices. Its horizontal test is squared distance <25600 (160 units). The first visit inside sets the latch even when the player has no current vehicle. The code only draws if the vehicle exists. Moving outside clears the latch.
2. **Test the wanted threshold.** `0040ABA8–0040ABC8` tests unsigned `(random & 0x64) < wanted[+0x1C]`. For stars 1–6 the thresholds are 0, 0, 12, 18, 24 and 30. Possible masked values are 0, 4, 32, 36, 64, 68, 96 and 100. Thus stars 3–6 accept **exactly the same two outcomes**. A rejected roll waits until the location is rearmed. A separate sixteen-slot queue submits supplied endpoints within 170 units (3D) of their midpoint and clears the entry. Its check bypasses the random node gate.
3. **Lay out the line.** `0040A418` takes the larger lane sum from the two path links, multiplies by five and adds five. The cross-road vector and node's offset byte determine whether to submit one segment or two. `0040B348` chooses Barracks 218 for army, else FBI car 193, else Enforcer 234, else patrol 207. An unloaded selected vehicle falls back to 207. This priority also applies when multiple specialist override bits are set.
4. **Place the vehicles.** Each segment gets up to six candidate vehicles, `min(6, trunc(length / (modelCollisionRadius × 1.5 + 0.25)))`. The routine varies orientation, tries up to eight placement offsets and sets mission and speed to zero. It admits a vehicle to the world if up-Z exceeds 0.94, records which side faces the player, sets the deferred-cops bit at `+0x260` and writes `now + 7000` at `+0x288`. The rest of `0040B348` handles roadside objects along the segment.
5. **Deploy officers near the player.** The vehicle-pool pass `00433008 → 0040ADA0` checks the deferred bit and horizontal distance <51 to the position from `0024A458`. Two cops are placed beside each qualifying vehicle at scaled, rotated local offsets. The routine maps 193/234/218 to subtype 1/2/4 and defaults to subtype 0 if the required model is unavailable. It sets the officer's `+0x90C` to one, stores the vehicle at `+0x900`, sets a ten-second deadline at `+0x4EC` and orients the officer toward the player or current player vehicle. The caller clears the deferred bit. These officers start outside the roadblock car.

VCS grounds each parked car at `00151A88` using front and rear collision-box samples. The suspension calculation at `001345A0` gives flat-road clearances of 0.757 for the cruiser, 1.030 for the Enforcer, 0.868 for the FBI sedan and 1.437 for the Barracks. The MTA server requests the two paved-surface heights from the approaching player's streamed map, pitches each vehicle along its own heading and creates it with its model clearance. It retries missing surfaces for up to eight seconds while the encounter remains active. Valid slots can appear while another slot is waiting for map collision.

## Location-specific encounters

`0042C440` handles a distinct seven-type encounter record with an inclusive XY activation rectangle. If the previous timestamp is nonzero, another activation needs **more than** 20000 ms. Cases 1/4/5 require at least one star and a player on foot. Case 1 creates two patrol cars on mission 24, while cases 4/5 create one or two officers with ped objective 24 toward the supplied destinations. The two-unit branches clean up the first unit on second-unit failure. Cases 2/3/6/7 require at least two stars, a player vehicle and a negative dot product between player velocity and the vector from the candidate spawn to the player. Cases 2/6 initialize car mission 26 (intercept), cases 3/7 mission 3 (ram close). Cases 6/7 evaluate two spawn points independently. Vehicle creation uses model 207 and the normal police crew initializer. The stored deadlines are +25000 for case 1 and +10000 for the other vehicles. The intercept handler has a separate implementation at `00439CE0`. The script call at `00183168 → 0042C300` can register up to 96 encounter records. Ghidra indexed no incoming reference to `0042C440`; direct-call, direct-jump and aligned pointer searches also produced no caller. These seven branches describe what the handler would do on invocation. Its activation in unrestricted freeroam remains unverified.

## Static walkthroughs

- **One star, player beside a cruising patrol.** A forced traffic dispatch cannot run. With both XY differences ≤14 and the world gate clear, an existing cruising land patrol can order its single driver out. The separate encounter handler contains a level-one branch.
- **Two stars, newly dispatched patrol, two occupants.** Both capacity comparisons and the modulo-31 draw must pass. A low-three-bit mission draw of 2 selects block far, 3 selects ram far. In block close a player vehicle at exactly 0.04 fails the slow test. An overturned player vehicle bypasses that timer.
- **Four to five stars.** Outside the undercover window, a loaded Enforcer and SWAT ped permit the three-way SWAT draw at four. At five the FBI branch returns a loaded FBI car and four requested occupants. Roadblock *vehicles* change with the level even though the accepted roadblock random outcomes stay identical.
- **Six stars, constrained assets.** If either army vehicle is missing, the moving selector falls through to patrol after any higher-priority eligible branches. The roadblock selector only needs its chosen Barracks and uses patrol when that model is unavailable. A moving Rhino's close-mission dismount exclusion is specific to the two inspected branches.

These walkthroughs follow USA PS2 branches. The road acceptance, car physics and collision helpers also serve ordinary traffic. Their full algorithms and authored map coordinates are outside this decision trace. The San Andreas tree's `CarAI.cpp` provides comparative mission names; the numeric states, model IDs, branch order and distances here come from VCS.


## MTA assets and collision tests

For a distant land pursuit the server searches the directed VCS road graph. Each search state includes the arrival lane so the next turn must be legal from that lane. The search inspects at most 128 states and queues at most 256. A 50 ms traffic update admits one new search and two destination-road lookups across all pursuing vehicles. Patrols reuse their route between checks. Four seconds without forward progress triggers a new route check. Failed searches retry after one second. These are multiplayer performance limits. The VCS vehicle mission determines the switch between distant road navigation and close pursuit.

The traffic resource mounts the original six specialist skins (9, 10, 11, 117, 118 and 119) from a dedicated pedestrian archive. Rebuild the skins with the `--street-peds` option in `tools/import_vcs_traffic.py`.

The FBI Car (193) and Vice Cheetah (204) use native emergency parents 598 and 597. Traffic, scripted vehicles and the legacy `/dlc` command use the converted vehicles in `vcs_model/vehicle.img`. Their native sirens use a single red beacon inside the windshield. The marked cruiser and motorcycle retain their roof and fork lights. For a standalone traffic installation, run `python tools/police_ground_assets.py` after rebuilding the main vehicle archive. It packages the same two meshes with their referenced local and shared textures into `npchlc_traffic/police_models.img`.

Players can tap their configured horn key in the driver seat to switch the siren on and off. On tagged police vehicles, the client checks the native state after a short tap. If the game missed the tap, the server applies the requested state after verifying the driver and vehicle. SkyGfx reads the same siren state for the marked cruiser's roof bar and the Electra's beacon.

Roadblocks use VCS path-node heights and the MTA server collision bounds for vehicle count and spacing. For a stinger, the officer uses the pedestrian path and a nearby road node to face across the curb toward the road. This permits a throw from a street corner or another eligible roadside position. A vehicle approaching within 30 units triggers the underhand throw when the directional and path checks pass.

The twelve slats unfold in six crossed pairs over 2.5 seconds. Their centers advance along the officer's facing direction. The PS2 table at `0039CF70` sets the spacing to 1.8 times the sine of the current table angle, from 0 to 59 degrees. At full extension the furthest pair is 9.26 units from the officer. The legs rotate in opposite directions at each center. The client samples pavement height for the visible slats. The server estimates wheel positions from the MTA chassis bounds, checks their sweep relative to the moving pairs, and uses the vehicle's VCS wheel scale plus 0.1 for the contact radius. The server uses the throw's base height for contact, so a steep change of grade can differ from the client pavement sample.

The strip stays in the interior and dimension where its officer received the assignment. The ground regression test drives one estimated front-right wheel onto the segment, confirms that the other three wheel states stay intact, and moves the suspect to another interior to verify cleanup. [MTA wheel state order](https://wiki.multitheftauto.com/wiki/GetVehicleWheelStates)
