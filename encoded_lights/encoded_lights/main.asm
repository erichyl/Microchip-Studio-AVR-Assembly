;
; encoded_lights.asm
;
; Created: 2025-02-03 4:26:13 PM
; Author : Eric
;

.include "m2560def.inc"
.cseg
.org 0

	; initializion code
	ldi r16, 0xFF
	sts DDRL, r16
	out DDRB, r16
	ldi r16, low(RAMEND)
	ldi r17, high(RAMEND)
	out SPL, r16
	out SPH, r17

; start program
start:
	ldi r25, HIGH(WORD02 << 1)
	ldi r24, LOW(WORD02 << 1)
	rcall display_message
	rjmp end

end:
    rjmp end


; Functions
set_leds:
	; clear resgisters
	clr r10		
	clr r11
	clr r26

	ldi r26, 0x80		; load the value corresponding to led 6
	sbrc r16, 0			; if the digit in r16 corresponding to led 6 is cleared, skip the addition
	add r10, r26		; if the digit in r16 corresponding to led 6 is set, add to the output of PORTL

	ldi r26, 0x20		; repeat for each LED
	sbrc r16, 1
	add r10, r26

	ldi r26, 0x08
	sbrc r16, 2
	add r10, r26

	ldi r26, 0x02
	sbrc r16, 3
	add r10, r26

	ldi r26, 0x08		; repeat but now adding to the output of PORTB
	sbrc r16, 4
	add r11, r26

	ldi r26, 0x02
	sbrc r16, 5
	add r11, r26

	; turn on leds
	sts PORTL, r10
	out PORTB, r11
	ret

slow_leds:
	mov r16, r17		; copy r17 to r16
	rcall set_leds		; set leds according to the encoding in r16
	rcall delay_long	; long pause
	clr r16				; clear r16
	rcall set_leds		; turn all the leds off
	ret


fast_leds:
	mov r16, r17		; copy r17 to r16
	rcall set_leds		; set leds according to the encoding in r16
	rcall delay_short	; short pause
	clr r16				; clear r16
	rcall set_leds		; turn all the leds off
	ret


leds_with_speed:
	; push old pointer and values store in r17 and r16 to the stack
	push ZH
	push ZL
	push r17
	push r16

	; set stack pointer
	in ZH, SPH
	in ZL, SPL

	ldd r17, Z+8				; load parameter from SRAM to r17
	mov r26, r17				; copy to r26
	andi r26, 0b11000000		; andi to check if leds should be fast or slow
	tst r26						; if r26 is cleared, branch to fast
	breq fast
	rcall slow_leds				; call slow_leds
	rjmp leds_with_speed_end	; jump past the call for fast_leds to the end of the function

	fast:
		rcall fast_leds			; call fast_leds

	leds_with_speed_end:
	; pop old values in r16 and r17 as well as old stack pointer from stack
	pop r16
	pop r17
	pop ZL
	pop ZH
	ret


; delays
; about one second
delay_long:
	push r16

	ldi r16, 14
delay_long_loop:
	rcall delay
	dec r16
	brne delay_long_loop

	pop r16
	ret

; about 0.25 of a second
delay_short:
	push r16

	ldi r16, 4
delay_short_loop:
	rcall delay
	dec r16
	brne delay_short_loop

	pop r16
	ret

delay:
	rcall delay_busywait
	ret

delay_busywait:
	push r16
	push r17
	push r18

	ldi r16, 0x08

delay_busywait_loop1:
	dec r16
	breq delay_busywait_exit

	ldi r17, 0xff

delay_busywait_loop2:
	dec r17
	breq delay_busywait_loop1

	ldi r18, 0xff

delay_busywait_loop3:
	dec r18
	breq delay_busywait_loop2
	rjmp delay_busywait_loop3

delay_busywait_exit:
	pop r18
	pop r17
	pop r16
	ret


; Program Memory

PATTERNS:
	; LED pattern shown from left to right: "." means off, "o" means
    ; on, 1 means long/slow, while 2 means short/fast.
	.db "A", "..oo..", 1
	.db "B", ".o..o.", 2
	.db "C", "o.o...", 1
	.db "D", ".....o", 1
	.db "E", "oooooo", 1
	.db "F", ".oooo.", 2
	.db "G", "oo..oo", 2
	.db "H", "..oo..", 2
	.db "I", ".o..o.", 1
	.db "J", ".....o", 2
	.db "K", "....oo", 2
	.db "L", "o.o.o.", 1
	.db "M", "oooooo", 2
	.db "N", "oo....", 1
	.db "O", ".oooo.", 1
	.db "P", "o.oo.o", 1
	.db "Q", "o.oo.o", 2
	.db "R", "oo..oo", 1
	.db "S", "....oo", 1
	.db "T", "..oo..", 1
	.db "U", "o.....", 1
	.db "V", "o.o.o.", 2
	.db "W", "o.o...", 2
	.db "X", "oo....", 2	
	.db "Y", "..oo..", 2
	.db "Z", "o.....", 2
	.db "-", "o...oo", 1

WORD00: .db "HELLOWORLD", 0, 0
WORD01: .db "THE", 0
WORD02: .db "MICROCHIP-STUDIO", 0, 0
