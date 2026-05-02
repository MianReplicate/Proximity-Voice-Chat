-- Register the behaviour
behaviour("PVC")

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

	self.script.StartCoroutine(function()
        coroutine.yield(WaitForSeconds(1))
		GameEvents.onActorDiedInfo.RemoveListener(self.voiceChat, "onActorDied")
		self:log("Lobotomized voice chat! Now we gonna add our own implementation :sunglasses:")
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

	self.sourceToActors = {}

	self.sourceBank = self.voiceChat.targets.soundBank

	GameEvents.onActorDiedInfo.AddListener(self,"onActorDied")


	local template = self.targets.Template
	local audioSource = template.GetComponent(AudioSource)
	audioSource.volume = self.volume
	audioSource.maxDistance = self.maxDistanceHear
end

function PVC:Update()
	for source, actor in pairs(self.sourceToActors) do
		if(not source.isPlaying) then
			self.sourceToActors[source] = nil
			GameObject.Destroy(source.gameObject)
		else
			local position = Vector3(actor.position.x, actor.position.y + 1.5, actor.position.z)
			source.gameObject.transform.position = position
			source.gameObject.GetComponentInChildren(Image).enabled = self:hasAnyAudibleNoise(source)
			source.gameObject.transform.LookAt(Player.actor.transform)
		end
	end
end

function PVC:onActorDied(actor, damageInfo)
	-- don't bother playing if actor is too far for player to hear
	if(ActorManager.ActorDistanceToPlayer(actor) > self.maxDistancePlay) then
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

	local source = self:createNewSource()
	
	if(source) then
		self.script.StartCoroutine(function()
			coroutine.yield(WaitForSeconds(self.audioDelay))
			source.PlayOneShot(self.sourceBank.clips[math.random(1, #self.sourceBank.clips)])
			self.sourceToActors[source] = actor
		end)
	end
end

function PVC:createNewSource()
	local count = 0
	for _, _ in pairs(self.sourceToActors) do
		count = count + 1
	end
	if(count >= self.maxSounds) then
		return
	end

	local newSource = GameObject.Instantiate(self.targets.Template)
	local audioSource = newSource.GetComponent(AudioSource)

	audioSource.SetOutputAudioMixer(AudioMixer.Ingame)

	return audioSource
end

function PVC:hasAnyAudibleNoise(source, threshold)
	threshold = threshold or 0.01
	local samples = source.GetOutputData(0)

	local sum = 0;
    for i = 1, #samples, 1 do
        sum = sum + Mathf.Abs(samples[i])
	end

    local average = sum / #samples
    return average > threshold
end

function PVC:log(...)
	local string = "<color=#C8A2C8>[Proximity Voice Chat]:</color> "
	for _, extraArg in ipairs({...}) do
		string = string..tostring(extraArg)
	end
	print(string)
end