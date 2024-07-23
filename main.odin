package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

// TODO: memory to accumulator, accumulator-to-memory, signed displacements

// MOV
RM_TO_REG      :: 0b100010  // Register/memory to/from register
IMM_TO_REG_MEM :: 0b1100011 // Immediate to register/memory
IMM_TO_REG     :: 0b1011    // Immediate to register
MEM_TO_ACCUM   :: 0b1010000 // Memory to accumulator
ACCUM_TO_MEM   :: 0b1010001 // Accumulator to memory

// ADD
ADD_RM_TO_REG      :: 0b000000
// ADD_IMM_TO_REG_MEM :: 0b100000
ADD_IMM_TO_ACCUM   :: 0b0000010

// SUB
SUB_RM_TO_REG      :: 0b001010
// SUB_IMM_TO_REG_MEM :: 0b100000
SUB_IMM_TO_ACCUM   :: 0b0010110

// CMP
CMP_RM_TO_REG      :: 0b001110
// CMP_IMM_TO_REG_MEM :: 0b100000
CMP_IMM_TO_ACCUM   :: 0b0011110

ASC_IMM_TO_REG_MEM :: 0b100000


register_word := [8]string{"ax", "cx", "dx", "bx", "sp", "bp", "si", "di"}
register_byte := [8]string{"al", "cl", "dl", "bl", "ah", "ch", "dh", "bh"}

effective_address := [8]string{"bx + si", "bx + di", "bp + si", "bp + di", "si", "di", "bp", "bx"}

get_displacement :: proc(data: []byte, wide: bool) -> string {
    displacement, sign : string
    if !wide {
        displacement_value := i8(data[0])
        sign = "+" if displacement_value >= 0 else "-" 
        displacement = fmt.tprintf("%v %d", sign, abs(displacement_value))
    } else {
        displacement_value := i16(data[1])<< 8 | i16(data[0])
        sign = "+" if displacement_value >= 0 else "-" 
        displacement = fmt.tprintf("%v %d", sign, abs(displacement_value))
}
    return displacement

}

_main :: proc() {
    data, ok := os.read_entire_file(os.args[1])
    if !ok {
        log.error("Could not read file")
        return
    }
    defer delete(data)
    log.debugf("    DATA: %b", data)
    for i := 0; i < len(data); i += 1 {
        b := data[i]
        switch opcode := b >> 2; opcode {
        case RM_TO_REG, ADD_RM_TO_REG, SUB_RM_TO_REG, CMP_RM_TO_REG:
            opcode_name : string
            switch opcode {
            case RM_TO_REG:     opcode_name = "mov"
            case ADD_RM_TO_REG: opcode_name = "add"
            case SUB_RM_TO_REG: opcode_name = "sub"
            case CMP_RM_TO_REG: opcode_name = "cmp"
            }
            d := b >> 1 & 0b1
            w := b >> 0 & 0b1

            register_table := register_word if w == 1 else register_byte

            src, dst : string

            i += 1
            next_bytes := data[i:]
            mod := next_bytes[0] >> 6 & 0b11
            reg := next_bytes[0] >> 3 & 0b111
            rm  := next_bytes[0]      & 0b111

            address := effective_address[rm]

            switch mod {
            // Memory mode
            case 0b00: 
                src = register_table[reg] 
                if rm == 0b110 {
                    i += 1
                    next_bytes := data[i:]
                    displacement := i16(next_bytes[1]) << 8 | i16(next_bytes[0])
                    dst = fmt.tprintf("[%v]", displacement)
                    i += 1
                    break
                }
                dst = fmt.tprintf("[%v]", address)
            // Memory mode, 8-bit displacement follows
            case 0b01: 
                src = register_table[reg]
                i += 1
                displacement := get_displacement(data[i:], false)
                dst = fmt.tprintf("[%v %v]", address, displacement)
            // Memory mode, 16-bit displacement follows
            case 0b10:
                src = register_table[reg]
                i += 1
                displacement := get_displacement(data[i:], true)
                dst = fmt.tprintf("[%v %v]", address, displacement)
                i += 1
            // register-mode (no displacement)
            case 0b11: 
                dst = register_table[rm]
                src = register_table[reg]
            }

            if d == 0b1 {
                src, dst = dst, src
            }

            log.infof("RESULT: %v %v, %v", opcode_name, dst, src)
            continue
        
        }

        if b >> 1 == IMM_TO_REG_MEM {
            opcode_name := "mov"
            w := b & 0b1 
            register_table := register_word if w == 1 else register_byte

            i += 1
            next_bytes := data[i:]
            mod := next_bytes[0] >> 6 & 0b11
            rm  := next_bytes[0]      & 0b111

            address := effective_address[rm]

            dst, src : string

            switch mod {
            // Memory mode
            case 0b00: 
                dst = fmt.tprintf("[%v]", address)
            // Memory mode, 8-bit displacement follows
            case 0b01: 
                i += 1
                displacement := get_displacement(data[i:], false)
                dst = fmt.tprintf("[%v %v]", address, displacement)
            // Memory mode, 16-bit displacement follows
            case 0b10:
                i += 1
                displacement := get_displacement(data[i:], true)
                dst = fmt.tprintf("[%v %v]", address, displacement)
                i += 1
            // register-mode (no displacement)
            case 0b11: 
                dst = register_table[rm]
            }

            i += 1

            explicit_size_data := data[i:]
            if w == 0 {
                explicit_size := i8(explicit_size_data[0])
                src = fmt.tprintf("byte %v", explicit_size)
            } else {
                explicit_size := i16(explicit_size_data[1])<< 8 | i16(explicit_size_data[0])
                src = fmt.tprintf("word %v", explicit_size)
                i += 1
            }

            log.infof("RESULT: %v %v, %v", opcode_name, dst, src)
            continue

        }

        if b >> 1 == MEM_TO_ACCUM {
            w := b & 0b1

            i += 1
            next_bytes := data[i:]
            direct_address : string

            if w == 0 {
                val := i8(next_bytes[0])
                direct_address = fmt.tprintf("%d", val)
            } else {
                val := i16(next_bytes[1]) << 8 | i16(next_bytes[0])
                direct_address = fmt.tprintf("%d", val)
                i += 1
            }
            log.infof("RESULT: mov ax, [%v]", direct_address)

        }

        if b >> 1 == ACCUM_TO_MEM {
            w := b & 0b1

            i += 1
            next_bytes := data[i:]
            direct_address : string

            if w == 0 {
                val := i8(next_bytes[0])
                direct_address = fmt.tprintf("%d", val)
            } else {
                val := i16(next_bytes[1]) << 8 | i16(next_bytes[0])
                direct_address = fmt.tprintf("%d", val)
                i += 1
            }
            log.infof("RESULT: mov [%v], ax", direct_address)

        }

        if b >> 4 == IMM_TO_REG {
            opcode_name := "mov"
            w := b >> 3 & 0b1
            reg := b & 0b111

            register_table := register_word if w == 1 else register_byte

            dst := register_table[reg]
            src : string

            if w == 0 {
                i += 1
                next_bytes := data[i:]
                val := i8(next_bytes[0])
                src = fmt.tprintf("%v", val)
            } else {
                i += 1
                next_bytes := data[i:]
                // Little-endian, cast two u8 to i16
                val := i16(next_bytes[1])<< 8 | i16(next_bytes[0])
                src = fmt.tprintf("%v", val)
                i += 1
            } 
            log.infof("RESULT: %v %v, %v", opcode_name, dst, src)
            continue

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
