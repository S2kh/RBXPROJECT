# RBXPROJECT

Roblox executor UI library. `Main.lua` is the library and nothing else. A caller script loads it, opens a window, and decides which tabs to draw. See `Example.lua` for a complete caller.

## Loading

```lua
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/S2kh/RBXPROJECT/main/Main.lua"))()
```

That one line is the whole loader. `Example.lua` shows a complete caller built on top of it.

## Window

```lua
local Window = Library.new({
    Title     = "My Script",   -- title bar
    Folder    = "MyScript",    -- workspace folder for configs
    TintIcons = true,          -- recolour icons to the theme (white/mono PNGs). false for full-colour icons
    Settings  = true,          -- pinned UI Settings tab (menu key, unload)
    Config    = true,          -- pinned Config tab (new/load/save/delete/autoload)
    MenuKey   = Enum.KeyCode.Insert,
})
```

UI Settings and Config are built by the library and always sit at the bottom of the tab rail, after every caller tab.

| Method | What it does |
|---|---|
| `Window:AddTab(name, icon)` | New tab. `icon` is an asset id number, an `rbxassetid://` string, or nil for a letter tile |
| `Window:Notify(title, body, seconds)` | Toast in the bottom-right corner |
| `Window:SetVisible(bool)` | Show or hide the menu |
| `Window:SetMenuKey(Enum.KeyCode)` | Change the open/close key |
| `Window:OnUnload(fn)` | Register cleanup to run on unload |
| `Window:AutoLoad()` | Apply the autoload config. Call once after all tabs are built |
| `Window:Unload()` | Turn off every toggle, run OnUnload callbacks, disconnect tracked connections, destroy the GUI |

## Tab icons

Uploaded to Roblox and exposed as `Library.Icons`:

`Combat`, `Player`, `Visuals`, `World`, `Teleport`, `Misc`, `Settings`, `Config`

## Elements

Every element takes an options table. `Flag` is the key used in `Library.Flags` and in saved configs. It defaults to `Name`.

```lua
Tab:AddSection("Heading")
Tab:AddLabel("Some text")                        -- returns {Set = fn}
Tab:AddToggle({Name, Flag, Default, Callback})   -- right-click for keybind (Always / Toggle / Hold)
Tab:AddSlider({Name, Flag, Min, Max, Default, Step, Suffix, Callback})
Tab:AddButton({Name, Callback})
Tab:AddDropdown({Name, Flag, Options, Default, Callback, Search, MaxVisible})   -- el:SetOptions(list) swaps options
Tab:AddTextbox({Name, Flag, Default, Placeholder, Callback})
Tab:AddKeybind({Name, Flag, Default = Enum.KeyCode, Callback})   -- hidden on mobile
```

Elements return an object with `:Set(value, silent)`. Read current values from `Library.Flags.<Flag>` or drive an element with `Library.Elements.<Flag>:Set(v)`.

Dropdown lists scroll after `MaxVisible` rows (default 8). `Search = true` adds a filter box for long lists such as item catalogues; a filtered list renders at most `MaxRender` rows (default 60) and says how many more are hidden.

## Helpers

| Field | What it is |
|---|---|
| `Library.Connect(signal, fn)` | Connect and track. Use for RunService / UserInputService loops so Unload can disconnect them |
| `Library.Flags` | flag → current value |
| `Library.Elements` | flag → element object |
| `Library.Theme` | colour and font table |
| `Library.IsMobile` | true on touch devices without a keyboard |
| `Library.Storage` | file-backed config storage |

## Configs

Stored as `<Folder>/configs/<name>.json` in the executor workspace. `<Folder>/autoload.txt` names the config to apply on inject. Falls back to session memory when the executor has no file API.

## Re-execution

Running a caller script again unloads the previous window first, so there is never more than one menu.

## Scripts

| Script | Loader |
|---|---|
| Blade Ball: auto parry, sword and explosion skins, emote unlock | `loadstring(game:HttpGet("https://raw.githubusercontent.com/S2kh/RBXPROJECT/main/scripts/BladeBall.lua"))()` |

The Blade Ball cosmetics are client-side only. They wrap the game's own controller tables (sword controller, VFX controller, emote controller, inventory client) so the game renders the swap itself. Emote wheel slot assignments are saved to `BladeBall/emote_wheel.json`.
