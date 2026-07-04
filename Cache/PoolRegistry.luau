--!strict

local RbxSignal = require(script.Parent.RbxSignal)

export type RegisteredPool = {
	GetStats: ((self: any) -> {[string]: any})?,
	Trim: ((self: any, retainedCount: number?) -> number)?,
	Destroy: ((self: any) -> ())?,
}

export type MetricsSnapshot = {
	totals: {[string]: number},
	pools: {[string]: {[string]: any}},
	capturedAt: number,
}

local statFields = table.freeze({
	"available",
	"inUse",
	"created",
	"returned",
	"discarded",
	"activeLeases",
})

local PoolRegistry = {}

local pools: {[string]: RegisteredPool} = {}

PoolRegistry.Registered = RbxSignal.new()
PoolRegistry.Removed = RbxSignal.new()

function PoolRegistry.Register(name: string, pool: RegisteredPool, replaceExisting: boolean?): boolean
	if type(name) ~= "string" or name == "" or type(pool) ~= "table" then
		return false
	end

	local existingPool = pools[name]
	if existingPool ~= nil and replaceExisting ~= true then
		return false
	end

	if existingPool ~= nil and type(existingPool.Destroy) == "function" then
		existingPool:Destroy()
	end

	pools[name] = pool
	PoolRegistry.Registered:Fire(name, pool)
	return true
end

function PoolRegistry.Get(name: string): RegisteredPool?
	return pools[name]
end

function PoolRegistry.Remove(name: string, destroyPool: boolean?): boolean
	local pool = pools[name]
	if pool == nil then
		return false
	end

	pools[name] = nil
	if destroyPool ~= false and type(pool.Destroy) == "function" then
		pool:Destroy()
	end

	PoolRegistry.Removed:Fire(name, pool)
	return true
end

function PoolRegistry.GetPools(): {[string]: RegisteredPool}
	return table.clone(pools)
end

function PoolRegistry.GetStats(): {[string]: {[string]: any}}
	local result: {[string]: {[string]: any}} = {}

	for name, pool in pairs(pools) do
		if type(pool.GetStats) == "function" then
			result[name] = pool:GetStats()
		else
			result[name] = { name = name }
		end
	end

	return result
end

function PoolRegistry.GetMetricsSnapshot(): MetricsSnapshot
	local poolStats = PoolRegistry.GetStats()
	local totals = {
		available = 0,
		inUse = 0,
		created = 0,
		returned = 0,
		discarded = 0,
		activeLeases = 0,
		pools = 0,
	}

	for _, stats in pairs(poolStats) do
		totals.pools = totals.pools + 1
		for _, field in ipairs(statFields) do
			totals[field] = totals[field] + (tonumber(stats[field]) or 0)
		end
	end

	return {
		totals = totals,
		pools = poolStats,
		capturedAt = os.clock(),
	}
end

function PoolRegistry.DestroyAll()
	local names: {string} = {}
	for name in pairs(pools) do
		table.insert(names, name)
	end

	for _, name in ipairs(names) do
		PoolRegistry.Remove(name, true)
	end
end

return PoolRegistry

