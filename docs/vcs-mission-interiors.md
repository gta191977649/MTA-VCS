# VCS mission interiors

The US PS2 mission script supplies the door triggers, player landings and building swap hashes. The level files identify each replacement model. The entrance converter resolves floor heights against the exported collision in the destination interior and dimension. Free roam exposes the following playable spaces.

| Space | PS2 evidence | Map behavior |
| --- | --- | --- |
| White Stallionz Bar | `BRY_B4_2139` opens swap `2806232871` and `BRY_B4_6482` returns Vic to the street. | The front door leads to model 6453 in dimension 1154. The original return trigger is just inside the same front door. |
| Fort Baxter administration building | `DIA_C4_27308` and `DIA_C4_27486` switch model 1510 to 6402 and back. | The door uses dimension 1106. The inner trigger sits half a unit inside the script door where the floor begins. The barracks and Jerry's quarters retain their separate entrances. |
| Freighter | `BRY_B3_25774` and `BRY_B3_27306` take Vic between the deck and the ship interior while rescuing Lance. | The deck door leads to model 6399 in dimension 66. Both landings use the offsets in the mission script. |
| Mendez mansion | `LAN_C10_30282` tests the outside door. `LAN_C10_28825` gives control to Vic for the Armando fight. `LAN_C10_29140` returns Vic outside. | Model 7084 occupies dimension 162. Free roam provides a return trigger at the original indoor scene entrance. |
| Mendez Building offices | `DIA_C5_21726`, `DIA_C5_22755`, `DIA_C5_26502` and `DIA_C5_27454` move Vic between the roof and two office floors. | Both stairways use their original world coordinates. The office volume follows model 3036 and selects timecycle row 1 on the two floors. The roof retains outdoor weather. |
| Phil's warehouse | `PHI_A2_8563` opens building swap `3953754966` for the forklift section of *Boomshine Blowout*. | Entity 6069 uses the open replacement 6382 with the existing exterior LOD. The warehouse and its loading door are in the outdoor world, so players and vehicles can enter directly. |

## Other source candidates

The existing King Knuts routes cover the Downtown room used in `LAN_B2`. The barracks, shooting range, Jerry's quarters, Lance's hideout and the mall also have existing routes. The `phill_concert` resource owns ticketing, stadium entry and return for the concert. The mission interior catalog uses those existing owners.

The asset named `biker_bar_exterior` is entity 1056, model 2583, at approximately `(-600.28, 636.97, 14.64)`. Neither the BEACH nor the MAINLA swap table references 2583 as the original or replacement model. The converted interior placements contain no room within 64 units of its origin. `BRY_B3_22103` places Vic nearby outdoors. The separately identified White Stallionz interior belongs to the bar on the mainland at `(-1088.0, 126.6)`.

The Louise and Forbes room swaps in `LOU_A4`, `LOU_B2`, `LAN_B4`, `BRY_B3` and `BRY_B4` stage scripted camera scenes. Their converted assets remain available. The legacy SCARAP and STRIPC entrance records and the four SKY records lack a verified playable mission route in this pass. The source sweep covered literal building swaps, area-profile changes, nearby literal player transitions and the existing portal catalog. Dynamic script operands require separate evidence.

## Verification

The converter's `verify_enex.py` checks every generated landing against collision and replays both directions through the production ENEX server and client scripts. `python tools/check_enex_mall.py` exercises the mall and mission routes against a native loopback MTA server. Client acceptance additionally checks walking across Phil's loading door and taking the Mendez stairs in both directions.
