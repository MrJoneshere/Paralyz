--!strict
-- Paralyz / src/holdmine.luau
-- Hidden hold-to-mine (user decision 2026-10-09): always on, no GUI control.
--
-- The game debounces rapid manual left clicks, so spamming does nothing.
-- This listens for a REAL MouseButton1 press and keeps firing Tool:Activate()
-- on the equipped pickaxe until the button is released - the exact call the
-- auto-farm uses, at the farm's proven swing-clamp floor (0.15s). The user
-- aims normally with their camera; only the click spam is automated.
--
-- Rules:
--   * Pickaxes only (name contains "pickaxe", same test as util.bestPickaxe).
--   * Clicks consumed by GUIs are skipped (gameProcessed) - clicking menu
--     buttons never swings.
--   * The loop dies on release, on focus loss (IsMouseButtonPressed goes
--     false) and on unload, so it can never keep swinging on its own.

return function(deps)
	local util = deps.util

	local holdmine = {}

	local CADENCE = 0.15 -- seconds between Activate calls while holding

	local UIS = game:GetService("UserInputService")
	local holding = false
	local started = false
	local beganConn: RBXScriptConnection? = nil
	local endedConn: RBXScriptConnection? = nil

	local function isPickaxe(tool: Tool): boolean
		return string.find(string.lower(tool.Name), "pickaxe", 1, true) ~= nil
	end

	-- Fires while the button is physically held; swings only when a pickaxe
	-- is equipped, so a tool switch mid-hold simply pauses the mining.
	local function swingLoop()
		while holding and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
			local tool = util.equippedTool()
			if tool and isPickaxe(tool) then
				pcall(function()
					tool:Activate()
				end)
			end
			task.wait(CADENCE)
		end
		holding = false
	end

	function holdmine.start()
		if started then
			return
		end
		started = true
		beganConn = UIS.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or holding then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				holding = true
				task.spawn(swingLoop)
			end
		end)
		endedConn = UIS.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				holding = false
			end
		end)
	end

	function holdmine.stop()
		holding = false
		if beganConn then
			beganConn:Disconnect()
			beganConn = nil
		end
		if endedConn then
			endedConn:Disconnect()
			endedConn = nil
		end
		started = false
	end

	function holdmine.isHolding(): boolean
		return holding
	end

	return holdmine
end
