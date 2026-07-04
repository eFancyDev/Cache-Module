--!strict

local CacheService = require(script.Parent.CacheService)

export type InstanceCache = {
	Get: (self: InstanceCache, parent: Instance?) -> Instance,
	Release: (self: InstanceCache, item: Instance) -> boolean,
	Warm: (self: InstanceCache, count: number) -> (),
	Trim: (self: InstanceCache, retainedCount: number?) -> number,
	GetStats: (self: InstanceCache) -> CacheService.CacheStats,
	Destroy: (self: InstanceCache) -> (),
}

type InternalInstanceCache = InstanceCache & {
	_template: Instance,
	_cache: CacheService.Cache,
}

local InstanceCache = {}
InstanceCache.__index = InstanceCache

function InstanceCache.new(template: Instance, initialSize: number?, maxRetained: number?): InstanceCache
	assert(typeof(template) == "Instance", "Cache@Instance: template must be an Instance")

	local cache = CacheService.new(function()
		return template:Clone()
	end, function(item: Instance)
		item.Parent = nil
		if item:IsA("BasePart") then
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero
		end
	end, function(item: Instance)
		item:Destroy()
	end, {
		name = template.Name,
		initialSize = initialSize or 0,
		maxRetained = maxRetained or 128,
	})

	return setmetatable({
		_template = template,
		_cache = cache,
	}, InstanceCache) :: InternalInstanceCache
end

function InstanceCache:Get(parent: Instance?): Instance
	local item = self._cache:Acquire()
	item.Parent = parent
	return item
end

function InstanceCache:Release(item: Instance): boolean
	return self._cache:Release(item)
end

function InstanceCache:Warm(count: number)
	self._cache:Warm(count)
end

function InstanceCache:Trim(retainedCount: number?): number
	return self._cache:Trim(retainedCount)
end

function InstanceCache:GetStats(): CacheService.CacheStats
	return self._cache:GetStats()
end

function InstanceCache:Destroy()
	self._cache:Destroy()
end

return InstanceCache

