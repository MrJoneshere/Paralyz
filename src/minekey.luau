--!strict
-- Paralyz / src/minekey.luau
-- Keybind auto-mining (user request 2026-10-12): F7 toggles continuous
-- pickaxe swings while a pickaxe is equipped - "hold-to-mine without
-- holding", made for going AFK on top of a mining spot.
--
-- It only ever calls Tool:Activate() - the exact call the auto-farm and
-- hold-to-mine use - at the same proven 0.15s floor. Nothing in here
-- moves the character, touches the camera or fires anything itself; the
-- game's own tool logic does the mining.
--
-- Rules kept from holdmine:
--   * pickaxes only (name contains "pickaxe", same test as util.bestPickaxe).
--   * no pickaxe equipped = the loop idles (swings nothing).
--   * stop() on unload kills the loop for good.
--   * gameProcessed keys are ignored (typing in chat never toggles).
--
-- Hidden feature, no GUI entry (user's choice); a toast reports the state
-- on every toggle so it is never a mystery.

return function(deps)
	local util = deps.util

	local minekey = {}

	local KEY = Enum.KeyCode.F7
	local CADENCE = 0.15 -- seconds between swings (proven clamp floor)

	local UIS = game:GetService("UserInputService")

	local listening = false
	local swinging = false
	local conn: RBXScriptConnection? = nil

	local function isPickaxe(tool: Tool): boolean
		return string.find(string.lower(tool.Name), "pickaxe", 1, true) ~= nil
	end

	local function swingLoop()
		while swinging do
			local tool = util.equippedTool()
			if tool and isPickaxe(tool) then
				pcall(function()
					tool:Activate()
				end)
			end
			task.wait(CADENCE)
		end
	end

	local function toggle()
		swinging = not swinging
		if swinging then
			task.spawn(swingLoop)
		end
		if util and util.notify then
			util.notify("Auto-mine", swinging and "ON - swinging while a pickaxe is equipped" or "OFF")
		end
	end

	function minekey.start()
		if listening then
			return
		end
		listening = true
		conn = UIS.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode == KEY then
				toggle()
			end
		end)
	end

	function minekey.stop()
		swinging = false
		listening = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	function minekey.isRunning(): boolean
		return listening
	end

	function minekey.isSwinging(): boolean
		return swinging
	end

	return minekey
end
