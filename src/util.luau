--!strict
-- Paralyz / src/util.luau
-- Character, tool, juice, rock and camera-aim helpers shared by every module.

return function(deps)
	local config = deps.config

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")

	local util = {}

	util.Players = Players
	util.ReplicatedStorage = ReplicatedStorage
	util.RunService = RunService

	local LocalPlayer = Players.LocalPlayer

	------------------------------------------------------------------ character
	function util.character()
		return LocalPlayer.Character
	end

	function util.humanoid(): Humanoid?
		local char = util.character()
		return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	end

	function util.root(): BasePart?
		local char = util.character()
		return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	function util.alive(): boolean
		local hum = util.humanoid()
		return hum ~= nil and hum.Health > 0
	end

	-------------------------------------------------------------------- tools
	local function toolList(): { Instance }
		local char = util.character()
		local out = {}
		for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
			table.insert(out, t)
		end
		if char then
			for _, t in ipairs(char:GetChildren()) do
				if t:IsA("Tool") then
					table.insert(out, t)
				end
			end
		end
		return out
	end

	function util.findTool(namePattern: string): Tool?
		local needle = string.lower(namePattern)
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") and string.find(string.lower(t.Name), needle, 1, true) then
				return t
			end
		end
		return nil
	end

	-- Pickaxes, best first: Op > Omega > Diamond > Metal > Iron > plain Pickaxe.
	local PICKAXE_RANK = { "op", "omega", "diamond", "metal", "iron", "pickaxe" }

	function util.bestPickaxe(): Tool?
		local found = {}
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") and string.find(string.lower(t.Name), "pickaxe", 1, true) then
				table.insert(found, t)
			end
		end
		if #found == 0 then
			return nil
		end
		local best, bestRank = found[1], #PICKAXE_RANK
		for _, t in ipairs(found) do
			local low = string.lower(t.Name)
			for i, key in ipairs(PICKAXE_RANK) do
				if string.find(low, key, 1, true) and i < bestRank then
					best, bestRank = t, i
					break
				end
			end
		end
		return best
	end

	function util.isEquipped(tool: Tool): boolean
		local char = util.character()
		return char ~= nil and tool.Parent == char
	end

	-- Equip and wait until the tool really is in the character.
	function util.equip(tool: Tool, timeout: number?): boolean
		if not tool then
			return false
		end
		if util.isEquipped(tool) then
			return true
		end
		local char = util.character()
		if not char then
			return false
		end
		tool.Parent = char
		local deadline = os.clock() + (timeout or 2)
		while os.clock() < deadline do
			if util.isEquipped(tool) then
				return true
			end
			task.wait(0.05)
		end
		return util.isEquipped(tool)
	end

	function util.equippedTool(): Tool?
		local char = util.character()
		return char and char:FindFirstChildOfClass("Tool") :: Tool?
	end

	-------------------------------------------------------------------- juice
	-- MoonJuice is carried as ordinary Tools that own a Credits NumberValue;
	-- the sell remote counts them, so this list is the whole currency model.
	function util.juiceTools(): { { tool: Tool, credits: number } }
		local out = {}
		for _, t in ipairs(toolList()) do
			if t:IsA("Tool") then
				local c = t:FindFirstChild("Credits")
				if c and c:IsA("NumberValue") then
					table.insert(out, { tool = t, credits = c.Value })
				end
			end
		end
		return out
	end

	function util.juiceCount(): number
		return #util.juiceTools()
	end

	function util.juiceValue(): number
		local total = 0
		for _, entry in ipairs(util.juiceTools()) do
			total += entry.credits
		end
		return total
	end

	function util.credits(): number
		local stats = LocalPlayer:FindFirstChild("Stats")
		local credits = stats and stats:FindFirstChild("Credits")
		return credits and (credits :: NumberValue).Value or 0
	end

	-- Sells the whole stack. This is the exact call the game's own
	-- "sell everything" button makes, so the server treats it identically.
	function util.sellAll(): number
		local count = util.juiceCount()
		if count == 0 then
			return 0
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("SellMoonjuice")
		if remote then
			(remote :: RemoteEvent):FireServer(count, true)
		end
		return count
	end

	-------------------------------------------------------------------- rocks
	-- Rocks live in a folder called "Rocks" somewhere under each planet - on
	-- some planets it is a direct child, on others it hangs off the planet's
	-- Center part - and the server fills it in waves.
	function util.rocks(): { BasePart }
		local out = {}
		local planets = workspace:FindFirstChild("Planets")
		if not planets then
			return out
		end
		for _, planet in ipairs(planets:GetChildren()) do
			for _, inst in ipairs(planet:GetDescendants()) do
				if inst:IsA("Folder") and inst.Name == "Rocks" then
					for _, rock in ipairs((inst :: Folder):GetChildren()) do
						if rock:IsA("BasePart") then
							table.insert(out, rock)
						end
					end
				end
			end
		end
		return out
	end

	function util.minableRocks(): { BasePart }
		local out = {}
		for _, rock in ipairs(util.rocks()) do
			local flag = rock:FindFirstChild("Minable")
			-- Minable=false has been observed on rocks that still accept a swing,
			-- so the flag is reported but never used as a filter by default.
			if flag == nil or flag:IsA("BoolValue") then
				table.insert(out, rock)
			end
		end
		return out
	end

	function util.nearestRock(from: Vector3?): BasePart?
		local origin = from or (util.root() and util.root().Position)
		if not origin then
			return nil
		end
		local best, bestDist
		for _, rock in ipairs(util.minableRocks()) do
			local d = (rock.Position - origin).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist = rock, d
			end
		end
		return best
	end

	------------------------------------------------------------------ monsters
	function util.monsters(): { Model }
		local out = {}
		local unanchored = workspace:FindFirstChild("Unanchored")
		if not unanchored then
			return out
		end
		for _, folderName in ipairs({ "MoonMonsters", "SmallMoonMonsters" }) do
			local folder = unanchored:FindFirstChild(folderName)
			if folder then
				for _, child in ipairs(folder:GetChildren()) do
					if child:IsA("Model") then
						table.insert(out, child)
					end
				end
			end
		end
		return out
	end

	function util.aliveMonsters(): { Model }
		local out = {}
		for _, model in ipairs(util.monsters()) do
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				table.insert(out, model)
			end
		end
		return out
	end

	function util.nearestMonster(from: Vector3?, maxDist: number?): Model?
		local origin = from or (util.root() and util.root().Position)
		if not origin then
			return nil
		end
		local best, bestDist
		for _, model in ipairs(util.aliveMonsters()) do
			local pivot = model:GetPivot().Position
			local d = (pivot - origin).Magnitude
			if (not maxDist or d <= maxDist) and (not bestDist or d < bestDist) then
				best, bestDist = model, d
			end
		end
		return best
	end

	--------------------------------------------------------------------- aim
	-- The game asks the client for Mouse.Target when a tool is activated, so
	-- mining only works when the camera's ray through the mouse really lands on
	-- the rock. This solves a camera CFrame that makes that true, then holds it.
	local AIM_BIND = "ParalyzAim"

	function util.stopAim()
		pcall(function()
			RunService:UnbindFromRenderStep(AIM_BIND)
		end)
	end

	local function solveAimCFrame(targetPos: Vector3, standOff: number): CFrame?
		local cam = workspace.CurrentCamera
		if not cam then
			return nil
		end
		local mouse = LocalPlayer:GetMouse()
		local mousePx = Vector2.new(mouse.X, mouse.Y)

		-- Keep the current side of the target so the view never flips.
		local offset = cam.CFrame.Position - targetPos
		if offset.Magnitude < 1 then
			offset = Vector3.new(0, 1, 0)
		end
		local base = targetPos + offset.Unit * standOff + Vector3.new(0, 3, 0)

		local cf = CFrame.lookAt(base, targetPos)
		for _ = 1, 12 do
			cam.CFrame = cf
			local ray = cam:ViewportPointToRay(mousePx.X, mousePx.Y)
			local desired = targetPos - ray.Origin
			if desired.Magnitude < 1 then
				break
			end
			desired = desired.Unit
			cf = cf
				* CFrame.lookAt(Vector3.zero, ray.Direction)
					:ToObjectSpace(CFrame.lookAt(Vector3.zero, desired))
		end
		return cf
	end

	-- Returns true when the camera is locked on and the mouse sees the target.
	function util.aimAt(targetPos: Vector3?, standOff: number?): boolean
		local target = targetPos or (util.root() and util.root().Position)
		if not target then
			return false
		end
		local cf = solveAimCFrame(target, standOff or config.farm.aimDistance)
		if not cf then
			return false
		end
		local cam = workspace.CurrentCamera
		util.stopAim()
		RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, function()
			cam.CFrame = cf
		end)
		task.wait() -- let the frame land so Mouse.Target refreshes
		return util.mouseTarget() == target
	end

	function util.mouseTarget(): BasePart?
		return LocalPlayer:GetMouse().Target :: BasePart?
	end

	-------------------------------------------------------------------- misc
	function util.dist(a: Vector3, b: Vector3): number
		return (a - b).Magnitude
	end

	function util.lookAt(pos: Vector3)
		local cam = workspace.CurrentCamera
		local root = util.root()
		if cam and root then
			cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
		end
	end

	-- Notification hook the loader installs once the window exists.
	local notifyFn: ((title: string, content: string?) -> ())? = nil

	function util.setNotify(fn)
		notifyFn = fn
	end

	function util.notify(title: string, content: string?)
		if notifyFn then
			task.spawn(pcall, notifyFn, title, content)
		end
	end

	function util.safe(fn, ...)
		local args = table.pack(...)
		local ok, res = pcall(function()
			return fn(table.unpack(args, 1, args.n))
		end)
		if ok then
			return res
		end
		return nil
	end

	return util
end
