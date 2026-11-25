# Player dialogs

Add `<include resource="samp" />` to the resource that opens the dialog. The following functions are server exports on `exports.samp`.

| Function | Result |
| --- | --- |
| `ShowPlayerDialog(player, id, style, caption, info, button1 [, button2])` | Opens or replaces the player's dialog. Returns true on success. IDs range from 0 to 32767. A negative integer ID dismisses the active dialog. |
| `HidePlayerDialog(player)` | Dismisses the active dialog without producing a response. Returns false if none is open. |
| `IsPlayerUsingDialog(player)` | Returns whether a dialog is pending. |
| `GetPlayerDialogID(player)` | Returns the active ID, or -1. |
| `GetPlayerDialogData(player)` | Returns the ID, style, caption, info, and both button labels, or false. |

| SA-MP style | ID | Content |
| --- | --- | --- |
| DIALOG_STYLE_MSGBOX | 0 | Message |
| DIALOG_STYLE_INPUT | 1 | Message and text entry |
| DIALOG_STYLE_LIST | 2 | One selectable item per line |
| DIALOG_STYLE_PASSWORD | 3 | Message and masked text entry |
| DIALOG_STYLE_TABLIST | 4 | Newline-separated rows with tab-separated cells |
| DIALOG_STYLE_TABLIST_HEADERS | 5 | First line contains column headers |

Use `{RRGGBB}` for inline colors. An empty second button label gives a single-button dialog. Opening any style shows the cursor automatically. Enter accepts the focused button, Escape cancels, Tab switches buttons, and arrow keys or a double-click select a list item.

## Response example

Register the handler on the **opening resource's root** with event propagation disabled. The first argument identifies the player. The response is 1 for the first button and 0 for cancellation. List indices start at zero and exclude the header. Text entry returns the typed value, while lists return the selected first cell with color codes removed. A non-list dialog returns -1 for the list index.

```lua
local vehicleDialog = 42

addCommandHandler("vehicles", function(player)
    exports.samp:ShowPlayerDialog(player, vehicleDialog, 5, "Vehicles",
        "Vehicle\tPrice\nInfernus\t1000\nCheetah\t900", "Select", "Cancel")
end)

addEventHandler("onPlayerDialogResponse", resourceRoot,
    function(player, id, response, listitem, inputtext)
        if id == vehicleDialog and response == 1 then
            outputChatBox("Selected " .. inputtext, player)
        end
    end, false)
```

The frontend uses the installed SA-MP control atlas and Arial Bold. The R5 dialog draw routine at RVA 0x6F890 uses the smaller game font with four black outline passes for message text and tab-list headers. Captions use the DXUT font and a one-pixel diagonal shadow. List entries use the DXUT list font. R5 layout and response routines at RVAs 0x6FFB0 and 0x70630 supply the list size bounds, four-column limit, and 128-byte reply limit. The MTA implementation preserves UTF-8 character boundaries when applying byte limits.

Dialog captions, prompts, button labels, list items, and tab-list headers accept {RRGGBB} tags with six case-insensitive hexadecimal digits. A prompt keeps its color across line breaks. Each list row and each tab-list cell starts with its own default color. List responses return the selected first cell with valid tags removed. Input and password responses preserve the typed text, including braces and tags.
