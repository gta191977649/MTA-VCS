# Ordinary melee driver pull-outs

Verified on 2026-11-26 with Ghidra MCP, Lua regression checks, an isolated loopback MTA 1.7 build 27005 server, and a real MTA client. No Anode was used.

## Behavior and original evidence

Ordinary melee objective 8 now reuses the native driver-door approach and pull-out controller previously restricted to committed road rage. This supports player and pedestrian drivers and male and female attackers. The attack continues on foot after the seat transfer. Door/seat/target validation, locked and moving vehicle gates, and sync ownership remain enforced. Firearm and police arrest execution retain their respective controllers. Changing threats cancels an older extraction; MTA's pending entry no longer prematurely ends an ordinary attack.

Ghidra MCP decompiled the open US PS2 `SLUS_215.90 (VCS)` function at `0x00101D30`, identified by the existing recovery as `CPed::KillCharOnFootMelee`. Its occupied-target branch selects driver door 10, resolves the door position through `0x00303800`, seeks that vehicle door through `0x0020B460`, and requests run movement. There is no committed-road-rage requirement on this ordinary melee branch. Police have a separate branch. The [retained decompilation](ghidra-00101d30.c) is static evidence; live execution below concerns the MTA adapter.

## Verification

The following checks passed:

- `python -B tools/ped_ai_check.py`: ordinary male/female attacks against player/ped drivers; correct driver and door; locked/moving cars; firearm switching; unrelated occupants; pending seat transfer; on-foot continuation; threat replacement cancellation; legacy carjack recovery.
- `python -B tools/check_vcs_road_rage.py`: existing committed retaliation, native request validation, sync migration and target-loss cleanup.
- `python -B tools/check_vcs_traffic.py`: complete existing traffic regression suite, including the preceding driver lifetime fix.

All four cases in the final complete live run passed with `committed=false`. Server native events confirmed seat-zero entry with the intended victim, victim exit with the attacking ped as jacker, and the attacker leaving the car. Client samples confirmed subsequent on-foot melee and target health loss:

| Attacker / victim | Original attacker / car IDs | Result |
| --- | --- | --- |
| Male / player | 14 / 270 | Native extraction and melee passed |
| Female / player | 24 / 211 | Native extraction and melee passed |
| Male / ped | 62 / 175 | Native extraction and melee passed |
| Female / ped | 64 / 271 | Native extraction and melee passed |

See [selected live samples and native events](live-verification.log). Production traffic spawned the actors and selected their routes. The temporary fixture prepared stationary cars, assigned an ordinary fight objective through the production intelligence, and left native entry, drag, exit and combat to production code. To isolate this behavior, fixture cars were restored to full health, scene admission preceded actor detachment, and collisions with unrelated traffic were disabled locally. Earlier interrupted fixtures were discarded and rerun.

## Limits and cleanup

Screenshot verification remains incomplete: the game menu interfered with capture, and the user stopped Computer Use while the client was being checked. No earlier or mismatched screenshot is presented as evidence for the final four-case run. Audio was not separately assessed by listening. Vehicle models, obstructed doors and multiplayer latency were not exhaustively sampled.

The isolated server was stopped after matching its PID and executable path. Temporary Lua controls remain solely in the isolated environment. Client resource-stop cleanup releases test input and restores the camera. No production test controls were added.
