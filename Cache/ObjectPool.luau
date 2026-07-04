--!strict

local CacheService = require(script.Parent.CacheService)
local RbxSignal = require(script.Parent.RbxSignal)

export type ObjectPool = {
	ItemAcquired: RbxSignal.Signal,
	ItemReleased: RbxSignal.Signal,
	Destroying: RbxSignal.Signal,
	Acquire: (self: ObjectPool) -> (any, number),
	Release: (self: ObjectPool, item: any, leaseId: number?) -> boolean,
	Warm: (self: ObjectPool, count: number) -> (),
	Trim: (self: ObjectPool, retainedCount: number?) -> number,
	GetStats: (self: ObjectPool) -> {[string]: any},
	Destroy: (self: ObjectPool) -> (),
}

local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool.new(factory: () -> any, reset: (any) -> (), destroyItem: (any) -> (), options: CacheService.CacheOptions?): ObjectPool
	local poolOptions: CacheService.CacheOptions = options or {}
	local cache = CacheService.new(factory, reset, destroyItem, poolOptions)
	local name = poolOptions.name
	if name == nil then
		name = "ObjectPool"
	end

	local self = {
		ItemAcquired = RbxSignal.new(),
		ItemReleased = RbxSignal.new(),
		Destroying = RbxSignal.new(),
		_cache = cache,
		_name = name,
		_activeLeases = {},
		_leaseCounter = 0,
		_isDestroyed = false,
	}

	return setmetatable(self, ObjectPool) :: any
end

function ObjectPool.Acquire(self: any): (any, number)
	assert(not self._isDestroyed, "Cache@ObjectPool: object pool is destroyed")

	local item = self._cache:Acquire()
	self._leaseCounter = self._leaseCounter + 1
	self._activeLeases[item] = self._leaseCounter
	self.ItemAcquired:Fire(item, self._leaseCounter)

	return item, self._leaseCounter
end

function ObjectPool.Release(self: any, item: any, leaseId: number?): boolean
	if self._isDestroyed then
		return false
	end

	local activeLease = self._activeLeases[item]
	if activeLease == nil then
		return false
	end

	if leaseId ~= nil and leaseId ~= activeLease then
		return false
	end

	self._activeLeases[item] = nil
	if not self._cache:Release(item) then
		return false
	end

	self.ItemReleased:Fire(item, activeLease)
	return true
end

function ObjectPool.Warm(self: any, count: number)
	self._cache:Warm(count)
end

function ObjectPool.Trim(self: any, retainedCount: number?): number
	return self._cache:Trim(retainedCount)
end

function ObjectPool.GetStats(self: any): {[string]: any}
	local stats = self._cache:GetStats() :: {[string]: any}
	stats.name = self._name
	stats.leases = self._leaseCounter
	stats.activeLeases = 0

	for _ in pairs(self._activeLeases) do
		stats.activeLeases = stats.activeLeases + 1
	end

	return stats
end

function ObjectPool.Destroy(self: any)
	if self._isDestroyed then
		return
	end

	self.Destroying:Fire()
	self._isDestroyed = true
	table.clear(self._activeLeases)
	self._cache:Destroy()
	self.ItemAcquired:Destroy()
	self.ItemReleased:Destroy()
	self.Destroying:Destroy()
end

return ObjectPool

