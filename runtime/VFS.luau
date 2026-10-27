--!strict
local VFS = {}
VFS.__index = VFS
local function normalize(path: string): string
	path = string.upper((string.gsub(path, "/", "\\")))
	path = string.gsub(path, "^[A-Z]:", "")
	local parts = {}
	for p in string.gmatch(path, "[^\\]+") do
		if p == ".." then
			table.remove(parts)
		elseif p ~= "." and p ~= "" then
			table.insert(parts, p)
		end
	end
	return "\\" .. table.concat(parts, "\\")
end
function VFS.new(assets: { [string]: string }?)
	local self: any = setmetatable(
		{ files = {}, handles = {}, nextHandle = 5, searches = {}, nextSearch = 1, cwd = "\\", attributes = {} },
		VFS
	)
	for path, data in pairs(assets or {}) do
		self.files[normalize(path)] = data
	end
	return self
end
function VFS.resolve(self: any, path: string): string
	local p = string.gsub(path, "/", "\\")
	p = string.gsub(p, "^[A-Za-z]:", "")
	if string.sub(p, 1, 1) ~= "\\" then
		p = self.cwd .. "\\" .. p
	end
	return normalize(p)
end
function VFS.chdir(self: any, path: string): boolean
	local target = self:resolve(path)
	if target == "\\" then
		self.cwd = target
		return true
	end
	for name: any in pairs(self.files) do
		if string.sub(name, 1, #target + 1) == target .. "\\" then
			self.cwd = target
			return true
		end
	end
	return false
end
function VFS.open(self: any, path: string, mode: number, create: boolean?): (number?, number?)
	local name = self:resolve(path)
	if mode < 0 or mode > 2 then
		return nil, 12
	end
	if create then
		self.files[name] = ""
	elseif self.files[name] == nil then
		return nil, 2
	end
	local h = self.nextHandle
	while self.handles[h] do
		h += 1
	end
	self.nextHandle = h + 1
	self.handles[h] = { path = name, pos = 0, mode = mode }
	return h, nil
end
function VFS.close(self: any, h: number): boolean
	if not self.handles[h] then
		return false
	end
	self.handles[h] = nil
	return true
end
function VFS.read(self: any, h: number, count: number): (string?, number?)
	local f: any = self.handles[h]
	if not f then
		return nil, 6
	end
	if f.mode == 1 then
		return nil, 5
	end
	local s = self.files[f.path]
	local data = string.sub(s, f.pos + 1, f.pos + count)
	f.pos += #data
	return data, nil
end
function VFS.write(self: any, h: number, data: string): (number?, number?)
	local f: any = self.handles[h]
	if not f then
		return nil, 6
	end
	if f.mode == 0 then
		return nil, 5
	end
	local s = self.files[f.path]
	if f.pos > #s then
		s ..= string.rep("\0", f.pos - #s)
	end
	self.files[f.path] = string.sub(s, 1, f.pos) .. data .. string.sub(s, f.pos + #data + 1)
	f.pos += #data
	if #data == 0 then
		self.files[f.path] = string.sub(s, 1, f.pos)
	end
	return #data, nil
end
function VFS.seek(self: any, h: number, offset: number, origin: number): (number?, number?)
	local f: any = self.handles[h]
	if not f then
		return nil, 6
	end
	local base = if origin == 0 then 0 elseif origin == 1 then f.pos elseif origin == 2 then #self.files[f.path] else nil
	if base == nil or base + offset < 0 then
		return nil, 1
	end
	f.pos = base + offset
	return f.pos, nil
end
function VFS.remove(self: any, path: string): boolean
	local n = self:resolve(path)
	if self.files[n] == nil then
		return false
	end
	for _, handle: any in pairs(self.handles) do
		if handle.path == n then
			return false
		end
	end
	self.files[n] = nil
	return true
end
function VFS.rename(self: any, old: string, new: string): boolean
	local a, b = self:resolve(old), self:resolve(new)
	if self.files[a] == nil or self.files[b] ~= nil then
		return false
	end
	for _, handle: any in pairs(self.handles) do
		if handle.path == a then
			return false
		end
	end
	self.files[b], self.files[a] = self.files[a], nil
	return true
end
function VFS.find(self: any, pattern: string): { any }
	local p = self:resolve(pattern)
	local dir, glob = string.match(p, "^(.*\\)([^\\]*)$")
	if not dir or not glob then
		return {}
	end
	local escaped = string.gsub(glob, "([%(%)%.%%%+%-%[%]%^%$])", "%%%1")
	escaped = string.gsub(string.gsub(escaped, "%*", ".*"), "%?", ".")
	if glob == "*.*" then
		escaped = ".*"
	end
	local result: { any } = {}
	for name: any, data: any in pairs(self.files) do
		local d, file = string.match(name, "^(.*\\)([^\\]+)$")
		if d == dir and file and string.match(file, "^" .. escaped .. "$") then
			table.insert(result, { name = file, size = #data })
		end
	end
	table.sort(result, function(a: any, b: any)
		return a.name < b.name
	end)
	return result
end
VFS.normalize = normalize
return VFS
