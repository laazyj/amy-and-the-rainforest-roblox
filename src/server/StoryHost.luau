--!strict
--[[
	StoryHost: runs the Story for each player. It turns engine signals into
	Player events, feeds them to the player's StoryEngine, and carries out
	the World commands that come back, in order, through WorldImpl:

	  - a Wait pauses for its seconds (the Chapter card, Sam's catch);
	  - a ShowDialogue is sent; once the step's commands are carried out,
	    if the engine is showing a Dialogue, the host waits until the client
	    says DialogueFinished (or 300 s pass) and feeds that to the engine.

	While a player's commands are being carried out the host is busy for
	them, and other Player events from them are dropped, as a player cannot
	act in the middle of a Beat or a Dialogue.

	StoryServer.server.luau starts it. The engine walkthrough
	(tests/engine/walkthrough.luau) starts it too, in a Luau Execution task
	where Scripts do not run, and drives the handlers below with a fake
	player; `setSend` replaces the one place a message leaves for a client,
	since FireClient needs a real Player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = ReplicatedStorage:WaitForChild("core")
local Events = require(Core:WaitForChild("Events"))
local Net = require(Core:WaitForChild("Net"))
local StoryEngine = require(Core:WaitForChild("StoryEngine"))
local World = require(Core:WaitForChild("World"))
local Content = require(ReplicatedStorage:WaitForChild("content"):WaitForChild("Story"))
local Remotes = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("Net"))

local CharacterHost = require(script.Parent.CharacterHost)
local LightingHost = require(script.Parent.LightingHost)
local PickupHost = require(script.Parent.PickupHost)
local PromptBridge = require(script.Parent.PromptBridge)
local PropHost = require(script.Parent.PropHost)
local SceneBuilder = require(script.Parent.SceneBuilder)
local WorldImpl = require(script.Parent.WorldImpl)

-- How long the host waits for DialogueFinished before going on without it.
local DIALOGUE_TIMEOUT = 300

type Session = {
	engine: StoryEngine.Engine,
	world: World.World,
	busy: boolean,
	dialogueDone: boolean,
	alive: boolean,
}

local story = Content.story
local sessions: { [any]: Session } = {}
local remotes: Remotes.Remotes? = nil

local StoryHost = {}

-- Every message to a client goes through send. A real player gets it over
-- the remote; the walkthrough replaces it with setSend.
local send = function(player: any, remote: RemoteEvent, ...: any)
	remote:FireClient(player, ...)
end

function StoryHost.setSend(replacement: (player: any, remote: RemoteEvent, ...any) -> ())
	send = replacement
end

local function toClient(player: any, command: Events.WorldCommand)
	local name, args = Net.message(command)
	assert(name and args, `{command.kind} does not go to the client`)
	local ok, reason = Net.check(name, args)
	assert(ok, reason)
	send(player, (remotes :: Remotes.Remotes)[name], table.unpack(args, 1, args.n))
end

local function awaitDialogue(session: Session)
	local waited = 0
	while session.alive and not session.dialogueDone and waited < DIALOGUE_TIMEOUT do
		waited = waited + task.wait(0.1)
	end
end

-- Carries out `commands`, and those of every step a finished Dialogue leads to.
local function carryOut(session: Session, commands: { Events.WorldCommand })
	local pending: { Events.WorldCommand }? = commands
	while pending and session.alive do
		for _, command in pending do
			if not session.alive then
				return
			end
			if command.kind == "ShowDialogue" then
				session.dialogueDone = false
			end
			World.execute(session.world, command)
		end
		pending = nil
		if session.engine.progress.showing then
			awaitDialogue(session)
			if session.alive then
				local _, _, next = session.engine:step({ kind = "DialogueFinished" })
				pending = next
			end
		end
	end
end

-- Runs `advance` on the player's engine and carries out what it returns,
-- unless the host is already busy for them.
local function run(player: any, advance: (engine: StoryEngine.Engine) -> { Events.WorldCommand })
	local session = sessions[player]
	if not session or session.busy then
		return
	end
	session.busy = true
	carryOut(session, advance(session.engine))
	session.busy = false
end

-- A Player event from `player`.
function StoryHost.handle(player: any, event: Events.PlayerEvent)
	run(player, function(engine)
		local _, _, commands = engine:step(event)
		return commands
	end)
end

local function initPlayer(player: any)
	if sessions[player] then
		return
	end
	sessions[player] = {
		engine = StoryEngine.new(player.UserId, nil, story),
		world = WorldImpl.new(story, player, function(command)
			toClient(player, command)
		end),
		busy = false,
		dialogueDone = false,
		alive = true,
	}
end

-- The client has loaded: the Story starts (once).
function StoryHost.onClientReady(player: any)
	initPlayer(player)
	task.spawn(run, player, function(engine: StoryEngine.Engine)
		local _, _, commands = engine:start()
		return commands
	end)
end

-- The client has shown the last Line of the Dialogue it was given.
function StoryHost.onDialogueFinished(player: any)
	local session = sessions[player]
	if session then
		session.dialogueDone = true
	end
end

StoryHost.onTalkPromptTriggered = PromptBridge.onTalkPromptTriggered

-- The active Quest's id ("chapter1.ask_dad") and Quest; nil before the
-- player has one and after the Story is complete.
function StoryHost.activeQuest(player: any): (string?, any)
	local session = sessions[player]
	if not session then
		return nil, nil
	end
	return session.engine:activeQuest()
end

-- A handler for a client -> server remote that drops a malformed payload.
local function fromClient(remote: string, handler: (player: Player) -> ()): (Player, ...any) -> ()
	return function(player, ...)
		if Net.check(remote, table.pack(...)) then
			handler(player)
		end
	end
end

local function playersToPoll(): { any }
	local list = {}
	for player, session in sessions do
		if not session.busy then
			table.insert(list, player)
		end
	end
	return list
end

local function removePlayer(player: Player)
	local session = sessions[player]
	if session then
		session.alive = false
	end
	sessions[player] = nil
	PickupHost.clear(player)
end

-- Builds what the Story needs in the world and connects the engine's
-- signals. Once per server.
function StoryHost.start()
	assert(not remotes, "StoryHost has already started")
	local made = Remotes.createRemotes()
	remotes = made

	CharacterHost.build(story)
	local zones = SceneBuilder.buildZones(story)
	PropHost.build(story)
	made.DialogueFinished.OnServerEvent:Connect(fromClient("DialogueFinished", StoryHost.onDialogueFinished))
	PickupHost.build(story, function(player, pickup)
		StoryHost.handle(player, { kind = "TouchedPickup", pickup = pickup })
	end)
	LightingHost.build(story)
	PromptBridge.connect(CharacterHost.prompts(), zones, StoryHost.handle, playersToPoll)

	Players.PlayerAdded:Connect(initPlayer)
	for _, player in Players:GetPlayers() do
		initPlayer(player)
	end
	made.ClientReady.OnServerEvent:Connect(fromClient("ClientReady", StoryHost.onClientReady))
	Players.PlayerRemoving:Connect(removePlayer)

	print("[StoryServer] Story engine ready: " .. story.title)
end

return StoryHost
