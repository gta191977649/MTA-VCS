# Turismo, Crash! and Rush! verification

Tests used one MTA client on an isolated loopback server with underworldwarp disabled. The game resources created the racers and checkpoints, processed collisions, and saved results in the staged SQLite database.

## PS2 references

US MAIN.txt mission 36 defines five Little Havana courses and four Vice Point courses in RACEHUB_15714. RACEHUB_16083 supplies separate player checkpoints and NPC driving targets. RACEHUB_24607 supplies the four starting positions, the three opponent models and course-specific speeds. Race entry is on foot, followed by a trip to the grid in the correct vehicle class. Race records retain elapsed time, best lap and best position per course. The port stores milliseconds.

| Hub | Race | Class | Laps | Entry | Win |
| --- | --- | --- | ---: | ---: | ---: |
| Little Havana | Escobar Run-Way | Motorbike | 2 | $100 | $500 |
| Little Havana | Downtown Showdown | Car | 2 | $150 | $600 |
| Little Havana | Port Sports | Motorbike | 2 | $200 | $800 |
| Little Havana | Rum & Salsa Sting | Car | 1 | $250 | $1,000 |
| Little Havana | Cuban Wheels | Motorbike | 2 | $300 | $1,200 |
| Vice Point | Fools Rush | Car | 2 | $350 | $1,400 |
| Vice Point | High Stakes Highway | Motorbike | 1 | $400 | $1,600 |
| Vice Point | Asphalt Assault | Motorbike | 2 | $450 | $1,800 |
| Vice Point | Supercharged Circuit | Car | 2 | $500 | $2,000 |

Mission 27 uses the Prawn Island studio Coach for Crash! and the Viceport Linerunner for Rush!. Each run lasts three minutes. Crash! requires $2,000 damage and Rush! requires $1,700. A first success pays $1,000 and subsequent successes pay $250. CRASH_1731 sets bike dismount $50, flip $150, spin $10 per 90 degrees before the knock-on multiplier, high flier $25, sunk $250 and destroyed $300. CRASH_5373 allows up to 30 seconds to regain the original vehicle. VCS grants temporary 1,800 HP. In the multiplayer port teardown removes the bonus while preserving damage. An otherwise surviving vehicle stays above the 250 HP fire threshold. A burning vehicle retains its lower health.

Ghidra MCP decompilation of the US PS2 ELF identifies opcode 004A at 003D0910 reading four arguments and selecting autopilot modes 8 or 9 after routing to the XYZ target. Opcode 03A4 at 003D71D0 consumes the vehicle's last collision reference at offset 0x2A8. Opcode 0520 at 00185B48 forwards the course index and elapsed time to 0028A2F0. The corresponding gta-reversed CTaskComplexCarDriveMission::SetUpCar also joins the road graph and sets the physics, cruise speed and driving style.

## Real client

The Little Havana hub opened the five-course menu and deducted $100 from the $1,500 fixture balance. The driver brought a staged PCJ-600 to the starting grid. Three NPCs drove separate original PCJs and changed position relative to the player. During the opening segment, the server observed independent opponent displacements of 18-27 m over roughly 0.7 s. The checkpoint fixture moved the player across all 38 gates after the first automated steering attempt stalled. Finishing first raised the player's balance from $1,400 to $1,900. The database retained a 59,547 ms total time, a 20,837 ms best lap, position 1 and one win. [Turismo payout](turismo-payout.jpg)

The Crash! fixture supplied eight empty, weakened cars at 255 HP and repositioned the Coach for each approach. The connected player accelerated into each car. Eight independently detected impacts and destruction states credited $300 each. At the end of the full 180 seconds, the account balance increased from $1,900 to $2,900. SQLite retained a score of 2,400 and one win. [Damage score](crash-damage.jpg) and [completion](crash-complete.jpg)

A separate live Rush! run started with an 800 HP Linerunner. The mission raised its health to 1,800, the fixture applied 100 damage, and cancellation returned the truck at 700 HP. A second entry and cancellation left its health at 700. The repeated run used the normal sub-mission command and the original vehicle.

## Lua regressions

Running tools/check_vcs_motorsport.py exercised nine different course selections and 333 checkpoint crossings, wrong vehicle class, insufficient funds, simultaneous runs, return-to-vehicle handling, all three rivals, a runner-up finish, every vehicle damage category, both score requirements and first/repeat payouts. The same test covers preserving road-vehicle health on cancellation and reentry. Running tools/import_vcs_motorsport.py with MAIN.txt and --check compared the generated route and grid tables with the local US script.
