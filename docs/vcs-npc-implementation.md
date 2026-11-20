# VCS street NPC implementation and testing guide

Choose a scenario from the [behavior overview](vcs-npc-overview.md). Record the original VCS model ID, initiator, victim, target vehicle, seat, and event order. A single carjacking can trigger a driver trying to reclaim the car, passengers leaving in stages, and bystanders moving away. Track each actor's target and timers separately.

## Finding the code for a behavior

Street behavior lives in `mods/deathmatch/resources/[traffic]/npchlc_traffic`. Its `meta.xml` defines load order and cross-resource interfaces. The neighboring `npc_hlc` resource executes tasks on the current syncer. In PowerShell, use `Get-Content -LiteralPath` for paths containing square brackets.

| Behavior | US PS2 entry points | MTA implementation and evidence |
|---|---|---|
| Hearing gunfire, dodging bullets, taking hits, witnessing attacks, and gang hostility | 001EFFB0, 002D9D18, 002201A0, 00307550 | `ped_ai.lua`, `ped_ai_rules.lua`, `ped_evasion*`, and `ped_voice*`. [Perception and reactions](vcs-npc-reactions.md) |
| Pursuit on foot, melee, armed attacks, and a target entering a vehicle | 003BC9A8, 00101D30, 00100BA0 | In `ped_ai_tasks.lua`, `ped_combat_navigation.lua`, and `npc_hlc/tasks_c.lua`, check line of sight, 3D distance, and the two successive action timers. [Combat](vcs-npc-combat.md) |
| Carjacking, reclaiming a seat, road rage after a collision, and stopping to exit | 002FDCB0, 00306010, 00306680, 00429110, 00429488 | In `traffic_crash_decisions.lua`, `traffic_vehicle_pursuit.lua`, `traffic_road.lua`, and `ped_carjack.lua`, trace native seat callbacks for the same driver and original vehicle. [Carjacking](vcs-carjack.md) · [Impacts and abandoned vehicles](vcs-vehicle-impact.md) |
| An approaching vehicle, sidestepping, diving, and getting up | 004342D8, 00209908, 00209CD0 | `ped_evasion.lua` defines the geometry and action phases. Client and server modules with the same prefix validate landing positions, the syncer, and progress. [Vehicle evasion](vcs-vehicle-evade.md) |
| Sitting, standing up, working, beach activities, queues, companions, conversation, NPC-initiated theft and mugging | 002D9210, 0020ED50, 001F16D0, 003C0B6C | In `traffic_ambient.lua`, `ped_activity*`, `ped_social.lua`, `ped_theft.lua`, and `ped_mugging.lua`, distinguish reserving a position, approaching, turning, completing the action, and cancellation. [Ambient activities and in-car services](vcs-npc-activities.md) · [Wait actions](vcs-npc-wait.md) |
| Gunpoint threats, raised hands, cowering, dropping cash, and reactions when the threat ends | 001F8D98 → 0021FB38, 0020F638, 003C0E9C | `ped_special.lua` stores the aggressor and deadline. `ped_special_c.lua` plays the PS2 animation and probes the ground. An NPC who successfully stole money can drop cash once. The server sets each pickup's value and handles collection. [Gunpoint reactions and fire](vcs-npc-special.md) |
| Burning, medical aid, firefighting, and police intervention | 002BD7C8, 001F8ECC, 00409090, 00324FC8 | `ped_special.lua` handles burning actors. `ped_services.lua` manages incidents, responders, and officers. `wanted.lua` handles wanted levels and arrest outcomes. [Emergency services](vcs-npc-services.md) |
| Current and temporary objectives, script takeover, and release | 003BB670, 003BB408, 003BB450, 003BC8F8, SCM 01C4 / 0112 | See `ped_objectives.lua` and `ped_script_control.lua`. VCS has one saved objective slot. Physical states and wait states have separate lifetimes. [Objective arbitration](vcs-npc-behavior.md) |

## Checking PS2 assets and code

For water population, boat control, ambient flights, and client test locations, see [Boat traffic and AIRTRAIN](vcs-water-air-traffic.md).

The Ghidra MCP program is `SLUS_215.90 (VCS)`. Addresses in these chapters are virtual addresses. The extracted disc contains `SLUS_215.90`, `PS2/GAME.DTZ`, `GTA3PS2.IMG`, and `AUDIO/SET0`. If the decompiler shows a floating-point ID or a register with no apparent source, check the call site, delay slot, and jump table. To identify a natural trigger, trace the setter's callers back to population generation, an event, or an SCM opcode.

- `tools/ped_ai_profiles.py` reads personality and weapon range. Weapon root slot 0x28 in GAME.DTZ points to a manager. Follow its +4 pointer, then read field +8 from each record at stride 0x70. MTA weapon mappings are in `ped_ai_rules.lua`.
- `tools/vcs_traffic_animations.py` and `tools/ped_activity_import.py` convert animations and attractors. Standard group entries 0x9C and 0x9D are handsup and handsCOWER, respectively. Generated files live in the resource's `ped_models` and `ped_activity` directories. [Locations and animation sources](vcs-street-ai.md)
- `tools/ped_voice_import.py` runs the PS2 model and event selector and converts the original bank-2 ranges to WAV. Look up the original model ID in `ped_voice/catalog.lua`. Some model and event combinations have no sample on the disc. [Voice call sites](vcs-voice-calls.md)
- Structural references include `D:/dev/VCSPC/VCS PC/PedIntelligence.cpp` and `D:/dev/gta-reversed/source/game_sa/Tasks`. The vehicle impact chapter identifies VCS evidence, SA reference behavior, and thresholds chosen for the port.

## Mission scripts

Use `exports.npchlc_traffic` on the server. Each takeover belongs to one calling resource and is released automatically when that resource stops. In the example, the caller supplies the actual ground height.

```lua
local traffic = exports.npchlc_traffic
local ped = traffic:createTrafficScriptPed(23, x, y, z, interior, dimension)
if ped then
    traffic:assignTrafficPedObjective(ped, "walk", destinationX, destinationY, destinationZ, "run")
end
-- Call traffic:releaseTrafficPed(ped) in the mission completion callback.
```

| Export | Behavior |
|---|---|
| `acquireTrafficPed(ped)` | Takes control of an existing traffic NPC and suspends its street activity or driving task. |
| `acquireTrafficPedInArea(x1,y1,x2,y2,z,interior,dimension,civilians,gangs,special,previous)` | Searches the rectangle within a Z difference of 5, newest creation first. Returns the first NPC element matching the requested categories. |
| `assignTrafficPedObjective(ped,order,...)` | Supports walk, attack, flee, follow, waitInCar, exitVehicle, and clear. waitInCar takes milliseconds. Zero means wait indefinitely. On expiry the native exit action takes over. Special orders are ignite, extinguish, and cashEligible. clear removes tasks while retaining control of the actor. |
| `releaseTrafficPed(ped)` | Returns the NPC to traffic control. A surviving actor's health is restored to 100. An interrupted flee objective can resume. |

## Regression checks

Run these commands from the repository root.

```powershell
py -B tools/ped_ai_profiles.py 'D:/ps2_game/Grand Theft Auto - Vice City Stories (USA)' --check
py -B tools/ped_ai_check.py
py -B tools/ped_objectives_check.py
py -B tools/ped_activity_check.py
py -B tools/ped_ambient_check.py
py -B tools/ped_evasion_check.py
py -B tools/ped_voice_check.py
py -B tools/ped_services_check.py
py -B tools/check_vcs_wanted.py
py -B tools/check_vcs_traffic.py --disc 'D:/ps2_game/Grand Theft Auto - Vice City Stories (USA)' --vcs-pc-dir 'D:/Game/vcs_pc_edition' --native
```

`ped_objectives_check.py` covers the 15-unit hands-up boundary, switching aim and lowering the weapon, replayed pickup responses, flee renewal, scripted fire, and cleanup when a resource stops. Traffic tests cover two pursuit overshoots, stalls, braking, a target moving again, obstructions, bounded rerouting, and native exit requests. See [Emergency services](vcs-npc-services.md) for live MTA medical and firefighting records and [Street scenarios](vcs-street-ai.md) for client images and audio.

## Verification limits

Civilian pursuit anti-circling logic, client ground probes, workbench activities, and fair-weather beach activities are MTA adaptations. The [dispatch table](vcs-npc-dispatch.md) and individual chapters identify special mission flags, dispatch entries without a confirmed natural trigger, and material differences between engines. The pursuit retest used the server and controlled probe replies. The driver's exit animation still needs client verification.

### Reproducing a circling driver

1. Select a civilian driver already pursuing the player after a vehicle collision. Record the driver, vehicle, and player elements. A second driver passing the same location should continue cruising.
2. Keep the player stationary on flat, open ground. Record displacement over two seconds and the driver's closest approach. Within 10 units, check the walking route and braking speed after two overshoots or four seconds without closing the gap. At a speed of 0.05 or less, the current syncer should receive an exit request.
3. Have the player drive away during braking, then repeat with the player waiting in place. In the first case the driver should resume pursuit. In the second, the same driver should approach on foot after the native seat-exit callback. Move the player into another vehicle and verify that the attack target follows the occupied vehicle.
4. Separate the two actors with a wall, put one on a bridge and the other below it, or place deep water outside the driver's door. A failed exit probe allows at most one reroute before pursuit ends.
5. Give the vehicle and player different syncers and repeat the stationary and moving tests. The native server can verify authorization, phase transitions, and exit requests. Use a client to verify the door, the exit animation, and the transition to the next action.

The final isolated MTA 1.7 server run recorded 600 active tasks across 112 samples. Scheduler p95 and p99 were both 2 ms. These measurements came from one machine. A separate simulation covered 100 observers.


### How pedestrians resume after an activity

Start with `updateBehavior` and `updateWander` in `traffic_ambient.lua`. Injury recovery, threat responses, couples and conversation, ambient activities, vehicle interactions, and first aid share these entry points. A task module can submit the next objective when its own task ends. For example, a paramedic looks for another eligible patient before requesting `returnCar` if the original vehicle is available. Once the driver seat is confirmed, the road controller takes over the same NPC. A pedestrian waiting at a traffic light resumes the saved crossing route.

When all modules release control, the pedestrian scheduler clears stale tasks, asks the syncer to probe nearby entries to the path network, and issues `walkTrafficToPoint`. See `pedestrianEntryPoints` in `traffic_graph.lua` for entry selection and `traffic_world.lua` for probe requests and replies. Compare `getNPCTaskCount` with the queue length traffic expects. A probe reply that arrives in time remains available for the next poll. If the actor has moved or changed worlds, the scheduler requests a new probe.

Run `python -B tools/ped_activity_check.py` to check the full seating animation sequence. Run `python -B tools/check_vcs_traffic.py` to check task handoffs, cleared queues, and probe replies arriving after a poll. Adding `--native --disc "<extracted US PS2 disc directory>"` creates a paramedic, patient, and ambulance on an isolated MTA server and checks that the paramedic receives the HLC task to walk back to the vehicle after reviving the patient.


### Mall pedestrian spawning and floor checks

See portals MALL1 through MALL7 in `vcs/portals.xml`. The mall interior uses interior 0, dimension 3090, with entry points around Z −201. `enex/server.lua` validates the departure position against the portal ID. After the client confirms the floor has loaded, it synchronizes the destination and dimension with the server. Use the portal data to locate the mall. The old enex.ipl height or the interior number alone is insufficient.

The spawn entry point is `collectCandidate` in `traffic_ambient.lua`. Underground segments are intersected at the player's actual elevation and filtered by floor. Day and night population tables come from the PS2 MALL zone. On the client, `traffic_world_c.lua` checks that spawn points and walking targets have a physical floor in the current interior and dimension. Rooms without usable pedestrian paths do not borrow nodes from another floor.
