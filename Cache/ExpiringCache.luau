--!strict

local RbxSignal = require(script.Parent.RbxSignal)

export type ExpiringCache = {
	Changed: RbxSignal.Signal,
	Evicted: RbxSignal.Signal,
	Set: (self: ExpiringCache, key: any, value: any, lifetime: number?) -> (),
	Get: (self: ExpiringCache, key: any) -> any?,
	Remove: (self: ExpiringCache, key: any) -> boolean,
	Sweep: (self: ExpiringCache, maximum: number?) -> number,
	GetStats: (self: ExpiringCache) -> {[string]: number},
	Clear: (self: ExpiringCache) -> (),
	Destroy: (self: ExpiringCache) -> (),
}

type Entry = {
	value: any,
	expiresAt: number,
}

local defaultLifetime = 30

local ExpiringCache = {}
ExpiringCache.__index = ExpiringCache

local function normalizeLifetime(lifetime: number?): number
	local resolvedLifetime = defaultLifetime
	if lifetime ~= nil then
		resolvedLifetime = lifetime
	end

	assert(typeof(resolvedLifetime) == "number" and resolvedLifetime >= 0, "Cache@Expiring: lifetime must be a non-negative number")
	return resolvedLifetime
end

function ExpiringCache.new(defaultLifetimeOverride: number?): ExpiringCache
	local lifetime = normalizeLifetime(defaultLifetimeOverride)
	local self = {
		Changed = RbxSignal.new(),
		Evicted = RbxSignal.new(),
		_entries = {},
		_defaultLifetime = lifetime,
		_hits = 0,
		_misses = 0,
		_evictions = 0,
		_isDestroyed = false,
	}

	return setmetatable(self, ExpiringCache) :: any
end

function ExpiringCache.Set(self: any, key: any, value: any, lifetime: number?)
	assert(not self._isDestroyed, "Cache@Expiring: cannot set on a destroyed cache")

	local ttl = self._defaultLifetime
	if lifetime ~= nil then
		ttl = normalizeLifetime(lifetime)
	end

	local expiresAt = os.clock() + ttl
	if ttl == 0 then
		expiresAt = math.huge
	end

	self._entries[key] = {
		value = value,
		expiresAt = expiresAt,
	} :: Entry

	self.Changed:Fire(key, value)
end

function ExpiringCache.Get(self: any, key: any): any?
	local entry = self._entries[key]
	if entry == nil then
		self._misses = self._misses + 1
		return nil
	end

	if entry.expiresAt <= os.clock() then
		self._entries[key] = nil
		self._misses = self._misses + 1
		self._evictions = self._evictions + 1
		self.Evicted:Fire(key)
		self.Changed:Fire(key, nil)
		return nil
	end

	self._hits = self._hits + 1
	return entry.value
end

function ExpiringCache.Remove(self: any, key: any): boolean
	if self._entries[key] == nil then
		return false
	end

	self._entries[key] = nil
	self.Changed:Fire(key, nil)
	return true
end

function ExpiringCache.Sweep(self: any, maximum: number?): number
	local removed = 0
	local now = os.clock()

	for key, entry in pairs(self._entries) do
		if entry.expiresAt <= now then
			self._entries[key] = nil
			removed = removed + 1
			self.Evicted:Fire(key)
			self.Changed:Fire(key, nil)

			if maximum ~= nil and removed >= maximum then
				break
			end
		end
	end

	self._evictions = self._evictions + removed
	return removed
end

function ExpiringCache.GetStats(self: any): {[string]: number}
	local size = 0
	for _ in pairs(self._entries) do
		size = size + 1
	end

	return {
		size = size,
		hits = self._hits,
		misses = self._misses,
		evictions = self._evictions,
	}
end

function ExpiringCache.Clear(self: any)
	for key in pairs(self._entries) do
		self.Changed:Fire(key, nil)
	end

	table.clear(self._entries)
end

function ExpiringCache.Destroy(self: any)
	if self._isDestroyed then
		return
	end

	self._isDestroyed = true
	self:Clear()
	self.Changed:Destroy()
	self.Evicted:Destroy()
end

return ExpiringCache

