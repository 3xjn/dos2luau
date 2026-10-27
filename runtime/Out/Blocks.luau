--!strict
local blocks: {[number]: any} = {}
for k, v in require(script.Parent.Blocks_001) do blocks[k] = v end
return blocks
