--!strict
return {
	format = "coff", packing = nil, mode32 = true, imageBase = 4096,
	image = "\184\255\255\255\127\005\001\000\000\000\187\000\000\002\000\137\003\244",
	entryCS = 0, entryIP = 4096, initialSS = 0, initialSP = 524288,
	minExtraParagraphs = 0, maxExtraParagraphs = 0,
	relocations = {},
	warnings = {},
	directBlocks = {
		[4096] = true,
		[4101] = true,
		[4106] = true,
	},
	blockRanges = {
		[4096] = {cs=0, ip=4096, length=5},
		[4101] = {cs=0, ip=4101, length=5},
		[4106] = {cs=0, ip=4106, length=5},
		[4111] = {cs=0, ip=4111, length=2},
		[4113] = {cs=0, ip=4113, length=1},
	},
}
