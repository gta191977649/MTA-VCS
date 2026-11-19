# Multi Theft Auto: Vice City Stories Map 
![Screen_1](screens/2.png)


A Total Convention of VCS Map to MTASA with original game atmosphere.
The goal of this project is to provide a boilerplate for your further gamemode development.
This resource includes VCS styled map, hud, vehicles, weapons, peds, weather, etc.
Currently, many things are still working in progress, if you find any issue or you want to contribute, you're welcome!

## Reload VCS scripts

The server starts `eagleLoader`, `vcs`, and then `leeds_engine`. After changing a VCS script, run `restart leeds_engine` in the server console. The engine stops the managed scripts in reverse dependency order, then starts them with the changes on disk. The map and Eagle Loader stay running.

During an engine reload, the client keeps the San Andreas HUD and native color filter suppressed and carries the VCS weather through the restart.

After adding a resource directory, run `refresh` before `restart leeds_engine`. When deploying a resource rename such as `ui` to `frontend`, stop the MTA server, replace the resource files, then start the server again.

For a server already running before this change, run `reloadacl`, `refresh`, and `start leeds_engine` once. Update the ordered list in [resources.lua](mods/deathmatch/resources/%5Bvcs%5D/leeds_engine/resources.lua) when adding a VCS script resource. Optional entries are reloaded when they are running.

## NPC traffic and wanted level

`npchlc_traffic` loads a schema-version-1 network from its `graphFile` resource setting. For another map, point that setting at the map's network JSON. Set `modelIdSpace` to `"mta"` in the graph for native ped and vehicle IDs, or provide `modelBindings` entries with `originalId`, `kind` and `model`.

For streamed replacements, a graph can name a separate `modelProvider` resource. The provider exports `getTrafficModelBase(originalId, kind)` on the server and may export `getTrafficVehicleGroundGeometry(vehicle)` on the client. The traffic resource tags each supported actor with `npchlc_traffic:modelProvider` and `npchlc_traffic:originalModel`. A provider can emit the local event `npc_hlc:onVehicleGroundGeometry` on a vehicle after installing or updating its axle metadata. The `modelProvider` resource setting accepts `auto` to use the graph, `none` to disable the provider, or a resource name to override it.

### VCS example

Import the navigation data from the unpacked US PS2 disc, then run `refresh` and `restart leeds_engine`.

```powershell
py -B tools/import_vcs_traffic.py 'D:\ps2_game\Grand Theft Auto - Vice City Stories (USA)'
```

The import stays in the server's local `npchlc_traffic/paths/generated` directory. It contains 5,308 pedestrian, 2,701 road and 378 water nodes, 17,652 directed links, 260 points on the original fixed-wing loop, and the population profiles initialized by `MAIN.SCM`. The manifest records the PS2 inputs, hashes, offsets and route coverage. `getTrafficStatus()` reports the runtime load state and counts. Validated graph data becomes available when the state reaches `ready`.

To install the original traffic models from the local disc, build `vcsconv.exe` from the local librw and librwgta sources with `tools/build_vcs_model_converter.py`, then append `--convert-models <path-to-vcsconv.exe>` to the import command. This creates the separate `[model]/vcs_model` resource. `ped.img` holds 75 pedestrian models, each with the first outfit from its original PS2 palette. `vehicle.img` holds 78 vehicle models, including AIRTRAIN. Original pedestrian locomotion is stored in a separate IFP in the same resource. The loader starts the resource when installed and the client applies the models as tagged actors stream in.

Server scripts can call `exports.npchlc_traffic:setNPCTrafficRoute(ped, nodeIds, loop)` with consecutive, connected original node IDs. The actor must match the route's kind and scene, and an NPC driver must be in the driver seat. Scripted road routes use the original lane center calculation for lane 0. The server event `npchlc_traffic:onNPCTrafficRouteDone(completed)` uses the ped as its source. `sampleTrafficFlight("fake-plane", gameTimeMs, slot)` returns a position and matrix basis for the original fixed-wing cycle. The three original phase slots are numbered 0 through 2.

In game, `/trafficdebug` toggles the nearby road, pedestrian and boat paths. Use `/trafficdebug road`, `/trafficdebug ped` or `/trafficdebug boat` to filter the overlay. The lines and node IDs are drawn in screen space and remain visible through map geometry. Road arrows indicate lane direction. Red arrows mark the approaches with traffic lights.

`getTrafficPopulationAt(x, y, z, hour, modelSlot)` returns the original zone profile, density and optional model group selection. `findTrafficPedestrianAnchor(x, y, z, previousId)` selects a nearby pedestrian node. `chooseTrafficPedestrianStep(nodeId, heading, reachableNodeIds)` selects the next node from links the caller has checked for line of sight. The resource applies the verified normal traffic-light cycle.

The `roadPopulationMode` resource setting defaults to `auto`. US PS2 graphs use the original zone density even when the graph contains a PC schedule. Other graphs use their schedule when available. Set `zone` or `scheduled` to select a source explicitly. If the requested schedule is missing, the resource logs a warning and uses zone density. `getTrafficRoadStatus()` reports the effective `densityProfile`, area-capacity deferrals as `capacity` and server-budget deferrals as `globalCapacity`.

Ordinary traffic fades near the PS2 outer retention distances of 160 m for road vehicles and 65–97.5 m for pedestrians, depending on the observer's vehicle speed. The road range is also capped by `unoccupied_vehicle_syncer_distance` from the server configuration and is reported as `range` by `getTrafficRoadStatus()`. Restart the server after changing that configuration file.

`getTrafficDynamicRoute("police-helicopter")` returns the original pursuit parameters. The resource can dispatch the original POLMAV when the original COP pilot is bound and a server-side terrain and flight provider is registered. The current installation supplies the POLMAV model. [Police provider contract](mods/deathmatch/resources/%5Btraffic%5D/npchlc_traffic/wanted-evidence.md)

The generated model resource binds the original pedestrian skins and enables ordinary civilian spawning. The built-in world probe uses the nearby MTA client's streamed collision and conservatively applies the visible spawn-distance rule. `getTrafficAmbientStatus()` reports bound models and spawned pedestrians. `chooseTrafficCivilianVehicle(x, y, z, water, hour)` exposes the verified zone and model-frequency selection for bound road or boat models.

Ordinary road traffic uses the original spawn circles, population weights, lane centers and light cycle. During cruise, the MTA sync owner advances the vehicle along the PS2 four-point curve (`00318870`). Each route update carries up to three consecutive segments, allowing the owner to keep moving while the next update arrives. Front and rear collision probes three units apart supply ride height and pitch (`00437B98`). A collision hands control to MTA vehicle physics. `getTrafficRoadStatus()` returns the number of managed road vehicles. The 77 road, water and aircraft models with stable bindings reuse the project's SA-adapted VCS assets inside `vehicle.img`.

The generated resource binds the original AIRTRAIN model, ID 280, for the three synchronized aircraft. `bindTrafficFixedWingModel(false)` removes them. The flight clock advances independently of viewers. When a player approaches the current or last published position, the server publishes the pose using MTA's native transform setters. These updates are broadcast by MTA. Automatic water traffic, territory and police road population, and additional original pedestrian behaviors remain in progress.

`setTrafficSignalConditions(wind, forcedGreen)` accepts the original VCS wind value and script override. Above 1.1 the lights alternate between amber and off every 1,024 ms.

`exports.npchlc_traffic:setPlayerWanted(player, level, reason)` updates MTA's native wanted level and the existing HUD. Listen to the server event `onPlayerWanted(oldLevel, newLevel, reason)` on the player or on `root`. Native changes from other scripts are observed every 200 ms. Use the export if a script needs an event for each intermediate change. [PS2 wanted evidence and API](mods/deathmatch/resources/%5Btraffic%5D/npchlc_traffic/wanted-evidence.md)

Run the repeatable local checks with Python, Lupa and the bundled Windows MTA server.

```powershell
py -B tools/check_vcs_traffic.py --native --disc 'D:\ps2_game\Grand Theft Auto - Vice City Stories (USA)'
py -B tools/check_vcs_wanted.py
```

The traffic test covers 100 simulated sessions and an isolated server running 600 NPC tasks without clients. Use `exports.npc_hlc:getNPCSchedulerStats()` to inspect the server-side task count and timing percentiles during deployment. Real client frame time, network convergence and bandwidth require the separate 100-client test with clustered players, dispersed players and concurrent pursuits.

## Gameplay HUD

Run the importer before starting the server. Point it at the unpacked US PS2 release (SLUS-21590 v1.00).

```powershell
py tools/import_vcs_frontend.py 'D:\ps2_game\Grand Theft Auto - Vice City Stories (USA)'
```

It extracts the HUD and font atlases from `PS2/GAME.DTZ`, the weapon icons and radar map from `GTA3PS2.IMG`, the text from `AMERICAN.GXT`, and the HUD samples from the `AUDIO/SET0` sound bank. The generated `frontend/ps2` directory is local to each deployment. Its manifest records the sources, offsets and SHA-256 hashes.

With Pillow and Lupa installed, run `py tools/check_vcs_hud_aspect.py --output hud-aspect.png` to render the imported HUD across six resolutions and verify the radar diameter and placement.
Run `py tools/check_vcs_font_layout.py --output hud-font-layout.png` to verify the original font atlases and gameplay text scaling.

Gameplay scripts call `exports.frontend`. Numeric GameText styles `0–7` use independent styled text slots. Style `8` is the project’s compatibility entry for location names. Use `showGameText(text, style, duration)` for `VEHICLE_NAME`, `LOCATION_NAME`, `garage`, `radio`, and `radioTuning`. Durations are in milliseconds. A duration of `0` keeps a named style or caption visible until replaced or hidden.

Client scripts can show a pager with `showVcsPager(text, duration)` or start a countdown with `showVcsCountdown(label, duration, warningSeconds)`. They can clear those displays using `hideVcsPager()` and `hideVcsCountdown()`.

Use `showTextBox(text, duration, playCue)` for top-left prompts. It plays the original help cue on each successful call unless `playCue` is `false`. Use a duration of `0` to keep the message visible and `showTextBox(false)` to clear your resource's message. Server callers pass the target player first.

Register mission NPCs with `showNpcHealthBar(ped, label, slot, maxHealth)` and remove them with `hideNpcHealthBar(slot)`. From a server script, pass the recipient player first to either function. There are three slots. A missing slot uses `1`, and a missing maximum health uses `100`. The bar follows the ped's synchronized health and reappears when a living target streams back in.

With the `debug` resource running, use `/hudtext <style> [text]` to preview any of the styles above and `/hudcaption [text]` to show or clear a persistent caption. Users with permission for `command.hudnpc` can use `/hudnpc show 1`, `/hudnpc health 1 25`, `/hudnpc dimension 1 1`, and `/hudnpc destroy 1` to test a targeted bar.

# Bug and Issue
* Wrong LODs position and rotation for some objects (LODs with duplicated objects not working)
* Timed Object are missing

# Progress
* Map
  * Interiors
  * Empire Buildings
  * Objects Fix
    * ~~Aplha Blending Textures~~
    * ~~Breakble Objects~~
    * ~~Time Object~~
    * UV Animation
    * Incorrect Objects Roatation
    * ~~Txds Mapping (Needs custom implmention fix txdp flag)~~
   * 2DFX Lighting Fix - Done
     * ~~Street Lamp (Done)~~
     * ~~Traffic Light (Done)~~ 
* Vehicle (Partially done)
* Peds
* Weapons
* HUD/UI
  * Game Texts
    * ~~Radio~~
    * ~~Vehicle Name~~
    * Zone Name
  * HUD
    * Weapon
    * ~~Health~~
    * ~~Armour~~
    * ~~Oxygen (In Water)~~
    * ~~Cash~~
* Radio Stations - Done
    * ~~Flash FM~~
    * ~~Emotion~~
    * ~~Wave 103~~
    * ~~Praradise~~
    * ~~Fresh FM~~
    * ~~VCFL~~
* Post Fx
    * Shader 
      * ~~Sun Effect~~
      * ~~Trail~~
      * ~~Radiosity~~
      * ~~Building Pipeline~~
      * Water Pipeline
      * Leeds Vehicle Pipeline
      * Grading
    * Weather
      * ~~Timecyc~~ (Note Some parameter is not supported by mta yet, but all supported have been correctly ported) 
      * ~~Color filter~~
    * Particle FX
      * ~~Water (Only the texture is ported)~~
      * ~~Clouds~~
      * Explosion FX
      * Fire
      * ~~Corona (Light Particle)~~
