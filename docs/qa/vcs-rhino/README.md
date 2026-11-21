# Rhino road wheels

The test ran on a real MTA 1.7 client connected to an isolated VCS loopback server. The baseline used the production vehicle constructor for original model 246 and confirmed that the canonical provider had bound model 432 and its Rhino textures. A temporary resource put the player in seat 0, captured both sides after settling, then applied the normal accelerator and followed the moving vehicle. Distances use GTA world units.

## Before the change

The VCS Rhino showed two partial wheel faces through a narrow central opening. Broad hull-colored panels obscured the expected row on both sides. The six native wheel dummies still rotated during acceleration. Both native axle sizes were 1.30. The moving baseline capture was taken at 9.74 units/s. [Stationary, left side](before-left.jpg) · [Moving, left rear](before-driving.jpg)

A separate component-visibility inspection of the old asset exposed the native model's wheel copies. With the high-detail hull hidden, six wheel faces were visible on the near side. Toggling only the low-detail chassis component left the close silhouette unchanged. The final model retains the original low-detail chassis. [Old wheel row with the hull hidden for inspection](before-hull-hidden.jpg)

## After the change

The final archive retained both chassis levels of detail. A fresh client first streamed a native MTA vehicle created with model 432 and no original-model tag. The active provider returned the Rhino textures and both axle sizes were 1.50. The side door and armor remained intact. Tire edges remained visible below the skirts, and the old wheel faces no longer appeared through the door. [Left side](after-left.jpg) · [Right side](after-right.jpg) · [Player driving at 10.43 units/s](after-driving.jpg)

For an inspection after the normal captures, the fixture temporarily hid the body and doors. Three distinct wheels are visible along the near side, with their counterparts across the vehicle. The six visual frames kept their original local axle positions at longitudinal +2.356, −0.757 and −2.357, with lateral positions ±1.55. [Wheel placement with armor hidden](after-hull-hidden.jpg)

The observer sampled after the wheel controller, 49 times while stationary and accelerating to 17.75 units/s. Across all six wheels, the maximum difference from the corresponding native wheel's root rotation rounded to 0.000 degrees on all three axes. The vertical position matched front/rear suspension and the interpolated middle axle to 0.0000 units. Pavement rays measured wheel centers 0.735–0.758 units above the road, compared with the mesh radius of 0.74958. For these measurements the fixture stopped ambient traffic to keep other vehicles from disturbing the tank.

The actual `/dlc RHINO` command created a vehicle with `mod.model=RHINO` and synchronized original ID 246. The player drove it at 9.90 units/s in the sampled frame. All six visual wheel poses matched their native counterparts. The camera 0.20 units above the pavement showed the three tire edges below the armor. The hull and turret also rendered from 80.11 units away, with a few palm fronds overlapping the front of the roof. Native vehicle sound events were recorded during the drive. Both final runs used archive SHA-256 `38f35b6ea51df4ded64764b3394e4378d562197deb27ab1c05f17e8e27f3787b`. The legacy model resource logged a separate `tug.txd` warning during startup. [Normal road-level view](after-road-level.jpg) · [Hull at 80 units](after-distance.jpg)
