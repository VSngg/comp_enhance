package main

import "sim86"
import "core:fmt"
import "core:mem"
import "core:log"

// test_file := #load("part1/listing_0042_completionist_decode")
test_file := #load("part1/listing_0037_single_register_mov")

_main :: proc() {
	log.info("Sim86 Version:", sim86.GetVersion())

	table: sim86.Instruction_Table
	sim86.Get8086InstructionTable(&table)
	log.info("8086 Instruction Encoding Count:", table.encoding_count)

	offset: int = 0
	for offset < len(test_file) {
		decoded: sim86.Instruction
		sim86.Decode8086Instruction(u32(len(test_file) - offset), &test_file[offset], &decoded)
		if decoded.op != .None {
			offset += cast(int)decoded.size
			log.debugf("Size: %v, Op: %v, Flags: 0x%x", decoded.size, sim86.MnemonicFromOperationType(decoded.op), decoded.flags)
			log.debugf("%v", sim86.RegisterNameFromOperand(&decoded.operands[0].register))
			log.debugf("%v", sim86.RegisterNameFromOperand(&decoded.operands[1].register))
		} else {
			log.error("Unrecognized instruction")
			break
		}
	}
}

main :: proc() {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)

    logger := log.create_console_logger(log.Level.Debug, {.Level, .Terminal_Color, .Time})
    context.logger = logger

    _main()

    // destroy after main for tracking allocator not to complain
    log.destroy_console_logger(logger)

    for _, leak in track.allocation_map {
        fmt.printf("[TRACKING ALLOCATOR]: %v leaked %m\n", leak.location, leak.size)
    }
    for bad_free in track.bad_free_array {
        fmt.printf("[TRACKING ALLOCATOR]: %v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
    }
}
