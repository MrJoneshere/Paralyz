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
