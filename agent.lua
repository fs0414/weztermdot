local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

local STATUS_ICON = { idle = "⚫", running = "🔵", unknown = "?" }
local STATUS_NERD_ICON = { idle = "md_robot_off_outline", running = "md_robot" }
local cache = { result = {}, timestamp = 0 }
local CACHE_TTL = 3

-- Walk ppid chain to find a claude ancestor pid
local function find_claude_ancestor(pid, procs, claude_pids)
	local visited = {}
	local current = pid
	while current and current > 1 and not visited[current] do
		visited[current] = true
		if claude_pids[current] then
			return current
		end
		local info = procs[current]
		if not info then
			break
		end
		current = info.ppid
	end
	return nil
end

-- Detect agent status for a single pane; returns status string or nil
local function detect_pane_agent(p, procs, claude_pids, claude_status)
	local ok_info, fg_info = pcall(function()
		return p:get_foreground_process_info()
	end)
	local fg_pid = ok_info and fg_info and fg_info.pid

	if fg_pid and procs[fg_pid] then
		local cpid = find_claude_ancestor(fg_pid, procs, claude_pids)
		return cpid and (claude_status[cpid] or "idle") or nil
	end

	local proc_path = p:get_foreground_process_name() or ""
	local proc_name = proc_path:match("([^/]+)$") or proc_path

	if proc_name:find("claude") then
		return "idle"
	end

	for pid, info in pairs(procs) do
		if info.name == proc_name or info.fullpath == proc_path then
			local cpid = find_claude_ancestor(pid, procs, claude_pids)
			if cpid then
				return claude_status[cpid] or "idle"
			end
		end
	end
	return nil
end

--- Scan all panes for running agents. Results are cached for CACHE_TTL seconds.
function M.scan()
	local now = os.time()
	if now - cache.timestamp < CACHE_TTL then
		return cache.result
	end

	local ok, stdout = wezterm.run_child_process({ "ps", "-eo", "pid,ppid,comm" })
	local procs = {}
	local children = {}
	local claude_pids = {}
	if ok and stdout then
		for line in stdout:gmatch("[^\n]+") do
			local pid_s, ppid_s, comm = line:match("(%d+)%s+(%d+)%s+(.+)")
			if pid_s then
				local pid = tonumber(pid_s)
				local ppid = tonumber(ppid_s)
				local name = comm:gsub("^%s+", ""):gsub("%s+$", "")
				local basename = name:match("([^/]+)$") or name
				procs[pid] = { ppid = ppid, name = basename, fullpath = name }
				if not children[ppid] then
					children[ppid] = {}
				end
				table.insert(children[ppid], pid)
				if basename:find("claude") then
					claude_pids[pid] = true
				end
			end
		end
	end

	-- Claude Code spawns caffeinate while running and kills it when idle.
	local claude_status = {}
	for cpid in pairs(claude_pids) do
		local is_active = false
		for _, child_pid in ipairs(children[cpid] or {}) do
			if procs[child_pid].name == "caffeinate" then
				is_active = true
				break
			end
		end
		claude_status[cpid] = is_active and "running" or "idle"
	end

	local agents = {}
	for _, mux_win in ipairs(wezterm.mux.all_windows()) do
		local workspace = mux_win:get_workspace()
		for _, tab in ipairs(mux_win:tabs()) do
			for _, p in ipairs(tab:panes()) do
				local status = detect_pane_agent(p, procs, claude_pids, claude_status)
				if status then
					local cwd = p:get_current_working_dir()
					local dir = cwd and cwd.file_path or "unknown"
					table.insert(agents, {
						workspace = workspace,
						pane_id = p:pane_id(),
						project = dir:match("([^/]+)$") or dir,
						dir = dir,
						status = status,
					})
				end
			end
		end
	end

	cache.result = agents
	cache.timestamp = now
	return agents
end

--- Return cached agents without triggering a new scan.
function M.cached()
	return cache.result
end

--- Return a wezterm action that opens the agent dashboard InputSelector.
function M.dashboard_action()
	return wezterm.action_callback(function(window, pane)
		cache.timestamp = 0
		local agents = M.scan()
		if #agents == 0 then
			window:toast_notification("wezterm", "No running agents", nil, 3000)
			return
		end

		local choices = {}
		for _, a in ipairs(agents) do
			local icon = STATUS_ICON[a.status] or "?"
			table.insert(choices, {
				label = string.format("%s %s [%s]  %s", icon, a.project, a.workspace, a.dir),
				id = a.workspace,
			})
		end

		window:perform_action(act.InputSelector({
			title = string.format("Running Agents (%d)", #agents),
			choices = choices,
			action = wezterm.action_callback(function(win, p, id)
				if id then
					win:perform_action(act.SwitchToWorkspace({ name = id }), p)
				end
			end),
		}), pane)
	end)
end

--- Return command palette entries for augment-command-palette.
function M.palette_entries()
	local agents = cache.result
	local running_count = 0
	for _, a in ipairs(agents) do
		if a.status == "running" then
			running_count = running_count + 1
		end
	end

	local dashboard_label = #agents == 0 and "Agent Dashboard"
		or string.format("Agent Dashboard (%d agents, %d running)", #agents, running_count)

	local entries = {
		{
			brief = dashboard_label,
			icon = "md_robot",
			action = M.dashboard_action(),
		},
	}
	for _, a in ipairs(agents) do
		local icon = STATUS_ICON[a.status] or "?"
		table.insert(entries, {
			brief = string.format("Agent %s %s [%s]", icon, a.project, a.workspace),
			icon = STATUS_NERD_ICON[a.status] or "md_robot_outline",
			action = wezterm.action_callback(function(win, p)
				win:perform_action(act.SwitchToWorkspace({ name = a.workspace }), p)
			end),
		})
	end
	return entries
end

return M
