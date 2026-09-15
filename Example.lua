--[[
	Example caller script. Loads the library from GitHub and draws a menu with it.
	Copy this file as the starting point for a new script. Everything here is optional except
	Library.new and Window:AutoLoad.
]]

-- ---------------------------------------------------------------- loader
-- The ?v=<time> defeats the raw.githubusercontent CDN cache so every inject pulls the latest Main.lua.
-- Drop the query once the script is stable if you want the CDN to cache it again.
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/S2kh/RBXPROJECT/main/Main.lua?v=" .. tick()))()

-- ---------------------------------------------------------------- window
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local Window = Library.new({
	Title  = "Example",     -- title bar text
	Folder = "Example",     -- executor workspace folder for configs: Example/configs/*.json
	-- TintIcons = false,   -- set when icons are full-colour PNGs
	-- Settings = false,    -- drop the pinned UI Settings tab
	-- Config = false,      -- drop the pinned Config tab
	-- MenuKey = Enum.KeyCode.Insert,
	-- AutoSave = true,     -- opt-in, off by default: nothing writes to disk unless you press Save config
})

local function getHumanoid()
	local c = LocalPlayer.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

-- ---------------------------------------------------------------- tabs
-- Caller tabs appear in the order they're added. UI Settings and Config always sit below them.
local Player = Window:AddTab("Player", Library.Icons.Player)
Player:AddSection("Movement")
Player:AddSlider({Name = "Walk speed", Flag = "WalkSpeed", Min = 16, Max = 250, Default = 16, Callback = function(v)
	local hum = getHumanoid()
	if hum then hum.WalkSpeed = v end
end})

local noclip = false
-- Three stacked dots sit left of each toggle's switch (desktop) to mark it right-clickable. Right-click
-- opens the keybind popup to pick Always / Toggle / Hold; the dots become a keycap once a key is bound.
Player:AddToggle({Name = "Noclip", Flag = "Noclip", Callback = function(v) noclip = v end})
-- Library.Connect tracks the connection so Unload disconnects it.
Library.Connect(RunService.Stepped, function()
	if not noclip then return end
	local c = LocalPlayer.Character
	if not c then return end
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
	end
end)

local infJump = false
Player:AddToggle({Name = "Infinite jump", Flag = "InfJump", Callback = function(v) infJump = v end})
Library.Connect(UIS.JumpRequest, function()
	local hum = infJump and getHumanoid()
	if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

local Visuals = Window:AddTab("Visuals", Library.Icons.Visuals)
Visuals:AddSection("ESP")
Visuals:AddToggle({Name = "Box ESP", Flag = "BoxESP", Callback = function(v) print("Box ESP", v) end})
Visuals:AddDropdown({Name = "Box colour", Flag = "BoxColour", Options = {"Red", "Green", "Blue"}})
Visuals:AddSlider({Name = "Max distance", Flag = "ESPDistance", Min = 50, Max = 2000, Default = 500, Step = 50, Suffix = " studs"})
Visuals:AddTextbox({Name = "Custom label", Flag = "ESPLabel", Placeholder = "optional"})
Visuals:AddColorPicker({Name = "ESP colour", Flag = "ESPColor", Default = "#FF6B57", Callback = function(c) print("colour", c) end})

-- sub-tabs: a horizontal bar inside the tab, each with its own page
local World = Window:AddTab("World")
local Players_ = World:AddSubTab("Players")
Players_:AddToggle({Name = "Name tags", Flag = "NameTags", Default = true})
local Map = World:AddSubTab("Map")
Map:AddSlider({Name = "Fog", Flag = "Fog", Min = 0, Max = 100, Default = 0, Suffix = "%"})
Visuals:AddButton({Name = "Notify test", Callback = function() Window:Notify("Visuals", "Button pressed.") end})

-- Read any element's current value from Library.Flags, or drive it with Library.Elements.Flag:Set(v).
-- e.g. Library.Elements.WalkSpeed:Set(50)

-- Config tab (pinned, bottom of the rail): type a name, press "New config" to create it from
-- defaults, adjust the toggles/sliders above, then press "Save config" to write them. Save won't
-- touch a name that hasn't been created, and New won't overwrite one that already exists. With
-- AutoSave off (the default) nothing is written until you press Save.

-- Restore anything the script changed when the menu unloads.
Window:OnUnload(function()
	local hum = getHumanoid()
	if hum then hum.WalkSpeed = 16 end
end)

-- Must be last: applies the autoload config to the tabs above.
Window:AutoLoad()
Window:Notify("Example", "Loaded. Press " .. Library.MenuKey.Name .. " to toggle.")
