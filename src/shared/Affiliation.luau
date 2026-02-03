-- ReplicatedStorage.Affiliation
-- Lightweight affiliation helpers for fast friend/foe checks.

local Affiliation = {}

Affiliation.Attributes = {
	TeamId = "TeamId",
	OwnerUserId = "OwnerUserId",
}

local function normalizePositiveInt(value: any): number
	if type(value) ~= "number" then
		return 0
	end
	if value ~= value or value <= 0 then
		return 0
	end
	return math.floor(value)
end

function Affiliation.GetTeamIdForPlayer(player: Player): number
	local attr = player:GetAttribute(Affiliation.Attributes.TeamId)
	local teamId = normalizePositiveInt(attr)
	if teamId > 0 then
		return teamId
	end
	return player.UserId
end

function Affiliation.StampPlayer(player: Player)
	local teamId = Affiliation.GetTeamIdForPlayer(player)
	player:SetAttribute(Affiliation.Attributes.TeamId, teamId)
	player:SetAttribute(Affiliation.Attributes.OwnerUserId, player.UserId)
end

function Affiliation.StampCharacter(player: Player, character: Model)
	character:SetAttribute(Affiliation.Attributes.TeamId, Affiliation.GetTeamIdForPlayer(player))
	character:SetAttribute(Affiliation.Attributes.OwnerUserId, player.UserId)
end

function Affiliation.StampNpc(npc: Model, ownerUserId: number?, teamId: number?)
	local normalizedTeamId = normalizePositiveInt(teamId)
	local normalizedOwner = normalizePositiveInt(ownerUserId)

	if normalizedTeamId > 0 then
		npc:SetAttribute(Affiliation.Attributes.TeamId, normalizedTeamId)
	else
		npc:SetAttribute(Affiliation.Attributes.TeamId, 0)
	end

	if normalizedOwner > 0 then
		npc:SetAttribute(Affiliation.Attributes.OwnerUserId, normalizedOwner)
	else
		npc:SetAttribute(Affiliation.Attributes.OwnerUserId, 0)
	end
end

function Affiliation.GetTeamIdFromModel(model: Model): number
	return normalizePositiveInt(model:GetAttribute(Affiliation.Attributes.TeamId))
end

function Affiliation.GetOwnerUserIdFromModel(model: Model): number
	return normalizePositiveInt(model:GetAttribute(Affiliation.Attributes.OwnerUserId))
end

function Affiliation.AreFriendlyTeam(teamA: number, teamB: number): boolean
	teamA = normalizePositiveInt(teamA)
	teamB = normalizePositiveInt(teamB)
	if teamA <= 0 or teamB <= 0 then
		return false
	end
	return teamA == teamB
end

function Affiliation.AreFriendly(a: Instance, b: Instance): boolean
	local modelA = if a:IsA("Model") then (a :: Model) else a:FindFirstAncestorOfClass("Model")
	local modelB = if b:IsA("Model") then (b :: Model) else b:FindFirstAncestorOfClass("Model")
	if not modelA or not modelB then
		return false
	end
	return Affiliation.AreFriendlyTeam(Affiliation.GetTeamIdFromModel(modelA), Affiliation.GetTeamIdFromModel(modelB))
end

return Affiliation
