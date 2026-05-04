-- Register the behaviour
behaviour("PVC")

local function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
end

local function validateAgainstTemplate(givenTable, template)
	for index, _ in pairs(template) do
		if(givenTable[index] == nil) then
			error("Passed in a table without a required index: "..index)
		end
	end
end

function PVC:Awake()
	self.voiceChatMutatorName = "AuthenticVoiceChatMutator(Clone)"
end

function PVC:Start()
	local obj = GameObject.Find(self.voiceChatMutatorName)
	if(obj) then
		self.voiceChat = ScriptedBehaviour.GetScript(obj)
	else
		error("Voice Chat not found! Cannot start up Proximity Voice Chat :(")
	end

	self.version = "1.3.0"
	self.script.StartCoroutine(function()
        coroutine.yield(WaitForSeconds(1))
		GameEvents.onActorDiedInfo.RemoveListener(self.voiceChat, "onActorDied")
		self:log("Lobotomized voice chat! Now we gonna add our own implementation :sunglasses:")
		self:log("Version: "..self.version)
    end)

	local config = self.script.mutator.configuration
	self.affectsPlayer = config.GetBool("affectsPlayer")
	self.audioDelay = config.GetFloat("audioDelay")
	self.volume = config.GetRange("volume")
	self.maxSounds = config.GetInt("maxSounds")
	self.maxDistanceHear = config.GetInt("maxDistanceHear")
	self.maxDistancePlay = config.GetInt("maxDistancePlay")
	self.playForFriendlyFire = config.GetBool("playForFriendlyFire")
	self.playForPlayerTeam = config.GetBool("playForPlayerTeam")
	self.audioChance = config.GetRange("audioChance")
	self.resortToVCIfTooFar = config.GetBool("resortToVCIfTooFar")
	self.conversationsAllowed = true or config.GetBool("conversationsAllowed")
	self.onelinersAllowed = true or config.GetBool("onelinersAllowed")
	self.debugMode = config.GetBool("debug")

	self.identifiableConvos = {}
	self.conversations = {}
	self.oneliners = {}

	self.ongoingConversation = nil

	self.currentTime = 0
	self.minTimeBetween = 1
	self.attemptTime = 5
	self.conversationChance = 0.5
	self.onelinerChance = 0.5
	self.currentID = 0

	self.sourceToActors = {}
	self.actorsToSources = {}

	self.sourceBank = self.voiceChat.targets.soundBank

	GameEvents.onActorDiedInfo.AddListener(self,"onActorDied")
	GameEvents.onActorCreated.AddListener(self, "onActorCreated")

	for _, actor in ipairs(ActorManager.actors) do
		self:onActorCreated(actor)
	end

	local template = self.targets.Template
	local audioSource = template.GetComponent(AudioSource)
	audioSource.volume = self.volume
	audioSource.maxDistance = self.maxDistanceHear
end

function PVC:Update()
	for source, actor in pairs(self.sourceToActors) do
		if(not source.isPlaying) then
			self:stopSpeakingActor(actor)
		else
			local position = Vector3(actor.position.x, actor.position.y + 1.8, actor.position.z)
			source.gameObject.transform.position = position
			source.gameObject.GetComponentInChildren(Image).enabled = self:hasAnyAudibleNoise(source)
			source.gameObject.transform.LookAt(PlayerCamera.activeCamera.transform)
		end
	end

		if(self.ongoingConversation or self.tryingToGetConversation) then
		return
	end

	self.currentTime = self.currentTime + Time.deltaTime
	if(self.currentTime < self.minTimeBetween + self.attemptTime) then
		return
	end

	self:debug("Rolling chance for a new convo")
	local debugID
	local tableToUse = nil

	if(debugID ~= nil) then
		tableToUse = self.identifiableConvos
		self:debug("Using debug id!")
	elseif(math.random() < self.conversationChance and self.conversationsAllowed) then
		tableToUse = self.conversations
		self:debug("Using conversation")
	elseif(math.random() < self.onelinerChance and self.onelinersAllowed) then
		tableToUse = self.oneliners
		self:debug("Using one liner")
	else
		self.currentTime = self.minTimeBetween
		return
	end

	if(#tableToUse <= 0 and debugID == nil) then
		self:debug("No valid tables to use for conversation!")
		self.currentTime = 0
		return
	end

	self.script.StartCoroutine(function()
		self.tryingToGetConversation = true
		local speakers = nil
		local randomConversation = nil
		local maxTries = 20
		local tries = 0

		self:debug("Attempting to get speakers")
		while(speakers == nil and tries < maxTries) do
			if(debugID ~= nil) then
				randomConversation = tableToUse[debugID]
			else
				randomConversation = tableToUse[math.random(1, #tableToUse)]
			end
			speakers = self:getSpeakersFor(randomConversation)
			tries = tries + 1
		end

		if(speakers == nil) then
			self.tryingToGetConversation = false
			self.currentTime = 0
			return
		end

		self:debug("Starting conversation!")
		local id = self.currentID
		self.ongoingConversation = {
			id = id,
			speakers = speakers,
			conversation = randomConversation
		}
		self.currentID = self.currentID + 1
		self.tryingToGetConversation = false

		for _, line in ipairs(randomConversation.lines) do
			if(not self:sanityCheckForConversation(id)) then
				return
			end
			
			local speaker = self:getSpeakerInContext(line.speakerID)
			local source
			if(self.useVCForConvo) then
				self:debug("Using Global VC for the clip!")
				self.voiceChat.queuedClip = true
				source = self.voiceChat.targets.audioSource
				self.voiceChat.currentSpeaker = speaker.name
				self.voiceChat.color = ColorScheme.GetTeamColor(speaker.team)
				source.PlayOneShot(line.clip)
			else
				source = self:playClip(speaker, line.clip, 0, true, line.volumeMultiplier)
			end

			self:debug("Starting "..line.clip.ToString():match("^[^%(]+"):gsub("%s+$", "")..", volume at "..line.volumeMultiplier..": Speaker "..speaker.name)

			for _, functionToRun in ipairs(line.functions) do
				if(not self:sanityCheckForConversation(id)) then
					return
				end
				functionToRun(speaker, self)
			end

			coroutine.yield(WaitForSeconds(0.2))
			while(source ~= nil and source.isPlaying) do
				coroutine.yield()
			end
		end
		
		self:stopConversation()
	end)
end

function PVC:onActorDied(actor, damageInfo)
	if(self.ongoingConversation ~= nil) then
		for _, _actor in pairs(self.ongoingConversation.speakers) do
			if(_actor == actor) then
				self:debug("A speaker was killed!")
				self:stopConversation(actor) -- Have to cancel the conversation because a speaker died
				return
			end
		end
	end

	-- don't bother playing if actor is too far for player to hear
	if(ActorManager.ActorDistanceToPlayer(actor) > self.maxDistancePlay) then
		if(self.resortToVCIfTooFar) then
			self.voiceChat:onActorDied(actor, damageInfo)
		end
		return
	end

	if(actor.isPlayer and not self.affectsPlayer) then
		return
	end

	if(not self.playForPlayerTeam and actor.team == Player.actor.team) then
		return
	end

	if(not self.playForFriendlyFire and damageInfo.sourceActor.team == actor.team) then
		return
	end

	if(math.random() > self.audioChance) then
		return
	end

	self:playClip(actor, self.sourceBank.clips[math.random(1, #self.sourceBank.clips)], self.audioDelay)
end

function PVC:createNewSource(ignoreLimit)
	local count = 0
	for _, _ in pairs(self.sourceToActors) do
		count = count + 1
	end
	if(not ignoreLimit and count >= self.maxSounds) then
		return
	end

	local newSource = GameObject.Instantiate(self.targets.Template)
	local audioSource = newSource.GetComponent(AudioSource)

	audioSource.SetOutputAudioMixer(AudioMixer.Ingame)

	return audioSource
end

function PVC:playClip(actor, clip, audioDelay, ignoreLimit, volumeMultiplier)
	self:stopSpeakingActor(actor)

	local source = self:createNewSource(ignoreLimit)
	
	if(source) then
		source.volume = source.volume * (volumeMultiplier or 1)
		self.script.StartCoroutine(function()
			coroutine.yield(WaitForSeconds(audioDelay))
			source.PlayOneShot(clip)
			self.sourceToActors[source] = actor
			self.actorsToSources[actor] = source
		end)
	end

	return source
end

function PVC:stopSpeakingActor(actor)
	local source = self.actorsToSources[actor]
	if(source) then
		self.sourceToActors[source] = nil
		self.actorsToSources[actor] = nil
		source.Stop()
		GameObject.Destroy(source.gameObject)
	end
end

function PVC:hasAnyAudibleNoise(source, threshold)
	threshold = threshold or 0.001
	local samples = source.GetOutputData(0)

	local sum = 0;
    for i = 1, #samples, 1 do
        sum = sum + Mathf.Abs(samples[i])
	end

    local average = sum / #samples
    return average > threshold
end

function PVC:addOneLiner(speakerTemplate, interruptable, id)
	validateAgainstTemplate(speakerTemplate, self:getLineTemplate())

	interruptable = interruptable or false
	local conversation = self:getConversationTemplate()
	conversation.metadata.interruptable = interruptable
	table.insert(conversation.lines, speakerTemplate)

	self:addConversation(conversation, true, id)
end

function PVC:addLinesAsConversation(lines, interruptable, id)
	local temp = self:getLineTemplate()
	local conversation = self:getConversationTemplate()
	conversation.metadata.interruptable = interruptable

	for _, line in ipairs(lines) do
		validateAgainstTemplate(line, temp)
		table.insert(conversation.lines, line)
	end

	self:addConversation(conversation, false, id)
end

function PVC:addConversation(conversation, isOneLiner, id)
	validateAgainstTemplate(conversation, self:getConversationTemplate())

	local toAddTo = self.conversations
	if(isOneLiner) then
		toAddTo = self.oneliners
	end
	if(id) then
		self.identifiableConvos[id] = conversation
	end
	table.insert(toAddTo, conversation)
	self:log("Successfully added conversation: "..(id or ""))
end

function PVC:getLineTemplate(clip, speakerID, volumeMultiplier, functions)
	return {
		speakerID = speakerID or "a", -- Use speakerID to refer to a specific speaker in a conversation. Each speakerID that pops up the first time in a conversation will be assigned to a random actor nearby the player
		volumeMultiplier = volumeMultiplier or 1, -- for if your clip is too quiet!
		clip = clip or nil, -- AudioClip
		functions = functions or {} -- Functions that run in synchronous order as a conversation goes on (use for funny voicelines that would warrant this)
	}
end

function PVC:getConversationTemplate(lines, interruptable)
	return {
		metadata = {
			interruptable = interruptable or false, -- Can it be interrupted when actor takes damage? (ignored when speaking actor dies)
		},
		lines = lines or {}
	}
end

function PVC:getSpeakerInContext(id)
	return self.ongoingConversation.speakers[id]
end

function PVC:getSpeakersFor(conversation)
	if(conversation == nil) then
		self.tryingToGetConversation = false
		self.currentTime = 0
		error("There is no such conversation to get speakers for!")
	end

	local speakers = {}
	local actors = ActorManager.AliveActorsInRange(Player.actor.transform.position, self.maxDistanceHear - 5)
	for i, actor in ipairs(actors) do
		if(actor == Player.actor) then
			table.remove(actors, i)
			break
		end
	end

	local needed = {}
	local count = 0

	for _, line in ipairs(conversation.lines) do
		local speakerID = line.speakerID
		if(needed[speakerID]) == nil then
			needed[speakerID] = true
			count = count + 1
		end
	end

	if(#actors < count) then
		if(self.resortToVCIfTooFar and not self.voiceChat.queuedClip) then
			self.useVCForConvo = true
			actors = ActorManager.GetActorsOnTeam(Player.actor.team)

			for i, actor in ipairs(actors) do
				if(actor == Player.actor) then
					table.remove(actors, i)
					break
				end
			end
		end
	end

	shuffle(actors)

	for _, line in ipairs(conversation.lines) do
		local speakerID = line.speakerID
		if(speakers[speakerID]) == nil then
			if(#actors <= 0) then
				self:debug("No more actors could be found nearby for speakers :(")
				self.useVCForConvo = false
				return nil
			end

			speakers[speakerID] = table.remove(actors, 1)
			self:debug("Found speaker for "..speakerID)
		end
	end

	return speakers
end

function PVC:sanityCheckForConversation(id)
	if(self.ongoingConversation == nil or self.ongoingConversation.id ~= id) then
		return false
	end
	return true
end

function PVC:onActorCreated(actor)
	actor.onTakeDamage.AddListener(self, "onActorDamaged")
end

function PVC:onActorDamaged(actor)
	if(self.ongoingConversation ~= nil and self.ongoingConversation.conversation.metadata.interruptable) then
		for _, _actor in pairs(self.ongoingConversation.speakers) do
			if(_actor == actor) then
				self:debug("A speaker was damaged!")
				self:stopConversation(actor) -- Have to cancel the conversation because a speaker was damaged
				return
			end
		end
	end
end

function PVC:stopConversation(actor)
	self:debug("Stopped conversation!")
	self.ongoingConversation = nil
	self.currentTime = 0

	if(actor ~= nil) then
		self:stopSpeakingActor(actor)
	end
	if(self.useVCForConvo) then
		self.useVCForConvo = false
		self.voiceChat.queuedClip = false
	end
end

function PVC:log(...)
	local string = "<color=#C8A2C8>[Proximity Voice Chat]:</color> "
	for _, extraArg in ipairs({...}) do
		string = string..tostring(extraArg)
	end
	print(string)
end

function PVC:debug(...)
	if(self.debugMode) then
		self:log(...)
	end
end