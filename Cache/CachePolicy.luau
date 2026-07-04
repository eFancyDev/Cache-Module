--!strict

export type PolicyOptions = {
	TargetAvailableRatio: number?,
	PressureTrimRatio: number?,
	MinimumRetained: number?,
}

export type StatsLike = {
	available: number?,
	inUse: number?,
	peakInUse: number?,
}

local CachePolicy = {}

CachePolicy.Defaults = table.freeze({
	TargetAvailableRatio = 0.35,
	PressureTrimRatio = 0.5,
	MinimumRetained = 4,
})

function CachePolicy.GetPressure(stats: StatsLike): number
	local available = tonumber(stats.available) or 0
	local inUse = tonumber(stats.inUse) or 0
	local peakInUse = tonumber(stats.peakInUse) or 0
	local retained = available + inUse

	if retained <= 0 then
		return 0
	end

	local activePressure = inUse / retained
	local peakPressure = 0
	if peakInUse > 0 then
		peakPressure = inUse / peakInUse
	end

	return math.clamp(math.max(activePressure, peakPressure), 0, 1)
end

function CachePolicy.GetTrimTarget(stats: StatsLike, options: PolicyOptions?): number
	local policy = options or CachePolicy.Defaults
	local available = tonumber(stats.available) or 0
	local inUse = tonumber(stats.inUse) or 0
	local minimumRetained = policy.MinimumRetained or CachePolicy.Defaults.MinimumRetained
	local targetRatio = policy.TargetAvailableRatio or CachePolicy.Defaults.TargetAvailableRatio
	local pressureTrimRatio = policy.PressureTrimRatio or CachePolicy.Defaults.PressureTrimRatio
	local pressure = CachePolicy.GetPressure(stats)
	local idealAvailable = math.max(minimumRetained, math.ceil(math.max(inUse, 1) * targetRatio))

	if pressure >= 0.85 then
		idealAvailable = math.max(minimumRetained, math.floor(idealAvailable * pressureTrimRatio))
	end

	return math.clamp(idealAvailable, 0, math.max(available, idealAvailable))
end

function CachePolicy.GetHealth(stats: StatsLike): string
	local pressure = CachePolicy.GetPressure(stats)

	if pressure >= 0.9 then
		return "Critical"
	end

	if pressure >= 0.75 then
		return "Pressure"
	end

	if pressure >= 0.5 then
		return "Warm"
	end

	return "Healthy"
end

return CachePolicy

