# Roadblock vehicle height

Three four-star Enforcers stayed buried in the uphill road at node 160 before the fix. The original screenshots show the asphalt cutting through the body lettering and hiding most of the wheels. With the revised placement, the same three lateral slots put the vans on the road, including the two outer slots near the curbs. The client captured both runs from the same street camera after the SUV approached and the guards arrived. [Before](roadblock-buried-enforcers-before.jpg) · [After](roadblock-enforcers-after.jpg) · [After at wheel height](roadblock-enforcer-wheels-after.jpg)

| Production roadblock | First observed tyre bottom relative to pavement | Tyre bottom after 2 seconds | Last observed body clearance |
| --- | --- | --- | --- |
| Four-star Enforcer, graded road, before | −1.45 to −1.13 | −1.65 to −1.33 | −1.21 to −1.17 |
| Four-star Enforcer, same road, after | −0.04 to +0.30 | −0.12 to +0.08 | +0.15 to +0.22 |
| Four-star Enforcer, flatter road, before | −0.53 to −0.46 | +0.001 to +0.004 | +0.14 to +0.19 |
| Four-star Enforcer, same flatter road, after | +0.005 to +0.079 | +0.003 | +0.14 to +0.19 |
| Six-star Barracks, same graded road, after | −0.21 to +0.44 | −0.22 to −0.05 | +0.12 to +0.20 |

At node 160 (−385.125, 1086.375) the graph records Z 12. The road beneath the original Enforcer centers measured 13.10–13.15. The old code created all three at origin Z 12.841 and they stayed there over 10 seconds. The fixed origins were 14.244, 14.149 and 14.233. The player’s SUV approached to 15.4 units. The wheel-height view shows the center van's front and rear tyres. Small residual tyre overlap is measurable on the graded road, especially on the outermost van. [Three six-star Barracks on the same grade](roadblock-barracks-after.jpg)

On the flatter street (−653.125, 747.5), the original placement briefly buried both Enforcers before native physics pushed them up. The fixed vans started above the measured road and settled with all eight tyre estimates within 0.003 units of pavement. The player approached to 14.6 units. [Both vans on the flatter road](roadblock-flat-wheels-after.jpg)

A real MTA 1.7 client joined an isolated loopback server on November 21, 2026. A temporary Lua resource triggered a normal wanted-level roadblock approach and observed the production-selected vehicles. It did not reposition the vans. The connected client sampled all four front and rear wheel dummy positions at roughly 50 ms intervals initially, then less frequently through settling. At each wheel XY it cast through the static road surface and subtracted the converted tyre radius from the wheel-center Z. The Barracks has an extra axle; the reported range covers its front and rear axles. Body clearance is the origin Z plus the model's lower bounding-box Z relative to pavement directly under the origin, an approximation on a slope. All units are MTA world units.

The server accepted the linked original 960 × 600 captures, which were visually reviewed. The client registered native world-sound events during the approach. The Windows game-session meter read zero during the follow-up audio sample, so playback loudness was unverified. The client script log recorded no gameplay errors during the accepted runs. The fixture released driver input, restored the camera and reset wanted status before the verified test-server process was stopped.
