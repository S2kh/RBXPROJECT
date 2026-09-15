# RBXPROJECT

Roblox executor UI library. `Main.lua` is the library and nothing else. A caller script loads it, opens a window, and decides which tabs to draw. See `Example.lua` for a complete caller.

## Loading

```lua
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/S2kh/RBXPROJECT/main/Main.lua?v=" .. tick()))()
```

That one line is the whole loader. `Example.lua` shows a complete caller built on top of it. The `?v=` .. tick() forces a fresh copy every inject; `raw.githubusercontent.com` otherwise serves a cached `Main.lua` for a few minutes after a push, so a plain URL can load stale code right after an update. Drop the query once the script is stable if you prefer the CDN cache.

## Window

```lua
local Window = Library.new({
    Title     = "My Script",   -- title bar
    Folder    = "MyScript",    -- workspace folder for configs
    AutoSave  = true,          -- write the active config on every change (off by default)
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
| `Tab:AddSubTab(name)` | Horizontal sub-tab inside a tab. Returns a tab: every element method works on it. The bar appears on the first call and the first sub-tab is selected |
| `Tab:SelectSubTab(sub)` | Switch sub-tab from code |
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
Tab:AddToggle({Name, Flag, Default, Callback})   -- three dots mark it bindable: click them or right-click the row for Always / Toggle / Hold
Tab:AddSlider({Name, Flag, Min, Max, Default, Step, Suffix, Callback})
Tab:AddButton({Name, Flag, Callback})   -- bindable: the key fires the button (click the dots or right-click)
Tab:AddDropdown({Name, Flag, Options, Default, Callback, Search, MaxVisible})   -- el:SetOptions(list) swaps options; bindable: the key steps to the next option
Tab:AddTextbox({Name, Flag, Default, Placeholder, Callback})
Tab:AddColorPicker({Name, Flag, Default = Color3 or "#RRGGBB", Callback})   -- Value is a Color3; saved in configs as hex
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

The workflow is explicit: type a name, press **New config** to create it from defaults, adjust your settings, then press **Save config** to write them. New refuses a name that already exists; Save and Set autoload refuse a name that has not been created yet. Nothing is written to disk unless you press Save (see AutoSave below).

**Auto-save** is its own switch, off by default and separate from Set autoload. The Config tab has an "Auto-save the active config" toggle; `AutoSave = true` in `Library.new` just sets its starting state. When off, nothing is written unless you press Save config. When on, every flag or keybind change writes the active config after a short debounce; a config becomes active when it is loaded, saved, or auto-loaded, and nothing is written while one is being applied. The toggle is standalone, so it is never stored inside a config.

Set autoload only records which config to apply on inject (via `Window:AutoLoad()`); it does not turn on auto-save.

## Re-execution

Running a caller script again unloads the previous window first, so there is never more than one menu.
