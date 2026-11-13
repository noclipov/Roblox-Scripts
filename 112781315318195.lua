local VIM        = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local LP         = game:GetService("Players").LocalPlayer

local INSET    = GuiService:GetGuiInset()
local BUTTONS  = { "ClickBonusExtra", "ClickBonus" } -- порядок = приоритет
local COOLDOWN = 0.15 -- антидребезг (не даёт кликнуть дважды подряд)

local lastClick, mainUI = 0, nil

local function click(btn)
	local c = btn.AbsolutePosition + btn.AbsoluteSize / 2
	local x, y = c.X + INSET.X, c.Y + INSET.Y
	VIM:SendMouseMoveEvent(x, y, game)
	VIM:SendMouseButtonEvent(x, y, 0, true,  game, 0)
	task.wait(0.03)
	VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

local function tryClick()
	local now = os.clock()
	if now - lastClick < COOLDOWN or not mainUI then return end

	for _, name in ipairs(BUTTONS) do
		local b = mainUI:FindFirstChild(name)
		if b and b.Visible and b.Active then
			lastClick = now
			pcall(click, b)
			return
		end
	end
end

local function watchButton(btn)
	btn:GetPropertyChangedSignal("Visible"):Connect(tryClick)
	btn:GetPropertyChangedSignal("Active"):Connect(tryClick)
end

local function watchMainUI(m)
	mainUI = m
	m.ChildAdded:Connect(function(c)
		if c.Name == "ClickBonus" or c.Name == "ClickBonusExtra" then
			watchButton(c)
			task.spawn(tryClick) -- клик сразу, не ждём следующего тика
		end
	end)
	for _, n in ipairs(BUTTONS) do
		local b = m:FindFirstChild(n)
		if b then watchButton(b) end
	end
	tryClick()
end

-- Подписка на PlayerGui (MainUI может появиться позже)
do
	local m = LP.PlayerGui:FindFirstChild("MainUI")
	if m then watchMainUI(m) end
	LP.PlayerGui.ChildAdded:Connect(function(c)
		if c.Name == "MainUI" then watchMainUI(c) end
	end)
end

-- Страховка: дешёвый поллинг 5 Гц на случай, если сигналы не сработали
task.spawn(function()
	while task.wait(0.2) do tryClick() end
end)