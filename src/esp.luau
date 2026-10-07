--!strict
-- Paralyz / src/esp.luau
-- Highlight-based ESP with one optional label.
--
-- Kept deliberately boring so it cannot tank a weak GPU:
--   * A pool of Highlight instances capped per layer (config.esp.limits).
--     Highlights are assigned on a slow scan and then cost nothing per
--     frame - Roblox follows the adornee on its own, no redraw loop.
--   * One Drawing label, repositioned every frame to the nearest
--     on-screen target. That is the only per-frame work.
--   * Nothing survives: stop destroys the pool and the folder.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local DrawingAny = (getgenv and getgenv().Drawing) or Drawing
	local Players = util.Players
	local RunService = util.RunService
	local esp = {}

	local enabled = false

	-- The single label: text object plus the entries it may pick from.
	local label = nil
	local labelTargets = {}

	------------------------------------------------------------- highlights
	local folder: Folder? = nil
	local pool: { Highlight } = {}

	local totalLimit = config.esp.limits.players
		+ config.esp.limits.monsters
		+ config.esp.limits.juice
		+ config.esp.limits.rocks

	local function ensureFolder(): Folder
		if folder and folder.Parent then
			return folder
		end
		local f = Instance.new("Folder")
		f.Name = "ParalyzESP"
		f.Parent = workspace
		folder = f
		return f
	end

	local function destroyPool()
		for _, hl in ipairs(pool) do
			pcall(function()
				hl:Destroy()
			end)
		end
		pool = {}
		if folder then
			pcall(function()
				folder:Destroy()
			end)
			folder = nil
		end
	end

	-- One pass: hand each live entry the next pooled Highlight, park the
	-- rest. Entries arrive nearest-first and already capped per layer, so
	-- the nearest targets always win a slot.
	local function applyScan(layers)
		local f = ensureFolder()
		local depth = if config.esp.throughWalls
			then Enum.HighlightDepthMode.AlwaysOnTop
			else Enum.HighlightDepthMode.Occluded
		local idx = 1
		for _, layer in ipairs(layers) do
			for _, e in ipairs(layer.entries) do
				if idx > totalLimit then
					break
				end
				if idx > #pool then
					local hl = Instance.new("Highlight")
					hl.Name = "ParalyzESP"
					hl.Parent = f
					table.insert(pool, hl)
				end
				local hl = pool[idx]
				hl.Adornee = e.inst
				hl.FillColor = e.color
				hl.OutlineColor = e.color
				hl.FillTransparency = config.esp.fill
				hl.OutlineTransparency = config.esp.outline
				hl.DepthMode = depth
				hl.Enabled = true
				idx += 1
			end
		end
		for i = idx, #pool do
			pool[i].Enabled = false
			pool[i].Adornee = nil
		end
	end

	--------------------------------------------------------------- scanning
	-- Entries: { inst, pos, text, color, d } nearest-first, capped.

	local function origin(): Vector3
		local root = util.root()
		return root and root.Position or Vector3.zero
	end

	local function slice(list, cap)
		for i = #list, cap + 1, -1 do
			table.remove(list, i)
		end
		return list
	end

	local function scanPlayers()
		local out = {}
		local o = origin()
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= Players.LocalPlayer then
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if char and root and hum and (hum :: Humanoid).Health > 0 then
					local d = util.dist(o, (root :: BasePart).Position)
					if d <= config.esp.maxDistance then
						table.insert(out, {
							inst = char,
							pos = (root :: BasePart).Position,
							text = string.format(
								"%s  %d/%d  [%dm]",
								player.DisplayName,
								math.floor((hum :: Humanoid).Health),
								math.floor((hum :: Humanoid).MaxHealth),
								math.floor(d)
							),
							color = config.esp.colors.player,
							d = d,
						})
					end
				end
			end
		end
		table.sort(out, function(a, b)
			return a.d < b.d
		end)
		return slice(out, config.esp.limits.players)
	end

	local function scanMonsters()
		local out = {}
		local o = origin()
		for _, model in ipairs(util.aliveMonsters()) do
			local pivot = model:GetPivot().Position
			local d = util.dist(o, pivot)
			if d <= config.esp.maxDistance then
				local hum = model:FindFirstChildOfClass("Humanoid")
				table.insert(out, {
					inst = model,
					pos = pivot,
					text = string.format(
						"%s  %d  [%dm]",
						model.Name,
						math.floor(hum and hum.Health or 0),
						math.floor(d)
					),
					color = config.esp.colors.monster,
					d = d,
				})
			end
		end
		table.sort(out, function(a, b)
			return a.d < b.d
		end)
		return slice(out, config.esp.limits.monsters)
	end

	-- MoonJuice tanks lying around the world (tools under Workspace.Unanchored).
	local function scanJuice()
		local out = {}
		local o = origin()
		local unanchored = workspace:FindFirstChild("Unanchored")
		if not unanchored then
			return out
		end
		for _, inst in ipairs(unanchored:GetChildren()) do
			if inst:IsA("Tool") and inst:FindFirstChild("Credits") then
				local part = inst:FindFirstChildWhichIsA("BasePart", true)
				if part then
					local d = util.dist(o, (part :: BasePart).Position)
					if d <= config.esp.maxDistance then
						local credits = inst:FindFirstChild("Credits")
						table.insert(out, {
							inst = part :: BasePart,
							pos = (part :: BasePart).Position,
							text = string.format(
								"Juice %d [%dm]",
								math.floor(credits and (credits :: NumberValue).Value or 0),
								math.floor(d)
							),
							color = config.esp.colors.juice,
							d = d,
						})
					end
				end
			end
		end
		table.sort(out, function(a, b)
			return a.d < b.d
		end)
		return slice(out, config.esp.limits.juice)
	end

	local function scanRocks()
		local out = {}
		local o = origin()
		for _, rock in ipairs(util.minableRocks()) do
			local d = util.dist(o, rock.Position)
			if d <= config.esp.maxDistance then
				table.insert(out, {
					inst = rock,
					pos = rock.Position,
					text = string.format("Rock [%dm]", math.floor(d)),
					color = config.esp.colors.rock,
					d = d,
				})
			end
		end
		table.sort(out, function(a, b)
			return a.d < b.d
		end)
		return slice(out, config.esp.limits.rocks)
	end

	local function scan()
		local layers = {}
		local merged = {}
		if state.enabled("ESPPlayers") then
			local entries = scanPlayers()
			table.insert(layers, { entries = entries })
			for _, e in ipairs(entries) do
				table.insert(merged, e)
			end
		end
		if state.enabled("ESPMonsters") then
			local entries = scanMonsters()
			table.insert(layers, { entries = entries })
			for _, e in ipairs(entries) do
				table.insert(merged, e)
			end
		end
		if state.enabled("ESPJuice") then
			local entries = scanJuice()
			table.insert(layers, { entries = entries })
			for _, e in ipairs(entries) do
				table.insert(merged, e)
			end
		end
		if state.enabled("ESPRocks") then
			local entries = scanRocks()
			table.insert(layers, { entries = entries })
			for _, e in ipairs(entries) do
				table.insert(merged, e)
			end
		end
		applyScan(layers)
		labelTargets = merged
	end

	------------------------------------------------------------------ label
	local function ensureLabel()
		if label or not DrawingAny then
			return label
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

	--------------------------------------------------------------- run loop
	local scanConn: thread? = nil
	local drawConn: RBXScriptConnection? = nil

	local function start()
		if drawConn then
			return
		end
		ensureLabel()

		drawConn = RunService.RenderStepped:Connect(function()
			local text = label
			if not text then
				return
			end
			if not state.enabled("ESPLabels") then
				text.Visible = false
				return
			end
			local cam = workspace.CurrentCamera
			if not cam then
				text.Visible = false
				return
			end

			-- Nearest on-screen target wins the single label.
			local best, bestScreen
			for _, t in ipairs(labelTargets) do
				local screen, onScreen = cam:WorldToViewportPoint(t.pos)
				if onScreen and screen.Z > 0 then
					if not bestScreen or screen.Z < bestScreen.Z then
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
			pcall(task.cancel, scanConn)
			scanConn = nil
		end
		if label then
			label.Visible = false
		end
		labelTargets = {}
		destroyPool()
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
