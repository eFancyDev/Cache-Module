--!strict

local CachePolicy = require(script.Parent.CachePolicy)
local PoolRegistry = require(script.Parent.PoolRegistry)

export type HealthSnapshot = {
	[string]: {
		status: string,
		pressure: number,
		stats: {[string]: any},
	},
}

type PoolStatsReader = (any) -> {[string]: any}
type PoolTrimmer = (any, number) -> number

local CacheMaintenance = {}

local function resolvePoolMethods(pool: any): (PoolStatsReader?, PoolTrimmer?)
	if type(pool) ~= "table" then
		return nil, nil
	end

	local getStatsCandidate = pool.GetStats
	if type(getStatsCandidate) ~= "function" then
		return nil, nil
	end

	local trimCandidate = pool.Trim
	if type(trimCandidate) ~= "function" then
		return nil, nil
	end

	local getStats = getStatsCandidate :: PoolStatsReader
	local trim = trimCandidate :: PoolTrimmer

	return getStats, trim
end

function CacheMaintenance.TrimPool(pool: any, options: CachePolicy.PolicyOptions?): number
	local getStats, trim = resolvePoolMethods(pool)
	if getStats == nil or trim == nil then
		return 0
	end

	local stats = getStats(pool)
	local target = CachePolicy.GetTrimTarget(stats, options)
	local removed = trim(pool, target)

	return tonumber(removed) or 0
end

function CacheMaintenance.TrimRegistry(options: CachePolicy.PolicyOptions?): number
	local removed = 0
	local pools = PoolRegistry.GetPools()

	for _, pool in pairs(pools) do
		removed = removed + CacheMaintenance.TrimPool(pool, options)
	end

	return removed
end

function CacheMaintenance.GetHealthSnapshot(): HealthSnapshot
	local poolStats = PoolRegistry.GetStats()
	local health = {}

	for name, stats in pairs(poolStats) do
		health[name] = {
			status = CachePolicy.GetHealth(stats),
			pressure = CachePolicy.GetPressure(stats),
			stats = stats,
		}
	end

	return health
end

function CacheMaintenance.GetMetricsSnapshot(): PoolRegistry.MetricsSnapshot
	return PoolRegistry.GetMetricsSnapshot()
end

function CacheMaintenance.DestroyRegistry()
	PoolRegistry.DestroyAll()
end

return CacheMaintenance

