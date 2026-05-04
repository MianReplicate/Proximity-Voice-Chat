-- Register the behaviour
behaviour("AddConversations")

local function splitNameNumber(s)
    local i = #s

    while i > 0 and s:sub(i,i):match("%d") do
        i = i - 1
    end

    local name = s:sub(1, i)
    local number = s:sub(i + 1)

    return name, number
end

function AddConversations:Start()
	self.common = {
		lookAt = function(id)
			return function(actor, pvc)
				local otherActor = pvc:getSpeakerInContext(id)
				local direction = (otherActor.transform.position - actor.transform.position).normalized
			end
		end,
	}


	self.pvc = self.targets.pvc.self
	self:AddOneLiners()
	self:AddConversations(
		{
			frog1 = {"a", 3},
			frog2 = {"b", 3},
			frog3 = {"c", 3},
			frog4 = {"b", 3},
			frog5 = {"c", 3},
			frog6 = {"a", 3},
			frog7 = {"c", 3},

			hello2 = {"b"},

			imhit2 = {"b"},
			imhit4 = {"b"},
			imhit5 = {"c"},

			russian2 = {"b"},
			russian4 = {"b"},
			russian6 = {"b"},

			terrorist2 = {"b"},

			pray2 = {"b"},

			jp2 = {"b"},
			jp4 = {"c"},
			jp5 = {"b"},

			pdick2 = {"b"},

			plantB1 = {"b"},
			plantB3 = {"c"},

			greenlight2 = {"b"},
			greenlight4 = {"c"}
		}
	)
end

function AddConversations:AddOneLiners(specificClips)
	specificClips = specificClips or {}
	local oneliners = self.targets.oneliners

	for _, clip in ipairs(oneliners.clips) do
		local name = clip.ToString():match("^[^%(]+"):gsub("%s+$", "")

		local args = specificClips[name]
		if(args) then
			args = table.unpack(args)
		end
		self.pvc:addOneLiner(self.pvc:getLineTemplate(clip, args), false, name)
	end
end

function AddConversations:AddConversations(specificClips, interruptableConvos)
	interruptableConvos = interruptableConvos or {}
	local conversations = self.targets.conversations
	local conversationID = nil
	local conversationBatch = nil

	for _, clip in ipairs(conversations.clips) do
		local cleanID, num = splitNameNumber(clip.ToString():match("^[^%(]+"):gsub("%s+$", ""))
		if(cleanID ~= conversationID) then
			if(conversationID ~= nil and conversationBatch ~= nil) then
				local interruptable = interruptableConvos[cleanID] or false
				self.pvc:addLinesAsConversation(conversationBatch, interruptable, conversationID)
				conversationBatch = nil
			end
			conversationID = cleanID
		end


		conversationBatch = conversationBatch or {}
		local args = specificClips[cleanID..num]
		if(args) then
			args = table.unpack(args)
		end
		local lineTemplate = self.pvc:getLineTemplate(clip, args)
		table.insert(conversationBatch, lineTemplate)
	end
end