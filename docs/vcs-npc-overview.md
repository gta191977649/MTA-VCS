# What NPCs do in Vice City Stories

Follow one person through the tree. During a carjacking, for example, the driver may fight for the car, the passengers may climb out, and a pedestrian in front of the car may dive away. Each reacts to a different part of the same incident.

[Port implementation and verification guide](vcs-npc-implementation.md) · [Open the full-size behavior tree](vcs-npc-overview.svg)

```mermaid
flowchart LR
    root["An NPC on the street"] --> ordinary["Going about the day"]
    root --> danger["Someone poses a threat"]
    root --> traffic["A vehicle changes the situation"]
    root --> injury["An emergency unfolds"]
    root --> order["A mission takes control"]

    ordinary --> walk["Walk alone or follow a companion"]
    walk --> meet["Pass someone, turn to look, or stop to chat"]
    meet --> carry["Part company and carry on"]
    ordinary --> place["Approach an available activity spot"]
    place --> occupy["Take a place, wait or sit, then leave"]
    ordinary --> drive["Drive a route or ride as a passenger"]
    ordinary --> gang["Gang members follow a leader or stop to talk together"]
    walk --> light["Wait at a crossing, then continue when it clears"]
    drive --> service["A passenger providing a service can stay while the car is parked, then get out"]

    danger --> hear["Hear a gunshot or have a bullet pass close by"]
    hear --> run["Flee the source, or dodge the bullet"]
    hear --> resist["An armed, confrontational listener may fight back"]
    danger --> aim["Someone points a gun at the NPC"]
    aim --> hands["Stop and raise hands; some drop valuables"]
    hands --> after["When the threat passes, flee, fight or walk away"]
    danger --> hit["Take a hit, or see the player attacked while following them"]
    hit --> defend["Fight the attacker, retreat, or stay out of it"]
    run --> safe["Keep running while danger stays close; then settle down"]

    traffic --> approach["A car bears down on a pedestrian"]
    approach --> evade["Signal, step aside, dive or keep walking"]
    evade --> recover["After a dive, get up if able; a late dodge can still end in a collision"]
    traffic --> crash["A traffic vehicle is hit"]
    crash --> road["A driver may shout and regain the lane; a rider can be thrown off"]
    crash --> chase["An angry driver pursues the target by car"]
    chase --> stalled["If the target stays put and passes fail, check for a safe place to stop"]
    stalled --> foot["Brake and exit, then pursue the person or attack the occupied vehicle"]
    stalled --> blocked["A blocked exit permits one route change before disengaging"]
    traffic --> steal["Someone takes a car"]
    ordinary --> thief["A street criminal spots a suitable car nearby"] --> steal
    steal --> driver["Pulled-out driver flees, confronts the new driver or tries to reclaim the car"]
    steal --> riders["Passengers may leave one after another"]

    injury --> law["An officer picks up a pursuit"]
    law --> arrest["Close in and attempt an arrest, or break off if the target is lost"]
    injury --> medic["A medic finds a casualty"]
    medic --> treat["Approach and give aid; another medic may wait or seek another casualty"]
    treat --> result["A casualty may recover; the medic moves on when the call ends"]
    injury --> fire["A firefighter spots a fire"]
    fire --> attend["Approach the fire; switch to a closer one or seek another when it is gone"]
    injury --> burn["The NPC catches fire"]
    burn --> escape["Run from the source; return to walking if the flames go out and the NPC can move"]

    order --> directed["Follow the assigned action"]
    directed --> release["When released, return to street life or continue an interrupted escape"]
    classDef origin fill:#123447,color:#fff,stroke:#123447
    classDef situation fill:#d6eaf0,color:#16384a,stroke:#477286
    class root origin
    class ordinary,danger,traffic,injury,order situation
```

## How personality changes the outcome

- **A frightened pedestrian can keep running after the first scare.** If they are fleeing a person or vehicle that follows them, staying close can prolong the chase. A driver fleeing the spot where they were dragged out can keep running from that spot even after the stolen car moves away.
- **A quick temper can change what happens after a carjacking.** A driver who would fight may still have to finish climbing or falling out first. By the time they get up, the person behind the wheel may have changed.
- **Being nearby and being a companion lead to different choices.** A willing follower can defend the player against an attacker. Other pedestrians may hear the shot, dodge a bullet, run away, or continue what they were doing. Gang members can also come to regard the attacker's group as hostile.
- **Work can be interrupted.** A medic approaching a casualty can flee a threatening player. At a casualty, one medic can give aid while another waits. If the casualty recovers first, the medic can move on. An officer whose target escapes can leave the pursuit and return to the patrol car.

## Three scenes to read across the tree

| What happens | What the people involved may do next |
| --- | --- |
| A player fires past two pedestrians. | One hears the shot and runs from the shooter. Another, farther from the shooter but close to the bullet, may dodge. Someone actually hit responds to the attacker and may fight back. |
| A car approaches someone crossing the street. | The pedestrian may gesture, sidestep or dive. A successful dive leaves them on the ground briefly before they rise. If the car reaches them first, they can still be hurt. |
| A player drags a driver out of a car with passengers. | The driver may shout, flee the spot, challenge the new driver or try to take the car back. The passengers can start leaving at different times while the driver's reaction is still playing out. |

## Debugging an individual pedestrian in game

Enter `/trafficdebug` to show overhead labels for traffic NPCs in view. Enter it again or use `/trafficdebug off` to hide them. The `road`, `ped`, and `boat` filters select the underlying path network. All three modes show labels for drivers, passengers, and pedestrians.

- Labels and path target lines use the 3D distance between the NPC and the local player. In the same interior and dimension, they are fully visible within 12 metres, fade between 12 and 35 metres, and disappear at 35 metres.
- The first line shows temper and fear from PEDSTATS. When temper exceeds fear, “Hot temper” appears in red. The carjacking response uses the same comparison to decide whether the driver gets angry.
- The second line shows the behavior, the HLC task name used in code, and its execution phase, for example `fight > killPed`. During conversation it shows the current gesture or listening phase. For seating it shows approach, turn, and sit phases. “Awaiting sync” means the executing client has yet to report a sample.
- The red bar in the black frame shows current HP relative to the character's configured spawn health. A white bar appears when armor is above zero.
- A solid cyan line and cross mark the point the executor is moving toward. During a detour, a faint dashed line connects the temporary point to the subsequent walking target. Waiting and stationary animations have no movement line.

Look under `mods/deathmatch/resources/[traffic]`. Search for the task name from the label in `npc_hlc/tasks_c.lua` to find its `performTask` handler. Pedestrian and vehicle avoidance decisions are in `npc_hlc/traffic_pedestrians_c.lua`. Conversation and activity phases are in `npchlc_traffic/ped_social.lua` and `ped_activity.lua`, respectively. If a spectator and the controlling client see different targets, check the subscription, syncer, and task revision in `npc_debug_s.lua`, then check the execution snapshot in `control_npc_c.lua`.
