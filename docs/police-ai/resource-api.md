# Using wanted state from an MTA resource

The `wanted` resource owns the score, pending crime reports, level, parole, cap and response overrides for each connected player. It runs these rules on the server, updates MTA's native wanted level, and sends the affected player a HUD update. Add this dependency to the calling resource's `meta.xml`.

```xml
<include resource="wanted" />
```

## Server scripts

```lua
addEventHandler("onPlayerWanted", root, function(previous, current, reason)
    outputDebugString(("%s went from %d to %d stars (%s)"):format(
        getPlayerName(source), previous, current, reason))
end)

-- From a server mission script with a player element in scope.
exports.wanted:setPlayerWanted(player, 3, "mission")
local level = exports.wanted:getPlayerWanted(player)
```

`onPlayerWanted(previous, current, reason)` fires once per level change with the affected player as `source`. Setting the same level reseeds its score and clears pending crimes without emitting a transition. Writes through MTA's native server setter are reconciled within one four-bucket cycle (nominally 200 ms) or on the next authority read. The reason for these changes is `native`.

| Server export | Meaning |
| --- | --- |
| `setPlayerWanted(player, level[, reason])` | Set an integer level from 0 to 6, subject to the player's cap. Returns success. The default reason is `script`. |
| `getPlayerWanted(player)` | Read the current level. Returns false for an invalid player. |
| `raisePlayerWanted(player, minimum[, reason])` | Restore any higher level saved by parole and enforce the requested minimum. |
| `resetPlayerWanted(player[, reason])` | Clear the player's level, queue, parole, cap, multiplier and response overrides. |
| `reportWantedEvent(player, event, incident[, immediate])` | Translate a PS2 world event, report the crime and apply the event's minimum level. |
| `reportWantedCrime(player, crime, incident[, immediate[, reduced]])` | Submit a classified PS2 crime. The incident identity is an element or number. Omitting `immediate` uses the police-presence check. |
| `suspendPlayerWanted(player)` | Apply Pay 'n' Spray parole and start the 20-second saved-score window. |
| `setPlayerWantedCap(player, maximum)` | Apply the level's story point ceiling and clamp the live score. |
| `setPlayerCrimeMultiplier(player, multiplier)` | Scale new crime points for this player. |
| `setPlayerPoliceOverride(player, name, enabled)` | Toggle `swat`, `fbi`, `army`, `suppressPolice` or `suppressGarage`. The two suppression flags affect helicopter eligibility. |
| `getPlayerPoliceResponse(player)`, `getWantedResponseForLevel(level)` | Read a response table with officer and vehicle limits, roadblock threshold, helicopter count and special-unit eligibility. The first applies the player's overrides. |

Police presence comes from the registered traffic resource. Without traffic, the module still manages wanted state, and a presence check finds no officers. The server's `onPlayerPoliceResponseChange` event invalidates dispatch caches when overrides change without a level transition. See the [event and crime tables](wanted-and-dispatch.md).

## Client HUD

Read the snapshot when the HUD starts. Listen on `localPlayer` for later changes. Both callback types receive values published by the server. A parole update can change the flashing stars while leaving the live level unchanged.

```lua
local stars, suspended = 0, 0
addEventHandler("onClientResourceStart", resourceRoot, function()
    stars, suspended = exports.wanted:getLocalWantedSnapshot()
end)
addEventHandler("onClientPlayerWanted", localPlayer, function(_, level)
    stars = level
end)
addEventHandler("onClientWantedSnapshot", localPlayer, function(level, paroleStars)
    stars, suspended = level, paroleStars
end)
```

The client resource exposes only `getLocalWantedSnapshot()`. Server mutations, score calculations and dispatch decisions run independently of the HUD.

The `frontend` resource draws the wanted stars, parole flash and localized Busted title. Custody requests the existing game-text style 2 for 5,000 ms. An interrupted arrest clears only the requesting resource's message in that slot. The traffic debug overlays also submit their text to the frontend renderer.

## Phil's mission truck

Call these server exports on `npchlc_traffic` from the PHI_A3 escort setup. The caller supplies a live Barracks on SA base 433 and three distinct mission-owned peds in the same interior and dimension. They must be on foot and free of other attachments. A tagged truck must have VCS model 218. Set up the BMYCR skins, Uzi loadouts (SA weapon 28), health, combat targets and driver in the mission resource. Mounting leaves the driver's seat, player wanted states and ground police roster alone.

```lua
-- Create each mission actor with original VCS model 37 (BMYCR).
local npc = exports.npchlc_traffic
local riders = {}
for i = 1, 3 do
    riders[i] = npc:createTrafficScriptPed(37, x, y, z, interior, dimension)
end
local mounted = npc:mountPhilBarracksRiders(truck, riders[1], riders[2], riders[3])
-- At the mission's detach or cleanup point
if mounted then exports.npchlc_traffic:unmountPhilBarracksRiders(truck) end
```

The three truck-local positions are (0.75, −1.5, 1.7), (−0.75, −2.2, 1.7) and (0, −4, 1.7). The mount requests 180 degrees of rotation relative to the truck. The mission controls where each rider aims. The export returns true on success, including a repeat for the same mounted trio. It rejects a different crew while the bed is occupied. A failed mount rolls back earlier attachments in that call. Unmounting, an explosion, truck destruction or stopping the owning resource releases the riders. The calling mission retains ownership of their lifetimes. Freeroam has no PHI_A3 mission runner.
