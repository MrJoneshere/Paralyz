--!strict
-- Paralyz / src/instantprompts.luau
-- Instant proximity prompts - a direct port of Infinite Yield's ;instantpp.
--
-- IY does NOT zero HoldDuration. Its trick: connect
-- ProximityPromptService.PromptButtonHoldBegan and call the executor builtin
-- fireproximityprompt() the moment the player BEGINS holding a prompt, so the
-- hold never has to finish. uninstantpp disconnects; this module exposes the
-- same thing as start/stop behind the Settings -> Instant Prompts toggle.
--
-- Notes:
--   * fireproximityprompt is a Real builtin (confirmed via search-api).
--   * The connection callback is pcall-wrapped so a bad prompt can never kill
--     the connection or spam errors.
--   * start() is idempotent (conn guard), stop() disconnects cleanly - same
--     reconnect-first shape as IY's execCmd("uninstantproximityprompts").

return function(deps)
	local util = deps.util

	local instantprompts = {}

	local PPS = game:GetService("ProximityPromptService")
	local conn: RBXScriptConnection? = nil
	-- Ownership claim for the single-owner listener pattern: the env token
	-- stops OTHER generations from stacking, this flag keeps stop() ->
	-- start() working inside the owning generation.
	local owns = false

	local function fire(prompt: ProximityPrompt)
		pcall(fireproximityprompt, prompt)
	end

	function instantprompts.start()
		if conn then
			return
		end
		if type(fireproximityprompt) ~= "function" then
			if util and util.notify then
				util.notify("Instant Prompts", "this executor has no fireproximityprompt")
			end
			return
		end
		if not owns then
			-- Reload-safety: stacked hold-began connections multi-fire
			-- every prompt. Oldest generation owns it forever.
			local env: any = getgenv()
			if env["ParalyzOwn_conn_instantprompts"] then
				return
			end
			env["ParalyzOwn_conn_instantprompts"] = true
			owns = true
		end
		conn = PPS.PromptButtonHoldBegan:Connect(fire)
	end

	function instantprompts.stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	function instantprompts.isRunning(): boolean
		return conn ~= nil
	end

	return instantprompts
end
