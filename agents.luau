--!strict
-- Herdr-style agent statuses from Tern's agent blocks (window half).
--
-- Tern reports `idle | working | waiting_input | exited` and has no status
-- event, so this polls `cx.agents:list()` and derives Herdr's statuses:
--   working  — the agent is running
--   blocked  — it waits for your input
--   done     — it went from working to idle and you haven't focused it since
--   idle     — anything else
-- `watch` handlers receive every per-agent transition plus the overall status
-- (blocked > working > done > idle, as led-agent-status reduces them).

export type Status = "working" | "blocked" | "done" | "idle"
export type Change = {
	-- Agent pane whose status changed; nil for a change caused by nothing but
	-- the poll starting (`overall` only).
	pane: number?,
	from: Status?,
	to: Status?,
	overall: Status,
}

local POLL_MS = 1000

local agents = {}

local handlers: { (Change, WindowCx) -> () } = {}
local status: { [number]: Status } = {}
local overall: Status = "idle"
local started = false
local primed = false

local RANK: { [Status]: number } = { blocked = 4, working = 3, done = 2, idle = 1 }

local function reduce(): Status
	local best: Status = "idle"
	for _, s in status do
		if RANK[s] > RANK[best] then
			best = s
		end
	end
	return best
end

local function emit(change: Change, cx: WindowCx)
	for _, fn in handlers do
		local ok, err = pcall(fn, change, cx)
		if not ok then
			tern.log.warn("agent status handler failed:", err)
		end
	end
end

local function poll(cx: WindowCx)
	local seen: { [number]: boolean } = {}
	local changes: { Change } = {}
	for _, a in cx.agents:list() do
		seen[a.pane] = true
		local before = status[a.pane]
		local now: Status
		if a.state == "working" then
			now = "working"
		elseif a.state == "waiting_input" then
			now = "blocked"
		elseif a.state == "idle" and (before == "working" or before == "done") then
			now = "done"
		else
			now = "idle"
		end
		if now ~= before then
			status[a.pane] = now
			-- An agent first seen is a baseline, not a transition.
			if before then
				table.insert(changes, { pane = a.pane, from = before, to = now, overall = overall })
			end
		end
	end
	for pane, before in status do
		if not seen[pane] then
			status[pane] = nil
			table.insert(changes, { pane = pane, from = before, to = nil, overall = overall })
		end
	end
	local next_overall = reduce()
	local moved = next_overall ~= overall
	overall = next_overall
	for _, c in changes do
		c.overall = overall
		emit(c, cx)
	end
	-- The first poll also reports the baseline, even when nothing moved.
	if (moved or not primed) and #changes == 0 then
		emit({ overall = overall }, cx)
	end
	primed = true
end

local function tick(cx: WindowCx?)
	if cx then
		local ok, err = pcall(poll, cx)
		if not ok then
			tern.log.warn("agent status poll failed:", err)
		end
	end
	tern.timer(POLL_MS, tick)
end

-- Focusing a finished agent marks it seen: done becomes idle.
local function focused(pane: number, cx: WindowCx)
	if status[pane] ~= "done" then
		return
	end
	status[pane] = "idle"
	overall = reduce()
	emit({ pane = pane, from = "done", to = "idle", overall = overall }, cx)
end

-- Registers `fn` for status changes. Call once per plugin at load; this
-- module owns the plugin's `focus` subscription. Polling starts at load, not
-- on `window_start`, which a plugin reload doesn't fire again.
function agents.watch(fn: (Change, WindowCx) -> ())
	table.insert(handlers, fn)
	if started then
		return
	end
	started = true
	tern.timer(0, tick)
	tern.on("focus", function(ev: FocusEvent, cx: WindowCx)
		focused(ev.pane, cx)
	end)
end

-- The current overall status.
function agents.overall(): Status
	return overall
end

return agents
