# Scoreboard

Press Tab to open the scoreboard and press Tab again to close it. Hold the right mouse button to use the pointer. Use the wheel or up/down keys to scroll rows. Drag the horizontal scrollbar, use left/right, or hold Shift while using the wheel to scroll columns. Clicking a header changes the sort order. Clicking a row selects it.

ID, Name, Score, Ping, and Country appear by default. The scoreboard assigns session IDs and reads score from the player's `score` element data. The bundled `ip2c` resource resolves country codes. An unknown address displays N/A. The stock `/setcountry AU` command sets a player's displayed code and flag for the session.

Other resources can use the stock MTA scoreboard exports and legacy aliases declared in `meta.xml`. Each column uses its element-data key, width, label, and priority. For example, from a server script:

```lua
exports.scoreboard:scoreboardAddColumn("rank", root, 120, "Rank", 6)
exports.scoreboard:scoreboardAddColumn("job", root, 180, "Job", 7)
setElementData(player, "rank", "Captain")
setElementData(player, "job", "Dispatcher")
```

Pass a player instead of `root` for a player-specific column. Client scripts can register a column with a formatting callback or set it later with `scoreboardSetColumnTextFunction`. The existing HTTP scoreboard reads the server column registry.

