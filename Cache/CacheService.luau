--!strict

local RbxSignal = require(script.Parent.RbxSignal)

export type CacheStats = {
	name: string,
	available: number,
	inUse: number,
	created: number,
	returned: number,
	discarded: number,
	peakInUse: number,
	maxRetained: number,
	lastAcquireAt: number?,
	lastReleaseAt: number?,
	pressure: number,
}

export type CacheOptions = {
	initialSize: number?,
	maxRetained: number?,
	name: string?,
	autoTrim: boolean?,
	trimThreshold: number?,
}

export type Cache = {
	ItemAcquired: RbxSignal.Signal,
	ItemReleased: RbxSignal.Signal,
	ItemDiscarded: RbxSignal.Signal,
	Destroying: RbxSignal.Signal,
	Acquire: (self: Cache) -> any,
	Release: (self: Cache, item: any) -> boolean,
	Warm: (self: Cache, count: number) -> (),
	GetStats: (self: Cache) -> CacheStats,
	GetPressure: (self: Cache) -> number,
	Clear: (self: Cache) -> (),
	Trim: (self: Cache, retainedCount: number?) -> number,
	ReleaseAll: (self: Cache) -> number,
	SetMaxRetained: (self: Cache, maxRetained: number) -> (),
	Destroy: (self: Cache) -> (),
}

local defaultMaxRetained = 128
local defaultTrimThreshold = 0.9

local CacheService = {}
CacheService.__index = CacheService

local function assertFiniteNumber(value: number, name: string)
	local isFinite = value == value and value ~= math.huge and value ~= -math.huge
	assert(typeof(value) == "number" and isFinite, "Cache@Service: " .. name .. " must be a finite number")
end

local function assertNonNilItem(item: any): any
	assert(item ~= nil, "Cache@Service: factory must not return nil")
	return item
end

local function getInUseMap(self: any): {[any]: any}
	local inUse = self._inUse
	assert(type(inUse) == "table", "Cache@Service: _inUse must be a table")
	return inUse :: {[any]: any}
end

function CacheService.new(factory: () -> any, reset: (any) -> (), destroyItem: (any) -> (), options: CacheOptions?): Cache
	assert(type(factory) == "function", "Cache@Service: factory is required")
	assert(type(reset) == "function", "Cache@Service: reset is required")
	assert(type(destroyItem) == "function", "Cache@Service: destroyItem is required")

	local initialSize = 0
	local maxRetained = defaultMaxRetained
	local trimThreshold = defaultTrimThreshold
	local name = "Cache"
	local autoTrim = false

	if options ~= nil then
		if options.initialSize ~= nil then
			initialSize = options.initialSize
		end
		if options.maxRetained ~= nil then
			maxRetained = options.maxRetained
		end
		if options.trimThreshold ~= nil then
			trimThreshold = options.trimThreshold
		end
		if options.name ~= nil then
			name = options.name
		end
		autoTrim = options.autoTrim == true
	end

	assertFiniteNumber(initialSize, "initialSize")
	assertFiniteNumber(maxRetained, "maxRetained")
	assertFiniteNumber(trimThreshold, "trimThreshold")
	assert(initialSize >= 0, "Cache@Service: initialSize must be non-negative")
	assert(maxRetained >= 0, "Cache@Service: maxRetained must be non-negative")
	assert(trimThreshold >= 0 and trimThreshold <= 1, "Cache@Service: trimThreshold must be between 0 and 1")

	local roundedMaxRetained = math.floor(maxRetained)
	local self = {
		ItemAcquired = RbxSignal.new(),
		ItemReleased = RbxSignal.new(),
		ItemDiscarded = RbxSignal.new(),
		Destroying = RbxSignal.new(),
		_available = {},
		_inUse = {},
		_factory = factory,
		_reset = reset,
		_destroyItem = destroyItem,
		_maxRetained = roundedMaxRetained,
		_name = name,
		_autoTrim = autoTrim,
		_trimThreshold = trimThreshold,
		_isDestroyed = false,
		_stats = {
			name = name,
			available = 0,
			inUse = 0,
			created = 0,
			returned = 0,
			discarded = 0,
			peakInUse = 0,
			maxRetained = roundedMaxRetained,
			lastAcquireAt = nil,
			lastReleaseAt = nil,
			pressure = 0,
		},
	}

	local cache = setmetatable(self, CacheService) :: any
	cache:Warm(math.min(math.floor(initialSize), roundedMaxRetained))

	return cache
end

function CacheService.Acquire(self: any): any
	assert(not self._isDestroyed, "Cache@Service: cannot acquire from a destroyed cache")

	local item = table.remove(self._available)
	if item == nil then
		item = assertNonNilItem(self._factory())
		self._stats.created = self._stats.created + 1
	end

	rawset(getInUseMap(self), item, true)
	self._stats.available = #self._available
	self._stats.inUse = self._stats.inUse + 1
	self._stats.peakInUse = math.max(self._stats.peakInUse, self._stats.inUse)
	self._stats.lastAcquireAt = os.clock()
	self._stats.pressure = self:GetPressure()
	self.ItemAcquired:Fire(item)

	return item
end

function CacheService.Release(self: any, item: any): boolean
	if self._isDestroyed then
		return false
	end

	if item == nil then
		return false
	end

	local trackedItem = item
	local inUse = getInUseMap(self)
	if rawget(inUse, trackedItem) ~= true then
		return false
	end

	rawset(inUse, trackedItem, nil)
	self._stats.inUse = math.max(0, self._stats.inUse - 1)
	self._reset(trackedItem)

	if #self._available >= self._maxRetained then
		self._destroyItem(trackedItem)
		self._stats.discarded = self._stats.discarded + 1
		self.ItemDiscarded:Fire(trackedItem)
	else
		table.insert(self._available, trackedItem)
		self._stats.returned = self._stats.returned + 1
		self.ItemReleased:Fire(trackedItem)
	end

	self._stats.available = #self._available
	self._stats.lastReleaseAt = os.clock()
	self._stats.pressure = self:GetPressure()

	if self._autoTrim and self._stats.pressure >= self._trimThreshold then
		self:Trim(math.floor(self._maxRetained * 0.5))
	end

	return true
end

function CacheService.Warm(self: any, count: number)
	assert(not self._isDestroyed, "Cache@Service: cannot warm a destroyed cache")
	assertFiniteNumber(count, "count")

	local target = math.min(math.max(0, math.floor(count)), self._maxRetained)
	while #self._available < target do
		local item = assertNonNilItem(self._factory())
		self._reset(item)
		table.insert(self._available, item)
		self._stats.created = self._stats.created + 1
	end

	self._stats.available = #self._available
	self._stats.pressure = self:GetPressure()
end

function CacheService.Trim(self: any, retainedCount: number?): number
	assert(not self._isDestroyed, "Cache@Service: cannot trim a destroyed cache")

	local requestedCount = 0
	if retainedCount ~= nil then
		requestedCount = retainedCount
	end
	assertFiniteNumber(requestedCount, "retainedCount")

	local target = math.clamp(math.floor(requestedCount), 0, self._maxRetained)
	local removed = 0

	while #self._available > target do
		local item = table.remove(self._available)
		if item ~= nil then
			self._destroyItem(item)
			self._stats.discarded = self._stats.discarded + 1
			self.ItemDiscarded:Fire(item)
			removed = removed + 1
		end
	end

	self._stats.available = #self._available
	self._stats.pressure = self:GetPressure()
	return removed
end

function CacheService.ReleaseAll(self: any): number
	local items = {}
	for item in pairs(self._inUse) do
		table.insert(items, item)
	end

	local released = 0
	for _, item in ipairs(items) do
		if self:Release(item) then
			released = released + 1
		end
	end

	return released
end

function CacheService.SetMaxRetained(self: any, maxRetained: number)
	assertFiniteNumber(maxRetained, "maxRetained")
	assert(maxRetained >= 0, "Cache@Service: maxRetained must be non-negative")

	self._maxRetained = math.floor(maxRetained)
	self._stats.maxRetained = self._maxRetained
	self:Trim(self._maxRetained)
end

function CacheService.GetPressure(self: any): number
	local retained = #self._available + self._stats.inUse
	if retained <= 0 then
		return 0
	end

	return math.clamp(self._stats.inUse / retained, 0, 1)
end

function CacheService.GetStats(self: any): CacheStats
	local stats = table.clone(self._stats)
	stats.name = self._name
	stats.maxRetained = self._maxRetained
	stats.available = #self._available
	stats.pressure = self:GetPressure()
	return stats
end

function CacheService.Clear(self: any)
	for _, item in ipairs(self._available) do
		self._destroyItem(item)
		self._stats.discarded = self._stats.discarded + 1
		self.ItemDiscarded:Fire(item)
	end

	table.clear(self._available)
	self._stats.available = 0
	self._stats.pressure = self:GetPressure()
end

function CacheService.Destroy(self: any)
	if self._isDestroyed then
		return
	end

	self.Destroying:Fire()
	self._isDestroyed = true
	self:Clear()

	for item in pairs(self._inUse) do
		self._destroyItem(item)
		self._stats.discarded = self._stats.discarded + 1
		self.ItemDiscarded:Fire(item)
	end

	table.clear(self._inUse)
	self._stats.inUse = 0
	self._stats.pressure = 0
	self.ItemAcquired:Destroy()
	self.ItemReleased:Destroy()
	self.ItemDiscarded:Destroy()
	self.Destroying:Destroy()
end

return CacheService

