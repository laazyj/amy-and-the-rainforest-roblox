--!strict
--[[
	StoryHost: runs the Story for each player. It turns engine signals into
	Player events, feeds them to the player's StoryEngine, and carries out
	the World commands that come back, in order, through WorldImpl:

	  - a Wait pauses for its seconds (the Chapter card, Sam's catch), and
	    holds while the player has the Pause screen open (SetPaused);
	  - a ShowDialogue is sent; once the step's commands are carried out,
	    if the engine is showing a Dialogue, the host waits until the client
	    says DialogueFinished, however long that takes, and feeds that to
	    the engine. There is no timed reading: a player who reads slowly,
	    or leaves the Pause screen open, holds the Story where it is.

	Every World command is held to its schema (World.execute) and every
	message to a client to the Net contract before it is sent; either
	failing is an error, not a dropped message.

	Analytics: each Story event is logged as it is raised, and each
	player's visit, its length on leave (src/server/Analytics).

	Chat: Roblox's text chat window and input bar show only where
	Config.chat says, on Dev; the server sets them, so they replicate to
	every client.

	Saves (Persist): a player's Save is opened when they join and written
	after every step that raised Story events, on a Resume and on leave.
	When their client is ready, a player who has not started begins the
	Story at once; a returning player is offered the Title screen
	(ShowTitle) and their Title choice continues, replays the Chapter from
	its Checkpoint, or starts again. While the Title screen is offered, the
	Story waits: no Player event is handled until the Title choice. The Dev
	shortcut /title offers it again mid-Story (offerTitle). Before either, a player whose Settings
	are not the defaults is sent them (ApplySettings); each change the
	client sends (ChangeSettings) goes into their Save.

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
local TextChatService = game:GetService("TextChatService")

local Core = ReplicatedStorage:WaitForChild("core")
local Events = require(Core:WaitForChild("Events"))
local Net = require(Core:WaitForChild("Net"))
local Save = require(Core:WaitForChild("Save"))
local Settings = require(Core:WaitForChild("Settings"))
local StoryEngine = require(Core:WaitForChild("StoryEngine"))
local TitleScreen = require(Core:WaitForChild("TitleScreen"))
local World = require(Core:WaitForChild("World"))
local Content = require(ReplicatedStorage:WaitForChild("content"):WaitForChild("Story"))
local Remotes = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("Net"))

local Analytics = require(script.Parent.Analytics)
local CharacterHost = require(script.Parent.CharacterHost)
local Config = require(script.Parent.Config)
local LightingHost = require(script.Parent.LightingHost)
local Persist = require(script.Parent.Persist)
local PickupHost = require(script.Parent.PickupHost)
local PromptBridge = require(script.Parent.PromptBridge)
local PropHost = require(script.Parent.PropHost)
local SceneBuilder = require(script.Parent.SceneBuilder)
local WorldImpl = require(script.Parent.WorldImpl)

type Session = {
	player: any,
	-- a returning player's Save while they are offered the Title screen
	offered: Save.Save?,
	engine: StoryEngine.Engine,
	world: World.World,
	busy: boolean,
	dialogueDone: boolean,
	alive: boolean,
	-- the player has the Pause screen open: a Wait holds
	paused: boolean,
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

local function message(player: any, name: string, args: Net.Args)
	local ok, reason = Net.check(name, args)
	assert(ok, reason)
	send(player, (remotes :: Remotes.Remotes)[name], table.unpack(args, 1, args.n))
end

local function toClient(player: any, command: Events.WorldCommand)
	local name, args = Net.message(command)
	assert(name and args, `{command.kind} does not go to the client`)
	message(player, name, args)
end

local function awaitDialogue(session: Session)
	while session.alive and not session.dialogueDone do
		task.wait(0.1)
	end
end

-- After a step that raised Story events, they are logged and the player's
-- Save gets their Progress.
local function recordAfter(session: Session, events: { Events.StoryEvent })
	Analytics.storyEvents(session.player, events)
	if #events > 0 then
		Persist.record(session.player, session.engine:snapshot())
	end
end

-- Carries out `commands`, and those of every step a finished Dialogue leads to.
local function carryOut(session: Session, events: { Events.StoryEvent }, commands: { Events.WorldCommand })
	recordAfter(session, events)
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
				local _, nextEvents, next = session.engine:step({ kind = "DialogueFinished" })
				recordAfter(session, nextEvents)
				pending = next
			end
		end
	end
end

-- Runs `advance` on the player's engine and carries out what it returns,
-- unless the host is already busy for them.
local function run(
	player: any,
	advance: (engine: StoryEngine.Engine) -> ({ Events.StoryEvent }, { Events.WorldCommand })
)
	local session = sessions[player]
	if not session or session.busy or session.offered then
		return
	end
	session.busy = true
	carryOut(session, advance(session.engine))
	session.busy = false
end

-- A Player event from `player`.
function StoryHost.handle(player: any, event: Events.PlayerEvent)
	run(player, function(engine)
		local _, events, commands = engine:step(event)
		return events, commands
	end)
end

-- Starts a session for `player` at `progress` (fresh when nil), ending any
-- session they had.
local function newSession(player: any, progress: StoryEngine.Progress?)
	local old = sessions[player]
	if old then
		old.alive = false
		PickupHost.clear(player)
	end
	local session: Session
	session = {
		player = player,
		engine = StoryEngine.new(player.UserId, progress, story),
		world = WorldImpl.new(story, player, function(command)
			toClient(player, command)
		end, function()
			return session.alive and session.paused
		end),
		busy = false,
		dialogueDone = false,
		alive = true,
		-- the Pause screen stays open across a Resume
		paused = old ~= nil and old.paused,
	}
	sessions[player] = session
end

local function initPlayer(player: any)
	if not sessions[player] then
		newSession(player, nil)
		Persist.open(player)
		Analytics.joined(player)
	end
end

local function startStory(engine: StoryEngine.Engine)
	local _, events, commands = engine:start()
	return events, commands
end

-- Offers `player` the Title screen's choices for `save`: the Story waits
-- (run handles no Player event) until their Title choice.
local function showTitle(session: Session, save: Save.Save, offer: TitleScreen.Offer)
	session.offered = save
	message(session.player, "ShowTitle", table.pack(offer.chapter, offer.canContinue))
end

-- The client has loaded, and the Title screen shows. Once the player's Save
-- is loaded: a player who has not started gets the Story's first Chapter
-- card at once, as always; a returning player is offered the Title
-- screen's choices (ShowTitle) and waits for their Title choice.
function StoryHost.onClientReady(player: any)
	initPlayer(player)
	task.spawn(function()
		local save = Persist.await(player)
		if save and not Settings.isDefault(save.settings) then
			message(player, "ApplySettings", table.pack(Settings.known(save.settings)))
		end
		local offer = save and TitleScreen.offer(story, save)
		local session = sessions[player]
		if offer and session and not StoryEngine.started(session.engine.progress) then
			showTitle(session, save, offer)
		else
			run(player, startStory)
		end
	end)
end

-- The player's Title choice: a Resume where it leads, or the Story from its
-- start for "restart". Ignored unless the Title screen was offered and no
-- choice made yet.
function StoryHost.onTitleChoice(player: any, choice: string)
	local session = sessions[player]
	local save = session and session.offered
	if not session or not save or not TitleScreen.CHOICES[choice] then
		return
	end
	session.offered = nil
	local chosen, progress = TitleScreen.choose(story, save, choice :: TitleScreen.Choice)
	Persist.replace(player, chosen)
	if not StoryEngine.started(progress) then
		run(player, startStory)
	else
		StoryHost.resume(player, progress)
	end
end

-- The Title screen offered to `player` at their current Progress, as to a
-- returning player, for the Dev shortcut /title: the session ends where it
-- is (a Beat or a Dialogue stops), the Save gets that Progress, and the
-- Story waits for the Title choice. Returns the Chapter offered, or nil and
-- why not.
function StoryHost.offerTitle(player: any): (string?, string?)
	local progress = StoryHost.progress(player)
	if not progress or not StoryEngine.started(progress) then
		return nil, "the Story has not started"
	end
	-- Studio has no DataStores: without a Save to load, offer one made now
	local save = Save.record(story, Persist.await(player) or Save.new(), progress)
	local offer = TitleScreen.offer(story, save) :: TitleScreen.Offer
	newSession(player, progress)
	Persist.record(player, progress)
	showTitle(sessions[player], save, offer)
	return offer.chapter, nil
end

-- Resume (plan section 2.4): a new session for `player` at `progress`, and
-- the World rebuilt to what its Quest expects. Their Save gets `progress`:
-- a Dev shortcut's jump is saved as if played to there.
function StoryHost.resume(player: any, progress: StoryEngine.Progress)
	newSession(player, progress)
	Persist.record(player, progress)
	run(player, function()
		return {}, StoryEngine.resume(story, progress)
	end)
end

-- The player's Progress, as it would be saved; nil without a session.
function StoryHost.progress(player: any): StoryEngine.Progress?
	local session = sessions[player]
	return if session then session.engine:snapshot() else nil
end

-- Whether the host is waiting on the player: no Beat or Dialogue of theirs
-- is being carried out.
function StoryHost.idle(player: any): boolean
	local session = sessions[player]
	return session ~= nil and not session.busy
end

-- The player opened or closed the Pause screen: while it is open, a Wait
-- holds, so a Beat stops where it is.
function StoryHost.onSetPaused(player: any, paused: boolean)
	local session = sessions[player]
	if session then
		session.paused = paused
	end
end

-- The player changed their Settings (held to the contract by fromClient).
function StoryHost.onChangeSettings(player: any, settings: Settings.Settings)
	Persist.changeSettings(player, settings)
end

-- The client has shown the last Line of the Dialogue it was given.
function StoryHost.onDialogueFinished(player: any)
	local session = sessions[player]
	if session then
		session.dialogueDone = true
	end
end

StoryHost.onTalkPromptTriggered = PromptBridge.onTalkPromptTriggered
StoryHost.onPlayerAdded = initPlayer

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
local function fromClient(remote: string, handler: (player: Player, ...any) -> ()): (Player, ...any) -> ()
	return function(player, ...)
		local ok, reason = Net.check(remote, table.pack(...))
		if ok then
			handler(player, ...)
		else
			warn(`dropped a malformed {remote} from {player.Name}: {reason}`)
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

-- The player has left: their Save gets their last Progress and is released.
function StoryHost.onPlayerRemoving(player: any)
	Persist.release(player, StoryHost.progress(player))
	Analytics.left(player)
	local session = sessions[player]
	if session then
		session.alive = false
	end
	sessions[player] = nil
	PickupHost.clear(player)
end

-- Roblox's chat window and input bar, shown only where Config.chat says.
local function applyChat()
	for _, class in { "ChatWindowConfiguration", "ChatInputBarConfiguration" } do
		local chat = TextChatService:FindFirstChildOfClass(class)
		if chat then
			(chat :: any).Enabled = Config.chat
		end
	end
end

-- Builds what the Story needs in the world and connects the engine's
-- signals. Once per server.
function StoryHost.start()
	assert(not remotes, "StoryHost has already started")
	applyChat()
	local made = Remotes.createRemotes()
	remotes = made

	Persist.start(story, StoryHost.progress)
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
	made.TitleChoice.OnServerEvent:Connect(fromClient("TitleChoice", StoryHost.onTitleChoice))
	made.ChangeSettings.OnServerEvent:Connect(fromClient("ChangeSettings", StoryHost.onChangeSettings))
	made.SetPaused.OnServerEvent:Connect(fromClient("SetPaused", StoryHost.onSetPaused))
	Players.PlayerRemoving:Connect(StoryHost.onPlayerRemoving)

	print("[StoryServer] Story engine ready: " .. story.title)
end

return StoryHost
