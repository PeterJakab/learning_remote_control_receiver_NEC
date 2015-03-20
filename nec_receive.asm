;**********************************************************************
;                                                                     *
;    Filename:	    nec_receive.asm                                   *
;    Date:                                                            *
;    File Version:                                                    *
;                                                                     *
;    Author:        el@jap.hu                                         *
;                   http://jap.hu/electronic/                         *
;**********************************************************************
;NOTES
;
; NEC IR decoding routine
;
;**********************************************************************
;HISTORY
;
; 001-20150315
;**********************************************************************

	list      p=16f627a

	GLOBAL nec_receive
	GLOBAL nec_flags, nec_packet

#include <p16f627a.inc>
#define RXBIT PORTA, 4

;***** VARIABLES
#define NEC_NEW_PACKET nec_flags, 0
#define NEC_REPEAT nec_flags, 1

; header_pulse nominal: 9000 us
; header_space nominal: 4500 us or 2250 us (repeat)
NEC_HEADER_PULSE_MIN EQU .6000
NEC_HEADER_PULSE_MAX EQU .12000
NEC_HEADER_SPACE_MIN EQU .1500
NEC_HEADER_SPACE_MAX EQU .6000
NEC_HEADER_SPACE_THR EQU .3375
#define NEC_HEADER_PRESCALER .64

; bit pulse nominal: 560 us
; bit space nominal: 560us (logic 0) or 1690 us (logic 1)
NEC_BIT_PULSE_MIN EQU .300
NEC_BIT_PULSE_MAX EQU .900
NEC_BIT_SPACE_MIN EQU .300
NEC_BIT_SPACE_MAX EQU .2000
NEC_BIT_SPACE_THR EQU .1125
#define NEC_BIT_PRESCALER  .8

;normal input logic
;define SKL btfsc
;define SKH btfss

;reverse input logic
#define SKL btfss
#define SKH btfsc

TIMER0_64 macro
	BANKSEL OPTION_REG
	movlw B'101'
	movwf OPTION_REG ; set prescaler to 1:64
	BANKSEL PORTA
	clrf TMR0
	endm

TIMER0_8 macro
	BANKSEL OPTION_REG
	movlw B'010'
	movwf OPTION_REG ; set prescaler to 1:8
	BANKSEL PORTA
	clrf TMR0
	endm

TIMER0 macro prescaler
	BANKSEL OPTION_REG

	if (prescaler == .64)
	movlw B'101'
	else
	if (prescaler == .8)
	movlw B'010'
	endif
	endif

	movwf OPTION_REG ; set prescaler to 1:8
	BANKSEL PORTA
	clrf TMR0
	endm

necdata UDATA

bitcnt		res	1
tmrval		res	1 ; timer value
bt		res	1 ; receive byte buffer
nec_flags	res	1 ;
btcnt		res	1 ; byte counter
nec_packet	res	4 ; received nec packet

neccode		CODE

nec_receive	; receive a NEC IR packet
		clrf nec_flags
		movlw .4 ; 4 bytes
		movwf btcnt
		movlw nec_packet
		movwf FSR
		TIMER0( NEC_HEADER_PRESCALER )
		bcf INTCON, T0IF

nec_00		; waiting for the first pulse
		btfsc INTCON, T0IF
		retlw .1 ; timeout
		SKH RXBIT
		goto nec_00

		clrf TMR0
nec_01		; measuring header pulse
		btfsc INTCON, T0IF
		retlw .2 ; timeout
		SKL RXBIT
		goto nec_01

		movf TMR0, W
		movwf tmrval
		clrf TMR0

		movlw (NEC_HEADER_PULSE_MIN/NEC_HEADER_PRESCALER)
		subwf tmrval, W
		btfss STATUS, C ; if (tmrval < header_pulse_min) return
		retlw .3 ; header pulse too short

		movlw (NEC_HEADER_PULSE_MAX/NEC_HEADER_PRESCALER)
		subwf tmrval, W
		btfsc STATUS, C ; if (tmrval >= header_pulse_max) return
		retlw .4 ; header pulse too long

nec_02		; measuring header space
		btfsc INTCON, T0IF
		retlw .5 ; timeout
		SKH RXBIT
		goto nec_02

		movf TMR0, W
		movwf tmrval
	 	TIMER0( NEC_BIT_PRESCALER )

		movlw (NEC_HEADER_SPACE_MIN/NEC_HEADER_PRESCALER)
		subwf tmrval, W
		btfss STATUS, C ; if (tmrval < header_space_min) return
		retlw .6 ; header space too short

		movlw (NEC_HEADER_SPACE_MAX/NEC_HEADER_PRESCALER)
		subwf tmrval, W
		btfsc STATUS, C ; if (tmrval >= header_space_max) return
		retlw .7 ; header space too long

		movlw (NEC_HEADER_SPACE_THR/NEC_HEADER_PRESCALER)
		subwf tmrval, W ; if (tmrval < header_space_thr) return repeat
		bnc nec_rep

nec_byte	movlw .8
		movwf bitcnt
nec_bit
nec_03		; measuring bit pulse
		btfsc INTCON, T0IF
		retlw .8 ; timeout
		SKL RXBIT
		goto nec_03

		movf TMR0, W
		movwf tmrval
		clrf TMR0

		movlw (NEC_BIT_PULSE_MIN/NEC_BIT_PRESCALER)
		subwf tmrval, W
		btfss STATUS, C ; if (tmrval < bit_pulse_min) return
		retlw .9 ; bit pulse too short

		movlw (NEC_BIT_PULSE_MAX/NEC_BIT_PRESCALER)
		subwf tmrval, W
		btfsc STATUS, C ; if (tmrval >= bit_pulse_max) return
		retlw .10 ; bit pulse too long

nec_04		; measuring bit space
		btfsc INTCON, T0IF
		retlw .11 ; timeout
		SKH RXBIT
		goto nec_04

		movf TMR0, W
		movwf tmrval
		clrf TMR0

		movlw (NEC_BIT_SPACE_MIN/NEC_BIT_PRESCALER)
		subwf tmrval, W
		btfss STATUS, C ; if (tmrval < bit_space_min) return
		retlw .12 ; bit pulse too short

		movlw (NEC_BIT_SPACE_MAX/NEC_BIT_PRESCALER)
		subwf tmrval, W
		btfsc STATUS, C ; if (tmrval >= bit_space_max) return
		retlw .13 ; bit pulse too long

		movlw (NEC_BIT_SPACE_THR/NEC_BIT_PRESCALER)
		subwf tmrval, W ; if (tmrval < bit_space_thr) C=0 else C=1

		rrf bt, F ; shift bit into byte buffer: order MSB..LSB
		decfsz bitcnt, F
		goto nec_bit ; receive next bit
		movf bt, W
		movwf INDF
		incf FSR, F
		decfsz btcnt, F
		goto nec_byte ; receive next byte

		xorwf nec_packet+2, W
		xorlw 0xff
		btfss STATUS, Z
		retlw .14 ; command data error

		bsf NEC_NEW_PACKET

nec_05		; wait for the end of bit pulse
		btfsc INTCON, T0IF
		retlw .0 ; timeout (but buffer received)
		SKL RXBIT
		goto nec_05
		retlw 0 ; OK, buffer received

nec_rep		; repeat received
		bsf NEC_REPEAT
		bsf NEC_NEW_PACKET
		retlw 0

		end

