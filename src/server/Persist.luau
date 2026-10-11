--!strict
--[[
	Persist: keeps each player's Save (src/core/Save) in a DataStore through
	ProfileStore (plan section 2.3), keyed by Roblox user id, so Progress
	follows the account across PC, phone and tablet. One Save per player.

	  open(player)              starts the player's ProfileStore session,
	                            which locks their Save to this server
	  await(player)             their Save once loaded; nil when there is
	                            none to use (no DataStore access, or a Save
	                            this version cannot read)
	  record(player, progress)  new Progress, written on every Story event
	  replace(player, save)     a whole new Save (the Title screen's choices)
	  release(player, progress) on leave: writes the last Progress and ends
	                            the session, releasing the lock
	  close()                   on BindToClose: releases every session and
	                            waits for the writes

	A DataStore key takes about one write every 6 seconds, so a write is
	never sooner than WRITE_INTERVAL after the last: the Save in memory
	changes at once, and the write that follows carries the latest.

	The store is Config.storePrefix .. "Progress". The engine harness sets
	the prefix to a run's test prefix, so engine tests never touch a
	player's Save. A Save that cannot be read (two schema versions newer)
	is never written over; the player plays without saving.

	ProfileStore is a Wally package (wally.toml) built into
	ServerScriptService.ServerPackages; without it, Persist warns and the
	game plays without saves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = ReplicatedStorage:WaitForChild("core")
local Save = require(Core:WaitForChild("Save"))
local Story = require(Core:WaitForChild("Story"))
local StoryEngine = require(Core:WaitForChild("StoryEngine"))
local Config = require(script.Parent.Config)

-- The parts of ProfileStore (lm-loleris/profilestore 1.0.3) Persist uses.
type Signal = { Connect: (self: Signal, listener: (...any) -> ()) -> { Disconnect: (self: any) -> () } }
type Profile = {
	Data: any,
	Session: any?,
	OnSessionEnd: Signal,
	OnAfterSave: Signal,
	IsActive: (self: Profile) -> boolean,
	Save: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
	AddUserId: (self: Profile, userId: number) -> (),
}
type ProfileStore = {
	StartSessionAsync: (self: ProfileStore, key: string, params: { Cancel: () -> boolean }?) -> Profile?,
	GetAsync: (self: ProfileStore, key: string) -> Profile?,
}

type Entry = {
	loaded: boolean,
	profile: Profile?,
	-- nil until loaded, and when there is no Save to use
	save: Save.Save?,
	-- Progress recorded since `save` was last brought up to date
	latest: StoryEngine.Progress?,
	-- os.clock() of the last write, and whether one is waiting its turn
	lastWrite: number,
	pending: boolean,
}

local Persist = {}

-- Seconds between two writes of one Save.
Persist.WRITE_INTERVAL = 6
-- Longest close() waits for the last writes (BindToClose allows 30 s).
Persist.CLOSE_TIMEOUT = 25

local story: Story.Story? = nil
local store: ProfileStore? = nil
local entries: { [any]: Entry } = {}

function Persist.storeName(): string
	return Config.storePrefix .. "Progress"
end

-- The DataStore key of a player's Save.
local function key(player: any): string
	return `Player_{player.UserId}`
end

-- Brings the Save, and the profile's Data that ProfileStore writes, up to
-- date with the latest Progress recorded.
local function settle(entry: Entry)
	local latest, profile = entry.latest, entry.profile
	if latest and entry.save and profile then
		entry.save = Save.record(story :: Story.Story, entry.save, latest)
		profile.Data = Save.write(entry.save)
	end
	entry.latest = nil
end

-- Writes the Save once WRITE_INTERVAL has passed since the last write.
local function write(entry: Entry)
	if not entry.profile or entry.pending then
		return
	end
	entry.pending = true
	task.delay(math.max(0, entry.lastWrite + Persist.WRITE_INTERVAL - os.clock()), function()
		entry.pending = false
		local profile = entry.profile
		if profile and profile:IsActive() then
			settle(entry)
			entry.lastWrite = os.clock()
			profile:Save()
		end
	end)
end

-- Runs `start` (a write) and returns a function that waits for the write to
-- finish, true once it has, false after CLOSE_TIMEOUT seconds.
local function saving(profile: Profile, start: () -> ()): () -> boolean
	local done = false
	local connection = profile.OnAfterSave:Connect(function()
		done = true
	end)
	start()
	return function()
		local waited = 0
		while not done and waited < Persist.CLOSE_TIMEOUT do
			waited += task.wait(0.1)
		end
		connection:Disconnect()
		return done
	end
end

local function load(player: any, entry: Entry)
	local profile = (store :: ProfileStore):StartSessionAsync(key(player), {
		Cancel = function()
			return entries[player] ~= entry
		end,
	})
	if not profile then
		entry.loaded = true
		return
	elseif entries[player] ~= entry then
		profile:EndSession()
		return
	end
	if player.UserId > 0 then
		profile:AddUserId(player.UserId)
	end
	local save, reason = Save.read(story :: Story.Story, profile.Data)
	if save then
		entry.profile = profile
		entry.save = save
		profile.OnSessionEnd:Connect(function()
			if entries[player] == entry and entry.profile == profile then
				-- another server took the Save: the player joined somewhere else
				entry.profile = nil
				if typeof(player) == "Instance" and player:IsA("Player") then
					player:Kick("Your story is open on another device.")
				end
			end
		end)
	else
		warn(`[Persist] {player.Name}'s Save is not read, and will not be written: {reason}`)
		profile:EndSession()
	end
	entry.loaded = true
end

-- Starts loading `player`'s Save, once.
function Persist.open(player: any)
	if entries[player] then
		return
	end
	local entry: Entry = { loaded = store == nil, lastWrite = 0, pending = false }
	entries[player] = entry
	if store then
		task.spawn(load, player, entry)
	end
end

-- `player`'s Save once loaded (yields until then); nil when there is none to
-- use or Persist has not opened it.
function Persist.await(player: any): Save.Save?
	local entry = entries[player]
	while entry and not entry.loaded and entries[player] == entry do
		task.wait(0.1)
	end
	if entry and entry.save then
		settle(entry)
		return Save.write(entry.save) :: any
	end
	return nil
end

function Persist.replace(player: any, save: Save.Save)
	local entry = entries[player]
	if entry and entry.save and entry.profile then
		entry.save = save
		entry.latest = nil
		entry.profile.Data = Save.write(save)
		write(entry)
	end
end

-- Kept as the latest Progress; the Save is brought up to date when written.
function Persist.record(player: any, progress: StoryEngine.Progress)
	local entry = entries[player]
	if entry and entry.save and entry.profile then
		entry.latest = progress
		write(entry)
	end
end

-- Writes `player`'s Save now and waits for the write (engine tests).
function Persist.flush(player: any): boolean
	local entry = entries[player]
	local profile = entry and entry.profile
	if not profile then
		return false
	end
	settle(entry)
	entry.lastWrite = os.clock()
	return saving(profile, function()
		profile:Save()
	end)()
end

-- Ends `player`'s session after writing `progress` (which can have changed
-- with no Story event: a Pickup touched, a Dialogue shown), and returns a
-- function that waits for that last write (true once it is done).
function Persist.release(player: any, progress: StoryEngine.Progress?): () -> boolean
	local entry = entries[player]
	entries[player] = nil
	local profile = entry and entry.profile
	if not profile then
		return function()
			return true
		end
	end
	entry.latest = progress or entry.latest
	settle(entry)
	entry.profile = nil
	return saving(profile, function()
		profile:EndSession()
	end)
end

-- What the store holds for `player`, read without a session: the stored
-- data and whether a session holds its lock. For engine tests.
function Persist.stored(player: any): (any, boolean)
	local profile = store and store:GetAsync(key(player))
	if not profile then
		return nil, false
	end
	return profile.Data, profile.Session ~= nil
end

-- Releases every session, waiting for the last writes. Bound to
-- BindToClose by start(). `progressOf` gives each player's latest Progress.
function Persist.close(progressOf: (player: any) -> StoryEngine.Progress?): boolean
	local waits = {}
	for player in entries do
		table.insert(waits, Persist.release(player, progressOf(player)))
	end
	local all = true
	for _, wait in waits do
		all = wait() and all
	end
	return all
end

-- Opens the store for `forStory` and binds close() to BindToClose. Without
-- the ProfileStore package, every player plays without saving.
function Persist.start(forStory: Story.Story, progressOf: (player: any) -> StoryEngine.Progress?)
	assert(not story, "Persist has already started")
	story = forStory
	local packages = script.Parent:FindFirstChild("ServerPackages")
	local module = packages and packages:FindFirstChild("ProfileStore")
	if not module or not module:IsA("ModuleScript") then
		warn("[Persist] no ProfileStore package (ServerScriptService.ServerPackages): playing without saves")
		return
	end
	local ProfileStore: any = (require :: any)(module)
	store = ProfileStore.New(Persist.storeName(), {})
	-- In a Luau Execution task the server never closes; were binding refused
	-- there, the engine tests call close() themselves (tests/engine/persist).
	local bound, reason = pcall(game.BindToClose, game, function()
		Persist.close(progressOf)
	end)
	if not bound then
		warn(`[Persist] BindToClose: {reason}`)
	end
end

return Persist
