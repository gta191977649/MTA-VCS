# mradar
Vice City Stories PS2 radar and HUD for MTA:SA, based on mradar.

The 64 original radar tiles use the VCS world coordinates from −2000 to 2000 on both axes. F11 or `/vcsmap` opens the full-screen map. A blip's `mradar:vcsIcon` element data can name an original VCS marker such as `radar_lance` or `radar_empire`. Standard MTA blip IDs with VCS equivalents use the corresponding VCS artwork. Other IDs use the normal colored marker.

The PS2 HUD atlas supplies the clock, cash and wanted stars. The resource uses original VCS graphics for the status bars, targeting overlays and corresponding weapons. Weapons exclusive to San Andreas retain their original MTA icons.

## Features
- default blips and radar areas are supported
- default blips coloring
- artificial horizon and altimeter
- original textures set format
- modify-friendly
- no scaling-bugs
- optional rectangle radar
- new F11 map
- waypoint by click (by [Southland-FR](https://github.com/Southland-FR))
- map legend
- map cursor moving
- localization support
- new crosshair

## Localization

Implemented languages:
- English (default)
- Spanish
- Russian

Choose one of `text` script files in `meta.xml`

## Settings
You can configure this resource with predefined global Lua variables. See script files.

- `mradar_main_client.lua` radar and big map
- `mradar_crosshair_client.lua` crosshair
- `mradar_hud_client.lua` hud

Some of important settings are below

- `RADAR_BLIP_COLOR_ENABLED` (**default is `false`**) - enables blips painting (usually blips have red or black color, u should always define blips color when this feature is enabled) 
- `RADAR_RECTANGLE` (**default is `false`**) - enables rectangle radar (instead of circle)
- `BIGMAP_ENABLED` (**default is `true`**) - enables new big map (F11)
- `BIGMAP_CURSOR_SWITCHABLE` (**default is `true`**) - enables cursor switching when big map (F11) is visible
- `BIGMAP_SWITCH_CURSOR_KEY` (**default is `mouse3`**) - cursor switching key
- `BIGMAP_CURSOR_ENABLED` (**default is `false`**) - enables cursor by default when big map (F11) is visible
- `BIGMAP_WAYPOINT_ENABLED` (**default is `true`** - depends on enabled cursor) - enables `waypoint` blip by click
- `BIGMAP_POST_GUI` (**defaults is `false`**) - enables big map "post-gui" drawing
- `BIGMAP_SOUND_ENABLED` (**defaults is `false`**) - enables big map sounds

## Exported client-side functions
- `getMRadarVisible()`
- `setMRadarVisible(bool visible)`
- `getMHudVisible()`
- `setMHudVisible(bool visible)`

## Screenshots

![screenshot1](https://i.imgur.com/Bq9AYHn.jpeg)
![screenshot2](https://i.imgur.com/VsHtxxd.png)
![screenshot3](https://i.imgur.com/PESLkec.png)
![screenshot4](https://i.imgur.com/09Sj79X.png)
![screenshot5](https://i.imgur.com/Kk9vmvK.jpeg)
![screenshot6](https://i.imgur.com/Fbv28ue.jpeg)
![screenshot7](https://i.imgur.com/CZ6B879.jpeg)
![screenshot8](https://i.imgur.com/snoqD4H.png)
![screenshot9](https://i.imgur.com/hXxG9LM.png)
