# Vice City Stories end credits

Type `/credit` in game chat to start the credits. Hold **Space** to fast-forward or press **Enter** (including keypad Enter) or **Backspace** to fade out of the credits and back into gameplay. `/credit stop` immediately restores gameplay. The `/vcscredits` alias supports the same commands. Starting the resource alone leaves gameplay active. Client scripts can use `exports.vcs_credit:startCredits()`, `stopCredits()`, and `isCreditsRunning()`.

## Original PS2 evidence

The target was the US executable **SLUS_215.90**, SHA-256 `3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547`. Addresses below are virtual addresses in the Ghidra program `SLUS_215.90 (VCS)`.

| Location | Observed behavior |
| --- | --- |
| `0x273180` | Constructs the GXT table name with `CRED%02d` and the record keys with `CR%02d_%02d`. Starts scroll at 48. Stores the offset and text pointer of each record. Offset increments by the measured line count times the rounded line advance. The measuring box is 478 logical units wide. |
| `0x272E78` | Advances by 1 unit per normal frame or 20 while accelerated. Sets font 1, center alignment, and a drawing box from x=40 to x=440 in the 480×272 coordinate space. The last record offset plus 704 is the termination threshold. |
| `0x273080` | Places each block at its stored offset plus 498 minus scroll. Culls block origins outside the open interval (-206, 398). Draws at y minus one with scale 0.6 and RGB (220, 220, 220). |
| `0x261BE8`, `0x262818`, `0x3F4138` | Center lines from their measured widths, process explicit newlines and word wrapping, and round scaled glyph advances and line spacing upward. Font 1 uses the GameText atlas. |
| `MAIN.SCM` at `0x24DC3` | The ending sequence fades out, sets 21:00, stages the player at (269.4673, -1158.7444, 10.9), waits two seconds, starts credit group 0 and the ending tune, and selects passing cars for the cinematic. |
| `0x288050`, `0x37B938` | Opcode 04D7 enters the vehicle camera director. It tries shot IDs in the repeating order 0, 21, 7, 3, 20, 1, 21, 8, 2, 20, 5, 2, 22, 1. Line of sight, vehicle position and available street objects determine which shots play. |
| `0x366D40`, `0x2FA898`, `0x18B530`, `0x1896A0` | Opcode 02A1 starts stream 0x6D. Its service restarts it at the beginning when finished. The disc CDSTREAM.IRX path table resolves the stream to `AUDIO/MUSIC/THEME.VB`. |

All 118 records across the nine groups match the US disc's `AMERICAN.GXT`. Playback uses the existing frontend GXT and glyph atlas, including the authored blank lines and accented characters. The local Ogg is a conversion of the disc's stereo 32 kHz theme (83.328 seconds).

## MTA playback

The scroll uses a nominal 30 Hz PS2 clock independent of client frame rate. The resource centers its logical viewport using the project's HUD aspect mapping. Font layout and record offsets are built once. At normal speed the complete sequence lasts about 7 minutes 16 seconds including the entry and exit fades.

The original mission looks for a car with a driver and an open passenger seat within 60 units on each horizontal axis. It picks another car after 10–18 seconds. The MTA scene follows ambient NPC drivers locally so other players keep control of their vehicles. While waiting for an eligible car, the credits and theme continue over black.

The camera can ride beside a wheel, track a car from the roadside, fly overhead, zoom from a streetlight or travel between two poles. The pole shots use the ten eligible model names and their collision bounds from the disc's `GAME.DTZ`. MTA supplies the streamed objects and visibility checks. The original mission clears the wanted level, so its police-pursuit camera modes 7 and 8 are skipped. Traffic density and driving speed follow the server's traffic settings.

For a later frame-cost comparison, record the traffic conditions and camera subjects along with the time into the roll. A black waiting period and a moving traffic shot exercise different parts of the renderer.
