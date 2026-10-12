--!strict
-- Paralyz / src/flystand.luau
-- Upright character while flying (user request 2026-10-12):
-- "when i fly my character starts to spin... make sure it stands like
-- normal even when flying".
--
-- Diagnosis (live probe during the complaint):
--   * Humanoid was in Enum.HumanoidStateType.Physics with a tipped-over
--     HRP orientation (-49, -164, -105) - the ragdoll/physics state.
--   * In Physics state the rig has no motor control: no walk animation,
--     AutoRotate does nothing, and leftover angular momentum makes the
--     character tumble/spin forever.
--   * The game itself has NO character-fly implementation (the Events.Fly
--     remote has zero client callers) - the user flies via their own
--     hub (IY), which never restores the humanoid state afterwards.
--
-- Fix: an always-on 0.1s watchdog - while alive and unseated, leave
-- Physics/PlatformStand via ChangeState(GettingUp) (character snaps
-- upright, animations resume, AutoRotate faces movement again), and
-- damp any rotational momentum (RotVelocity > 1 rad/s -> scaled down).
-- Ground walking never trips it: a standing character is never in
-- Physics state and its RotVelocity is ~0. Silent - no toast, no keybind.

return function(deps)
	local util = deps.util

	local flystand = {}

	local Players = game:GetService("Players")

	local running = false
	local CHECK = 0.1

	local function watch()
		while running do
			task.wait(CHECK)
			if not running then
				break
			end
			local ok, err = pcall(function()
				local char = Players.LocalPlayer.Character
				if not char then
					return
				end
				local hum = char:FindFirstChildOfClass("Humanoid")
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not (hum and hrp) or hum.Health <= 0 or hum.SeatPart then
					return
				end
				local state = hum:GetState()
				if state == Enum.HumanoidStateType.Physics or hum.PlatformStand then
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
				local rv = hrp.RotVelocity
				if rv.Magnitude > 1 then
					hrp.RotVelocity = rv * 0.15
				end
			end)
			if not ok then
				warn("[Paralyz] flystand error: " .. tostring(err))
			end
		end
	end

	function flystand.start()
		if running then
			return
		end
		running = true
		task.spawn(watch)
	end

	function flystand.stop()
		running = false
	end

	function flystand.isRunning(): boolean
		return running
	end

	return flystand
end
