;
; LCD.asm
;
; Created: 2025-02-03 5:00:02 PM
; Author : Eric
;

.cseg
; timers
.org 0
	jmp reset

.org 0x22
	jmp timer1

.org 0x54
	jmp timer4

.include "m2560def.inc"
.include "lcd.asm"

; define variables
.cseg
#define CLOCK 16.0e6
#define DELAY1 0.01
#define DELAY3 0.1
#define DELAY4 0.5

#define BUTTON_RIGHT_MASK 0b00000001	
#define BUTTON_UP_MASK    0b00000010
#define BUTTON_DOWN_MASK  0b00000100
#define BUTTON_LEFT_MASK  0b00001000

#define BUTTON_RIGHT_ADC  0x032
#define BUTTON_UP_ADC     0x0b0
#define BUTTON_DOWN_ADC   0x160
#define BUTTON_LEFT_ADC   0x22b
#define BUTTON_SELECT_ADC 0x316

.equ PRESCALE_DIV=1024   ; w.r.t. clock, CS[2:0] = 0b101

; 16-bit timers.
.equ TOP1=int(0.5+(CLOCK/PRESCALE_DIV*DELAY1))
.if TOP1>65535
.error "TOP1 is out of range"
.endif

.equ TOP3=int(0.5+(CLOCK/PRESCALE_DIV*DELAY3))
.if TOP3>65535
.error "TOP3 is out of range"
.endif

.equ TOP4=int(0.5+(CLOCK/PRESCALE_DIV*DELAY4))
.if TOP4>65535
.error "TOP4 is out of range"
.endif

reset:
	; initialize buttons
	.equ ADCSRA_BTN=0x7A
	.equ ADCSRB_BTN=0x7B
	.equ ADMUX_BTN=0x7C
	.equ ADCL_BTN=0x78
	.equ ADCH_BTN=0x79

	; define registers for timer1
	.def DATAH=r25
	.def DATAL=r24
	.def BOUNDARY_H=r1
	.def BOUNDARY_L=r0

	; initialize BOUNDARY with the RAMEND
	ldi r16, low(RAMEND)
	mov BOUNDARY_L, r21
	ldi r16, high(RAMEND)
	mov BOUNDARY_H, r21

; initialize the ADC converter 
	ldi temp, (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0)
	sts ADCSRA, temp
	ldi temp, (1 << REFS0)
	sts ADMUX, r16

	; Timer 1 with an interrupt handler.
	ldi r17, high(TOP1)
	ldi r16, low(TOP1)
	sts OCR1AH, r17
	sts OCR1AL, r16
	clr r16
	sts TCCR1A, r16
	ldi r16, (1 << WGM12) | (1 << CS12) | (1 << CS10)
	sts TCCR1B, r16
	ldi r16, (1 << OCIE1A)
	sts TIMSK1, r16

	; Timer 3 is for updating the LCD display with a polling loop.
	ldi r17, high(TOP3)
	ldi r16, low(TOP3)
	sts OCR3AH, r17
	sts OCR3AL, r16
	clr r16
	sts TCCR3A, r16
	ldi r16, (1 << WGM32) | (1 << CS32) | (1 << CS30)
	sts TCCR3B, r16

	; Timer 4 is for updating the contents to be displayed on the LCD.
	ldi r17, high(TOP4)
	ldi r16, low(TOP4)
	sts OCR4AH, r17
	sts OCR4AL, r16
	clr r16
	sts TCCR4A, r16
	ldi r16, (1 << WGM42) | (1 << CS42) | (1 << CS40)
	sts TCCR4B, r16
	ldi r16, (1 << OCIE4A)
	sts TIMSK4, r16
sei


; Start
rcall lcd_init

; load pointers
ldi ZL, low(TOP_LINE_CONTENT)
ldi ZH, high(TOP_LINE_CONTENT)
ldi YL, low(CURRENT_CHARSET_INDEX)
ldi YH, high(CURRENT_CHARSET_INDEX)

; initialize CURRENT_CHAR_INDEX to 0
clr r18
sts CURRENT_CHAR_INDEX, r18

; initialize all of TOP_LINE_CONTENT to ' '
; and all of CURRENT_CHARSET_INDEX to 0
ldi r16, ' '
ldi r17, 16
init_TLC_and_CCL:
	st Z+, r16
	st Y+, r18
	dec r17
	brne init_TLC_and_CCL

; timer3 polling
start:
	rjmp timer3

stop:
	rjmp stop

;
timer1:
	; prolog
	push r16
	lds r16, SREG
	push r16
	push DATAL
	push DATAH
	push BOUNDARY_L
	push BOUNDARY_H
	push r19
	push r18
	push r17

	; clear register
	clr r19

	; check select button boundary
	lds	r16, ADCSRA_BTN	
	ori r16, 0x40
	sts	ADCSRA_BTN, r16

; wait for it to complete, check for ADSC bit
wait:
	lds r16, ADCSRA_BTN
	andi r16, 0x40
	brne wait

	; read the value and store the 10 bit results in DATAH:DATAL
	lds DATAL, ADCL_BTN
	lds DATAH, ADCH_BTN

	ldi r17, low(BUTTON_SELECT_ADC)
	mov BOUNDARY_L, r17
	ldi r17, high(BUTTON_SELECT_ADC)
	mov BOUNDARY_H, r17

	clr r18
	; if DATAH:DATAL < BOUNDARY_H:BOUNDARY_L
	;	r18=1 button is pressed
	; else
	;	r18=0
	cp DATAL, BOUNDARY_L
	cpc DATAH, BOUNDARY_H
	brsh timer1_end		; if >= 800, no button pressed
	ldi r18, 1

check_button_left:
	; if DATAH:DATAL < BOUNDARY_H:BOUNDARY_L
	;	r19='L' and check_button_down
	; else
	;	no button pressed
	ldi r17, low(BUTTON_LEFT_ADC)
	mov BOUNDARY_L, r17
	ldi r17, high(BUTTON_LEFT_ADC)
	mov BOUNDARY_H, r17
	cp DATAL, BOUNDARY_L
	cpc DATAH, BOUNDARY_H
	brsh timer1_end		
	ldi r19, 'L'

check_button_down:
	; if DATAH:DATAL < BOUNDARY_H:BOUNDARY_L
	;	r19='D' and check_button_down
	; else
	;	no button pressed
	ldi r17, low(BUTTON_DOWN_ADC)
	mov BOUNDARY_L, r17
	ldi r17, high(BUTTON_DOWN_ADC)
	mov BOUNDARY_H, r17
	cp DATAL, BOUNDARY_L
	cpc DATAH, BOUNDARY_H
	brsh timer1_end	
	ldi r19, 'D'

check_button_up:
	; if DATAH:DATAL < BOUNDARY_H:BOUNDARY_L
	;	r19='U' and check_button_down
	; else
	;	no button pressed	
	ldi r17, low(BUTTON_UP_ADC)
	mov BOUNDARY_L, r17
	ldi r17, high(BUTTON_UP_ADC)
	mov BOUNDARY_H, r17
	cp DATAL, BOUNDARY_L
	cpc DATAH, BOUNDARY_H
	brsh timer1_end	
	ldi r19, 'U'

check_button_right:
	; if DATAH:DATAL < BOUNDARY_H:BOUNDARY_L
	;	r19='R' Right button is pressed
	; else
	;	no button pressed	
	ldi r17, low(BUTTON_RIGHT_ADC)
	mov BOUNDARY_L, r17
	ldi r17, high(BUTTON_RIGHT_ADC)
	mov BOUNDARY_H, r17
	cp DATAL, BOUNDARY_L
	cpc DATAH, BOUNDARY_H
	brsh timer1_end	
	ldi r19, 'R'
	

timer1_end:
	; store LAST_BUTTON_PRESSED and BUTTON_IS_PRESSED
	sts LAST_BUTTON_PRESSED, r19
    sts BUTTON_IS_PRESSED, r18

	; epilog
	pop r17
	pop r18
	pop r19
	pop BOUNDARY_H
	pop BOUNDARY_L
	pop DATAH
	pop DATAL
	pop r16
	sts SREG, r16
	pop r16
	reti


; timer 3
timer3:
	in temp, TIFR3
	sbrs temp, OCF3A
	rjmp timer3

	; set curser to bottom right corner
	ldi r16, 1
	ldi r17, 15
	push r16
	push r17
	rcall lcd_gotoxy
	pop r17
	pop r16

	; if button is pressed, display '*',
	; if not pressed, display '-' at cursor location
	lds r19, BUTTON_IS_PRESSED
	cpi r19, 0x01
	breq star
	; display '-'  at cursor location
	ldi r19, '-'
	push r19
	rcall lcd_putchar
	pop r19
	rjmp letter

star:
	; display '*'  at cursor location
	ldi r19, '*'
	push r19
	rcall lcd_putchar
	pop r19
	rjmp letter

; part B
letter:
	; set cursor the the bottom left corner
	ldi r16, 1
	ldi r17, 0
	push r16
	push r17
	rcall lcd_gotoxy
	pop r17
	pop r16

	; load r20 with the character of the LAST_BUTTON_PRESSED, 
	; load r19 with a space characater ' '
	lds r20, LAST_BUTTON_PRESSED
	ldi r19, ' '

check_left:
	; check if LAST_BUTTON_PRESSED is 'L', else branch to check_down
	cpi r20, 'L'
	brne check_down

	; if LAST_BUTTON_PRESSED is 'L', display L on lcd and ' ' for the others
	push r20
	rcall lcd_putchar
	pop r20
	push r19
	rcall lcd_putchar
	pop r19
	push r19
	rcall lcd_putchar
	pop r19
	push r19
	rcall lcd_putchar
	pop r19
	rjmp display_top_line

check_down:
	; check if LAST_BUTTON_PRESSED is 'D', else branch to check_up
	cpi r20, 'D'
	brne check_up

	; if LAST_BUTTON_PRESSED is 'D', display D on lcd and ' ' for the others
	push r19
	rcall lcd_putchar
	pop r19
	push r20
	rcall lcd_putchar
	pop r20
	push r19
	rcall lcd_putchar
	pop r19
	push r19
	rcall lcd_putchar
	pop r19
	rjmp display_top_line

check_up:
	; check if LAST_BUTTON_PRESSED is 'U', else branch to check_right
	cpi r20, 'U'
	brne check_right

	; if LAST_BUTTON_PRESSED is 'U', display U on lcd and ' ' for the others
	push r19
	rcall lcd_putchar
	pop r19
	push r19
	rcall lcd_putchar
	pop r19
	push r20
	rcall lcd_putchar
	pop r20
	push r19
	rcall lcd_putchar
	pop r19
	rjmp display_top_line

check_right:
	; check if LAST_BUTTON_PRESSED is 'R', else branch to display_top_line
	cpi r20, 'R'
	brne display_top_line

	; if LAST_BUTTON_PRESSED is 'R', display R on lcd and ' ' for the others
	push r19
	rcall lcd_putchar
	pop r19
	push r19
	rcall lcd_putchar
	pop r19
	push r19
	rcall lcd_putchar
	pop r19
	push r20
	rcall lcd_putchar
	pop r20
	rjmp display_top_line

; part C
display_top_line:
	; load CURRENT_CHAR_INDEX into r17 and clear r16
	clr r16
	lds r17, CURRENT_CHAR_INDEX

	; set curser to the top row to display TOP_LINE_CONTENT
	push r16
	push r17
	rcall lcd_gotoxy
	pop r17
	pop r16

	; initialize pointer for TOP_LINE_CONTENT
	ldi XL, low(TOP_LINE_CONTENT)
	ldi XH, high(TOP_LINE_CONTENT)

	; move pointer to CURRENT_CHAR_INDEX
	lds r17, CURRENT_CHAR_INDEX
	add XL, r17
	adc XH, r16

	; load the character at pointed location and display at cursor location
	ld r18, X
	push r18
	rcall lcd_putchar
	pop r18


timer3_end:
	; continue polling
	rjmp timer3

; part C
timer4:
	; prolog
	push ZL
	push ZH
	push YL
	push YH
	push XL
	push XH
	push r18
	push r17
	push r16
	lds r16, SREG
	push r16

	; if none of the buttons have been pressed, branch to end of timer4
	lds r16, BUTTON_IS_PRESSED
	cpi r16, 0x00
	breq timer4_end
	
	; initialize pointers for AVAILABLE_CHARSET, CURRENT_CHARSET_INDEX, and TOP_LINE_CONTENT
	ldi ZL, low(AVAILABLE_CHARSET<<1)
	ldi ZH, high(AVAILABLE_CHARSET<<1)
	ldi YL, low(CURRENT_CHARSET_INDEX)
	ldi YH, high(CURRENT_CHARSET_INDEX)
	ldi XL, low(TOP_LINE_CONTENT)
	ldi XH, high(TOP_LINE_CONTENT)
	
	; move TOP_LINE_CONTENT pointer to correct location by adding CURRENT_CHAR_INDEX
	clr r16
	lds r17, CURRENT_CHAR_INDEX
	add XL, r17
	adc XH, r16

	; move CURRENT_CHARSET_INDEX to the correct location by adding CURRENT_CHAR_INDEX
	add YL, r17
	adc YH, r16

	; move AVAILABLE_CHARSET to the correct location by adding the correct index from CURRENT_CHARSET_INDEX
	; AVAILABLE_CHARSET pointer will now point to the character that should be in the location of the cursor
	ld r17, Y
	add ZL, r17
	adc ZH, r16

	; check which button was pressed
	lds r16, LAST_BUTTON_PRESSED
	cpi r16, 'L'
	breq left_button_pressed
	cpi r16, 'D'
	breq down_button_pressed
	cpi r16, 'U'
	breq up_button_pressed
	cpi r16, 'R'
	breq right_button_pressed
	rjmp timer4_end

left_button_pressed:
	; if left button is pressed, moves cursor to the left if CURRENT_CHAR_INDEX != 0 (left boundary)
	lds r16, CURRENT_CHAR_INDEX
	tst r16
	breq timer4_end
	dec r16
	sts CURRENT_CHAR_INDEX, r16
	rjmp timer4_end

down_button_pressed:
	; if up button is pressed, displays the next character in AVAILABLE_CHARSET
	; does not display the next character if the current character is the first character
	ld r17, Y
	tst r17				; test if the index in CURRENT_CHARSET_INDEX at the cursor location is 0
	breq store_lcd		; if = 0, branch to store unchanged character
	dec r17				; else decrement the index in CURRENT_CHARSET_INDEX at the cursor location
	sbiw Z, 1			; and point AVAILABLE_CHARSET to the previous character
	st Y, r17			; store decremented index back to CURRENT_CHARSET_INDEX
	rjmp store_lcd		; jump to store changed character

up_button_pressed:
	; if up button is pressed, displays the next character in AVAILABLE_CHARSET
	; does not display the next character if the next character is the null terminator
	ld r17, Y
	adiw Z, 1			; point AVAILABLE_CHARSET to the next character
	lpm r18, Z			; load character in AVAILABLE_CHARSET
	tst r18				; test loaded character
	brne update_up		; if character isnt null pointer, branch to update pointer
	sbiw Z, 1			; if character is null pointer, point AVAILABLE_CHARSET back to original character
	rjmp store_lcd		; jump to store unchanged character

update_up:
	inc r17				; increment the index in CURRENT_CHARSET_INDEX at the cursor location
	st Y, r17			; store incremented index back to CURRENT_CHARSET_INDEX
	rjmp store_lcd		; jump to store changed character

right_button_pressed:
	; if right button is pressed, moves cursor to the right if CURRENT_CHAR_INDEX < 15 (right boundary)
	lds r16, CURRENT_CHAR_INDEX
	cpi r16, 15
	breq timer4_end
	inc r16
	sts CURRENT_CHAR_INDEX, r16
	rjmp timer4_end

store_lcd:
	; stores character pointed to in AVAILABLE_CHARSET to the correct location in TOP_LINE_CONTENT
	lpm r18, Z
	st X, r18


timer4_end:
	; epilog
	pop r16
	sts SREG, r16
	pop r16
	pop r17
	pop r18
	pop XH
	pop XL
	pop YH
	pop YL
	pop ZH
	pop ZL
	reti

compare_words:
	; if high bytes are different, look at lower bytes
	cp r17, r19
	breq compare_words_lower_byte

	; since high bytes are different, use these to
	; determine result
	;
	; if C is set from previous cp, it means r17 < r19
	; 
	; preload r25 with 1 with the assume r17 > r19
	ldi r25, 1
	brcs compare_words_is_less_than
	rjmp compare_words_exit

compare_words_is_less_than:
	ldi r25, -1
	rjmp compare_words_exit

compare_words_lower_byte:
	clr r25
	cp r16, r18
	breq compare_words_exit

	ldi r25, 1
	brcs compare_words_is_less_than  ; re-use what we already wrote...

compare_words_exit:
	ret

.cseg
AVAILABLE_CHARSET: .db "0123456789abcdef_", 0


; Data Segment
.dseg

BUTTON_IS_PRESSED: .byte 1			
LAST_BUTTON_PRESSED: .byte 1        

TOP_LINE_CONTENT: .byte 16			
CURRENT_CHARSET_INDEX: .byte 16		
CURRENT_CHAR_INDEX: .byte 1			

.dseg