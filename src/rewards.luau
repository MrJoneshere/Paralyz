--!strict
-- Paralyz / src/rewards.luau
-- Free income that needs no player input.
--
-- Two paths, both measured safe in earlier sessions:
--   * Playtime: the server pushes Events.PlaytimeReward {Action = "Ready"}
--     on its1800s cycle; answering with Events.PlaytimeClaim:FireServer()
--     pays the chest. Pure listener - no polling, no input.
--   * Daily/Weekly quests: Knit QuestService:GetQuests() (may return a
--     table or a promise - both handled), then ClaimQuest(kind, id) for
--     anything Complete and not Claimed. A Daily claim paid +150 credits
--     when first verified.
--
-- The poll also gives the menu something honest to show: what is ready.

return function(deps)
	local config = deps.config
	local state = deps.state
	local util = deps.util

	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local rewards = {}

	local running = false
	local playtimeConn: RBXScriptConnection? = nil
	local claimedNow = 0
	local lastSummary = "not checked yet"

	------------------------------------------------------------- playtime
	local function startPlaytime()
		if playtimeConn then
			return
		end
		local events = ReplicatedStorage:FindFirstChild("Events")
		local reward = events and events:FindFirstChild("PlaytimeReward")
		local claim = events and events:FindFirstChild("PlaytimeClaim")
		if not (reward and claim) then
			return
		end
		playtimeConn = (reward :: RemoteEvent).OnClientEvent:Connect(function(a1, a2)
			-- Payload shape observed as a table {Action = "Ready"}; accept a
			-- bare "Ready" string too rather than miss the window.
			local ready = (type(a1) == "table" and (a1 :: any).Action == "Ready")
				or a1 == "Ready"
				or (type(a2) == "table" and (a2 :: any).Action == "Ready")
			if not ready then
				return
			end
			pcall(function()
				(claim :: RemoteEvent):FireServer()
			end)
			claimedNow += 1
			util.notify("Playtime", "chest ready - claimed")
		end)
	end

	local function stopPlaytime()
		if playtimeConn then
			playtimeConn:Disconnect()
			playtimeConn = nil
		end
	end

	---------------------------------------------------------------- quests
	local function getQuestService(): any?
		local ok, knit = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
		end)
		if not ok then
			return nil
		end
		local ok2, service = pcall(function()
			return (knit :: any).GetService("QuestService")
		end)
		if not ok2 then
			return nil
		end
		return service
	end

	local function fetchQuests(service: any): { [string]: any }?
		local ok, res = pcall(function()
			return service:GetQuests()
		end)
		if not ok then
			return nil
		end
		-- Knit may hand back a promise; await it inside the same guard.
		if typeof(res) == "Promise" then
			local ok2, val = pcall(function()
				return (res :: any):await()
			end)
			if not ok2 then
				return nil
			end
			res = val
		end
		if type(res) ~= "table" then
			return nil
		end
		return res
	end

	-- One pass: claim everything ready, summarise the rest. Returns the
	-- number of claims fired.
	function rewards.claimReady(): number
		local service = getQuestService()
		if not service then
			return 0
		end
		local quests = fetchQuests(service)
		if not quests then
			return 0
		end
		local claimed = 0
		local ready = 0
		local total = 0
		for _, kind in ipairs({ "Daily", "Weekly" }) do
			local bucket = (quests :: any)[kind]
			if type(bucket) == "table" then
				for _, quest in pairs(bucket) do
					if type(quest) == "table" then
						total += 1
						if (quest :: any).Complete and not (quest :: any).Claimed then
							ready += 1
							local ok = pcall(function()
								service:ClaimQuest(kind, (quest :: any).Id)
							end)
							if ok then
								claimed += 1
								local reward = (quest :: any).Reward
								util.notify(
									"Quest claimed",
									string.format(
										"%s: %s (+%s %s)",
										kind,
										(quest :: any).Name or (quest :: any).Id,
										reward and tostring(reward.Amount) or "?",
										reward and tostring(reward.Type) or "reward"
									)
								)
							end
							task.wait(0.3) -- one claim at a time, politely
						end
					end
				end
			end
		end
		claimedNow += claimed
		lastSummary = ready > 0
				and string.format("%d ready / %d total - claimed %d", ready, total, claimed)
			or string.format("all clear - %d quests tracked", total)
		return claimed
	end

	----------------------------------------------------------------- loop
	-- A RemoteFunction that never returns would freeze this loop inside
	-- pcall forever - pcall catches errors, not hangs, and this game has
	-- proven RFs can wedge (see NOTES: ServerControl). So each pass runs
	-- in its own thread with a completion flag: a pass that does not come
	-- back within config.rewards.passTimeout is abandoned (one zombie
	-- thread, never more) and the loop keeps ticking. A merely-slow pass
	-- self-heals: when it finally returns, it clears the flag and the
	-- normal cadence resumes.
	local passPending = false
	local hangNotified = false

	local function pollLoop()
		while running do
			if state.enabled("AutoRewards") then
				if passPending then
					if not hangNotified then
						hangNotified = true
						util.notify(
							"Rewards",
							"quest pass stopped answering - pausing quest claims (playtime chests still auto-claim)"
						)
					end
				else
					passPending = true
					task.spawn(function()
						pcall(function()
							rewards.claimReady()
						end)
						passPending = false
						hangNotified = false
					end)
					-- Give a healthy pass time to finish in-place so stats
					-- refresh promptly; timeout just moves on to the wait.
					local t0 = os.clock()
					while passPending and os.clock() - t0 < config.rewards.passTimeout do
						task.wait(0.25)
					end
				end
			end
			task.wait(config.rewards.pollDelay)
		end
	end

	function rewards.start(): boolean
		if running then
			return false
		end
		running = true
		startPlaytime()
		task.spawn(pollLoop)
		return true
	end

	function rewards.stop()
		running = false
		stopPlaytime()
	end

	function rewards.sync()
		-- The listener runs regardless (a free chest arriving while the
		-- toggle is off should still be grabbed); the poll only claims
		-- quests while AutoRewards is on.
		if not playtimeConn then
			startPlaytime()
		end
	end

	function rewards.stats(): string
		return string.format("%d claimed - %s", claimedNow, lastSummary)
	end

	return rewards
end
