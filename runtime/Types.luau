--!strict
-- Shared contract. Keep the first 16 bytes in the required 8086 register order.
export type CPUState = {
	regs: buffer,
	es: number,
	cs: number,
	ss: number,
	ds: number,
	fs: number,
	gs: number,
	ip: number,
	flags: number,
	loadSegment: number,
	currentBlockKey: number,
	halted: boolean,
	waitingForKey: boolean,
	yieldRequested: boolean,
	fpu: { number },
	fpuTop: number,
	discoveredBlocks: { [number]: boolean },
	[string]: any,
}
export type Bus = {
	ram: buffer,
	read8: (self: Bus, addr: number) -> number,
	read16: (self: Bus, addr: number) -> number,
	write8: (self: Bus, addr: number, val: number) -> (),
	write16: (self: Bus, addr: number, val: number) -> (),
	segOffToPhys: (seg: number, off: number) -> number,
	in8: (self: Bus, port: number) -> number,
	out8: (self: Bus, port: number, val: number) -> (),
	registerPortHandler: (self: Bus, port: number, readFn: (() -> number)?, writeFn: ((number) -> ())?) -> (),
	[string]: any,
}
export type CompiledBlockFn = (cpu: CPUState, bus: Bus, budget: number) -> (number, number)
export type ProgramMeta = {
	format: string,
	image: string,
	entryCS: number,
	entryIP: number,
	initialSS: number,
	initialSP: number,
	relocations: { { offset: number, segment: number } },
	[string]: any,
}
return {}
