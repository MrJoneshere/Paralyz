--!strict
-- Paralyz / src/promptkey.luau
-- F8 prompt auto-fire (user request 2026-10-12): while toggled on, the
-- nearest enabled ProximityPrompt in range is fired every 0.1s - bulk
-- converting at the Omega/Ion machines without spamming the key.
--
-- Why a toggle instead of "repeat while the prompt key is held": prompt
-- keys are per-prompt (each prompt carries its own KeyboardKeyCode), and
-- blind auto-repeat on EVERY held prompt would also double-fire purchase
-- prompts (hold-to-buy = multiple buys). A conscious toggle standing at
-- the machine is safe and needs no key detection at all.
--
-- Uses the same fireproximityprompt builtin as instantprompts. Never moves
-- the character. Nearest = closest enabled prompt within its own
-- MaxActivationDistance of the character root.

return function(deps)
	local util = deps.util

	local promptkey = {}

	local KEY = Enum.KeyCode.F8
	local RATE = 0.1 -- seconds between auto-fires

	local UIS = game:GetService("UserInputService")
	local Players = game:GetService("Players")

	local listening = false
	local autofiring = false
	local conn: RBXScriptConnection? = nil

	local function nearestPrompt(): ProximityPrompt?
		local plr = Players.LocalPlayer
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return nil
		end
		local best: ProximityPrompt? = nil
		local bestDist = math.huge
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled and d.MaxActivationDistance > 0 then
				-- Adornee is the prompt's PARENT (BasePart / Attachment / Model).
				local pos = nil
				local par = d.Parent
				if par then
					if par:IsA("BasePart") then
						pos = par.Position
					elseif par:IsA("Attachment") then
						pos = par.WorldPosition
					else
						local bp = par:FindFirstChildWhichIsA("BasePart", true)
						if bp then
							pos = bp.Position
						end
					end
				end
				if pos then
					local dist = (pos - root.Position).Magnitude
					if dist <= d.MaxActivationDistance and dist < bestDist then
						bestDist = dist
						best = d
					end
				end
			end
		end
		return best
	end

	local function fireLoop()
		while autofiring do
			local p = nearestPrompt()
			if p then
				pcall(fireproximityprompt, p)
			end
			task.wait(RATE)
		end
	end

	local function toggle()
		autofiring = not autofiring
		if autofiring then
			task.spawn(fireLoop)
		end
		if util and util.notify then
			util.notify("Prompt auto", autofiring and "ON - firing the nearest prompt 10x/s" or "OFF")
		end
	end

	function promptkey.start()
		if listening then
			return
		end
		if type(fireproximityprompt) ~= "function" then
			if util and util.notify then
				util.notify("Prompt auto", "this executor has no fireproximityprompt")
			end
			return
		end
		listening = true
		do
			-- Reload-safety: live-reload stacks listeners across reloads,
			-- which multi-fires the key. Oldest generation owns F8 forever.
			local env: any = getgenv()
			if env["ParalyzOwn_key_promptkey"] then
				return
			end
			env["ParalyzOwn_key_promptkey"] = true
		end
		-- Not gated on gameProcessed (same lesson as minekey F7): GUIs claim
		-- keys and mark them processed; only a focused text box blocks F8.
		conn = UIS.InputBegan:Connect(function(input)
			if input.KeyCode ~= KEY then
				return
			end
			if UIS:GetFocusedTextBox() then
				return
			end
			toggle()
		end)
	end

	function promptkey.stop()
		autofiring = false
		listening = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	function promptkey.isRunning(): boolean
		return listening
	end

	function promptkey.isFiring(): boolean
		return autofiring
	end

	return promptkey
end
