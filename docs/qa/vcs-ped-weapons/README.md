# Ambient group weapon verification

Tested on 21 November 2026 with a real MTA 1.7 client connected to an isolated loopback server. A temporary resource sampled the original model, population group, weapon slot, inventory and task. These probes are confined to the test server.

| Scene | Observation |
| --- | --- |
| GANG4 street formation | Model 97 had host rifle 31 in slot 5 with 9,999 rounds on spawn, script acquisition and release. After a bat strike, the selected actor entered `killPed` at revision 15. Its rifle inflicted two attributed player damage events with losses of 3 and 10. [Formation screenshot](gang4-rifles.jpg) |
| GANG8 golf territory | Production spawned models 105 and 106 with VCS weapon 3, host golf club 2, in slot 1. Both retained PEDSTATS index 14. Server and client agreed on the selected model 106, and the club survived acquisition and release. [Golf course screenshot](gang8-golfers.jpg) |
| Civilian golfer | Model 105 created through the script-ped export had group CIVMALE and empty inventory before and after release. |
| Patrol | Production model 8 had fists selected, a baton in slot 1 and a pistol with 1,000 rounds in slot 2. |
| Service fixtures | Models 12 and 13 had empty inventories. Model 9 carried host SMG 28. Models 10 and 11 carried host SMG 29. All three armed fixtures had 1,000 rounds before and after release. |

The script-ped series sampled eight instances per model. It observed both original weapon choices for GANG1, GANG2, GANG3, GANG5, GANG6, GANG7 and GANG9. GANG4 and GANG8 have identical first and second choices. MTA reported 9,999 rounds for the VCS grant of 25,001.

The offline regression exercised rolls 49 and 50 for every group and compared the weapon pairs against both the initial and restored US PS2 MAIN.SCM records. The traffic suite also checked the model-to-PEDSTATS assignments and the gang vehicle lookup, including shared model 171. [Native references and weapon mappings](../../vcs-npc-weapons.md)

For the seated-to-foot check, the temporary test resource constrained the traffic vehicle selection to the golf cart (184). Production created its GANG8 driver and equipped a golf club. The test stopped the cart and removed the driver from the seat. The same actor resumed walking with the club selected. This run measured inventory across a controlled seat change. [Driving](gang8-driver.jpg) · [On foot](gang8-on-foot.jpg)
