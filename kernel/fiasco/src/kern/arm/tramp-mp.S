#include "globalconfig.h"
#include "tcboffset.h"

	.section .mp_tramp, "awx"
	.p2align 12

#ifdef CONFIG_ARM_V7
invalidate_l1_v7:
	// B2.2.7
	mrc     p15, 1, r0, c0, c0, 1
	ands    r3, r0, #0x07000000
	mov     r3, r3, lsr #23
	beq     finished
	mov     r10, #0
loop1:
	add     r2, r10, r10, lsr #1
	mov     r1, r0, lsr r2
	and     r1, r1, #7
	cmp     r1, #2
	blt     skip
	mcr     p15, 2, r10, c0, c0, 0
	isb
	mrc     p15, 1, r1, c0, c0, 0
	and     r2, r1, #7
	add     r2, r2, #4
	movw    r4, #0x3ff
	ands    r4, r4, r1, lsr #3
	clz     r5, r4
	mov     r9, r4
loop2:
	movw    r7, #0x7fff
	ands    r7, r7, r1, lsr #13
loop3:
	orr     r11, r10, r9, lsl r5
	orr     r11, r11, r7, lsl r2
	mcr     p15, 0, r11, c7, c6, 2
	subs    r7, r7, #1
	bge     loop3
	subs    r9, r9, #1
	bge     loop2
skip:
	add     r10, r10, #2
	cmp     r3, r10
	bgt     loop1
	dsb
finished:
	mov     r0, #0
	mcr     p15, 2, r0, c0, c0, 0
	dsb
	isb
	mov     pc, lr
#endif

	.global _tramp_mp_entry
_tramp_mp_entry:
	// IRQs off, SVC
	mrs   r0, cpsr
	orr   r0, #0xd3
	msr   cpsr_c, r0

	// enable SMP
#ifndef CONFIG_ARM_EM_NS
	adr   r0, .Lmpcore_phys_base
	ldr   r0, [r0]
	ldr   r1, [r0]
	orr   r1, #1
	str   r1, [r0]
#endif

#ifdef CONFIG_ARM_V7
	bl    invalidate_l1_v7
#endif

	mcr   p15, 0, r0, c7, c5, 0 // ICIALLU
	mcr   p15, 0, r0, c7, c5, 6 // BPIALL

	mcr   p15, 0, r0, c7, c10, 4 // dsb
#ifdef CONFIG_ARM_V6
	mcr   p15, 0, r0, c7, c7, 0  // inv both
#endif

#ifdef CONFIG_ARM_V7
	// ACTRL is implementation defined
	mrc   p15, 0, r0, c0, c0, 0  // read MIDR
	adr   r3, .Lactrl_cpuid      // load addr
	ldm   r3, {r1, r2}           // load mask + val
	and   r3, r0, r1             // apply mask
	teq   r3, r2                 // check value
	bne   2f                     // only do mcr on this CPU
#endif

	mrc   p15, 0, r1, c1, c0, 1
#ifdef CONFIG_ARM_V7
	tst   r1, #0x40
	bne   2f
	lsr   r0, r0, #8
	and   r0, r0, #7
	cmp   r0, #7
	orrne r1, r1, #0x41
	orreq r1, r1, #0x40
#else
	orr   r1, r1, #0x20
#endif
	mcr   p15, 0, r1, c1, c0, 1

2:

	// TLB flush
	mcr p15, 0, r0, c8, c7, 0

	adr r0, _tramp_mp_startup_dcr
	ldr r0, [r0]
	mcr p15, 0, r0, c3, c0

	// reset ASID and PROCID
	mov r0, #0
	mcr p15, 0, r0, c13, c0, 1

	// init TTBCR
	adr r0, _tramp_mp_startup_ttbcr
	ldr r1, [r0]
	mcr p15, 0, r1, c2, c0, 2

#ifdef CONFIG_ARM_LPAE
	adr r0, _tramp_mp_startup_mair0
	ldr r0, [r0]
	mcr p15, 0, r0, c10, c2, 0  // MAIR0
#endif

	mov r0, #0
	mcr p15, 0, r0, c8, c7, 0

	adr r0, _tramp_mp_startup_pdbr
	ldr r0, [r0]
	tst r1, #(1 << 31)
	movne  r1, #0
	mcrrne p15, 0, r0, r1, c2
	mcreq  p15, 0, r0, c2, c0

	adr r0, _tramp_mp_startup_cp15_c1
	ldr r0, [r0]
	mcr p15, 0, r0, c1, c0

	// barrier
	mrc p15, 0, r0, c2, c0, 0
	mov r0, r0
	ldr r0, 1f
	mov pc, r0
1:
	.long _tramp_mp_virt

.Lmpcore_phys_base:
	.long MPCORE_PHYS_BASE

.Lactrl_cpuid:
	.long 0xff0fff00
	.long 0x410fc000

	// we run paged now
_tramp_mp_virt:
	// spinlock on cpu-init
	adr	r0, _tramp_mp_spinlock
1:	ldr	r1, [r0]
	teq	r1, #0
	wfene
	bne	1b

2:	ldrex	r1, [r0]
	teq	r1, #0
	bne	1b
	mov	r1, #2
	strex	r2, r1, [r0]
	teq	r2, #0
	bne	1b

	// TLB flush
	mcr p15, 0, r0, c8, c7, 0

	adr	sp, _tramp_mp_init_stack_top
	nop
	ldr	pc, [pc, #-4]

	.long BOOT_AP_CPU

.macro defvar name
.global \name
\name: .long 0
.endm

defvar _tramp_mp_startup_cp15_c1
defvar _tramp_mp_startup_pdbr
defvar _tramp_mp_startup_dcr
defvar _tramp_mp_startup_ttbcr
defvar _tramp_mp_startup_mair0
defvar _tramp_mp_spinlock

_tramp_mp_init_stack:
	.space 1024
_tramp_mp_init_stack_top:

