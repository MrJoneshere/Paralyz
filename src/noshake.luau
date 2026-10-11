--!strict
-- Paralyz / src/noshake.luau
-- Auto-disable screen shake at script execution (user request 2026-10-12):
-- "whenever the script is executed it waits no time and just turns off
-- screen shake from settings so i dont need to do that, in any place".
-- Quiet by design - no toast, it just happens.
--
-- How the game does it (reverse-engineered read-only, subplace index):
--   * Settings row click [docId 39]:
--       if Display.Text == "Enabled" then
--           Display.Text = "Disabled"
--           Image = <disabled graphic>
--           Events.CameraShake:FireServer(true)   <- the DISABLE action
--       end
--   * The server answers by parenting a NumberValue "Anti Screen Shake"
--     into the player.
--   * PlayerGui ScreenGui.CameraShake [docId 36] skips EVERY shake while
--     that object exists:
--       if not LocalPlayer:FindFirstChild("Anti Screen Shake") then
--           u18:ShakeOnce(...)
--       end
--   * The object is never created by any indexed game script, so it is
--     wiped with the player on rejoin -> the user's manual every-session
--     chore. This module replays their exact manual action instead.
--
-- Implementation: if the object is missing, FireServer(true) - the same
-- remote call the settings button makes - then verify it appeared (3s).
-- If the server never answers, parent the same NumberValue client-side:
-- the only consumer checks presence, so the effect is identical. The row
-- UI (Display "Disabled" + matching image) is synced so the settings menu
-- shows the true state when opened later. Boot-time only: if you later
-- deliberately re-enable shake in settings, this does not fight you.

return function(deps)
	local util = deps.util

	local noshake = {}

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local OBJ = "Anti Screen Shake"
	local DISABLED_IMAGE = "rbxassetid://124658924075155" -- row image when Display = "Disabled"

	local running = false

	local function exists(): boolean
		return Players.LocalPlayer:FindFirstChild(OBJ) ~= nil
	end

	-- Replay the settings row's disable click exactly.
	local function fireDisable(): boolean
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("CameraShake")
		if not remote then
			return false
		end
		return pcall(function()
			remote:FireServer(true)
		end)
	end

	-- Fallback: parent the same object locally. CameraShake only checks
	-- presence, so a client-side copy fully blocks the shake event.
	local function makeLocal()
		if exists() then
			return
		end
		pcall(function()
			local v = Instance.new("NumberValue")
			v.Name = OBJ
			v.Value = 0
			v.Parent = Players.LocalPlayer
		end)
	end

	-- Keep the settings row honest: Display "Disabled" + its image, so
	-- opening the menu later shows the real state. Purely cosmetic and
	-- fully guarded - the settings GUI may not exist in every place.
	local function syncRow()
		pcall(function()
			local plrGui = Players.LocalPlayer.PlayerGui
			local gui = plrGui:FindFirstChild("Settings")
			local frame = gui and gui:FindFirstChild("Frame")
			local main = frame and frame:FindFirstChild("settings main frame")
			if not main then
				return
			end
			local label = nil
			for _, d in ipairs(main:GetDescendants()) do
				if string.find(string.lower(d.Name), "shake", 1, true) then
					label = d
					break
				end
			end
			if not label or not label:IsA("GuiObject") then
				return
			end
			local best = nil
			local bestDy = 0.12
			for _, d in ipairs(main:GetChildren()) do
				if d:IsA("Frame") then
					local dy = math.abs(d.Position.Y.Scale - label.Position.Y.Scale)
					if dy <= bestDy then
						best = d
						bestDy = dy
					end
				end
			end
			if not best then
				return
			end
			local btn = nil
			for _, c in ipairs(best:GetDescendants()) do
				if c:IsA("ImageButton") then
					btn = c
					break
				end
			end
			if not btn then
				return
			end
			btn.Image = DISABLED_IMAGE
			local disp = btn:FindFirstChild("Display")
			if disp and disp:IsA("TextLabel") then
				disp.Text = "Disabled"
			end
		end)
	end

	local function ensure()
		if not exists() then
			fireDisable()
			local t0 = os.clock()
			while not exists() and os.clock() - t0 < 3 do
				task.wait(0.1)
			end
			if not exists() then
				makeLocal()
			end
		end
		syncRow()
	end

	-- Called by the loader immediately after module fetch - before the
	-- window even exists ("waits no time").
	function noshake.start()
		if running then
			return
		end
		running = true
		task.spawn(function()
			local ok, err = pcall(ensure)
			if not ok then
				warn("[Paralyz] noshake failed: " .. tostring(err))
			end
		end)
	end

	function noshake.stop()
		running = false
	end

	function noshake.isRunning(): boolean
		return running
	end

	function noshake.isOff(): boolean
		return exists()
	end

	return noshake
end
