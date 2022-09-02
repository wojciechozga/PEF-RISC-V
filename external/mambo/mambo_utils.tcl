# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later
#
# behave like gdb
#
proc p { reg { t 0 } { c 0 } } {
    switch -regexp $reg {
	^r$ {
            set val [mysim cpu $c thread $t display gprs]
	}
        ^r[0-9]+$ {
            regexp "r(\[0-9\]*)" $reg dummy num
            set val [mysim cpu $c thread $t display gpr $num]
        }
        ^f[0-9]+$ {
            regexp "f(\[0-9\]*)" $reg dummy num
            set val [mysim cpu $c thread $t display fpr $num]
        }
        ^v[0-9]+$ {
            regexp "v(\[0-9\]*)" $reg dummy num
            set val [mysim cpu $c thread $t display vmxr $num]
        }
        default {
            set val [mysim cpu $c thread $t display spr $reg]
        }
    }

    return "$val"
}

#
# behave like gdb
#
proc sr { reg val {t 0} { c 0 } } {
    switch -regexp $reg {
        ^r[0-9]+$ {
            regexp "r(\[0-9\]*)" $reg dummy num
            mysim cpu $c:$t set gpr $num $val
        }
        ^f[0-9]+$ {
            regexp "f(\[0-9\]*)" $reg dummy num
            mysim cpu $c:$t set fpr $num $val
        }
        ^v[0-9]+$ {
            regexp "v(\[0-9\]*)" $reg dummy num
            mysim cpu $c:$t set vmxr $num $val
        }
        default {
            mysim cpu $c:$t set spr $reg $val
        }
    }
    p $reg $t $c
}

proc b { addr } {
    mysim trigger set pc $addr "just_stop"
    set at [i $addr]
    puts "breakpoint set at $at"
}

proc w { addr size } {
    set endaddr [expr $addr + $size ]
    mysim trigger set memory w $addr $endaddr 1 tr "just_stop"
    mysim trigger set memory w $addr $endaddr 0 tr "just_stop"
    set at [i $addr to $endaddr]
    puts "watchpoint set at $at"
}

proc wcls { addr size } {
    set endaddr [expr $addr + $size ]
    mysim trigger clear memory w $addr $endaddr
    set at [i $addr to $endaddr]
    puts "watchpoint clear at $at"
}

proc bcls { addr } {
    mysim trigger clear pc $addr
    set at [i $addr]
    puts "breakpoint clear at $at"
}

# Run until $console_string appears on the Linux console
#
# eg.
# break_on_console "Freeing unused kernel memory:"
# break_on_console "buildroot login:"

proc break_on_console { console_string } {
    mysim trigger set console "$console_string" "just_stop"
}

proc clear_console_break { console_string } {
    mysim trigger clear console "$console_string"
}

proc wr { start stop } {
    mysim trigger set memory system w $start $stop 0 "just_stop"
}

proc c { } {
    mysim go
}

proc i { pc { t 0 } { c 0 } } {
    set pc_laddr [mysim cpu $c util itranslate $pc]
    set inst [mysim cpu $c memory display $pc_laddr 4]
    set disasm [mysim cpu $c util ppc_disasm $inst $pc]
    return "\[$c:$t\]: $pc ($pc_laddr) Enc:$inst : $disasm"
}

proc ipc { {t 0} {c 0}} {
    set pc [mysim cpu $c thread $t display spr pc]
    i $pc $t $c
}

proc ipca { } {
    set cpus [myconf query cpus]
    set threads [myconf query processor/number_of_threads]

    for { set i 0 } { $i < $cpus } { incr i 1 } {
        for { set j 0 } { $j < $threads } { incr j 1 } {
            puts [ipc $j $i]
        }
    }
}

proc pa { spr } {
    set cpus [myconf query cpus]
    set threads [myconf query processor/number_of_threads]

    for { set i 0 } { $i < $cpus } { incr i 1 } {
        for { set j 0 } { $j < $threads } { incr j 1 } {
            set val [mysim cpu $i thread $j display spr $spr]
            puts "CPU: $i THREAD: $j SPR $spr = $val" 
        }
    }
}

proc s { {nr 1} } {
    for { set i 0 } { $i < $nr } { incr i 1 } {
        mysim step 1
        ipca
    }
}

proc z { count } {
    while { $count > 0 } {
        s
        incr count -1
    }
}

proc sample_pc { sample count } {
    while { $count > 0 } {
        mysim cycle $sample
        ipc
        incr count -1
    }
}

proc e2p { ea } {
    set pa [ mysim util dtranslate $ea ]
    puts "$pa"
}

proc x {  pa { size 8 } } {
    set val [ mysim memory display $pa $size ]
    puts "$pa : $val"
}

proc it { ea } {
    mysim util itranslate $ea
}
proc dt { ea } {
    mysim util dtranslate $ea
}

proc ex {  ea { size 8 } } {
    set pa [ mysim util dtranslate $ea ]
    set val [ mysim memory display $pa $size ]
    puts "$pa : $val"
}

proc di { location { count 16 } } {
    set addr [expr $location & 0xfffffffffffffff0]
    disasm_mem mysim $addr $count
}

proc hexdump { location count }    {
    set addr  [expr $location & 0xfffffffffffffff0]
    set top [expr $addr + ($count * 15)]
    for { set i $addr } { $i < $top } { incr i 16 } {
        set val [expr $i + (4 * 0)]
        set val0 [format "%08x" [mysim memory display $val 4]]
        set val [expr $i + (4 * 1)]
        set val1 [format "%08x" [mysim memory display $val 4]]
        set val [expr $i + (4 * 2)]
        set val2 [format "%08x" [mysim memory display $val 4]]
        set val [expr $i + (4 * 3)]
        set val3 [format "%08x" [mysim memory display $val 4]]

        set ascii ""
        set loc [format "0x%016x" $i]
        puts "$loc: $val0 $val1 $val2 $val3 $ascii"
    }
}

proc get_char { addr } {
    return [expr [mysim memory display "$addr" 1]]
}

proc p_str { addr { limit 0 } } {
    set addr_limit 0xfffffffffffffffff
    if { $limit > 0 } { set addr_limit [expr $limit + $addr] }
    set s ""

    for {} { [get_char "$addr"] != 0} { incr addr 1 } {
        # memory display returns hex values with a leading 0x
        set c [format %c [get_char "$addr"]]
        set s [string cat "$s" "$c"]
        if { $addr == $addr_limit } { break }
    }

    puts "$s"
}

proc slbv {} {
    puts [mysim cpu 0 display slb valid]
}

proc regs { { t 0 } { c 0 } } {
    puts "GPRS:"
    puts [mysim cpu $c thread $t display gprs]
}

proc tlbv { { c 0 } } {
    puts "$c:TLB: ----------------------"
    puts [mysim cpu $c display tlb valid]
}

proc exc { { i SystemReset } { c 0 } } {
    puts "$c:EXCEPTION:$i"
    puts [mysim cpu $c interrupt $i]
}

proc just_stop { args } {
    simstop
    ipca
}

proc st { count } {
    set sp [mysim cpu 0 display gpr 1]
    puts "SP: $sp"
    ipc
    set lr [mysim cpu 0 display spr lr]
    i $lr
    while { $count > 0 } {
        set sp [mysim util itranslate $sp]
        set lr [mysim memory display [expr $sp++16] 8]
        i $lr
        set sp [mysim memory display $sp 8]

        incr count -1
    }
}

proc mywatch { } {
    while { [mysim memory display 0x700 8] != 0 } {
        mysim cycle 1
    }
    puts "condition occurred "
    ipc
}

#
# force gdb to attach
#
proc gdb { {t 0} } {
    mysim set fast off
    mysim debugger wait $t
}

proc egdb { {t 0} } {
    set srr0 [mysim cpu 0 display spr srr0]
    set srr1 [mysim cpu 0 display spr srr1]
    mysim cpu 0 set spr pc $srr0
    mysim cpu 0 set spr msr $srr1
    gdb $t
}

proc mem_display_64_le { addr } {
    set data 0
    for {set i 0} {$i < 8} {incr i} {
	set data [ expr $data << 8 ]
	set l [ mysim memory display [ expr $addr+7-$i ] 1 ]
	set data [ expr $data | $l ]
    }
    return [format 0x%X $data]
}

proc mem_display_64 { addr le } {
    if { $le } {
	return [ mem_display_64_le $addr ]
    }
    # mysim memory display is big endian
    return [ mysim memory display $addr 8 ]
}

proc bt { {sp 0} { t 0 } { c 0 } } {
    set lr [mysim cpu $c:$t display spr pc]
    puts "pc:\t\t\t\t$lr"
    if { $sp == 0 } {
        set sp [mysim cpu $c:$t display gpr 1]
    }
    set lr [mysim cpu $c:$t display spr lr]
    puts "lr:\t\t\t\t$lr"

    set msr [mysim cpu $c:$t display spr msr]
    set le [ expr $msr & 1 ]

    # Limit to 200 in case of an infinite loop
    for {set i 0} {$i < 200} {incr i} {
        set pa [ mysim util dtranslate $sp ]
        set bc [ mem_display_64 $pa $le ]
        set lr [ mem_display_64 [ expr $pa + 16 ] $le ]
        puts "stack:$pa \t$lr"
        if { $bc == 0 } { break }
        set sp $bc
    }
    puts ""
}

proc ton { } {mysim mode turbo }
proc toff { } {mysim mode simple }

proc don { opt } {
    simdebug set $opt 1
}

proc doff { opt } {
    simdebug set $opt 0
}

# skisym and linsym return the address of a symbol, looked up from
# the relevant System.map or skiboot.map file.
proc linsym { name } {
    global linux_symbol_map

    # create a regexp that matches the symbol name
    set base {([[:xdigit:]]*) (.)}
    set exp [concat $base " $name\$"]
    set ret ""

    foreach {line addr type} [regexp -line -inline $exp $linux_symbol_map] {
        set ret "0x$addr"
    }

    return $ret
}

# skisym factors in skiboot's load address
proc skisym { name } {
    global skiboot_symbol_map
    global mconf

    set base {([[:xdigit:]]*) (.)}
    set exp [concat $base " $name\$"]
    set ret ""

    foreach {line addr type} [regexp -line -inline $exp $skiboot_symbol_map] {
        set actual_addr [expr "0x$addr" + $mconf(boot_load)]
	set ret [format "0x%.16x" $actual_addr]
    }

    return $ret
}

proc current_insn { { t 0 } { c 0 } } {
    set pc [mysim cpu $c thread $t display spr pc]
    set pc_laddr [mysim cpu $c util itranslate $pc]
    set inst [mysim cpu $c memory display $pc_laddr 4]
    set disasm [mysim cpu $c util ppc_disasm $inst $pc]
    return $disasm
}

global SRR1
global DSISR
global DAR

proc sreset_trigger { args } {
    variable SRR1

    mysim trigger clear pc 0x100
    mysim trigger clear pc 0x104
    set s [expr [mysim cpu 0 display spr srr1] & ~0x00000000003c0002]
    set SRR1 [expr $SRR1 | $s]
    mysim cpu 0 set spr srr1 $SRR1
}

proc exc_sreset { } {
    variable SRR1
    variable DSISR
    variable DAR

    # In case of recoverable MCE, idle wakeup always sets RI, others get
    # RI from current environment. For unrecoverable, RI would always be
    # clear by hardware.
    if { [current_insn] in { "stop" "nap" "sleep" "winkle" } } {
        set msr_ri 0x2
        set SRR1_powersave [expr (0x2 << (63-47))]
    } else {
        set msr_ri [expr [mysim cpu 0 display spr msr] & 0x2]
        set SRR1_powersave 0
    }

    # reason system reset
    set SRR1_reason 0x4

    set SRR1 [expr 0x0 | $msr_ri | $SRR1_powersave]
    set SRR1 [expr $SRR1 | ((($SRR1_reason >> 3) & 0x1) << (63-42))]
    set SRR1 [expr $SRR1 | ((($SRR1_reason >> 2) & 0x1) << (63-43))]
    set SRR1 [expr $SRR1 | ((($SRR1_reason >> 1) & 0x1) << (63-44))]
    set SRR1 [expr $SRR1 | ((($SRR1_reason >> 0) & 0x1) << (63-45))]

    if { [current_insn] in { "stop" "nap" "sleep" "winkle" } } {
        # mambo has a quirk that interrupts from idle wake immediately
        # and go over current instruction.
        mysim trigger set pc 0x100 "sreset_trigger"
        mysim trigger set pc 0x104 "sreset_trigger"
        mysim cpu 0 interrupt SystemReset
    } else {
        mysim trigger set pc 0x100 "sreset_trigger"
        mysim trigger set pc 0x104 "sreset_trigger"
        mysim cpu 0 interrupt SystemReset
    }

    # sleep and sometimes other types of interrupts do not trigger 0x100
    if { [expr [mysim cpu 0 display spr pc] == 0x100 ] } {
	sreset_trigger
    }
    if { [expr [mysim cpu 0 display spr pc] == 0x104 ] } {
	sreset_trigger
    }
}

proc mce_trigger { args } {
    variable SRR1
    variable DSISR
    variable DAR

    mysim trigger clear pc 0x200
    mysim trigger clear pc 0x204

    set s [expr [mysim cpu 0 display spr srr1] & ~0x00000000801f0002]
    set SRR1 [expr $SRR1 | $s]
    mysim cpu 0 set spr srr1 $SRR1
    mysim cpu 0 set spr dsisr $DSISR
    mysim cpu 0 set spr dar $DAR ; list
}

#
# Inject a machine check. Recoverable MCE types can be forced to unrecoverable
# by clearing MSR_RI bit from SRR1 (which hardware may do).
# If d_side is 0, then cause goes into SRR1. Otherwise it gets put into DSISR.
# DAR is hardcoded to always 0xdeadbeefdeadbeef
#
# Default with no arguments is a recoverable i-side TLB multi-hit
# Other options:
# d_side=1 dsisr=0x80 - recoverable d-side SLB multi-hit
# d_side=1 dsisr=0x8000 - ue error on instruction fetch
# d_side=0 cause=0xd  - unrecoverable i-side async store timeout (POWER9 only)
# d_side=0 cause=0x1  - unrecoverable i-side ifetch
#
proc exc_mce { { d_side 0 } { cause 0x5 } { recoverable 1 } } {
    variable SRR1
    variable DSISR
    variable DAR

#    puts "INJECTING MCE"

    # In case of recoverable MCE, idle wakeup always sets RI, others get
    # RI from current environment. For unrecoverable, RI would always be
    # clear by hardware.
    if { [current_insn] in { "stop" "nap" "sleep" "winkle" } } {
        set msr_ri 0x2
        set SRR1_powersave [expr (0x2 << (63-47))]
    } else {
        set msr_ri [expr [mysim cpu 0 display spr msr] & 0x2]
        set SRR1_powersave 0
    }

    if { !$recoverable } {
        set msr_ri 0x0
    }

    if { $d_side } {
        set is_dside 1
        set SRR1_mc_cause 0x0
        set DSISR $cause
        set DAR 0xdeadbeefdeadbeef
    } else {
        set is_dside 0
        set SRR1_mc_cause $cause
        set DSISR 0x0
        set DAR 0x0
    }

    set SRR1 [expr 0x0 | $msr_ri | $SRR1_powersave]

    set SRR1 [expr $SRR1 | ($is_dside << (63-42))]
    set SRR1 [expr $SRR1 | ((($SRR1_mc_cause >> 3) & 0x1) << (63-36))]
    set SRR1 [expr $SRR1 | ((($SRR1_mc_cause >> 2) & 0x1) << (63-43))]
    set SRR1 [expr $SRR1 | ((($SRR1_mc_cause >> 1) & 0x1) << (63-44))]
    set SRR1 [expr $SRR1 | ((($SRR1_mc_cause >> 0) & 0x1) << (63-45))]

    if { [current_insn] in { "stop" "nap" "sleep" "winkle" } } {
        # mambo has a quirk that interrupts from idle wake immediately
        # and go over current instruction.
        mysim trigger set pc 0x200 "mce_trigger"
        mysim trigger set pc 0x204 "mce_trigger"
        mysim cpu 0 interrupt MachineCheck
    } else {
        mysim trigger set pc 0x200 "mce_trigger"
        mysim trigger set pc 0x204 "mce_trigger"
        mysim cpu 0 interrupt MachineCheck
    }

    # sleep and sometimes other types of interrupts do not trigger 0x200
    if { [expr [mysim cpu 0 display spr pc] == 0x200 ] } {
	mce_trigger
    }
    if { [expr [mysim cpu 0 display spr pc] == 0x204 ] } {
	mce_trigger
    }
}

global R1

# Avoid stopping if we re-enter the same code. Wait until r1 matches.
# This helps stepping over exceptions or function calls etc.
proc stop_stack_match { args } {
    variable R1

    set r1 [mysim cpu 0 display gpr 1]
    if { $R1 == $r1 } {
        simstop
        ipca
    }
}

# inject default recoverable MCE and step over it. Useful for testing whether
# code copes with taking an interleaving MCE.
proc inject_mce { } {
    variable R1

    set R1 [mysim cpu 0 display gpr 1]
    set pc [mysim cpu 0 display spr pc]
    mysim trigger set pc $pc "stop_stack_match"
    exc_mce
    c
    mysim trigger clear pc $pc ; list
}

#
# We've stopped at addr and we need to inject the mce and continue
#
proc trigger_mce_ue_addr {args} {
    set addr [lindex [lindex $args 0] 1]
    mysim trigger clear memory system rw $addr $addr
    exc_mce 0x1 0x8000 0x1
}

proc inject_mce_ue_on_addr {addr} {
    mysim trigger set memory system rw $addr $addr 1 "trigger_mce_ue_addr"
}

# inject and step over one instruction, and repeat.
proc inject_mce_step { {nr 1} } {
    for { set i 0 } { $i < $nr } { incr i 1 } {
        inject_mce
        s
    }
}

# inject if RI is set and step over one instruction, and repeat.
proc inject_mce_step_ri { {nr 1} } {
    set reserve_inject 1
    set reserve_inject_skip 0
    set reserve_counter 0

    for { set i 0 } { $i < $nr } { incr i 1 } {
        if { [expr [mysim cpu 0 display spr msr] & 0x2] } {
            # inject_mce
            if { [mysim cpu 0 display reservation] in { "none" } } {
                inject_mce
                mysim cpu 0 set reservation none
                if { $reserve_inject_skip } {
                    set reserve_inject 1
                    set reserve_inject_skip 0
                }
            } else {
                if { $reserve_inject } {
                    inject_mce
                    mysim cpu 0 set reservation none
                    set reserve_inject 0
                } else {
                    set reserve_inject_skip 1
                    set reserve_counter [ expr $reserve_counter + 1 ]
                    if { $reserve_counter > 30 } {
                        mysim cpu 0 set reservation none
                    }
                }
            }
        }
        s
    }
}

proc uvc {} {
	if {$::tcl_version < 8.6} {
		package require fileutil
		set uv_con_file [::fileutil::tempfile]
	} else {
		file tempfile uv_con_file
	}
	mysim memory fwrite 0x31100000 0x100000 $uv_con_file
	puts [read [open $uv_con_file r]]
	file delete $uv_con_file
}
