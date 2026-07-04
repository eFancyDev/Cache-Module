--!strict

local CacheService = require(script.CacheService)
local ObjectPool = require(script.ObjectPool)
local ExpiringCache = require(script.ExpiringCache)
local InstanceCache = require(script.InstanceCache)
local PoolRegistry = require(script.PoolRegistry)
local CacheMaintenance = require(script.CacheMaintenance)
local CachePolicy = require(script.CachePolicy)
local RbxSignal = require(script.RbxSignal)

export type Cache = CacheService.Cache
export type CacheOptions = CacheService.CacheOptions
export type CacheStats = CacheService.CacheStats
export type ObjectPool = ObjectPool.ObjectPool
export type ExpiringCache = ExpiringCache.ExpiringCache
export type InstanceCache = InstanceCache.InstanceCache
export type RbxSignal = RbxSignal.Signal

local Cache = table.freeze({
	Version = "0.2.8",
	PackageTag = "Cache@Service",

	CreateCache = CacheService.new,
	CreatePool = ObjectPool.new,
	CreateExpiring = ExpiringCache.new,
	CreateInstanceCache = InstanceCache.new,

	new = CacheService.new,
	CacheService = CacheService,
	ObjectPool = ObjectPool,
	ExpiringCache = ExpiringCache,
	InstanceCache = InstanceCache,
	Registry = PoolRegistry,
	Maintenance = CacheMaintenance,
	Policy = CachePolicy,
	RbxSignal = RbxSignal,
})

return Cache

