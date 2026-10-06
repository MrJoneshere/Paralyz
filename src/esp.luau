--!strict
-- Paralyz / src/esp.luau
-- Drawing-library overlays: players, monsters, juice tanks and rocks.
--
-- Uses Camera:WorldToViewportPoint (WorldToScreenPoint is wrong for Drawing),
-- refreshes targets on a slow scan interval, and redraws labels every frame.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local DrawingAny = (getgenv and getgenv().Drawing) or Drawing
	local Players = util.Players
	local RunService = util.RunService
	local esp = {}

	------------------------------------------------------------------ labels
	local label = nil
	local enabled = false

	local function makeLabel()
		if label then
			return label
		end
		if not DrawingAny then
			return nil
		end
		local ok, made = pcall(function()
			return DrawingAny.new("Text")
		end)
		if not ok then
			return nil
		end
		made.Size = 14
		made.Center = true
		made.Outline = true
		made.Font = 2 -- Roboto Mono
		made.Visible = false
		label = made
		return label
	end

	-- Each target type resolves to { pos, text, color, priority }.
	local function scanPlayers()
		local out = {}
		local myRoot = util.root()
		local origin = myRoot and myRoot.Position or Vector3.zero
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= Players.LocalPlayer then
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if char and root and hum and hum.Health > 0 then
					local pos = (root :: BasePart).Position
					local d = util.dist(origin, pos)
					if d <= config.esp.maxDistance then
						table.insert(out, {
							pos = pos,
							text = string.format(
								"%s  %d/%d  [%dm]",
								player.DisplayName,
								math.floor(hum.Health),
								math.floor(hum.MaxHealth),
								math.floor(d)
							),
							color = config.esp.colors.player,
						})
					end
				end
			end
		end
		return out
	end

	local function scanMonsters()
		local out = {}
		local myRoot = util.root()
		local origin = myRoot and myRoot.Position or Vector3.zero
		for _, model in ipairs(util.aliveMonsters()) do
			local pos = model:GetPivot().Position
			local d = util.dist(origin, pos)
			if d <= config.esp.maxDistance then
				local hum = model:FindFirstChildOfClass("Humanoid")
				table.insert(out, {
					pos = pos,
					text = string.format(
						"%s  %d  [%dm]",
						model.Name,
						math.floor(hum and hum.Health or 0),
						math.floor(d)
					),
					color = config.esp.colors.monster,
				})
			end
		end
		return out
	end

	-- MoonJuice tanks lying around the world (tools under Workspace.Unanchored).
	local function scanJuice()
		local out = {}
		local myRoot = util.root()
		local origin = myRoot and myRoot.Position or Vector3.zero
		local unanchored = workspace:FindFirstChild("Unanchored")
		if not unanchored then
			return out
		end
		for _, inst in ipairs(unanchored:GetChildren()) do
			if inst:IsA("Tool") and inst:FindFirstChild("Credits") then
				local part = inst:FindFirstChildWhichIsA("BasePart", true)
				if part then
					local pos = (part :: BasePart).Position
					local d = util.dist(origin, pos)
					if d <= config.esp.maxDistance then
						local credits = inst:FindFirstChild("Credits")
						table.insert(out, {
							pos = pos,
							text = string.format(
								"Juice %d [%dm]",
								math.floor(credits and (credits :: NumberValue).Value or 0),
								math.floor(d)
							),
							color = config.esp.colors.juice,
						})
					end
				end
			end
		end
		return out
	end

	local function scanRocks()
		local out = {}
		local myRoot = util.root()
		local origin = myRoot and myRoot.Position or Vector3.zero
		for _, rock in ipairs(util.minableRocks()) do
			local d = util.dist(origin, rock.Position)
			if d <= config.esp.maxDistance then
				table.insert(out, {
					pos = rock.Position,
					text = string.format("Rock [%dm]", math.floor(d)),
					color = config.esp.colors.rock,
				})
			end
		end
		return out
	end

	--------------------------------------------------------------- scan loop
	local targets = {}
	local scanConn: RBXScriptConnection? = nil

	local function scan()
		-- Merge all enabled layers into one list; nearest wins the label.
		local list = {}
		if state.enabled("ESPPlayers") then
			for _, t in ipairs(scanPlayers()) do
				table.insert(list, t)
			end
		end
		if state.enabled("ESPMonsters") then
			for _, t in ipairs(scanMonsters()) do
				table.insert(list, t)
			end
		end
		if state.enabled("ESPJuice") then
			for _, t in ipairs(scanJuice()) do
				table.insert(list, t)
			end
		end
		if state.enabled("ESPRocks") then
			for _, t in ipairs(scanRocks()) do
				table.insert(list, t)
			end
		end
		targets = list
	end

	--------------------------------------------------------------- draw loop
	local drawConn: RBXScriptConnection? = nil

	local function start()
		if drawConn then
			return
		end
		local text = makeLabel()
		if not text then
			enabled = false -- nothing to draw with; let the next sync retry
			return
		end

		drawConn = RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			if not cam then
				text.Visible = false
				return
			end

			-- Pick the closest visible target and label just that one: one label
			-- keeps the overlay cheap on a GPU that is already at its limit.
			local best, bestScreen
			for _, t in ipairs(targets) do
				local screen, onScreen = cam:WorldToViewportPoint(t.pos)
				if onScreen and screen.Z > 0 then
					local d = screen.Z
					if not bestScreen or d < bestScreen.Z then
						best, bestScreen = t, screen
					end
				end
			end

			if best and bestScreen then
				text.Position = Vector2.new(bestScreen.X, bestScreen.Y)
				text.Text = best.text
				text.Color = best.color
				text.Visible = true
			else
				text.Visible = false
			end
		end)

		scanConn = task.spawn(function()
			while enabled do
				pcall(scan)
				task.wait(config.esp.refresh)
			end
		end)
	end

	local function stop()
		if drawConn then
			drawConn:Disconnect()
			drawConn = nil
		end
		if scanConn then
			-- The scan loop exits by itself once `enabled` goes false; cancel only
			-- matters if it is somehow still alive.
			pcall(task.cancel, scanConn)
			scanConn = nil
		end
		if label then
			label.Visible = false
		end
		targets = {}
	end

	-- Single switch the menu drives.
	function esp.sync()
		local anyOn = state.enabled("ESPPlayers")
			or state.enabled("ESPMonsters")
			or state.enabled("ESPJuice")
			or state.enabled("ESPRocks")

		if anyOn and not enabled then
			enabled = true
			start()
		elseif not anyOn and enabled then
			enabled = false
			stop()
		end
	end

	function esp.stop()
		enabled = false
		stop()
	end

	return esp
end
