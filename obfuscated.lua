local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

local API_URL = getgenv and getgenv().INERTIA_API_URL or "https://ezkeys.wtf"
local GET_KEY_URL = "https://ezkeys.wtf"

local function getRequest()
	return (syn and syn.request)
		or (http and http.request)
		or http_request
		or request
end

local function generateHWID()
	return game:GetService("RbxAnalyticsService"):GetClientId()
end

local function generateFingerprint()
	local player = Players.LocalPlayer
	return HttpService:JSONEncode(
		{
			UserId = player.UserId,
			AccountAge = player.AccountAge,
			MembershipType = tostring(player.MembershipType),
			Locale = player.LocaleId
		}
	)
end

local function check_key(key)
	local req = getRequest()
	if type(req) ~= "function" then
		return {valid = false, message = "HTTP request not supported"}
	end

	local payload =
		HttpService:JSONEncode(
		{
			key = tostring(key or ""),
			hwid = generateHWID(),
			ip = "roblox_client",
			fingerprint = generateFingerprint(),
			roblox_user_id = Players.LocalPlayer and Players.LocalPlayer.UserId or nil
		}
	)

	local ok, res =
		pcall(
		function()
			return req(
				{
					Url = API_URL .. "/api/verify",
					Method = "POST",
					Headers = {["Content-Type"] = "application/json"},
					Body = payload
				}
			)
		end
	)

	if not ok or not res then
		return {valid = false, message = "API request failed"}
	end

	local body = res.Body or res.body or ""
	local decodedOk, data =
		pcall(
		function()
			return HttpService:JSONDecode(body)
		end
	)

	if not decodedOk or type(data) ~= "table" then
		return {valid = false, message = "Invalid API response"}
	end

	if tonumber(res.StatusCode or res.Status or 200) >= 400 then
		return {valid = false, message = data.error or data.message or "Invalid key"}
	end

	if data.valid then
		return {valid = true, message = "KEY_VALID", data = data}
	end

	return {valid = false, message = data.error or data.message or "Invalid key"}
end

local function formatTimeLeft(seconds)
	seconds = tonumber(seconds) or 0
	if seconds < 0 then
		seconds = 0
	end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	return string.format("%dh %dm", h, m)
end

local Icons = {
	InertiaICON = "rbxassetid://107827379552049",
	Shield = "rbxassetid://105619007041452",
	Loading = "rbxassetid://116535712789945",
	Lock = "rbxassetid://114355063515473",
	Key = "rbxassetid://93569468678423",
	Check = "rbxassetid://119783053916823",
	CheckCircle = "rbxassetid://10709790644",
	XCircle = "rbxassetid://10747384394",
	Warning = "rbxassetid://130226573962640",
	Globe = "rbxassetid://10734950309",
	Info = "rbxassetid://94529541997278",
	ExternalLink = "rbxassetid://71038734318580",
	Copy = "rbxassetid://107485544510830",
	Spinner = "rbxassetid://10709767827",
	Database = "rbxassetid://114209748010261",
	Sparkles = "rbxassetid://10709767827",
	ErrorFolder = "rbxassetid://113312905787220",
	Candy = "rbxassetid://10709767827",
}

local function hasFileSystemSupport()
    local hasWritefile = pcall(function() return type(writefile) == "function" end)
    local hasReadfile = pcall(function() return type(readfile) == "function" end)
    local hasIsfile = pcall(function() return type(isfile) == "function" end)
    return hasWritefile and hasReadfile and hasIsfile
end

local fileSystemSupported = hasFileSystemSupport()

local function getLegacyKeyStoragePath()
	local uid = tostring(Players.LocalPlayer and Players.LocalPlayer.UserId or "0")
	local hwid = tostring(generateHWID() or "")
	hwid = hwid:gsub("[^%w]", "")
	if #hwid > 32 then
		hwid = hwid:sub(1, 32)
	end
	return string.format("inertia_key_%s_%s.txt", uid, hwid)
end

local function getKeyProfilePath()
	local uid = tostring(Players.LocalPlayer and Players.LocalPlayer.UserId or "0")
	return string.format("inertia_keys_%s.json", uid)
end

local function loadKeyProfile()
	local profile = { active_key = nil, keys = {} }
	if not fileSystemSupported then
		return profile
	end

	local function upsertKey(k)
		k = tostring(k or ""):upper()
		if k == "" then
			return
		end
		for _, item in ipairs(profile.keys) do
			if item.key == k then
				return
			end
		end
		table.insert(profile.keys, { key = k })
	end

	local ok = pcall(function()
		local path = getKeyProfilePath()
		if isfile(path) then
			local decoded = HttpService:JSONDecode(readfile(path))
			if type(decoded) == "table" then
				profile.active_key = decoded.active_key
				if type(decoded.keys) == "table" then
					for _, item in ipairs(decoded.keys) do
						if type(item) == "table" and item.key then
							local key = tostring(item.key):upper()
							local entry = {
								key = key,
								last_verified_at = tonumber(item.last_verified_at) or nil,
								expires_at = tonumber(item.expires_at) or nil,
								time_left_seconds = tonumber(item.time_left_seconds) or nil,
							}
							table.insert(profile.keys, entry)
						elseif type(item) == "string" then
							upsertKey(item)
						end
					end
				end
			end
		end

		if isfile("inertia_verified_key.txt") then
			upsertKey(readfile("inertia_verified_key.txt"))
			pcall(function()
				delfile("inertia_verified_key.txt")
			end)
		end

		local legacyPath = getLegacyKeyStoragePath()
		if isfile(legacyPath) then
			upsertKey(readfile(legacyPath))
		end
	end)

	if not ok then
		return profile
	end
	return profile
end

local function saveKeyProfile(profile)
	if not fileSystemSupported or type(profile) ~= "table" then
		return false
	end

	local ok = pcall(function()
		writefile(getKeyProfilePath(), HttpService:JSONEncode(profile))
	end)
	return ok
end

local function saveVerifiedKey(key, data)
	if not fileSystemSupported then
		return false
	end

	key = tostring(key or ""):upper()
	if key == "" then
		return false
	end

	local profile = loadKeyProfile()
	local entry = nil
	for _, item in ipairs(profile.keys) do
		if item.key == key then
			entry = item
			break
		end
	end
	if not entry then
		entry = { key = key }
		table.insert(profile.keys, entry)
	end

	entry.last_verified_at = os.time()
	if type(data) == "table" then
		local expiresAt = tonumber(data.expires_at)
		local left = tonumber(data.time_left_seconds or data.time_left)
		if expiresAt then
			entry.expires_at = math.floor(expiresAt)
			entry.time_left_seconds = math.max(0, entry.expires_at - os.time())
		elseif left then
			entry.expires_at = os.time() + math.max(0, math.floor(left))
			entry.time_left_seconds = math.max(0, math.floor(left))
		end
	end

	profile.active_key = key
	saveKeyProfile(profile)

	pcall(function()
		writefile(getLegacyKeyStoragePath(), key)
	end)

	return true
end

local function loadVerifiedKey()
	if not fileSystemSupported then
		return nil
	end

	local profile = loadKeyProfile()
	local bestKey = nil
	local bestLeft = -1

	for _, item in ipairs(profile.keys) do
		if type(item) == "table" and type(item.key) == "string" then
			local left = tonumber(item.time_left_seconds)
			if not left and tonumber(item.expires_at) then
				left = tonumber(item.expires_at) - os.time()
			end
			left = tonumber(left) or 0
			if left > bestLeft then
				bestLeft = left
				bestKey = item.key
			end
		end
	end

	local active = tostring(profile.active_key or ""):upper()
	if active ~= "" then
		return active
	end
	return bestKey
end

local function clearSavedKey(keyToRemove)
	if not fileSystemSupported then
		return false
	end

	local profile = loadKeyProfile()
	local changed = false

	if keyToRemove and tostring(keyToRemove) ~= "" then
		local k = tostring(keyToRemove):upper()
		for i = #profile.keys, 1, -1 do
			if profile.keys[i] and profile.keys[i].key == k then
				table.remove(profile.keys, i)
				changed = true
			end
		end
		if profile.active_key == k then
			profile.active_key = nil
			changed = true
		end
	else
		profile.keys = {}
		profile.active_key = nil
		changed = true
	end

	if changed then
		if keyToRemove and tostring(keyToRemove) ~= "" then
			if not profile.active_key then
				local bestKey = nil
				local bestLeft = -1
				for _, item in ipairs(profile.keys) do
					local left = tonumber(item.time_left_seconds)
					if not left and tonumber(item.expires_at) then
						left = tonumber(item.expires_at) - os.time()
					end
					left = tonumber(left) or 0
					if left > bestLeft then
						bestLeft = left
						bestKey = item.key
					end
				end
				profile.active_key = bestKey
			end
			saveKeyProfile(profile)
			if profile.active_key then
				pcall(function()
					writefile(getLegacyKeyStoragePath(), profile.active_key)
				end)
			end
		else
			pcall(function()
				delfile(getKeyProfilePath())
			end)
			pcall(function()
				delfile(getLegacyKeyStoragePath())
			end)
			pcall(function()
				delfile("inertia_verified_key.txt")
			end)
		end
	end

	return true
end

local Configuration = {
	ScreenGuiName = "InertiaKeySystem",
	Window = {Size = UDim2.new(0, 333, 0, 500)},
	Colors = {
		Bg = Color3.fromRGB(12, 12, 12),
		Primary = Color3.fromRGB(59, 130, 246),
		PrimaryDark = Color3.fromRGB(37, 99, 235),
		StatusIdle = Color3.fromRGB(249, 115, 22),
		StatusSuccess = Color3.fromRGB(16, 185, 129),
		StatusError = Color3.fromRGB(239, 68, 68),
		StatusVerifying = Color3.fromRGB(59, 130, 246),
		StatusWarning = Color3.fromRGB(254, 188, 46),
		TextMain = Color3.fromRGB(255, 255, 255),
		TextSec = Color3.fromRGB(161, 161, 170),
		TextMuted = Color3.fromRGB(113, 113, 122),
		Border = Color3.fromRGB(255, 255, 255),
		TrafficRed = Color3.fromRGB(255, 95, 87),
		TrafficYellow = Color3.fromRGB(254, 188, 46),
		TrafficGreen = Color3.fromRGB(40, 200, 64),
		Success = Color3.fromRGB(50, 205, 110),
		Error = Color3.fromRGB(245, 70, 90),
		Warning = Color3.fromRGB(255, 200, 50)
	},
	BorderTransparency = 0.15,
	Animations = {
		VeryFast = 0.1,
		Fast = 0.2,
		Medium = 0.4,
		Slow = 0.5,
		VerySlow = 0.6,
		Bounce = 0.6
	},
	Fonts = {
		Title = 24,
		Subtitle = 12,
		Button = 14,
		Input = 16,
		Body = 13,
		Small = 11,
		Tiny = 12
	}
}

local Utils = {}

Utils.Tween = function(obj, props, time, style, dir)
	local t =
		TweenService:Create(
		obj,
		TweenInfo.new(time or 0.3, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

Utils.CreateCorner = function(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Configuration.CornerRadius)
	corner.Parent = parent
	return corner
end

Utils.Round = function(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = obj
	return c
end

Utils.TweenBack = function(instance, properties, duration)
	return Utils.Tween(instance, properties, duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

Utils.CreateStroke = function(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Configuration.Colors.Border
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.77
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

Utils.Stroke = function(obj, color, thick, trans)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Thickness = thick or 1
	s.Transparency = trans or 0.9
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

Utils.CreateGradient = function(parent, color1, color2, rotation)
	local gradient = Instance.new("UIGradient")
	gradient.Color =
		ColorSequence.new(
		{
			ColorSequenceKeypoint.new(0, color1),
			ColorSequenceKeypoint.new(1, color2)
		}
	)
	gradient.Rotation = rotation or 300
	gradient.Parent = parent
	return gradient
end

local function SetBlur(enabled)
	local blur = Lighting:FindFirstChild("InertiaBlur")
	if enabled then
		if not blur then
			blur = Instance.new("BlurEffect")
			blur.Name = "InertiaBlur"
			blur.Size = 0
			blur.Parent = Lighting
		end
		Utils.Tween(blur, {Size = 24}, Configuration.Animations.Bounce)
	elseif blur then
		Utils.Tween(blur, {Size = 0}, Configuration.Animations.Medium)
		task.delay(
			0.4,
			function()
				blur:Destroy()
			end
		)
	end
end

local ToastSystem = {ActiveToasts = {}, MaxToasts = 3, ToastSpacing = 10}

ToastSystem.Create = function(parent, message, toastType, duration, statusCode)
	local colors = {
		success = Configuration.Colors.Success,
		error = Configuration.Colors.Error,
		warning = Configuration.Colors.Warning,
		info = Configuration.Colors.Primary
	}
	local icons = {
		success = Icons.CheckCircle,
		error = Icons.ErrorFolder,
		warning = Icons.Warning,
		info = Icons.Info
	}
	local toastColor = colors[toastType] or colors.Bg
	local toastIcon = icons[toastType] or nil
	if #ToastSystem.ActiveToasts >= ToastSystem.MaxToasts then
		local oldest = table.remove(ToastSystem.ActiveToasts, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
	local toastHeight = 56
	local toast = Instance.new("Frame")
	toast.Name = tick()
	toast.Size = UDim2.new(0, 0, 0, toastHeight)
	toast.Position = UDim2.new(0.5, 0, 0, 20)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.BackgroundColor3 = Configuration.Colors.Bg
	toast.BackgroundTransparency = 0.5
	toast.BorderSizePixel = 0
	toast.ZIndex = 300
	toast.ClipsDescendants = true
	toast.Parent = parent
	Utils.Round(toast, 14)
	Utils.CreateStroke(toast, toastColor, 1, 0.1)
	Utils.CreateGradient(toast, Configuration.Colors.Bg, Configuration.Colors.Bg, 1)
	local iconBg = Instance.new("Frame")
	iconBg.Name = "IconBg"
	iconBg.Size = UDim2.new(0, 36, 0, 36)
	iconBg.Position = UDim2.new(0, 12, 0.5, 0)
	iconBg.AnchorPoint = Vector2.new(0, 0.5)
	iconBg.BackgroundColor3 = toastColor
	iconBg.BackgroundTransparency = 0.85
	iconBg.BorderSizePixel = 0
	iconBg.ZIndex = 301
	iconBg.Parent = toast
	Utils.Round(iconBg, 18)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 20, 0, 20)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = toastIcon
	icon.ImageColor3 = toastColor
	icon.ZIndex = 302
	icon.Parent = iconBg
	local textContainer = Instance.new("Frame")
	textContainer.Name = "TextContainer"
	textContainer.Size = UDim2.new(1, statusCode and -110 or -60, 1, 0)
	textContainer.Position = UDim2.new(0, 56, 0, 0)
	textContainer.BackgroundTransparency = 1
	textContainer.ZIndex = 301
	textContainer.Parent = toast
	local text = Instance.new("TextLabel")
	text.Name = "Message"
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Text = message or ""
	text.TextColor3 = Configuration.Colors.TextMain
	text.TextSize = Configuration.Fonts.Body
	text.Font = Enum.Font.GothamMedium
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.TextWrapped = true
	text.ZIndex = 301
	text.Parent = textContainer
	if statusCode then
		local statusBadge = Instance.new("Frame")
		statusBadge.Name = "StatusBadge"
		statusBadge.Size = UDim2.new(0, 44, 0, 28)
		statusBadge.Position = UDim2.new(1, -12, 0.5, 0)
		statusBadge.AnchorPoint = Vector2.new(1, 0.5)
		statusBadge.BackgroundColor3 = toastColor
		statusBadge.BackgroundTransparency = 0.8
		statusBadge.BorderSizePixel = 0
		statusBadge.ZIndex = 301
		statusBadge.Parent = toast
		Utils.Round(statusBadge, 8)
		Utils.CreateStroke(statusBadge, toastColor, 1, Configuration.BorderTransparency)
		local statusCodeLabel = Instance.new("TextLabel")
		statusCodeLabel.Name = "StatusCode"
		statusCodeLabel.Size = UDim2.new(1, 0, 1, 0)
		statusCodeLabel.BackgroundTransparency = 1
		statusCodeLabel.Text = tostring(statusCode)
		statusCodeLabel.TextColor3 = toastColor
		statusCodeLabel.TextSize = Configuration.Fonts.Small
		statusCodeLabel.Font = Enum.Font.GothamBold
		statusCodeLabel.ZIndex = 302
		statusCodeLabel.Parent = statusBadge
	end
	table.insert(ToastSystem.ActiveToasts, toast)
	ToastSystem.RepositionToasts()
	local targetWidth = 320
	Utils.TweenBack(toast, {Size = UDim2.new(0, targetWidth, 0, toastHeight)}, Configuration.Animations.Medium)
	task.delay(
		duration or 3.5,
		function()
			if toast.Parent then
				Utils.Tween(
					toast,
					{
						Position = UDim2.new(0.5, 0, 0, -80),
						BackgroundTransparency = 1
					},
					Configuration.Animations.Medium
				)
				for i, t in ipairs(ToastSystem.ActiveToasts) do
					if t == toast then
						table.remove(ToastSystem.ActiveToasts, i)
						break
					end
				end
				task.wait(Configuration.Animations.Medium)
				toast:Destroy()
				ToastSystem.RepositionToasts()
			end
		end
	)
	return toast
end

ToastSystem.RepositionToasts = function()
	for i, toast in ipairs(ToastSystem.ActiveToasts) do
		local targetY = 20 + ((i - 1) * (60 + ToastSystem.ToastSpacing))
		Utils.Tween(toast, {Position = UDim2.new(0.5, 0, 0, targetY)}, Configuration.Animations.Medium)
	end
end

local function Build(prefillKey, prefillFromSaved)
	local parent = game:GetService("CoreGui")
	local old = parent:FindFirstChild(Configuration.ScreenGuiName)
	if old then
		old:Destroy()
	end
	local profile = loadKeyProfile()
	local screen = Instance.new("ScreenGui")
	screen.Name = Configuration.ScreenGuiName
	screen.ResetOnSpawn = false
	screen.Parent = parent
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.Parent = screen
	Utils.Tween(overlay, {BackgroundTransparency = 1}, 1)
	SetBlur(true)
	local main = Instance.new("Frame")
	local function applyResponsiveSize()
		local cam = workspace.CurrentCamera
		local v = cam and cam.ViewportSize
		if not v then
			main.Size = Configuration.Window.Size
			return
		end
		local w = math.clamp(v.X - 40, 280, Configuration.Window.Size.X.Offset)
		local h = math.clamp(v.Y - 120, 420, Configuration.Window.Size.Y.Offset)
		main.Size = UDim2.new(0, w, 0, h)
	end
	applyResponsiveSize()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveSize)
	end
	main.Position = UDim2.new(0.5, 0, 0.5, 60)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.BackgroundColor3 = Configuration.Colors.Bg
	main.BackgroundTransparency = 0.2
	main.ClipsDescendants = true
	main.Parent = screen
	Utils.Round(main, 24)
	Utils.Stroke(main, Color3.new(1, 1, 1), 1, 0.92)
	local glass = Instance.new("Frame")
	glass.Size = UDim2.fromScale(1, 1)
	glass.BackgroundColor3 = Color3.new(1, 1, 1)
	glass.BackgroundTransparency = 0.985
	glass.ZIndex = 0
	glass.Parent = main
	Utils.Round(glass, 24)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 54)
	bar.BackgroundTransparency = 1
	bar.Parent = main
	local dots = Instance.new("Frame")
	dots.Size = UDim2.new(0, 54, 0, 12)
	dots.Position = UDim2.new(0, 20, 0.5, 0)
	dots.AnchorPoint = Vector2.new(0, 0.5)
	dots.BackgroundTransparency = 1
	dots.Parent = bar
	local dColors = {
		Configuration.Colors.TrafficRed,
		Configuration.Colors.TrafficYellow,
		Configuration.Colors.TrafficGreen
	}
	for i, c in ipairs(dColors) do
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(12, 12)
		d.Position = UDim2.fromOffset((i - 1) * 18, 0)
		d.BackgroundColor3 = c
		d.BorderSizePixel = 0
		d.Parent = dots
		Utils.Round(d, 6)
	end
	local titleText = Instance.new("TextLabel")
	titleText.Size = UDim2.new(1, 0, 1, 0)
	titleText.Text = "INERTIA"
	titleText.TextColor3 = Color3.new(1, 1, 1)
	titleText.TextTransparency = 0.7
	titleText.TextSize = 10
	titleText.Font = Enum.Font.GothamBold
	titleText.BackgroundTransparency = 1
	titleText.Parent = bar
	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, 0, 1, -54)
	content.Position = UDim2.new(0, 0, 0, 54)
	content.BackgroundTransparency = 1
	content.ScrollBarThickness = 0
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 24)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = content
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 5)
	pad.Parent = content
	local logoContainer = Instance.new("Frame")
	logoContainer.Size = UDim2.fromOffset(80, 80)
	logoContainer.BackgroundTransparency = 1
	logoContainer.Parent = content
	Utils.Round(logoContainer, 20)
	local sIcon = Instance.new("ImageLabel")
	sIcon.Size = UDim2.fromScale(1, 1)
	sIcon.Position = UDim2.fromScale(0.5, 0.5)
	sIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	sIcon.Image = Icons.InertiaICON
	sIcon.ScaleType = Enum.ScaleType.Fit
	sIcon.BackgroundTransparency = 1
	sIcon.Parent = logoContainer
	local titleArea = Instance.new("Frame")
	titleArea.Size = UDim2.new(1, 0, 0, 44)
	titleArea.BackgroundTransparency = 1
	titleArea.Parent = content
	local mainTitle = Instance.new("TextLabel")
	mainTitle.Size = UDim2.new(1, 0, 0, 26)
	mainTitle.Text = "Inertia"
	mainTitle.TextColor3 = Color3.new(1, 1, 1)
	mainTitle.TextSize = 26
	mainTitle.Font = Enum.Font.GothamBold
	mainTitle.BackgroundTransparency = 1
	mainTitle.Parent = titleArea
	local titleGradient = Instance.new("UIGradient")
	titleGradient.Color =
		ColorSequence.new(
		{
			ColorSequenceKeypoint.new(0, Configuration.Colors.Primary),
			ColorSequenceKeypoint.new(0.16, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.32, Configuration.Colors.Primary),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.68, Configuration.Colors.Primary),
			ColorSequenceKeypoint.new(0.84, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Configuration.Colors.Primary)
		}
	)
	local offsetRange = 0.35
	titleGradient.Offset = Vector2.new(-offsetRange, 0)
	titleGradient.Parent = mainTitle
	local offsetX = -offsetRange
	local elapsed = 0
	local baseSpeed = 0.14
	local pulseEvery = 2.5
	local pulseWindow = 0.35
	local pulseAmp = 0.06
	RunService.Heartbeat:Connect(function(dt)
		if not titleGradient or not titleGradient.Parent then
			return
		end
		elapsed += dt
		local phase = elapsed % pulseEvery
		local bump = 0
		if phase < pulseWindow then
			bump = (pulseWindow - phase) / pulseWindow
		end
		local speed = baseSpeed + (pulseAmp * bump)
		offsetX += speed * dt
		if offsetX > offsetRange then
			offsetX = -offsetRange + (offsetX - offsetRange)
		end
		titleGradient.Offset = Vector2.new(offsetX, 0)
	end)
	local subTitle = Instance.new("TextLabel")
	subTitle.Size = UDim2.new(1, 0, 0, 16)
	subTitle.Position = UDim2.fromOffset(0, 28)
	subTitle.Text = API_URL:gsub("^https?://", "")
	subTitle.TextColor3 = Configuration.Colors.TextSec
	subTitle.TextSize = 13
	subTitle.Font = Enum.Font.Gotham
	subTitle.BackgroundTransparency = 1
	subTitle.Parent = titleArea
	local statusCard = Instance.new("Frame")
	statusCard.Size = UDim2.new(0, 280, 0, 68)
	statusCard.BackgroundColor3 = Color3.new(1, 1, 1)
	statusCard.BackgroundTransparency = 0.96
	statusCard.Parent = content
	Utils.Round(statusCard, 16)
	local sStroke = Utils.Stroke(statusCard, Color3.new(1, 1, 1), 1, 0.95)
	local sIconBg = Instance.new("Frame")
	sIconBg.Size = UDim2.fromOffset(42, 42)
	sIconBg.Position = UDim2.new(0, 14, 0.5, 0)
	sIconBg.AnchorPoint = Vector2.new(0, 0.5)
	sIconBg.BackgroundColor3 = Configuration.Colors.StatusIdle
	sIconBg.BackgroundTransparency = 0.9
	sIconBg.Parent = statusCard
	Utils.Round(sIconBg, 21)
	local sImg = Instance.new("ImageLabel")
	sImg.Size = UDim2.fromScale(0.5, 0.5)
	sImg.Position = UDim2.fromScale(0.5, 0.5)
	sImg.AnchorPoint = Vector2.new(0.5, 0.5)
	sImg.Image = Icons.Lock
	sImg.ImageColor3 = Configuration.Colors.StatusIdle
	sImg.BackgroundTransparency = 1
	sImg.Parent = sIconBg
	local sLabel = Instance.new("TextLabel")
	sLabel.Size = UDim2.new(1, -70, 0, 14)
	sLabel.Position = UDim2.fromOffset(70, 16)
	sLabel.Text = "CURRENT STATUS"
	sLabel.TextColor3 = Configuration.Colors.TextMuted
	sLabel.TextSize = 10
	sLabel.Font = Enum.Font.GothamBold
	sLabel.TextXAlignment = Enum.TextXAlignment.Left
	sLabel.BackgroundTransparency = 1
	sLabel.Parent = statusCard
	local sValue = Instance.new("TextLabel")
	sValue.Size = UDim2.new(1, -70, 0, 20)
	sValue.Position = UDim2.fromOffset(70, 32)
	sValue.Text = "No key detected"
	sValue.TextColor3 = Configuration.Colors.StatusIdle
	sValue.TextSize = 15
	sValue.Font = Enum.Font.GothamMedium
	sValue.TextXAlignment = Enum.TextXAlignment.Left
	sValue.BackgroundTransparency = 1
	sValue.Parent = statusCard
	local inputFrame = Instance.new("Frame")
	inputFrame.Size = UDim2.new(0, 280, 0, 52)
	inputFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	inputFrame.BackgroundTransparency = 0.975
	inputFrame.Parent = content
	Utils.Round(inputFrame, 14)
	local iStroke = Utils.Stroke(inputFrame, Color3.new(1, 1, 1), 1, 0.95)
	local kIcon = Instance.new("ImageLabel")
	kIcon.Size = UDim2.fromOffset(18, 18)
	kIcon.Position = UDim2.new(0, 14, 0.5, 0)
	kIcon.AnchorPoint = Vector2.new(0, 0.5)
	kIcon.Image = Icons.Key
	kIcon.ImageColor3 = Configuration.Colors.TextMuted
	kIcon.BackgroundTransparency = 1
	kIcon.Parent = inputFrame
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -85, 1, 0)
	box.Position = UDim2.fromOffset(45, 0)
	box.Text = ""
	box.PlaceholderText = "Enter your key..."
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextSize = 14
	box.Font = Enum.Font.Gotham
	box.BackgroundTransparency = 1
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = inputFrame
	local paste = Instance.new("ImageButton")
	paste.Size = UDim2.fromOffset(18, 18)
	paste.Position = UDim2.new(1, -14, 0.5, 0)
	paste.AnchorPoint = Vector2.new(1, 0.5)
	paste.Image = Icons.Copy
	paste.ImageColor3 = Configuration.Colors.TextMuted
	paste.BackgroundTransparency = 1
	paste.Parent = inputFrame

	if profile and type(profile.keys) == "table" and #profile.keys > 1 then
		local function maskKey(k)
			k = tostring(k or "")
			if #k <= 8 then
				return k
			end
			return k:sub(1, 4) .. "..." .. k:sub(-4)
		end

		local function getLeftSeconds(item)
			if type(item) ~= "table" then
				return 0
			end
			local left = tonumber(item.time_left_seconds)
			if not left and tonumber(item.expires_at) then
				left = tonumber(item.expires_at) - os.time()
			end
			return math.max(0, math.floor(tonumber(left) or 0))
		end

		table.sort(profile.keys, function(a, b)
			return getLeftSeconds(a) > getLeftSeconds(b)
		end)

		local selector = Instance.new("Frame")
		selector.Size = UDim2.new(0, 280, 0, 44)
		selector.BackgroundColor3 = Color3.new(1, 1, 1)
		selector.BackgroundTransparency = 0.975
		selector.Parent = content
		Utils.Round(selector, 14)
		Utils.Stroke(selector, Color3.new(1, 1, 1), 1, 0.95)

		local dbIcon = Instance.new("ImageLabel")
		dbIcon.Size = UDim2.fromOffset(18, 18)
		dbIcon.Position = UDim2.new(0, 14, 0.5, 0)
		dbIcon.AnchorPoint = Vector2.new(0, 0.5)
		dbIcon.Image = Icons.Database
		dbIcon.ImageColor3 = Configuration.Colors.TextMuted
		dbIcon.BackgroundTransparency = 1
		dbIcon.Parent = selector

		local selText = Instance.new("TextLabel")
		selText.Size = UDim2.new(1, -60, 1, 0)
		selText.Position = UDim2.fromOffset(45, 0)
		selText.BackgroundTransparency = 1
		selText.TextColor3 = Color3.new(1, 1, 1)
		selText.TextSize = 13
		selText.Font = Enum.Font.Gotham
		selText.TextXAlignment = Enum.TextXAlignment.Left
		selText.Text = "Saved keys"
		selText.Parent = selector

		local chevron = Instance.new("TextLabel")
		chevron.Size = UDim2.fromOffset(20, 20)
		chevron.Position = UDim2.new(1, -16, 0.5, 0)
		chevron.AnchorPoint = Vector2.new(1, 0.5)
		chevron.BackgroundTransparency = 1
		chevron.TextColor3 = Configuration.Colors.TextMuted
		chevron.TextSize = 16
		chevron.Font = Enum.Font.GothamBold
		chevron.Text = "˅"
		chevron.Parent = selector

		local list = Instance.new("Frame")
		list.Size = UDim2.new(0, 280, 0, 0)
		list.BackgroundColor3 = Color3.new(1, 1, 1)
		list.BackgroundTransparency = 0.985
		list.ClipsDescendants = true
		list.Parent = content
		Utils.Round(list, 14)
		Utils.Stroke(list, Color3.new(1, 1, 1), 1, 0.95)

		local listLayout = Instance.new("UIListLayout")
		listLayout.FillDirection = Enum.FillDirection.Vertical
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UDim.new(0, 6)
		listLayout.Parent = list

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = list

		local open = false

		local function setSelected(k)
			k = tostring(k or ""):upper()
			local found = nil
			for _, item in ipairs(profile.keys) do
				if item.key == k then
					found = item
					break
				end
			end
			if found then
				local left = getLeftSeconds(found)
				selText.Text = maskKey(found.key) .. " • " .. formatTimeLeft(left)
				profile.active_key = found.key
				saveKeyProfile(profile)
			end
		end

		local function toggle()
			open = not open
			chevron.Text = open and "˄" or "˅"
			if open then
				local h = math.min(#profile.keys * 34 + 16, 160)
				list.Size = UDim2.new(0, 280, 0, h)
			else
				list.Size = UDim2.new(0, 280, 0, 0)
			end
		end

		local click = Instance.new("TextButton")
		click.Size = UDim2.fromScale(1, 1)
		click.BackgroundTransparency = 1
		click.Text = ""
		click.Parent = selector
		click.MouseButton1Click:Connect(toggle)

		for i, item in ipairs(profile.keys) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 0, 30)
			btn.BackgroundColor3 = Color3.new(1, 1, 1)
			btn.BackgroundTransparency = 0.97
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.TextSize = 13
			btn.Font = Enum.Font.Gotham
			btn.AutoButtonColor = false
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.Parent = list
			Utils.Round(btn, 10)

			local left = getLeftSeconds(item)
			btn.Text = maskKey(item.key) .. " • " .. formatTimeLeft(left)

			btn.MouseButton1Click:Connect(function()
				box.Text = tostring(item.key):upper()
				setSelected(item.key)
				open = true
				toggle()
			end)
		end

		setSelected(prefillKey or profile.active_key or (profile.keys[1] and profile.keys[1].key))
	end
	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(0, 280, 0, 50)
	btnRow.BackgroundTransparency = 1
	btnRow.Parent = content
	local redeem = Instance.new("TextButton")
	redeem.Size = UDim2.new(0.5, -8, 1, 0)
	redeem.BackgroundColor3 = Configuration.Colors.Primary
	redeem.Text = "Redeem"
	redeem.TextColor3 = Color3.new(1, 1, 1)
	redeem.Font = Enum.Font.GothamBold
	redeem.TextSize = 14
	redeem.AutoButtonColor = false
	redeem.Parent = btnRow
	Utils.Round(redeem, 14)
	local getKey = Instance.new("TextButton")
	getKey.Size = UDim2.new(0.5, -8, 1, 0)
	getKey.Position = UDim2.new(0.5, 8, 0, 0)
	getKey.BackgroundColor3 = Color3.new(1, 1, 1)
	getKey.BackgroundTransparency = 0.955
	getKey.Text = "Get Key"
	getKey.TextColor3 = Color3.new(1, 1, 1)
	getKey.Font = Enum.Font.GothamBold
	getKey.TextSize = 14
	getKey.AutoButtonColor = false
	getKey.Parent = btnRow
	Utils.Round(getKey, 14)
	Utils.Stroke(getKey, Color3.new(1, 1, 1), 1, 0.94)
	local function ApplyHover(btn)
		local baseColor = btn.BackgroundColor3
		btn.MouseEnter:Connect(
			function()
				Utils.Tween(
					btn,
					{
						BackgroundColor3 = baseColor:Lerp(Color3.new(1, 1, 1), 0.1)
					},
					0.2
				)
				Utils.Tween(
					btn,
					{
						Size = UDim2.new(btn.Size.X.Scale, btn.Size.X.Offset + 4, btn.Size.Y.Scale, btn.Size.Y.Offset + 2)
					},
					0.2
				)
			end
		)
		btn.MouseLeave:Connect(
			function()
				Utils.Tween(btn, {BackgroundColor3 = baseColor}, 0.2)
				Utils.Tween(
					btn,
					{
						Size = UDim2.new(btn.Size.X.Scale, btn.Size.X.Offset - 4, btn.Size.Y.Scale, btn.Size.Y.Offset - 2)
					},
					0.2
				)
			end
		)
	end
	ApplyHover(redeem)
	ApplyHover(getKey)
	if prefillKey and tostring(prefillKey) ~= "" then
		box.Text = tostring(prefillKey):upper()
	end
	box.Focused:Connect(
		function()
			Utils.Tween(iStroke, {Transparency = 0.5, Thickness = 1.2}, 0.3)
		end
	)
	box.FocusLost:Connect(
		function()
			Utils.Tween(iStroke, {Transparency = 0.95, Thickness = 1}, 0.3)
		end
	)
	local spinConnection
	local dotsThread
	local function SetStatus(state)
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
			sImg.Rotation = 0
		end
		if dotsThread then
			task.cancel(dotsThread)
			dotsThread = nil
		end
		local color = Configuration.Colors.StatusIdle
		local icon = Icons.Lock
		local text = "No key detected"
		if state == "verifying" then
			color = Configuration.Colors.StatusVerifying
			icon = Icons.Loading
			text = "Verifying access"
			spinConnection =
				RunService.Heartbeat:Connect(
				function(dt)
					if not sImg or not sImg.Parent then
						if spinConnection then
							spinConnection:Disconnect()
						end
						spinConnection = nil
						return
					end
					sImg.Rotation = (sImg.Rotation + dt * 360) % 360
				end
			)
			local dots = {".", "..", "...", ""}
			local i = 1
			dotsThread =
				task.spawn(
				function()
					while sValue and sValue.Parent do
						if not sValue.Text:find("Verifying access", 1, true) then
							break
						end
						sValue.Text = text .. dots[i]
						i = (i % #dots) + 1
						task.wait(0.45)
					end
				end
			)
		elseif state == "success" then
			color = Configuration.Colors.StatusSuccess
			icon = Icons.CheckCircle
			text = "Access Granted"
		elseif state == "error" then
			color = Configuration.Colors.StatusError
			icon = Icons.XCircle
			text = "Invalid Key"
		end
		Utils.Tween(sValue, {TextColor3 = color}, 0.35)
		Utils.Tween(sImg, {ImageColor3 = color}, 0.35)
		Utils.Tween(sIconBg, {BackgroundColor3 = color}, 0.35)
		sValue.Text = text
		sImg.Image = icon
	end
	local function VerifyAndContinue(key, fromSaved)
			key = tostring(key or ""):upper()
			SetStatus("verifying")
			redeem.Text = "..."
			redeem.Active = false
            local result = check_key(key)
			redeem.Active = true
			redeem.Text = "Redeem"
			if not result then
				SetStatus("error")
				ToastSystem.Create(screen, "API request failed: " .. tostring(result), "error")
				return
			end
			if result.valid then
                saveVerifiedKey(key, result.data)
                getgenv().SCRIPT_KEY = key
				getgenv().INERTIA_KEY = key
				task.spawn(function()
					local url =
						(getgenv and getgenv().INERTIA_GAME_LOADER_URL)
						or "https://gist.githubusercontent.com/JustKondzio0010/1b8107f2889146cc991db0541c9a880d/raw/4b17bb0ede2e533ad4144edacd1b6dd2c9710300/INERTIALOADER"
					local ok, src = pcall(function()
						return game:HttpGet(url, true)
					end)
					if not ok or type(src) ~= "string" or src == "" then
						return
					end
					local fn = loadstring(src)
					if type(fn) ~= "function" then
						return
					end
					pcall(fn)
				end)
                SetStatus("success")
				local left = result.data and result.data.time_left_seconds
				if left ~= nil then
					local text = "Key verified • " .. formatTimeLeft(left) .. " left"
					ToastSystem.Create(screen, text, "success")
					sValue.Text = "Access Granted • " .. formatTimeLeft(left)
				else
					ToastSystem.Create(screen, "Key verified", "success")
				end
                task.wait(0.8)
                SetBlur(false)
                Utils.Tween(
                    main,
                    {
                        Position = UDim2.new(0.5, 0, 0.5, 100),
                        BackgroundTransparency = 1
                    },
                    0.7,
                    Enum.EasingStyle.Exponential,
                    Enum.EasingDirection.In
                )
                task.delay(
                    0.7,
                    function()
                        screen:Destroy()
                    end
                )
			else
				SetStatus("error")
				if fromSaved then
					clearSavedKey(key)
				end
				ToastSystem.Create(screen, result.message or "Invalid key", "error", nil, status)
			end
	end

	redeem.MouseButton1Click:Connect(
		function()
			local key = box.Text
			if tostring(key or "") == "" then
				SetStatus("error")
				ToastSystem.Create(screen, "Please enter a key", "error")
				return
			end
			VerifyAndContinue(key, false)
		end
	)
	getKey.MouseButton1Click:Connect(
		function()
			setclipboard(GET_KEY_URL)
			ToastSystem.Create(screen, "Key link has been copied to clipboard", "success")
		end
	)
	paste.MouseButton1Click:Connect(
		function()
			ToastSystem.Create(screen, "Paste functionality not supported in Roblox (security reasons)", "warning")
		end
	)
	main.Position = UDim2.new(0.5, 0, 0.5, 100)
	main.BackgroundTransparency = 1
	Utils.Tween(
		main,
		{
			Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundTransparency = 0.2
		},
		1,
		Enum.EasingStyle.Exponential
	)
	local dragging, dragStart, startPos
	bar.InputBegan:Connect(
		function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				dragStart = input.Position
				startPos = main.Position
			end
		end
	)
	UserInputService.InputChanged:Connect(
		function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = input.Position - dragStart
				main.Position =
					UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end
	)
	UserInputService.InputEnded:Connect(
		function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
			end
		end
	)
	if prefillKey and tostring(prefillKey) ~= "" then
		task.delay(0.15, function()
			if screen and screen.Parent then
				VerifyAndContinue(prefillKey, prefillFromSaved == true)
			end
		end)
	end
	return screen
end

do
	local profile = loadKeyProfile()
	if fileSystemSupported and profile and type(profile.keys) == "table" and #profile.keys > 1 then
		for i = #profile.keys, 1, -1 do
			local k = tostring(profile.keys[i] and profile.keys[i].key or ""):upper()
			if k ~= "" then
				local res = check_key(k)
				if res and res.valid and type(res.data) == "table" then
					local expiresAt = tonumber(res.data.expires_at)
					local left = tonumber(res.data.time_left_seconds or res.data.time_left)
					profile.keys[i].last_verified_at = os.time()
					if expiresAt then
						profile.keys[i].expires_at = math.floor(expiresAt)
						profile.keys[i].time_left_seconds = math.max(0, profile.keys[i].expires_at - os.time())
					elseif left then
						profile.keys[i].expires_at = os.time() + math.max(0, math.floor(left))
						profile.keys[i].time_left_seconds = math.max(0, math.floor(left))
					end
				else
					table.remove(profile.keys, i)
				end
			else
				table.remove(profile.keys, i)
			end
			task.wait(0.05)
		end

		local bestKey = nil
		local bestLeft = -1
		for _, item in ipairs(profile.keys) do
			local left = tonumber(item.time_left_seconds)
			if not left and tonumber(item.expires_at) then
				left = tonumber(item.expires_at) - os.time()
			end
			left = tonumber(left) or 0
			if left > bestLeft then
				bestLeft = left
				bestKey = item.key
			end
		end

		profile.active_key = bestKey
		saveKeyProfile(profile)
		if bestKey then
			pcall(function()
				writefile(getLegacyKeyStoragePath(), bestKey)
			end)
		end
	end
end

local savedKey = loadVerifiedKey()
local keyToCheck = savedKey or getgenv().SCRIPT_KEY
Build(keyToCheck, savedKey ~= nil)

while not getgenv().SCRIPT_KEY do
    task.wait(0.1)
end
