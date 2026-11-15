--!strict
-- Required gameplay remotes may arrive after profile/bootstrap work. Observe the
-- existing folder without blocking input setup or manufacturing readiness.
local Binding = {}

function Binding.new(options: any): any
	local root = options.Root
	local name = options.Name
	local className = options.ClassName or "RemoteEvent"
	assert(className == "RemoteEvent" or className == "RemoteFunction", "Supported functional remote class required")
	assert(typeof(root) == "Instance" and type(name) == "string", "Remote dependency root/name required")
	local self =
		{ destroyed = false, remote = nil, folder = nil, state = nil, connections = {}, folderConnections = {} }
	local handler: RBXScriptConnection? = nil
	local deadline: thread? = nil
	local generation = 0
	local function status(value: string, reason: string?)
		if self.state == value and self.reason == reason then
			return
		end
		self.state, self.reason = value, reason
		if options.OnState then
			options.OnState(value, reason)
		end
	end
	local function cancelDeadline()
		if deadline then
			task.cancel(deadline)
			deadline = nil
		end
	end
	local function waiting()
		cancelDeadline()
		status("Loading", "WAITING_FOR_" .. name)
		local token = generation
		deadline = task.delay(options.Timeout or 10, function()
			deadline = nil
			if not self.destroyed and generation == token and not self.remote then
				status("Unavailable", "MISSING_REMOTE_" .. name)
				warn("[GameplayDependency] MISSING_REMOTE_" .. name .. "; waiting for functional server registration")
			end
		end)
	end
	local function resolve()
		if self.destroyed then
			return
		end
		local candidate = self.folder and self.folder:FindFirstChild(name)
		local remote = if candidate and candidate:IsA(className) then candidate else nil
		if remote == self.remote then
			if candidate and not remote then
				status("Unavailable", "INVALID_REMOTE_CLASS_" .. name)
			end
			return
		end
		generation += 1
		cancelDeadline()
		if handler then
			handler:Disconnect()
			handler = nil
		end
		self.remote = remote
		-- A single callback owns its response connection for this generation.
		if options.OnRemote then
			handler = options.OnRemote(remote)
		end
		if remote then
			status("Ready", nil)
		else
			waiting()
		end
	end
	local function bindFolder()
		local folder = root:FindFirstChild("Remotes")
		if folder == self.folder then
			resolve()
			return
		end
		for _, connection in self.folderConnections do
			connection:Disconnect()
		end
		table.clear(self.folderConnections)
		self.folder = folder
		if folder then
			table.insert(
				self.folderConnections,
				folder.ChildAdded:Connect(function(child)
					if child.Name == name then
						resolve()
					end
				end)
			)
			table.insert(
				self.folderConnections,
				folder.ChildRemoved:Connect(function(child)
					if child.Name == name then
						resolve()
					end
				end)
			)
		end
		resolve()
	end
	function self.Destroy()
		if self.destroyed then
			return
		end
		self.destroyed = true
		generation += 1
		cancelDeadline()
		if handler then
			handler:Disconnect()
			handler = nil
		end
		for _, connection in self.connections do
			connection:Disconnect()
		end
		for _, connection in self.folderConnections do
			connection:Disconnect()
		end
		table.clear(self.connections)
		table.clear(self.folderConnections)
		self.remote, self.folder = nil, nil
	end
	table.insert(
		self.connections,
		root.ChildAdded:Connect(function(child)
			if child.Name == "Remotes" then
				bindFolder()
			end
		end)
	)
	table.insert(
		self.connections,
		root.ChildRemoved:Connect(function(child)
			if child == self.folder then
				bindFolder()
			end
		end)
	)
	waiting()
	bindFolder()
	return self
end

return Binding
