--!strict
-- Paralyz / src/hover.luau
-- F6 hover hold (user request 2026-10-12): "while flying when i stop it
-- doesnt just stop it falls very slowly" - freeze in place mid-air on
-- demand.
--
-- Mechanic: on toggle, parent a BodyVelocity named ParalyzHover to the
-- HumanoidRootPart - velocity (0,0,0) on all axes, MaxForce 1e6, P 1e4.
-- That fully cancels gravity and momentum (their fly has no hold force
-- when idle, so the character used to sink). Toggle off destroys it and
-- normal physics resume exactly where you hang. Works with any flight:
-- their hub's fly, the game's ship, or plain jumping off an asteroid.
--
-- Hidden keybind + toast, like F7/F8. F6 chosen because F9 opens the
-- Roblox dev console. Skipped while seated (never fights a vehicle
-- weld); auto-releases on respawn/character swap. stop() on unload
-- always destroys the force.

return function(deps)
	local util = deps.util

	local hover = {}

	local KEY = Enum.KeyCode.F6

	local UIS = game:GetService("UserInputService")
	local Players = game:GetService("Players")

	local listening = false
	local hovering = false
	local conn: RBXScriptConnection? = nil
	local charConn: RBXScriptConnection? = nil
	local bv: BodyVelocity? = nil

	local function release()
		if bv then
			pcall(function()
				bv:Destroy()
			end)
			bv = nil
		end
	end

	-- Returns false when the character can't hover (seated / missing).
	local function apply(): boolean
		local char = Players.LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum) or hum.Health <= 0 or hum.SeatPart then
			return false
		end
		local v = Instance.new("BodyVelocity")
		v.Name = "ParalyzHover"
		v.Velocity = Vector3.zero
		v.MaxForce = Vector3.new(1000000, 1000000, 1000000)
		v.P = 10000
		v.Parent = hrp
		bv = v
		return true
	end

	local function toggle()
		if hovering then
			hovering = false
			release()
		else
			if not apply() then
				if util and util.notify then
					util.notify("Hover", "can't hover right now (seated or no character)")
				end
				return
			end
			hovering = true
		end
		if util and util.notify then
			util.notify("Hover", hovering and "ON - frozen in place, F6 to release" or "OFF")
		end
	end

	function hover.start()
		if listening then
			return
		end
		listening = true
		-- Not gated on gameProcessed (same lesson as F7/F8): only a
		-- focused text box blocks the key.
		conn = UIS.InputBegan:Connect(function(input)
			if input.KeyCode ~= KEY then
				return
			end
			if UIS:GetFocusedTextBox() then
				return
			end
			toggle()
		end)
		charConn = Players.LocalPlayer.CharacterAdded:Connect(function()
			if hovering then
				hovering = false
				release()
			end
		end)
	end

	function hover.stop()
		hovering = false
		listening = false
		release()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if charConn then
			charConn:Disconnect()
			charConn = nil
		end
	end

	function hover.isRunning(): boolean
		return listening
	end

	function hover.isHovering(): boolean
		return hovering
	end

	return hover
end
