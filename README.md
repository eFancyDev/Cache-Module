<div align="center">

# Cache Module

<img alt="Roblox" src="https://img.shields.io/badge/Roblox-Luau-red?style=for-the-badge">
<img alt="Rojo" src="https://img.shields.io/badge/layout-Rojo-ff6b35?style=for-the-badge">
<img alt="Version" src="https://img.shields.io/badge/version-0.2.8-2f81f7?style=for-the-badge">
<img alt="Typecheck" src="https://img.shields.io/badge/typecheck-strict-7c3aed?style=for-the-badge">

A Roblox cache and pooling package for reusable runtime objects, temporary data, and Instance templates.

</div>

## Why Use This

Games create and destroy the same objects constantly: projectiles, hitboxes, coins, pickup models, temporary VFX parts, UI rows, sound emitters, and short-lived debounce records.

Cache Module gives those systems a reusable lifecycle:

- acquire something when work starts
- reset it when the work ends
- retain a controlled amount for reuse
- destroy overflow when pressure is too high
- inspect stats when something feels expensive

## Rojo Structure

This repo uses the standard Rojo module layout.

```txt
Cache/
  init.luau
  CacheService.luau
  ObjectPool.luau
  InstanceCache.luau
  ExpiringCache.luau
  PoolRegistry.luau
  CacheMaintenance.luau
  CachePolicy.luau
  RbxSignal.luau
```

In Roblox Studio this becomes:

```txt
ReplicatedStorage
  Cache [ModuleScript]
    CacheService [ModuleScript]
    ObjectPool [ModuleScript]
    InstanceCache [ModuleScript]
    ExpiringCache [ModuleScript]
    PoolRegistry [ModuleScript]
    CacheMaintenance [ModuleScript]
    CachePolicy [ModuleScript]
    RbxSignal [ModuleScript]
```

`Cache/init.luau` is the source of the parent `Cache` ModuleScript.

## Install

Use the included `default.project.json` with Rojo:

```bash
rojo serve default.project.json
```

Then require the package:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cache = require(ReplicatedStorage.Cache)
```

## Modules

| Module | Purpose |
| --- | --- |
| `CacheService` | Generic acquire/release cache for any non-nil object |
| `ObjectPool` | Lease-based wrapper that rejects stale releases |
| `InstanceCache` | Template-based Roblox Instance reuse |
| `ExpiringCache` | Temporary key-value cache with lifetime expiration |
| `PoolRegistry` | Register pools and collect global metrics |
| `CacheMaintenance` | Trim registered pools and inspect pool health |
| `CachePolicy` | Pressure, health, and trim target calculations |
| `RbxSignal` | Small signal implementation used by the package |

## Quick Start

### InstanceCache

Use this when you already have a template Instance.

```luau
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cache = require(ReplicatedStorage.Cache)

local coinCache = Cache.CreateInstanceCache(ServerStorage.CoinTemplate, 25, 150)

local coin = coinCache:Get(workspace)
coin:PivotTo(CFrame.new(0, 5, 0))

task.delay(10, function()
	coinCache:Release(coin)
end)
```

Good for pickups, hitboxes, VFX parts, dropped items, projectile visuals, and sound emitters.

### ObjectPool

Use this when a delayed task might try to release an old object after it has already been reused.

```luau
local projectilePool = Cache.CreatePool(function()
	return Instance.new("Part")
end, function(part)
	part.Parent = nil
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
end, function(part)
	part:Destroy()
end, {
	name = "Projectiles",
	initialSize = 50,
	maxRetained = 250,
})

local projectile, leaseId = projectilePool:Acquire()
projectile.Parent = workspace

task.delay(3, function()
	projectilePool:Release(projectile, leaseId)
end)
```

### ExpiringCache

Use this for temporary runtime records.

```luau
local recentHits = Cache.CreateExpiring(0.75)

local function canDamage(player: Player): boolean
	if recentHits:Get(player.UserId) then
		return false
	end

	recentHits:Set(player.UserId, true)
	return true
end
```

Good for duplicate suppression, short cooldown windows, recently processed ids, and temporary lookup data.

## Metrics

Register important pools when you want a global view.

```luau
Cache.Registry.Register("Projectiles", projectilePool)

local metrics = Cache.Registry.GetMetricsSnapshot()
print(metrics.totals.created, metrics.totals.inUse, metrics.totals.available)

local health = Cache.Maintenance.GetHealthSnapshot()
print(health.Projectiles.status, health.Projectiles.pressure)

Cache.Maintenance.TrimRegistry()
```

Health states:

| State | Meaning |
| --- | --- |
| `Healthy` | Comfortable retained capacity |
| `Warm` | Active but not pressured |
| `Pressure` | Most retained objects are in use |
| `Critical` | Near peak pressure |

## Root API

```luau
Cache.Version
Cache.PackageTag

Cache.CreateCache(factory, reset, destroyItem, options)
Cache.CreatePool(factory, reset, destroyItem, options)
Cache.CreateExpiring(defaultLifetime)
Cache.CreateInstanceCache(template, initialSize, maxRetained)

Cache.Registry
Cache.Maintenance
Cache.Policy
Cache.RbxSignal
```

## Options

```luau
type CacheOptions = {
	name: string?,
	initialSize: number?,
	maxRetained: number?,
	autoTrim: boolean?,
	trimThreshold: number?,
}
```

## Stats

```luau
type CacheStats = {
	name: string,
	available: number,
	inUse: number,
	created: number,
	returned: number,
	discarded: number,
	peakInUse: number,
	maxRetained: number,
	pressure: number,
	lastAcquireAt: number?,
	lastReleaseAt: number?,
}
```

## Notes

Cache Module is safe to place in `ReplicatedStorage`. It does not contain remotes, saved data schemas, admin logic, economy rules, or private validation.

Server and client code can both require it. Each side gets its own runtime cache state.

## License

MIT
