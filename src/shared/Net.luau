--!strict
--[[
	Net: the remotes the server and the client binder talk over, named and
	shaped by the contract in src/core/Net. The server makes them; the
	client waits for them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contract = require(ReplicatedStorage:WaitForChild("core"):WaitForChild("Net"))

export type Remotes = { [string]: RemoteEvent }

local Net = {}

-- Makes the StoryRemotes folder with one RemoteEvent per remote in the contract.
function Net.createRemotes(): Remotes
	local folder = Instance.new("Folder")
	folder.Name = Contract.FOLDER
	local remotes: Remotes = {}
	for name in Contract.REMOTES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
	return remotes
end

-- Waits for the server's remotes.
function Net.waitForRemotes(): Remotes
	local folder = ReplicatedStorage:WaitForChild(Contract.FOLDER)
	local remotes: Remotes = {}
	for name in Contract.REMOTES do
		remotes[name] = folder:WaitForChild(name) :: RemoteEvent
	end
	return remotes
end

return Net
