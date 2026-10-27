--!strict
return {
	format = "mz", packing = nil, mode32 = false, imageBase = 0,
	entryCS = 0, entryIP = 0, initialSS = 0, initialSP = 1024,
	minExtraParagraphs = 0, maxExtraParagraphs = 0,
	image = "\184\000\000\142\216\184\007\000\005\008\000\163\000\003\244",
	relocations = {{offset=1,segment=0},},
	warnings = {},
	directBlocks = {
		[5] = true,
		[8] = true,
		[11] = true,
	},
	blockRanges = {
		[0] = {cs=0, ip=0, length=3},
		[3] = {cs=0, ip=3, length=2},
		[5] = {cs=0, ip=5, length=6},
		[8] = {cs=0, ip=8, length=3},
		[11] = {cs=0, ip=11, length=3},
		[14] = {cs=0, ip=14, length=1},
	},
}
