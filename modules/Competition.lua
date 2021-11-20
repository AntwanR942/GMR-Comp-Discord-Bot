--[[ Database ]]
local DB = assert(SQL.open(ModuleDir.."/Competition.db"), "fatal: Failed to open Competition database!")
DB:exec("PRAGMA foreign_keys = ON;")

DB:exec("CREATE TABLE IF NOT EXISTS Competitions(ID INTEGER PRIMARY KEY AUTOINCREMENT, Name TEXT NOT NULL, Start TEXT NOT NULL, End TEXT, Ended INTEGER NOT NULL, Participants INTEGER NOT NULL, StatMID TEXT NOT NULL);")
DB:exec("CREATE TABLE IF NOT EXISTS Submissions(Content TEXT NOT NULL, Attachment TEXT NOT NULL, OwnerID TEXT NOT NULL, ID INTEGER NOT NULL, FOREIGN KEY (ID) REFERENCES Competitions (ID));")

local CreateCompSTMT = DB:prepare("INSERT INTO Competitions(Name, Start, End, Ended, Participants, StatMID) VALUES(?, ?, ?, 0, 0, ?)")
local CreateSubmission = DB:prepare("INSERT INTO Submissions(Content, Attachment, OwnerID, ID) VALUES(?, ?, ?, ?)")

--[[ Variables ]]
local CompetitionCID = Config["CompetitionCID"]
local CompetitionStatsCID = Config["CompetitionStatsCID"]

local LatestCompetitionID = assert(tonumber(DB:rowexec("SELECT count(1) FROM Competitions")), "fatal: Failed to get latest competition ID!")

local AwaitingResponse = {}
local WaitTime = Config["DefaultInterval"]

local Ready = false

--[[ Functions ]]
local function IsCompetitionOngoing()
    local Competition = {DB:rowexec(F([[SELECT * FROM Competitions WHERE CAST(End AS INTEGER) > %d OR End == "0";]], os.time()))}

    return (Competition and #Competition > 0 and {
        ["ID"] = tonumber(Competition[1]),
        ["Name"] = Competition[2],
        ["Start"] = tonumber(Competition[3]),
        ["End"] = tonumber(Competition[4]),
        ["Ended"] = tonumber(Competition[5]),
        ["Participants"] = tonumber(Competition[6]),
        ["StatMID"] = Competition[7]
    } or nil)
end

local function UpdateStatus(Ongoing)
    BOT:setStatus(Ongoing and "online" or "dnd")
    BOT:setGame({
        ["name"] = F("submissions %s!", (Ongoing and "open" or "closed")),
        ["type"] = 3
    })
end

local function EndCompetition(ID)
    local Competition = {DB:rowexec(F("SELECT * FROM Competitions WHERE ID == %d;", ID))}
    
    if not Competition or #Competition == 0 then return end

    local CompetitionStatChannel = BOT:getChannel(CompetitionStatsCID)
    if not CompetitionStatChannel then return end
    
    StatMessage = CompetitionStatChannel:getMessage(Competition[7])

    if StatMessage then
        StatMessage.embed["title"] = F("[ENDED] #%d | %s", tonumber(Competition[1]), Competition[2])
        StatMessage.embed["fields"] = {
            {
                ["name"] = "** **",
                ["value"] = F("%s **-->** %s", F("<t:%d:F>", tonumber(Competition[3])), F("<t:%d:F>", os.time())),
                ["inline"] = false
            },
            {
                ["name"] = "Participants",
                ["value"] = F("```%d```", tonumber(Competition[6])),
                ["inline"] = false
            }
        }
        
        StatMessage:setEmbed(StatMessage.embed)
    end

    DB:rowexec(F([[UPDATE Competitions SET Ended = 1, End = %s WHERE ID = %d;]], tostring(os.time()), tonumber(Competition[1])))
    UpdateStatus(false)
end

local function UpdateCompetition(Competition)
    local CompetitionStatChannel = BOT:getChannel(CompetitionStatsCID)
    if not CompetitionStatsCID then return end

    local StatMessage = CompetitionStatChannel:getMessage(Competition["StatMID"])
    if not StatMessage then return end

    StatMessage.embed["fields"] = {
        {
            ["name"] = "** **",
            ["value"] = F("%s **-->** %s", F("<t:%d:F>", Competition["Start"]), (Competition["End"] > 0 and F("<t:%d:F>", Competition["End"]) or "**TBA**")),
            ["inline"] = false
        },
        {
            ["name"] = "Participants",
            ["value"] = F("```%d```", Competition["Participants"]),
            ["inline"] = false
        }
    }

    StatMessage:setEmbed(StatMessage.embed)
end

--[[ Events ]]
BOT:on("ready", function()
    if Ready == true then return end

    Ready = true

    UpdateStatus(IsCompetitionOngoing())

    local Competitions = DB:exec(F([[SELECT * FROM Competitions WHERE Ended == 0 AND End != "0";]], os.time()))
    if not Competitions then return end
    
    for i = 1, #Competitions["End"] do
        Competitions["End"][i] = tonumber(Competitions["End"][i])

        if Competitions["End"][i] ~= 0 and Competitions["Ended"][i] == 0 then
            if Competitions["End"][i] < os.time() then
                Log(3, "Ending competition...")
                EndCompetition(tonumber(Competitions["ID"][i]))
            else
                Log(3, "Ending future competition...")
                Routine.setTimeout(math.abs(Competitions["End"][i] - os.time()) * 1000, coroutine.wrap(function()
                    EndCompetition(tonumber(Competitions["ID"][i]))
                end))
            end
        end
    end
end)

--[[ Commands ]]
CommandManager.Command("copen", function(Args, Payload)
    assert(#Args >= 2, "")
    assert(IsCompetitionOngoing() == nil, "there is already an ongoing competition!")

    local CommandS = ReturnRestOfCommand(Args, 2, " ", #Args).." "
    local Start = os.time()

    local Days = CommandS:match("(%d+)d ")
    local Hours = CommandS:match("(%d+)h ")
    local Minutes = CommandS:match("(%d+)m ")
    local Unix = CommandS:match("(%d+)u ")
    local ArgIgnore = 0
    
    if Days then 
        Days = tonumber(Days)
        assert(Days > 0 and Days <= 365, "you specified too many or too few days.")
        ArgIgnore = ArgIgnore + 1
    end

    if Hours then
        Hours = tonumber(Hours)
        assert(Hours > 0 and Hours <= 24, "you specified too many or too few hours.")
        ArgIgnore = ArgIgnore + 1
    end

    if Minutes then
        Minutes = tonumber(Minutes)
        assert(Minutes > 0 and Minutes <= 60, "you specified too many or too few Minutes.")
        ArgIgnore = ArgIgnore + 1
    end

    if Unix then
        Unix = tonumber(Unix)
        assert(Unix > os.time(), "the unix time provided is not valid.")
        ArgIgnore = ArgIgnore + 1
    end

    local Name = ReturnRestOfCommand(Args, 2 + ArgIgnore)
    assert(#Name > 0, "you haven't included a reminder.")

    local End = (ArgIgnore > 0 and Unix or ArgIgnore > 0 and os.time() + (Minutes ~= nil and (Minutes * 60) or 0) + (Hours ~= nil and (Hours * 60 * 60) or 0) + (Days ~= nil and (Days * 24 * 60 * 60) or 0) or 0)

    local CompetitionStatChannel = assert(BOT:getChannel(CompetitionStatsCID), "failed to fetch competition statistics channel.")

    local Stats = SimpleEmbed(nil, "")
    Stats["title"] = F("#%d | %s", LatestCompetitionID + 1, Name)
    Stats["fields"] = {
        {
            ["name"] = "** **",
            ["value"] = F("%s **-->** %s", F("<t:%d:F>", Start), (End > 0 and F("<t:%d:F>", End) or "**TBA**")),
            ["inline"] = false
        },
        {
            ["name"] = "Participants",
            ["value"] = "```0```",
            ["inline"] = false
        }
    }

    local StatMessage = assert(CompetitionStatChannel:send {
        embed = Stats
    })

    assert(CreateCompSTMT:reset():bind(Name, tostring(Start), tostring(End), StatMessage.id):step() == nil, "there was an internal error creating the competition.")

    LatestCompetitionID = LatestCompetitionID + 1
    UpdateStatus(true)

    if End > 0 then
        Routine.setTimeout(((End - os.time()) * 1000), coroutine.wrap(function()
            EndCompetition(LatestCompetitionID)
        end))
    end
end)

CommandManager.Command("cclose", function(Args, Payload)
    assert(#Args > 1, "")
    Args[2] = assert(tonumber(Args[2]), "you need to provide the ID of the competition you wish to close.")

    local Competition = IsCompetitionOngoing()
    assert(Competition ~= nil, "there is no competition ongoing at the moment!")
    assert(Competition["ID"] == Args[2], "there is no ongoing competition with that ID.")

    EndCompetition(Args[2])
    
    return SimpleEmbed(Payload, F("%s competition **[%s](%s)** ended successully!", Payload.author.mentionString, Competition["Name"], F("https://discord.com/channels/%s/%s/%s", Config["GMRGID"], CompetitionStatsCID, Competition["StatMID"])))
end)

BOT:on("messageCreate", function(Payload)
    local AID = Payload.author.id
    local CompetitionChannel = BOT:getChannel(CompetitionCID)

    if not CompetitionChannel or Payload.author.bot or Payload.guild ~= nil or AwaitingResponse[AID] then return end

    local Competition = IsCompetitionOngoing()

    if Competition == nil then 
        return SimpleEmbed(Payload, F("Sorry however there is no ongoing competition at the moment!\n\nHowever do keep a look out in the <#%s> channel for new competitions!", CompetitionCID))
    end

    AwaitingResponse[AID] = true

    SimpleEmbed(Payload, F("Are you sure you want to send the submission provided to be evaluated for the %s?\n\nPlease answer: ``yes`` or ``no``\n\n**You have %d seconds to answer otherwise your submission will not be submitted!**", Competition["Name"], WaitTime))

    local Success, SubmissionPayload = BOT:waitFor("messageCreate", WaitTime * 1000, function(SubmissionPayload)
        if SubmissionPayload.channel == Payload.channel then
            local Answer = SubmissionPayload.content:lower()

            if Answer == "yes" or Answer == "no" then
                AwaitingResponse[AID] = false

                return true
            end
        end

        return false
    end)

    if Success and SubmissionPayload.content:lower() == "yes" then
        local NSubmissions = (tonumber(DB:rowexec(F([[SELECT COUNT(*) FROM Submissions WHERE OwnerID == %s AND ID == %d;]], AID, Competition["ID"]))) or 0)

        if NSubmissions == 0 then
            Competition["Participants"] = Competition["Participants"] + 1
            DB:rowexec(F([[UPDATE Competitions SET Participants = Participants + 1 WHERE ID = %d;]], Competition["ID"]))
            UpdateCompetition(Competition)
        end

        CreateSubmission:reset():bind(Payload.content, Payload.attachment and Payload.attachment.url or "", AID, Competition["ID"]):step()

        local Embed = {
            ["author"] = {
                ["name"] = F("%s#%d", Payload.author.name, Payload.author.discriminator),
                ["icon_url"] = Payload.author.avatarURL
            },
            ["timestamp"] = Payload.timestamp,
            ["color"] = Config["EmbedColour"],
            ["description"] = F("**Submission #%s from **%s** for [%s](%s)!**\n\n%s", (NSubmissions + 1), Payload.author.mentionString, Competition["Name"], F("https://discord.com/channels/%s/%s/%s", Config["GMRGID"], CompetitionStatsCID, Competition["StatMID"]), Payload.content),
            ["fields"] = {
                {
                    ["name"] = "Attachment",
                    ["value"] = (Payload.attachment and Payload.attachment.url and F("[View Here!](%s)", Payload.attachment.url) or "No File Attached"),
                    ["inline"] = true
                }
            },
            ["footer"] = {
                ["text"] = F("Author: %s", AID)
            }
        }

        local Success, Err = CompetitionChannel:send {
            embed = Embed
        }

        if Success and not Err then
            return SimpleEmbed(Payload, "**Submission delivered!\n\nStay tuned for updates.**")
        end

        SimpleEmbed(Payload, "**There was a problem sending the submission, please try again.**")
    else
        AwaitingResponse[AID] = false

        return SimpleEmbed(Payload, "**Submission cancelled!**")
    end
end)
