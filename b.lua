--[[ External Librarys ]]
local JSON = require("json")
local Routine = require("timer")
local HTTP = require("coro-http")
local Query = require("querystring")
local Spawn = require("coro-spawn")
local FileReader = require("fs")
local PP = require("pretty-print")
local SQL = require("sqlite3")

--[[ Config ]]
local Config = assert(JSON.decode(FileReader.readFileSync("Config.json")), "Failed to read or parse Base.json!")

if Config._DEBUG == true then
	Config["GMRGID"] = "843951362907439135"
	Config["DefaultInterval"] = 15
	Config["CompetitionCID"] = "907405758243700796"
	Config["CompetitionStatsCID"] = "907405795761737788"
else
	Config["GMRGID"] = "835927915325161523"
	Config["DefaultInterval"] = 30
	Config["CompetitionCID"] = ""
	Config["CompetitionStatsCID"] = ""
end

--[[ Discord Utils ]]
local Discordia = require("discordia")
local BOT = Discordia.Client {
	cacheAllMembers = true,
	syncGuilds = true,
	dateTime = "%F @ %T",
	logLevel = (Config._DEBUG == true and 4 or 3)
}
Discordia.extensions()

--[[ Logger ]]
local Logger = Discordia.Logger((Config._DEBUG == false and 3 or 4), "%F @ %T", "GMR.log")
local Log = function(Level, ...) Logger:log(Level, ...) end

--[[ Command Handler ]]
local CommandManager = require("CM")

--[[ Functions ]]
local function SimpleEmbed(Channel, Description)
	local Embed = {
		["description"] = Description,
		["color"] = Config.EmbedColour
	}

	if Channel then
		local Channel = (Channel.channel or Channel)

		return Channel:send {
			embed = Embed
		}
	end 

	return Embed
end

local function TableIndexExist(t, Indexes)
	local CurrentPoint = t

	for _, Index in ipairs(Indexes) do
		if CurrentPoint[Index] then
			CurrentPoint = CurrentPoint[Index]
		else
			return false
		end
	end

	return true
end

local function ReturnRestOfCommand(AllArgs, StartIndex, Seperator, EndIndex)
    return table.concat(AllArgs, (Seperator ~= nil and type(Seperator) == "string" and Seperator or " "), StartIndex, EndIndex)
end

local function Interval(Ms, Func)
	return Routine.setInterval(Ms, function()
		coroutine.wrap(function()
			local Suc, Err = pcall(Func)

			if not Suc and Config._DEBUG == true then
				Log(1, Err or "")
			end
		end)()
	end)	
end

--[[ Module Func ]]
local function LoadModule(Module)
	local FilePath = Config.ModuleDir.."/"..Module..".lua"
	local Code = assert(FileReader.readFileSync(FilePath))

	Config[Module] = {}
	local Env = setmetatable({
		require = require,

		Discordia = Discordia,
		BOT = BOT,

		JSON = JSON,
		Routine = Routine,
		HTTP = HTTP,
		Spawn = Spawn,
		FileReader = FileReader,
		PP = PP,
		Query = Query,
		SQL = SQL,

		Config = Config,
		Module = Module,

		InitConfig = InitConfig,

		CommandManager = CommandManager,

		Log = Log, 
		Logger = Logger,
		Round = math.round,
		F = string.format,
		SimpleEmbed = SimpleEmbed,
		ReturnRestOfCommand = ReturnRestOfCommand,
		Interval = Interval,
		TableIndexExist = TableIndexExist,
		BotStart = os.time(),

		ModuleDir = Config.ModuleDir,
		Prefix = Config.Prefix,
		DefaultInterval = Config.DefaultInterval,
	}, {__index = _G})

	local Func = assert(loadstring(Code, "@"..Module, "t", Env))

	return Func()
end

--[[ Init ]]
do
	local Token = assert(FileReader.readFileSync("./token.txt"):split("\n")[1], "Could not find bot token. Please create a file called token.txt in the directory of your bot and put your bot token inside of it.")

	assert(FileReader.existsSync(Config.ModuleDir), "Could not find module directory, are you sure it is valid?")

	for File, Type in FileReader.scandirSync(Config.ModuleDir) do
		if Type == "file" then
			local FileName = File:match("(.*)%.lua")
			if FileName then
				local Suc, Err = pcall(LoadModule, FileName)

				if Suc == true then
					Log(3, "Module loaded: "..FileName)
				else
					Log(1, "Failed to load module "..FileName.." ["..Err.."]")

					if Err:lower():find("fatal") then
						_G = nil

						process:exit(1)
					end
				end
			end
		end
	end

	BOT:run("Bot "..Token)
end