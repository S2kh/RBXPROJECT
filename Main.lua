--[[
	AdvancedMenu · Roblox Luau UI library (executor build)

	This file is the library only. A caller script loads it, opens a window, and decides which tabs to draw:

		local Library = loadstring(<this file's source>)()
		local Window  = Library.new({Title = "My Script", Folder = "MyScript"})
		local Combat  = Window:AddTab("Combat", Library.Icons.Combat)
		Combat:AddToggle({Name = "Aimbot", Flag = "Aimbot", Callback = function(v) end})
		Window:AutoLoad()   -- call once after every tab is built

	"UI Settings" and "Config" are built by the library itself and always sit at the bottom of the tab rail.
	Pass Settings = false / Config = false to Library.new to leave one out.

	Elements: Tab, Section, Toggle (right-click → keybind: Always / Toggle / Hold), Slider, Button,
	          Dropdown (with :SetOptions; Search = true for long lists), Textbox, Keybind, Label, Notify.
	Mobile:   no keybinds; hiding the menu shows a draggable floating icon that reopens it.
	PC:       hiding shows a notification "Press <MenuKey> to open the menu".

	Executor extras:
	  - GUI is parented to gethui() / CoreGui (protected where the executor supports it), PlayerGui as fallback.
	  - Configs persist to <Folder>/configs/<name>.json via writefile/readfile. Autoload name lives in <Folder>/autoload.txt.
	  - Re-executing unloads the previous window first. Window:Unload() tears everything down and runs Window:OnUnload callbacks.
	  - Library.Connect(signal, fn) tracks a connection so Unload disconnects it. Use it for RunService / UIS loops in caller scripts.
]]

local GLOBAL_KEY = "AdvancedMenu"
if getgenv and getgenv()[GLOBAL_KEY] and type(getgenv()[GLOBAL_KEY].Unload) == "function" then
	pcall(function() getgenv()[GLOBAL_KEY]:Unload() end)
end

local Players         = game:GetService("Players")
local UIS             = game:GetService("UserInputService")
local TweenService    = game:GetService("TweenService")
local HttpService     = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local IS_MOBILE   = UIS.TouchEnabled and not UIS.KeyboardEnabled

local THEME = {
	Bg       = Color3.fromRGB(16, 17, 20),
	Panel    = Color3.fromRGB(23, 24, 28),
	Element  = Color3.fromRGB(28, 29, 35),
	Hover    = Color3.fromRGB(38, 39, 47),
	Stroke   = Color3.fromRGB(44, 46, 54),
	Rail     = Color3.fromRGB(11, 12, 15),
	Keycap   = Color3.fromRGB(28, 30, 37),
	AccentDim  = Color3.fromRGB(44, 30, 31),
	AccentText = Color3.fromRGB(255, 143, 122),
	DangerDim  = Color3.fromRGB(46, 26, 29),
	Text     = Color3.fromRGB(236, 237, 241),
	SubText  = Color3.fromRGB(140, 144, 156),
	Accent   = Color3.fromRGB(255, 107, 87),
	Danger   = Color3.fromRGB(226, 82, 82),
	Font     = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	Radius   = 10,
}

local FAST   = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- ---------------------------------------------------------------- helpers
-- Every connection to a service signal (UIS, RunService, Players…) goes through connect() so Unload can kill it.
-- Connections on GUI objects die with the GUI and don't need tracking.
local CONNS = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(CONNS, c)
	return c
end

local function tween(obj, props, info)
	local t = TweenService:Create(obj, info or FAST, props)
	t:Play()
	return t
end

local function create(class, props, children)
	local obj = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then obj[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = obj end
	obj.Parent = props.Parent
	return obj
end

local function corner(r) return create("UICorner", {CornerRadius = UDim.new(0, r or THEME.Radius)}) end
local function stroke(c, t) return create("UIStroke", {Color = c or THEME.Stroke, Thickness = t or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}) end
local function padding(v, h)
	h = h or v
	return create("UIPadding", {PaddingTop = UDim.new(0, v), PaddingBottom = UDim.new(0, v), PaddingLeft = UDim.new(0, h), PaddingRight = UDim.new(0, h)})
end
local function list(pad, dir)
	return create("UIListLayout", {Padding = UDim.new(0, pad or 6), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = dir or Enum.FillDirection.Vertical})
end
local function label(props)
	local base = {BackgroundTransparency = 1, Font = THEME.Font, TextSize = 14, TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left}
	for k, v in pairs(props) do base[k] = v end
	return create("TextLabel", base)
end
local function hoverable(obj, base, hover)
	obj.MouseEnter:Connect(function() tween(obj, {BackgroundColor3 = hover}) end)
	obj.MouseLeave:Connect(function() tween(obj, {BackgroundColor3 = base}) end)
end
local function keycap(text, parent)
	return create("TextLabel", {Text = text, Font = Enum.Font.Code, TextSize = 11, TextColor3 = THEME.Text, BackgroundColor3 = THEME.Keycap, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Parent = parent}, {corner(6), stroke(Color3.fromRGB(62, 64, 74)), padding(0, 8)})
end
local function toKeyCode(name)
	local ok, key = pcall(function() return Enum.KeyCode[name] end)
	return ok and key or nil
end
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function makeDraggable(frame, handle)
	local dragging, startInput, startPos
	handle.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, startInput, startPos = true, input.Position, frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	connect(UIS.InputChanged, function(input)
		if dragging and isMove(input) then
			local d = input.Position - startInput
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

-- Where the ScreenGui lives. gethui() > CoreGui > PlayerGui. Protects it when the executor offers that.
local function guiParent(gui)
	if syn and syn.protect_gui then pcall(syn.protect_gui, gui) elseif protectgui then pcall(protectgui, gui) end
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and typeof(hui) == "Instance" then return hui end
	local okCore, core = pcall(function() return game:GetService("CoreGui") end)
	if okCore and core then
		local probe = Instance.new("Folder")
		local canParent = pcall(function() probe.Parent = core end)
		probe:Destroy()
		if canParent then return core end
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

-- ---------------------------------------------------------------- storage
-- File-backed when the executor exposes the file API, otherwise session memory.
--   <Folder>/configs/<name>.json   one file per config
--   <Folder>/autoload.txt          name of the config to apply on inject
local HAS_FS = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
	and type(listfiles) == "function" and type(isfolder) == "function" and type(makefolder) == "function" and type(delfile) == "function"

local Storage = {_mem = {}, Folder = "AdvancedMenu"}

local function safeName(name) return (tostring(name):gsub("[^%w%-_%. ]", "")) end
local function configPath(name) return Storage.Folder .. "/configs/" .. safeName(name) .. ".json" end

function Storage.init(folder)
	Storage.Folder = folder or Storage.Folder
	if not HAS_FS then return end
	pcall(function()
		if not isfolder(Storage.Folder) then makefolder(Storage.Folder) end
		if not isfolder(Storage.Folder .. "/configs") then makefolder(Storage.Folder .. "/configs") end
	end)
end
function Storage.list()
	local names = {}
	if HAS_FS then
		local ok, files = pcall(listfiles, Storage.Folder .. "/configs")
		for _, f in ipairs(ok and files or {}) do
			local n = tostring(f):match("([^/\\]+)%.json$")
			if n then table.insert(names, n) end
		end
	else
		for k in pairs(Storage._mem) do table.insert(names, k) end
	end
	table.sort(names)
	return names
end
function Storage.save(name, tbl)
	local raw = HttpService:JSONEncode(tbl)
	if HAS_FS then pcall(writefile, configPath(name), raw) else Storage._mem[safeName(name)] = raw end
end
function Storage.load(name)
	local raw
	if HAS_FS then
		local ok, data = pcall(function() return isfile(configPath(name)) and readfile(configPath(name)) or nil end)
		raw = ok and data or nil
	else
		raw = Storage._mem[safeName(name)]
	end
	if not raw then return nil end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and decoded or nil
end
function Storage.delete(name)
	if HAS_FS then pcall(function() if isfile(configPath(name)) then delfile(configPath(name)) end end)
	else Storage._mem[safeName(name)] = nil end
end
function Storage.getAutoload()
	if HAS_FS then
		local ok, n = pcall(function() local p = Storage.Folder .. "/autoload.txt"; return isfile(p) and readfile(p) or nil end)
		n = ok and n or nil
		if n and n ~= "" then return n end
		return nil
	end
	return Storage._autoload
end
function Storage.setAutoload(name)
	if HAS_FS then
		pcall(function()
			local p = Storage.Folder .. "/autoload.txt"
			if name then writefile(p, name) elseif isfile(p) then delfile(p) end
		end)
	else
		Storage._autoload = name
	end
end

-- ---------------------------------------------------------------- library
local Library = {
	Flags = {},      -- flag -> current value
	Elements = {},   -- flag -> element object (has :Set)
	Binds = {},      -- flag -> {Key = Enum.KeyCode, Mode = "Always"|"Toggle"|"Hold"}
	MenuKey = Enum.KeyCode.Insert,
	Storage = Storage,
	Theme = THEME,
	Connect = connect,
	IsMobile = IS_MOBILE,
	-- Tab icons uploaded to Roblox. Pass one to Window:AddTab(name, Library.Icons.X).
	Icons = {
		Combat   = 119168694531898,
		Player   = 127505433136549,
		Visuals  = 84745516177083,
		World    = 93371680357706,
		Teleport = 85674376575351,
		Misc     = 110695217426888,
		Settings = 87862881290117,
		Config   = 105363416845572,
	},
}
Library.__index = Library
local Tab = {}
Tab.__index = Tab

-- opts: Title, Name, Folder, TintIcons (default true), Settings (default true), Config (default true), MenuKey
function Library.new(opts)
	opts = opts or {}
	local self = setmetatable({Tabs = {}, Visible = true, Listening = false, TintIcons = opts.TintIcons ~= false, _unloadCallbacks = {}}, Library)
	if opts.MenuKey then Library.MenuKey = opts.MenuKey end
	self.AutoSave = opts.AutoSave == true
	Library._window = self
	Storage.init(opts.Folder)

	self.Gui = create("ScreenGui", {
		Name = opts.Name or "AdvancedMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	self.Gui.Parent = guiParent(self.Gui)

	self.Main = create("Frame", {
		Name = "Main", Size = UDim2.fromOffset(680, 480), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = self.Gui,
	}, {corner(16), stroke(Color3.fromRGB(58, 60, 70)), create("UIGradient", {Rotation = 65, Color = ColorSequence.new(Color3.fromRGB(23, 25, 32), Color3.fromRGB(15, 16, 20))})})
	self.Scale = create("UIScale", {Scale = 1, Parent = self.Main})

	-- title bar
	local titleBar = create("Frame", {Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, Parent = self.Main})
	local dot = create("Frame", {Size = UDim2.fromOffset(9, 9), Position = UDim2.fromOffset(20, 23), BackgroundColor3 = THEME.Accent, Parent = titleBar}, {corner(5), stroke(THEME.Accent, 3)})
	dot.UIStroke.Transparency = 0.7
	TweenService:Create(dot.UIStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = 0.95, Thickness = 6}):Play()
	-- light sweep across the title bar on open
	self.Main.ClipsDescendants = true
	self.Shine = create("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 0, Parent = titleBar}, {corner(16),
		create("UIGradient", {Rotation = 15, Offset = Vector2.new(-1.5, 0), Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 0.4), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.58, 0.4), NumberSequenceKeypoint.new(1, 1)})})})
	label({Text = opts.Title or "Menu", Font = THEME.FontBold, TextSize = 15, Size = UDim2.new(1, -160, 1, 0), Position = UDim2.fromOffset(40, 0), Parent = titleBar})
	if IS_MOBILE then
		label({Text = "Mobile", TextSize = 12, TextColor3 = THEME.SubText, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(120, 54), Position = UDim2.new(1, -56, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = titleBar})
	else
		label({Text = "toggle", TextSize = 11, TextColor3 = THEME.SubText, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(60, 54), Position = UDim2.new(1, -150, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = titleBar})
		self.KeyChip = keycap(Library.MenuKey.Name, titleBar)
		self.KeyChip.Position = UDim2.new(1, -56, 0.5, 0)
		self.KeyChip.AnchorPoint = Vector2.new(1, 0.5)
	end
	local hideBtn = create("TextButton", {
		Text = "–", Font = THEME.FontBold, TextSize = 16, TextColor3 = THEME.SubText, AutoButtonColor = false,
		Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -14, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = THEME.Element, Parent = titleBar,
	}, {corner(8), stroke()})
	hoverable(hideBtn, THEME.Element, THEME.Hover)
	hideBtn.MouseButton1Click:Connect(function() self:SetVisible(false) end)
	makeDraggable(self.Main, titleBar)

	-- resize grip (bottom-right corner). Min 480x340, max 1200x900.
	local grip = create("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1), ZIndex = 5, Parent = self.Main})
	create("Frame", {Size = UDim2.fromOffset(12, 2), Position = UDim2.new(1, -6, 1, -10), AnchorPoint = Vector2.new(1, 0.5), Rotation = -45, BackgroundColor3 = THEME.SubText, BorderSizePixel = 0, Parent = grip}, {corner(1)})
	create("Frame", {Size = UDim2.fromOffset(6, 2), Position = UDim2.new(1, -6, 1, -5), AnchorPoint = Vector2.new(1, 0.5), Rotation = -45, BackgroundColor3 = THEME.SubText, BorderSizePixel = 0, Parent = grip}, {corner(1)})
	local resizing, rStart, rSize, rPos
	grip.InputBegan:Connect(function(i)
		if isPress(i) then
			resizing, rStart, rSize, rPos = true, i.Position, self.Main.Size, self.Main.Position
			i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then resizing = false end end)
		end
	end)
	connect(UIS.InputChanged, function(i)
		if resizing and isMove(i) then
			local d = i.Position - rStart
			local w = math.clamp(rSize.X.Offset + d.X, 480, 1200)
			local h = math.clamp(rSize.Y.Offset + d.Y, 420, 900)
			self.Main.Size = UDim2.fromOffset(w, h)
			-- anchor is centered, so shift position by half the growth to keep the top-left corner still
			self.Main.Position = UDim2.new(rPos.X.Scale, rPos.X.Offset + (w - rSize.X.Offset) / 2, rPos.Y.Scale, rPos.Y.Offset + (h - rSize.Y.Offset) / 2)
		end
	end)

	-- tab rail + content
	local rail = create("Frame", {Size = UDim2.new(0, 168, 1, -66), Position = UDim2.fromOffset(12, 54), BackgroundColor3 = THEME.Rail, Parent = self.Main}, {corner(12), stroke()})
	self.TabIndicator = create("Frame", {Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = THEME.AccentDim, Visible = false, ZIndex = 1, Parent = rail}, {corner(9), stroke(THEME.Accent)})
	self.TabIndicator.UIStroke.Transparency = 0.7
	self.TabList = create("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -70), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1, ZIndex = 2,
		ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = rail,
	}, {list(3)})
	create("Frame", {Size = UDim2.new(1, -16, 0, 1), Position = UDim2.new(0, 8, 1, -54), BackgroundColor3 = THEME.Stroke, BorderSizePixel = 0, Parent = rail})
	label({Text = "ACTIVE CONFIG", TextSize = 10, TextColor3 = THEME.SubText, Font = THEME.FontBold, Size = UDim2.new(1, -32, 0, 14), Position = UDim2.new(0, 16, 1, -44), Parent = rail})
	self.ConfigDot = create("Frame", {Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0, 16, 1, -25), BackgroundColor3 = THEME.Stroke, Parent = rail}, {corner(3)})
	self.ConfigLabel = label({Text = "None", TextSize = 12, TextColor3 = THEME.Text, Size = UDim2.new(1, -44, 0, 16), Position = UDim2.new(0, 28, 1, -30), Parent = rail})
	self.Content = create("Frame", {Size = UDim2.new(1, -204, 1, -66), Position = UDim2.fromOffset(192, 54), BackgroundTransparency = 1, ClipsDescendants = true, Parent = self.Main})

	-- notifications
	self.NotifHolder = create("Frame", {
		Size = UDim2.fromOffset(300, 500), Position = UDim2.new(1, -20, 1, -20), AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1, Parent = self.Gui,
	}, {create("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right})})

	if IS_MOBILE then self:_buildMobileIcon() end
	self:_bindInput()
	self.Main.Visible = false
	self:SetVisible(true)

	-- pinned tabs: always present, always last in the rail
	if opts.Settings ~= false then self:_buildSettingsTab(opts.SettingsName, opts.SettingsIcon) end
	if opts.Config ~= false then self:AddConfigTab(opts.ConfigName, opts.ConfigIcon) end

	if getgenv then getgenv()[GLOBAL_KEY] = self end
	return self
end

-- Registers a function to run when the window unloads (clean up drawings, restore state, etc).
function Library:OnUnload(fn)
	table.insert(self._unloadCallbacks, fn)
end

function Library:_buildSettingsTab(name, icon)
	local tab = self:AddTab(name or "UI Settings", icon or Library.Icons.Settings, true)
	tab:AddSection("Menu")
	tab:AddKeybind({Name = "Open / close menu", Flag = "MenuKey", Default = Library.MenuKey, Callback = function(key)
		self:SetMenuKey(key)
		self:Notify("Menu keybind", "Now bound to " .. key.Name)
	end})
	tab:AddButton({Name = "Test notification", Callback = function() self:Notify("Hello", "Notifications are working.") end})
	tab:AddSection("Script")
	tab:AddButton({Name = "Unload", Callback = function() self:Unload() end})
	tab:AddLabel(IS_MOBILE and "Tap the – button to shrink the menu into a floating icon. Tap the icon to bring it back."
		or "Right-click any toggle to give it a keybind and pick Always, Toggle or Hold.")
	self.SettingsTab = tab
	return tab
end

-- open / close ---------------------------------------------------------------
function Library:SetMenuKey(key)
	Library.MenuKey = key
	if self.KeyChip then self.KeyChip.Text = key.Name end
end

function Library:SetVisible(v)
	if v == self.Visible and self.Main.Visible == v then return end
	self.Visible = v
	if v then
		self.Main.Visible = true
		self.Scale.Scale = 0.9
		tween(self.Scale, {Scale = 1}, SPRING)
		if self.Shine then
			self.Shine.UIGradient.Offset = Vector2.new(-1.5, 0)
			tween(self.Shine.UIGradient, {Offset = Vector2.new(1.5, 0)}, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		end
		for i, t in ipairs(self.Tabs) do
			t.Scale.Scale = 0.85
			task.delay(0.04 * (i - 1), function() tween(t.Scale, {Scale = 1}, SPRING) end)
		end
		if self.MobileIcon then self.MobileIcon.Visible = false end
	else
		if self.Popup then self.Popup:Destroy(); self.Popup = nil end
		if self.PopupBlur then self.PopupBlur:Destroy(); self.PopupBlur = nil end
		tween(self.Scale, {Scale = 0.9}, FAST).Completed:Connect(function()
			if not self.Visible then self.Main.Visible = false end
		end)
		if IS_MOBILE then
			self.MobileIcon.Visible = true
			self.MobileIcon.Size = UDim2.fromOffset(0, 0)
			tween(self.MobileIcon, {Size = UDim2.fromOffset(56, 56)}, SPRING)
		else
			self:Notify("Menu hidden", "Press " .. Library.MenuKey.Name .. " to open the menu")
		end
	end
end

-- Disconnects every tracked service connection, destroys the GUI, clears the global handle.
-- Toggle callbacks are called with false first so features (noclip, fullbright…) restore themselves.
function Library:Unload()
	if self.Unloaded then return end
	self.Unloaded = true
	for _, el in pairs(Library.Elements) do
		if el.Type == "Toggle" and el.Value then pcall(el.Set, el, false) end
	end
	for _, fn in ipairs(self._unloadCallbacks) do pcall(fn) end
	for _, c in ipairs(CONNS) do pcall(function() c:Disconnect() end) end
	table.clear(CONNS)
	if self.Popup then self.Popup:Destroy() end
	if self.PopupBlur then self.PopupBlur:Destroy() end
	self.Gui:Destroy()
	if getgenv then getgenv()[GLOBAL_KEY] = nil end
end

function Library:_buildMobileIcon()
	local icon = create("TextButton", {
		Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(56, 56), Position = UDim2.new(0, 20, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = THEME.Panel, Visible = false, Parent = self.Gui,
	}, {corner(28), stroke(Color3.fromRGB(62, 64, 74))})
	for i = -1, 1 do
		create("Frame", {Size = UDim2.fromOffset(18, 2), Position = UDim2.new(0.5, 0, 0.5, i * 6), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0, Parent = icon}, {corner(1)})
	end
	local moved = false
	icon.InputBegan:Connect(function(i) if isPress(i) then moved = false end end)
	icon.InputChanged:Connect(function(i) if isMove(i) then moved = true end end)
	icon.InputEnded:Connect(function(i) if isPress(i) and not moved then self:SetVisible(true) end end)
	makeDraggable(icon, icon)
	self.MobileIcon = icon
end

-- global keybinds --------------------------------------------------------------
function Library:_bindInput()
	connect(UIS.InputBegan, function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard or gameProcessed or self.Listening then return end
		if input.KeyCode == Library.MenuKey then self:SetVisible(not self.Visible) return end
		for flag, bind in pairs(Library.Binds) do
			local el = Library.Elements[flag]
			if el and bind.Key == input.KeyCode then
				if bind.Mode == "Toggle" then el:Set(not el.Value)
				elseif bind.Mode == "Hold" then el:Set(true) end
			end
		end
	end)
	connect(UIS.InputEnded, function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		for flag, bind in pairs(Library.Binds) do
			local el = Library.Elements[flag]
			if el and bind.Key == input.KeyCode and bind.Mode == "Hold" then el:Set(false) end
		end
	end)
end

-- Waits for one key press. cb(keyCode|nil). Escape cancels.
function Library:ListenForKey(cb)
	self.Listening = true
	local conn
	conn = UIS.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		conn:Disconnect()
		task.defer(function() self.Listening = false end)
		cb(input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode or nil)
	end)
end

-- notifications ----------------------------------------------------------------
function Library:Notify(title, body, duration)
	duration = duration or 3.5
	local slot = create("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ClipsDescendants = true, Parent = self.NotifHolder})
	local card = create("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(320, 0), BackgroundColor3 = THEME.Panel, Parent = slot}, {corner(12), stroke(Color3.fromRGB(58, 60, 70))})
	local inner = create("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card}, {
		create("UIPadding", {PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 14)}), list(2)})
	label({Text = title, Font = THEME.FontBold, TextSize = 13, Size = UDim2.new(1, 0, 0, 16), Parent = inner})
	label({Text = body or "", TextSize = 12, TextColor3 = THEME.SubText, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = inner})
	create("Frame", {Size = UDim2.new(0, 3, 1, -20), Position = UDim2.fromOffset(0, 10), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0, Parent = card}, {corner(2)})
	local bar = create("Frame", {Size = UDim2.new(1, -24, 0, 2), Position = UDim2.new(0, 12, 1, -2), BackgroundColor3 = THEME.Accent, BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = card})
	tween(card, {Position = UDim2.new()}, SPRING)
	tween(bar, {Size = UDim2.new(0, 0, 0, 2)}, TweenInfo.new(duration, Enum.EasingStyle.Linear))
	task.delay(duration, function()
		if not slot.Parent then return end
		tween(card, {Position = UDim2.fromOffset(320, 0)}, FAST).Completed:Wait()
		slot:Destroy()
	end)
end

-- tabs -------------------------------------------------------------------------
-- icon: image asset id (number) or a full "rbxassetid://…" string. Omit for a letter tile.
-- Icons are tinted to match the theme when Library.new({TintIcons = true}) (default). Set false for full-colour icons.
-- pinned (internal): pinned tabs sort after every caller tab and are never auto-selected when a caller tab exists.
function Library:AddTab(name, icon, pinned)
	local tab = setmetatable({Name = name, Window = self, Pinned = pinned or false}, Tab)
	self._tabCount = (self._tabCount or 0) + 1
	tab.Button = create("TextButton", {
		Text = name, Font = THEME.Font, TextSize = 13, TextColor3 = THEME.SubText, TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = THEME.Element, BackgroundTransparency = 1,
		LayoutOrder = (pinned and 10000 or 0) + self._tabCount, Parent = self.TabList,
	}, {corner(9), create("UIPadding", {PaddingLeft = UDim.new(0, 42)})})
	tab.Scale = create("UIScale", {Parent = tab.Button})
	tab.Tile = create("TextLabel", {Text = icon and "" or string.sub(name, 1, 1), Font = THEME.FontBold, TextSize = 12, TextColor3 = THEME.SubText, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, -34, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = THEME.Element, Parent = tab.Button}, {corner(7)})
	tab.TileScale = create("UIScale", {Parent = tab.Tile})
	if icon then
		tab.Icon = create("ImageLabel", {
			Image = type(icon) == "number" and ("rbxassetid://" .. icon) or icon,
			ImageColor3 = self.TintIcons and THEME.SubText or Color3.new(1, 1, 1),
			BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = tab.Tile,
		})
	end
	tab.Page = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ScrollBarThickness = 3,
		ScrollBarImageColor3 = THEME.Stroke, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = self.Content,
	}, {list(6), create("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)})})
	tab.Button.MouseButton1Click:Connect(function() self:SelectTab(tab) end)
	tab.Button.MouseEnter:Connect(function() if self.CurrentTab ~= tab then tween(tab.Button, {BackgroundTransparency = 0}) end end)
	tab.Button.MouseLeave:Connect(function() if self.CurrentTab ~= tab then tween(tab.Button, {BackgroundTransparency = 1}) end end)
	table.insert(self.Tabs, tab)
	-- first tab gets selected; a caller tab added after only pinned ones takes over the selection
	if not self.CurrentTab or (self.CurrentTab.Pinned and not pinned) then self:SelectTab(tab) end
	return tab
end

function Library:SelectTab(tab)
	self.CurrentTab = tab
	for i, t in ipairs(self.Tabs) do
		local on = t == tab
		t.Page.Visible = on
		tween(t.Button, {BackgroundTransparency = 1, TextColor3 = on and THEME.Text or THEME.SubText})
		tween(t.Tile, {BackgroundColor3 = on and THEME.Accent or THEME.Element, TextColor3 = on and THEME.Bg or THEME.SubText})
		if t.Icon and self.TintIcons then tween(t.Icon, {ImageColor3 = on and THEME.Bg or THEME.SubText}) end
		if on then
			-- sliding highlight + icon bounce. Rail position comes from LayoutOrder rank, since pinned tabs sort last regardless of add order.
			local rank = 0
			for _, o in ipairs(self.Tabs) do
				if o.Button.LayoutOrder < t.Button.LayoutOrder then rank += 1 end
			end
			self.TabIndicator.Visible = true
			tween(self.TabIndicator, {Position = UDim2.fromOffset(8, 8 + rank * 39)}, SPRING)
			t.TileScale.Scale = 1
			tween(t.TileScale, {Scale = 1.25}, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)).Completed:Connect(function()
				tween(t.TileScale, {Scale = 1}, SPRING)
			end)
		end
	end
	tab.Page.Position = UDim2.fromOffset(0, 14)
	tween(tab.Page, {Position = UDim2.new()}, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
	-- staggered pop-in of the rows
	local n = 0
	for _, child in ipairs(tab.Page:GetChildren()) do
		local sc = child:IsA("GuiObject") and child:FindFirstChildOfClass("UIScale")
		if sc then
			n += 1
			sc.Scale = 0.94
			task.delay((n - 1) * 0.03, function() tween(sc, {Scale = 1}, SPRING) end)
		end
	end
end

-- element rows -----------------------------------------------------------------
local function row(tab, height)
	local f = create("Frame", {Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = THEME.Element, Parent = tab.Page}, {corner(), stroke(Color3.fromRGB(38, 40, 47)), create("UIScale", {})})
	hoverable(f, THEME.Element, THEME.Hover)
	return f
end

-- Autosave: with Library.new({AutoSave = true}), every flag or bind change writes the active config a
-- moment later (debounced), so nothing is lost to a forgotten Save. Nothing is written while a config is
-- being applied, and nothing until a config has been loaded or saved once, which makes it the active one.
local autosaveToken = 0
local function touch()
	local w = Library._window
	if not (w and w.AutoSave and w.ActiveConfig) or w._applying then return end
	autosaveToken += 1
	local token = autosaveToken
	task.delay(0.8, function()
		if token ~= autosaveToken then return end
		if w.AutoSave and w.ActiveConfig and not w._applying then Storage.save(w.ActiveConfig, w:Serialize()) end
	end)
end

local function register(el, opts)
	el.Flag = opts.Flag or opts.Name
	el.Default = el.Value
	el.Callback = opts.Callback or function() end
	Library.Elements[el.Flag] = el
	Library.Flags[el.Flag] = el.Value
end

function Tab:AddSection(text)
	label({Text = string.upper(text), Font = THEME.FontBold, TextSize = 11, TextColor3 = THEME.SubText, Size = UDim2.new(1, 0, 0, 24), Parent = self.Page})
	return self
end

function Tab:AddLabel(text)
	local l = label({Text = text, TextSize = 13, TextColor3 = THEME.SubText, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = self.Page})
	return {Set = function(_, t) l.Text = t end}
end

function Tab:AddToggle(opts)
	local window = self.Window
	local el = {Type = "Toggle", Value = opts.Default or false}
	register(el, opts)
	local f = row(self, 46)
	local hit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = f})
	label({Text = opts.Name, Size = UDim2.new(1, -200, 1, 0), Position = UDim2.fromOffset(14, 0), Parent = f})
	local bindRow = create("Frame", {Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(1, -68, 0, 0), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1, Visible = false, Parent = f}, {
		create("UIListLayout", {Padding = UDim.new(0, 6), FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder})})
	local bindKey = keycap("", bindRow)
	local bindMode = label({Text = "", Font = Enum.Font.Code, TextSize = 11, TextColor3 = THEME.AccentText, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = bindRow})
	local track = create("Frame", {Size = UDim2.fromOffset(42, 24), Position = UDim2.new(1, -14, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = THEME.Stroke, Parent = f}, {corner(12), stroke(THEME.Accent, 3)})
	track.UIStroke.Transparency = 1
	local knob = create("Frame", {Size = UDim2.fromOffset(18, 18), Position = UDim2.new(0, 3, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = track}, {corner(9)})

	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		touch()
		tween(track, {BackgroundColor3 = v and THEME.Accent or THEME.Stroke})
		tween(knob, {Position = v and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)}, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		-- knob squish + ring pulse when switching on
		knob.Size = UDim2.fromOffset(22, 14)
		tween(knob, {Size = UDim2.fromOffset(18, 18)}, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		if v then
			track.UIStroke.Thickness, track.UIStroke.Transparency = 3, 0.4
			tween(track.UIStroke, {Thickness = 10, Transparency = 1}, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)).Completed:Connect(function()
				if self.Value then track.UIStroke.Thickness = 3; tween(track.UIStroke, {Transparency = 0.6}) end
			end)
		else
			tween(track.UIStroke, {Transparency = 1})
		end
		if not silent then self.Callback(v) end
	end
	function el:RefreshBind()
		local b = Library.Binds[self.Flag]
		bindRow.Visible = b ~= nil
		if b then bindKey.Text = b.Key.Name; bindMode.Text = string.upper(b.Mode) end
	end

	hit.MouseButton1Click:Connect(function()
		local b = Library.Binds[el.Flag]
		if b and b.Mode == "Always" then
			window:Notify("Locked on", opts.Name .. " is bound as Always. Right-click it to change.")
			return
		end
		el:Set(not el.Value)
	end)
	if not IS_MOBILE then
		hit.MouseButton2Click:Connect(function() window:_openBindPopup(el, opts.Name) end)
	end
	el:Set(el.Value, true)
	return el
end

function Library:_openBindPopup(el, name)
	if self.Popup then self.Popup:Destroy() end
	if self.PopupBlur then self.PopupBlur:Destroy() end
	local blur = create("BlurEffect", {Size = 0, Parent = game:GetService("Lighting")})
	self.PopupBlur = blur
	tween(blur, {Size = 14}, TweenInfo.new(0.3))
	local overlay = create("TextButton", {Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 20, Parent = self.Main}, {corner(12)})
	self.Popup = overlay
	tween(overlay, {BackgroundTransparency = 0.45})
	local box = create("Frame", {Active = true, Size = UDim2.fromOffset(280, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = THEME.Panel, ZIndex = 21, Parent = overlay}, {corner(12), stroke(), padding(16), list(10)})
	local scale = create("UIScale", {Scale = 0.85, Parent = box})
	tween(scale, {Scale = 1}, SPRING)

	local bind = Library.Binds[el.Flag] and table.clone(Library.Binds[el.Flag]) or {Key = nil, Mode = "Toggle"}

	label({Text = "Keybind · " .. name, Font = THEME.FontBold, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), ZIndex = 22, Parent = box})
	local keyBtn = create("TextButton", {Text = bind.Key and bind.Key.Name or "Click, then press a key", Font = THEME.Font, TextSize = 13, TextColor3 = THEME.Text, AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = THEME.Element, ZIndex = 22, Parent = box}, {corner(), stroke()})
	hoverable(keyBtn, THEME.Element, THEME.Hover)

	local modeRow = create("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = THEME.Rail, ZIndex = 22, Parent = box}, {corner(10), stroke(), padding(4), list(4, Enum.FillDirection.Horizontal)})
	local modeBtns = {}
	local function refreshModes()
		for mode, b in pairs(modeBtns) do
			local on = mode == bind.Mode
			tween(b, {BackgroundColor3 = on and THEME.Accent or THEME.Rail, TextColor3 = on and THEME.Bg or THEME.SubText})
		end
	end
	local function apply()
		if bind.Key then
			Library.Binds[el.Flag] = {Key = bind.Key, Mode = bind.Mode}
			if bind.Mode == "Always" then el:Set(true) end
		else
			Library.Binds[el.Flag] = nil
		end
		touch()
		el:RefreshBind()
	end
	for _, mode in ipairs({"Always", "Toggle", "Hold"}) do
		local b = create("TextButton", {Text = mode, Font = THEME.FontBold, TextSize = 12, AutoButtonColor = false, Size = UDim2.new(1 / 3, -3, 1, 0), BackgroundColor3 = THEME.Rail, TextColor3 = THEME.SubText, ZIndex = 22, Parent = modeRow}, {corner(7)})
		modeBtns[mode] = b
		b.MouseButton1Click:Connect(function() bind.Mode = mode; refreshModes(); apply() end)
	end
	refreshModes()
	label({Text = "Always: locked on.  Toggle: key flips it.  Hold: on only while the key is held.", TextSize = 11, TextColor3 = THEME.SubText, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 22, Parent = box})

	local footer = create("Frame", {Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, ZIndex = 22, Parent = box}, {list(6, Enum.FillDirection.Horizontal)})
	local unbind = create("TextButton", {Text = "Unbind", Font = THEME.FontBold, TextSize = 12, TextColor3 = THEME.Danger, AutoButtonColor = false, Size = UDim2.new(0.5, -3, 1, 0), BackgroundColor3 = THEME.DangerDim, ZIndex = 22, Parent = footer}, {corner(8)})
	local done = create("TextButton", {Text = "Done", Font = THEME.FontBold, TextSize = 12, TextColor3 = THEME.Bg, AutoButtonColor = false, Size = UDim2.new(0.5, -3, 1, 0), BackgroundColor3 = THEME.Accent, ZIndex = 22, Parent = footer}, {corner(8)})
	hoverable(unbind, THEME.DangerDim, THEME.Hover)
	hoverable(done, THEME.Accent, THEME.AccentText)

	local function close()
		self.Popup = nil
		self.PopupBlur = nil
		tween(blur, {Size = 0}, FAST).Completed:Connect(function() blur:Destroy() end)
		tween(scale, {Scale = 0.9})
		tween(overlay, {BackgroundTransparency = 1}).Completed:Wait()
		overlay:Destroy()
	end
	keyBtn.MouseButton1Click:Connect(function()
		keyBtn.Text = "Press a key…  (Esc to cancel)"
		self:ListenForKey(function(key)
			if key then bind.Key = key end
			keyBtn.Text = bind.Key and bind.Key.Name or "Click, then press a key"
			apply()
		end)
	end)
	unbind.MouseButton1Click:Connect(function() bind.Key = nil; apply(); close() end)
	done.MouseButton1Click:Connect(close)
	overlay.MouseButton1Click:Connect(close)
end

function Tab:AddSlider(opts)
	local min, max, step = opts.Min or 0, opts.Max or 100, opts.Step or 1
	local el = {Type = "Slider", Value = opts.Default or min}
	register(el, opts)
	local f = row(self, 64)
	label({Text = opts.Name, Size = UDim2.new(1, -100, 0, 30), Position = UDim2.fromOffset(14, 6), Parent = f})
	local valueLabel = create("TextLabel", {Text = "", TextSize = 11, TextColor3 = THEME.AccentText, Font = Enum.Font.Code, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(1, -14, 0, 10), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = THEME.AccentDim, Parent = f}, {corner(6), stroke(THEME.Accent), padding(0, 8)})
	valueLabel.UIStroke.Transparency = 0.6
	local chipScale = create("UIScale", {Parent = valueLabel})
	local track = create("Frame", {Size = UDim2.new(1, -28, 0, 4), Position = UDim2.new(0, 14, 1, -18), BackgroundColor3 = THEME.Stroke, BorderSizePixel = 0, Parent = f}, {corner(2)})
	local fill = create("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track}, {corner(2), create("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(201, 70, 58), THEME.Accent)})})
	local knob = create("Frame", {Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Parent = track}, {corner(7), stroke(THEME.Accent, 3)})
	local hit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 12, 0, 32), Position = UDim2.new(0, -6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = track})

	function el:Set(v, silent)
		v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
		self.Value = v
		Library.Flags[self.Flag] = v
		touch()
		local a = (v - min) / (max - min)
		tween(fill, {Size = UDim2.fromScale(a, 1)}, TweenInfo.new(0.06))
		tween(knob, {Position = UDim2.new(a, 0, 0.5, 0)}, TweenInfo.new(0.06))
		valueLabel.Text = (math.floor(v * 100 + 0.5) / 100) .. (opts.Suffix or "")
		chipScale.Scale = 1.12
		tween(chipScale, {Scale = 1}, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		if not silent then self.Callback(v) end
	end

	local dragging = false
	local function update(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		el:Set(min + a * (max - min))
	end
	hit.InputBegan:Connect(function(i) if isPress(i) then dragging = true; tween(knob, {Size = UDim2.fromOffset(18, 18)}); update(i.Position.X) end end)
	connect(UIS.InputEnded, function(i) if dragging and isPress(i) then dragging = false; tween(knob, {Size = UDim2.fromOffset(14, 14)}) end end)
	connect(UIS.InputChanged, function(i) if dragging and isMove(i) then update(i.Position.X) end end)
	el:Set(el.Value, true)
	return el
end

function Tab:AddButton(opts)
	local f = row(self, 42)
	f.ClipsDescendants = true
	local btn = create("TextButton", {Text = opts.Name, Font = THEME.FontBold, TextSize = 13, TextColor3 = THEME.Text, AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = f})
	local scale = f:FindFirstChildOfClass("UIScale")
	btn.MouseButton1Click:Connect(function()
		-- ripple from the click point
		local m = UIS:GetMouseLocation() - f.AbsolutePosition
		local r = create("Frame", {Size = UDim2.new(), Position = UDim2.fromOffset(m.X, m.Y), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = THEME.Accent, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 1, Parent = f}, {create("UICorner", {CornerRadius = UDim.new(1, 0)})})
		local d = f.AbsoluteSize.X * 2.2
		tween(r, {Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1}, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)).Completed:Connect(function() r:Destroy() end)
		scale.Scale = 0.97
		tween(scale, {Scale = 1}, SPRING)
		if opts.Callback then opts.Callback() end
	end)
	return f
end

-- Dropdown. el:SetOptions(list) swaps the option set at runtime (player lists, etc).
-- The open list scrolls past MaxVisible rows (default 8). Search = true adds a filter box for long lists; a
-- filtered list renders at most MaxRender rows (default 60) and says how many more the filter is hiding.
function Tab:AddDropdown(opts)
	opts.Options = opts.Options or {}
	local ROW, GAP = 28, 2
	local maxVisible = opts.MaxVisible or 8
	local maxRender  = opts.MaxRender or 60
	local el = {Type = "Dropdown", Value = opts.Default or opts.Options[1] or ""}
	register(el, opts)
	local f = row(self, 42)
	f.ClipsDescendants = true
	local hit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42), Parent = f})
	label({Text = opts.Name, Size = UDim2.new(0.5, 0, 0, 42), Position = UDim2.fromOffset(14, 0), Parent = f})
	local valueLabel = label({Text = "", TextSize = 13, TextColor3 = THEME.SubText, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(0.5, -40, 0, 42), Position = UDim2.new(1, -36, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = f})
	local arrow = label({Text = "v", Font = THEME.FontBold, TextSize = 12, TextColor3 = THEME.SubText, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(20, 42), Position = UDim2.new(1, -12, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = f})
	local listFrame = create("Frame", {Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(10, 44), BackgroundTransparency = 1, Parent = f}, {list(4)})
	local search
	if opts.Search then
		search = create("TextBox", {Text = "", PlaceholderText = "Search…", PlaceholderColor3 = THEME.SubText, Font = THEME.Font, TextSize = 13, TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Size = UDim2.new(1, 0, 0, ROW), BackgroundColor3 = THEME.Bg, LayoutOrder = 1, Parent = listFrame}, {corner(6), stroke(), padding(0, 8)})
	end
	local scroll = create("ScrollingFrame", {Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = THEME.Stroke, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, LayoutOrder = 2, Parent = listFrame}, {list(GAP)})
	local open = false
	local optionBtns, rendered = {}, 0
	local more

	local function listHeight()
		local rows = math.min(rendered, maxVisible)
		return rows * ROW + math.max(rows - 1, 0) * GAP
	end
	local function resize()
		local h = 42
		if open then h = 42 + (search and ROW + 4 or 0) + listHeight() + 8 end
		tween(f, {Size = UDim2.new(1, 0, 0, h)}, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
	end
	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		touch()
		valueLabel.Text = tostring(v)
		for name, b in pairs(optionBtns) do tween(b, {TextColor3 = name == v and THEME.Accent or THEME.Text}) end
		if not silent then self.Callback(v) end
	end
	local function setOpen(o)
		open = o
		resize()
		tween(arrow, {Rotation = o and 180 or 0})
	end
	local function build()
		for _, b in pairs(optionBtns) do b:Destroy() end
		optionBtns = {}
		if more then more:Destroy(); more = nil end
		local q = search and string.lower(search.Text) or ""
		local matched = 0
		rendered = 0
		for i, option in ipairs(opts.Options) do
			local text = tostring(option)
			if q == "" or string.find(string.lower(text), q, 1, true) then
				matched += 1
				if matched <= maxRender then
					rendered += 1
					local b = create("TextButton", {Text = text, Font = THEME.Font, TextSize = 13, TextColor3 = option == el.Value and THEME.Accent or THEME.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = false, Size = UDim2.new(1, -6, 0, ROW), BackgroundColor3 = THEME.Rail, LayoutOrder = i, Parent = scroll}, {corner(6), padding(0, 10)})
					hoverable(b, THEME.Rail, THEME.Hover)
					optionBtns[option] = b
					b.MouseButton1Click:Connect(function() el:Set(option); setOpen(false) end)
				end
			end
		end
		if matched > rendered then
			rendered += 1
			more = label({Text = ("%d more, keep typing"):format(matched - (rendered - 1)), TextSize = 11, TextColor3 = THEME.SubText, Size = UDim2.new(1, -6, 0, ROW), LayoutOrder = #opts.Options + 1, Parent = scroll})
		end
		scroll.Size = UDim2.new(1, 0, 0, listHeight())
		scroll.CanvasPosition = Vector2.zero
		if open then resize() end
	end
	function el:SetOptions(options, silent)
		opts.Options = options or {}
		build()
		if not table.find(opts.Options, self.Value) then self:Set(opts.Options[1] or "", silent) end
	end
	build()
	if search then search:GetPropertyChangedSignal("Text"):Connect(build) end
	hit.MouseButton1Click:Connect(function() setOpen(not open) end)
	el:Set(el.Value, true)
	return el
end

function Tab:AddTextbox(opts)
	local el = {Type = "Textbox", Value = opts.Default or ""}
	register(el, opts)
	local f = row(self, 42)
	label({Text = opts.Name, Size = UDim2.new(0.45, 0, 1, 0), Position = UDim2.fromOffset(14, 0), Parent = f})
	local box = create("TextBox", {Text = el.Value, PlaceholderText = opts.Placeholder or "", PlaceholderColor3 = THEME.SubText, Font = THEME.Font, TextSize = 13, TextColor3 = THEME.Text, ClearTextOnFocus = false, Size = UDim2.new(0.55, -26, 0, 28), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = THEME.Bg, Parent = f}, {corner(6), stroke(), padding(0, 8)})
	function el:Set(v, silent) self.Value = v; Library.Flags[self.Flag] = v; touch(); box.Text = v; if not silent then self.Callback(v) end end
	box.FocusLost:Connect(function() el:Set(box.Text) end)
	box.Focused:Connect(function() tween(box.UIStroke, {Color = THEME.Accent}) end)
	box.FocusLost:Connect(function() tween(box.UIStroke, {Color = THEME.Stroke}) end)
	return el
end

-- A standalone keybind row (e.g. the menu open/close key). Hidden on mobile.
function Tab:AddKeybind(opts)
	local window = self.Window
	local el = {Type = "Keybind", Value = opts.Default and opts.Default.Name or "None"}
	register(el, opts)
	if IS_MOBILE then
		function el:Set(v) self.Value = v end
		return el
	end
	local f = row(self, 42)
	label({Text = opts.Name, Size = UDim2.new(1, -140, 1, 0), Position = UDim2.fromOffset(14, 0), Parent = f})
	local btn = create("TextButton", {Text = el.Value, Font = THEME.FontBold, TextSize = 12, TextColor3 = THEME.Text, AutoButtonColor = false, Size = UDim2.fromOffset(110, 28), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = THEME.Bg, Parent = f}, {corner(6), stroke()})
	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		touch()
		btn.Text = v
		if not silent then self.Callback(toKeyCode(v)) end
	end
	btn.MouseButton1Click:Connect(function()
		btn.Text = "…"
		window:ListenForKey(function(key) el:Set(key and key.Name or el.Value) end)
	end)
	return el
end

-- config tab -------------------------------------------------------------------
function Library:Serialize()
	local binds = {}
	for flag, b in pairs(Library.Binds) do binds[flag] = {Key = b.Key.Name, Mode = b.Mode} end
	return {flags = Library.Flags, binds = binds, menuKey = Library.MenuKey.Name}
end

function Library:Apply(data)
	self._applying = true
	for flag, v in pairs(data.flags or {}) do
		local el = Library.Elements[flag]
		if el and el.Type ~= "Keybind" then el:Set(v) end
	end
	Library.Binds = {}
	for flag, b in pairs(data.binds or {}) do
		if toKeyCode(b.Key) then Library.Binds[flag] = {Key = toKeyCode(b.Key), Mode = b.Mode} end
	end
	for _, el in pairs(Library.Elements) do
		if el.RefreshBind then el:RefreshBind() end
		if el.Type == "Keybind" and data.flags and data.flags[el.Flag] then el:Set(data.flags[el.Flag]) end
	end
	if data.menuKey and toKeyCode(data.menuKey) then self:SetMenuKey(toKeyCode(data.menuKey)) end
	self._applying = false
end

-- Call once after every tab is built. Applies the autoload config if one is set.
function Library:AutoLoad()
	local n = Storage.getAutoload()
	if not n then return end
	local data = Storage.load(n)
	if not data then return end
	self:Apply(data)
	self.ActiveConfig = n
	if self.RefreshConfigList then self.RefreshConfigList() end
	self:Notify("Config", "Auto-loaded " .. n)
end

function Library:AddConfigTab(name, icon)
	local tab = self:AddTab(name or "Config", icon or Library.Icons.Config, true)
	self.ConfigTab = tab
	tab:AddSection("Config name")
	local nameRow = row(tab, 42)
	local nameBox = create("TextBox", {Text = "", PlaceholderText = "Enter a config name…", PlaceholderColor3 = THEME.SubText, Font = THEME.Font, TextSize = 14, TextColor3 = THEME.Text, ClearTextOnFocus = false, BackgroundTransparency = 1, Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(14, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = nameRow})

	local grid = create("Frame", {Size = UDim2.new(1, 0, 0, 132), BackgroundTransparency = 1, Parent = tab.Page}, {
		create("UIGridLayout", {CellSize = UDim2.new(0.5, -3, 0, 40), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder}),
	})
	tab:AddSection("Saved configs")
	tab:AddLabel(HAS_FS and ("Stored in " .. Storage.Folder .. "/configs") or "No file API detected: configs live in memory for this session only.")
	if self.AutoSave then tab:AddLabel("Changes save to the active config on their own. Load or save a config once to make it the active one.") end
	local autoloadLabel = tab:AddLabel("")
	local listHolder = create("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = tab.Page}, {list(4)})
	local empty = label({Text = "No configs yet.", TextSize = 13, TextColor3 = THEME.SubText, Size = UDim2.new(1, 0, 0, 24), Parent = listHolder})

	local function refreshList()
		for _, c in ipairs(listHolder:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		local names = Storage.list()
		local auto = Storage.getAutoload()
		empty.Visible = #names == 0
		autoloadLabel:Set("Autoload: " .. (auto or "none"))
		self.ConfigLabel.Text = self.ActiveConfig or "None"
		self.ConfigDot.BackgroundColor3 = self.ActiveConfig and THEME.Accent or THEME.Stroke
		for _, n in ipairs(names) do
			local active = n == self.ActiveConfig
			local b = create("TextButton", {Text = n .. (n == auto and "   · autoload" or ""), Font = THEME.Font, TextSize = 13, TextColor3 = active and THEME.Accent or THEME.Text, TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = THEME.Element, Parent = listHolder}, {corner(), padding(0, 14)})
			hoverable(b, THEME.Element, THEME.Hover)
			b.MouseButton1Click:Connect(function() nameBox.Text = n end)
		end
	end
	self.RefreshConfigList = refreshList

	local function getName()
		local n = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if n == "" then self:Notify("Config", "Type a config name first.") return nil end
		return n
	end
	local actions = {
		{"New", function()
			local n = getName(); if not n then return end
			for _, el in pairs(Library.Elements) do if el.Set and el.Default ~= nil then el:Set(el.Default) end end
			Library.Binds = {}
			for _, el in pairs(Library.Elements) do if el.RefreshBind then el:RefreshBind() end end
			Storage.save(n, self:Serialize()); self.ActiveConfig = n; refreshList()
			self:Notify("Config created", n .. " starts from defaults.")
		end},
		{"Load", function()
			local n = getName(); if not n then return end
			local data = Storage.load(n)
			if not data then self:Notify("Config", "No config named " .. n) return end
			self:Apply(data); self.ActiveConfig = n; refreshList()
			self:Notify("Config loaded", n)
		end},
		{"Save", function()
			local n = getName(); if not n then return end
			Storage.save(n, self:Serialize()); self.ActiveConfig = n; refreshList()
			self:Notify("Config saved", n)
		end},
		{"Delete", function()
			local n = getName(); if not n then return end
			Storage.delete(n)
			if self.ActiveConfig == n then self.ActiveConfig = nil end
			if Storage.getAutoload() == n then Storage.setAutoload(nil) end
			refreshList(); self:Notify("Config deleted", n)
		end},
		{"Set autoload", function()
			local n = getName(); if not n then return end
			if not Storage.load(n) then self:Notify("Config", "Save " .. n .. " first.") return end
			Storage.setAutoload(n); refreshList()
			self:Notify("Autoload", n .. " will load on inject.")
		end},
		{"Clear autoload", function()
			Storage.setAutoload(nil); refreshList()
			self:Notify("Autoload", "Cleared.")
		end},
	}
	for i, a in ipairs(actions) do
		local danger, primary = a[1] == "Delete", a[1] == "New"
		local bg = danger and THEME.DangerDim or primary and THEME.AccentDim or THEME.Element
		local text = (a[1] == "New" or a[1] == "Load" or a[1] == "Save" or a[1] == "Delete") and (a[1] .. " config") or a[1]
		local b = create("TextButton", {Text = text, Font = THEME.FontBold, TextSize = 13, TextColor3 = danger and THEME.Danger or primary and THEME.AccentText or THEME.Text, AutoButtonColor = false, BackgroundColor3 = bg, LayoutOrder = i, Parent = grid}, {corner(), stroke(danger and THEME.Danger or primary and THEME.Accent or THEME.Stroke)})
		if danger or primary then b.UIStroke.Transparency = 0.6 end
		hoverable(b, bg, THEME.Hover)
		b.MouseButton1Click:Connect(a[2])
	end
	refreshList()
	return tab
end

return Library
