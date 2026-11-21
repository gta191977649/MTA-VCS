# VCS marker client acceptance

The final run used the real MTA 1.7 client connected to an isolated loopback server on UDP port 58053. The temporary stage was `C:\Users\nurupo\AppData\Local\Temp\mta-vcs-markers-1795241533202818300`. Production resources were copied from the current workspace, including SkyGfx, frontend and their dependencies. The server logged a fresh JOIN and the temporary resource's client-ready event.

`tools/check_vcs_markers.py` passed server/client creation and destruction, the eight named styles and six numeric aliases, synchronized position/size/color, interior/dimension filtering, per-player visibility, native marker-hit events, and minimap blips. Blips were absent by default; explicit opt-in created an attached blip and opt-out destroyed it. Server destruction reached the client. Test inputs and camera were restored. The harness verified the executable path and PID 128272 before stopping its server.

The client measured the default arrow at elapsed times 1546 and 2237 ms. Its angle changed from 26.5 to 199.25 degrees, matching 250 degrees/second. Its sine phase changed from -0.061321 to 0.916679, its rendered scale changed from 2.879213 to 2.322862, and its Z changed from 15.956396 to 16.651834. These are renderer measurements, corroborated by the two phase screenshots.

All original JPEGs below were opened and reviewed after the final arrow star-corona overlay change. The gallery includes checkpoint, ring, cylinder, arrow, corona, arrow2, pointer and cylinder2. The SkyGfx material transform places the meshes correctly, rotating faces show lighting, and both the standalone additive corona and arrow star glows have no black rectangular background. The side view shows the cyan arrow mutation, its surrounding glow and minimap blip; styles moved to another dimension/interior or hidden for the player are absent.

- [All styles, animation phase 1](run1-all-types-front-phase1.jpg)
- [All styles, animation phase 2](run1-all-types-front-phase2.jpg)
- [Side view, mutated arrow and opted-in minimap blip](run1-mutated-blip-on-side.jpg)

The screenshot handler checked the originating resource, player, expected scene tag and `status == "ok"` before writing the original bytes. `server.log` contains only the final run; `clientscript.log` contains only its three informational SkyGfx messages and no warnings or errors. `run.json` identifies the isolated stage and process. Temporary Lua probes and server configuration remain in the isolated stage; production resources expose no test controls.

This validates the MTA implementation and its live rendering. It is not a pixel-by-pixel comparison against a running PS2 game. The scene uses the San Andreas airport to isolate marker behavior from VCS map conversion.

Reproduce with `py -B tools/check_vcs_markers.py`. The harness creates another isolated stage, launches the real client connection and writes new evidence here. Review every new original screenshot before accepting a subsequent run.
