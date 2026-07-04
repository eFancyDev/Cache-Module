--!strict

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	Once: (self: Signal, callback: (...any) -> ()) -> Connection,
	Wait: (self: Signal) -> ...any,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
}

type InternalConnection = {
	Connected: boolean,
	_signal: any?,
	_callback: (...any) -> (),
	Disconnect: (self: InternalConnection) -> (),
}

type InternalSignal = {
	_connections: {InternalConnection},
	_waitingThreads: {thread},
	_isDestroyed: boolean,
}

local Connection = {}
Connection.__index = Connection

local RbxSignal = {}
RbxSignal.__index = RbxSignal

local function removeConnection(connections: {InternalConnection}, target: InternalConnection)
	local index = table.find(connections, target)
	if index ~= nil then
		table.remove(connections, index)
	end
end

function Connection.new(signal: InternalSignal, callback: (...any) -> ()): InternalConnection
	local connection = {
		Connected = true,
		_signal = signal,
		_callback = callback,
	}

	return setmetatable(connection, Connection) :: any
end

function Connection.Disconnect(self: InternalConnection)
	if not self.Connected then
		return
	end

	self.Connected = false

	local signal = self._signal
	self._signal = nil

	if signal ~= nil then
		removeConnection(signal._connections, self)
	end
end

function RbxSignal.new(): Signal
	local signal = {
		_connections = {},
		_waitingThreads = {},
		_isDestroyed = false,
	}

	return setmetatable(signal, RbxSignal) :: any
end

function RbxSignal.Connect(self: any, callback: (...any) -> ()): Connection
	assert(type(callback) == "function", "Cache@RbxSignal: callback must be a function")
	assert(not self._isDestroyed, "Cache@RbxSignal: cannot connect to a destroyed signal")

	local connection = Connection.new(self, callback)
	table.insert(self._connections, connection)

	return connection :: any
end

function RbxSignal.Once(self: any, callback: (...any) -> ()): Connection
	local connection: Connection? = nil

	connection = self:Connect(function(...)
		local activeConnection = connection
		if activeConnection ~= nil then
			activeConnection:Disconnect()
			connection = nil
		end

		callback(...)
	end)

	return connection :: Connection
end

function RbxSignal.Wait(self: any): ...any
	assert(not self._isDestroyed, "Cache@RbxSignal: cannot wait on a destroyed signal")

	local currentThread = coroutine.running()
	table.insert(self._waitingThreads, currentThread)

	return coroutine.yield()
end

function RbxSignal.Fire(self: any, ...: any)
	if self._isDestroyed then
		return
	end

	local connections = table.clone(self._connections)
	for _, connection in ipairs(connections) do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end

	local waitingThreads = self._waitingThreads
	self._waitingThreads = {}

	for _, waitingThread in ipairs(waitingThreads) do
		task.spawn(waitingThread, ...)
	end
end

function RbxSignal.DisconnectAll(self: any)
	local connections = table.clone(self._connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(self._connections)
end

function RbxSignal.Destroy(self: any)
	if self._isDestroyed then
		return
	end

	self._isDestroyed = true
	self:DisconnectAll()

	for _, waitingThread in ipairs(self._waitingThreads) do
		task.spawn(waitingThread)
	end

	table.clear(self._waitingThreads)
end

return RbxSignal

