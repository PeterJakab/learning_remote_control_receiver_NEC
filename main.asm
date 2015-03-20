;**********************************************************************
;                                                                     *
;    Filename:	    main.asm                                          *
;    Date:                                                            *
;    File Version:                                                    *
;                                                                     *
;    Author:        el@jap.hu                                         *
;                   http://jap.hu/electronic/                         *
;**********************************************************************
; HISTORY
;
; 001 - 20150316 NEC decoder started
; 008 - 20150318 LCD version - print codes on display
; 009 - 20150318 learning remote control
;**********************************************************************
;
;    Notes:
;**********************************************************************

	list      p=16f627a
	__CONFIG   _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC & _LVP_OFF & _MCLRE_OFF

#include <p16f627a.inc>
#include "nec_receive.inc"

; these are not actually used anywhere...
#define TYPE_TOGGLE 0x00
#define TYPE_OFF 0x01
#define TYPE_ON 0x02
#define TYPE_MOMENTARY 0x03

; porta bits
VALID_LED EQU 3
LEARN_BT EQU 5

EXPIRE_TIME  EQU .250000
EXPIRE_PR2   EQU .187
EXPIRE_TICK  EQU .16 * EXPIRE_PR2
EXPIRE_TIMER EQU EXPIRE_TIME / EXPIRE_TICK

#define VALID main_flags, 2
#define COMMAND main_flags, 3

NUM_CHANNELS	EQU .11

;***** VARIABLES
freemem		UDATA

main_flags	res 1

c_type		res 1
c_channel	res 1
act_nec_address	res 2
act_nec_command res 1

cur_state	res 2
expire_cnt	res 1
cur_ch		res 2
clear_ch	res 2

savew1		res 1
savestatus	res 1
savepclath	res 1
savefsr		res 1

lrn_channel	res 1
lrn_type	res 1

vectors		CODE 0

  		goto    main              ; go to beginning of program
		nop
		nop
		nop
		goto itr

eeprom_data	CODE 0x210E

address		de 0x00, 0xff ; remote control address bytes, fixed for all commands

toggle_ch	; 11 bytes for 11 channels
		de 0x16, 0x0c, 0x18, 0x5e ; ch0-3
		de 0x08, 0xff, 0xff, 0xff ; ch4-7
		de 0xff, 0xff, 0xff ; ch8-10

off_ch		; 11 bytes for 11 channels
		de 0x45, 0x07, 0xff, 0xff ; ch0-3
		de 0xff, 0xff, 0xff, 0xff ; ch4-7
		de 0xff, 0xff, 0xff ; ch8-10

on_ch		; 11 bytes for 11 channels
		de 0x47, 0x15, 0xff, 0xff ; ch0-3
		de 0xff, 0xff, 0xff, 0xff ; ch4-7
		de 0xff, 0xff, 0xff ; ch8-10

momentary_ch	; 11 bytes for 11 channels
		de 0x46, 0x09, 0xff, 0xff ; ch0-3
		de 0xff, 0xff, 0xff, 0xff ; ch4-7
		de 0xff, 0xff, 0xff ; ch8-10

end_of_data	de 0xff

maincode	CODE 5

channel_lookup_b
		addwf PCL, F
		dt 0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80 ; B0-B7

channel_lookup_a
		addwf PCL, F
		dt 0x01, 0x02, 0x04, 0x40, 0x80, 0x00, 0x00, 0x00 ; A0, A1, A2, A6, A7

type2address	addwf PCL, F
		dt LOW toggle_ch, LOW off_ch, LOW on_ch, LOW momentary_ch

search_codes	;
		clrf c_type
		movlw toggle_ch ; c_type = 0
		call search_1
		btfsc STATUS, Z
		return
		incf c_type, F
		movlw off_ch ; c_type = 1
		call search_1
		btfsc STATUS, Z
		return
		incf c_type, F
		movlw on_ch ; c_type = 2
		call search_1
		btfsc STATUS, Z
		return
		incf c_type, F
		movlw momentary_ch ; c_type = 3
		call search_1
		btfsc STATUS, Z
		return

		; no code found
		movlw 0xff
		movwf c_type
		movwf c_channel
		return

search_1	clrf c_channel
		BANKSEL EEADR
		movwf EEADR

search_2	
		BANKSEL EECON1
		bsf EECON1, RD
		movf EEDATA, W
		BANKSEL PORTA
		movwf act_nec_command

		movf act_nec_command, W
		xorwf nec_packet+2, W
		btfsc STATUS, Z
		return ; Z=1 - found
search_next	
		BANKSEL EEADR
		incf EEADR, F
		BANKSEL PORTA
		incf c_channel, F
		movlw NUM_CHANNELS
		xorwf c_channel, W
		bnz search_2
		bcf STATUS, Z ; Z=0 - not found
		return

itr
		movwf	savew1
		movf	STATUS,w
		clrf	STATUS
		movwf	savestatus
		movf	PCLATH,w
		movwf	savepclath
		clrf	PCLATH
	
		movf	FSR,w
		movwf	savefsr
	
		btfsc	PIR1, TMR2IF
		call	t2_int_handler
	
		movf	savefsr,w
		movwf	FSR
	
		movf	savepclath,w
		movwf	PCLATH
	
		movf	savestatus,w
		movwf	STATUS
	
		swapf	savew1,f
		swapf	savew1,w
	
		retfie
	

main		;F628 HARDWARE INIT
		movlw 0
		movwf PORTA
		movwf PORTB
		movlw 7
		movwf CMCON ; disable comparators

		; setup TMR2 for 3ms timer interrupts
		movlw B'110'
		movwf T2CON ; TMR2ON, 1:16 prescaler

		BANKSEL TRISA
		movlw EXPIRE_PR2
		movwf PR2 ; 16*187us=2992us

		; setup TMR0 for measuring pulse widths
		clrwdt ; changing default presc. assignment
		clrf TMR0
				; prescaler assigned to TMR0
		clrf OPTION_REG ; T0CS selects internal CLK

		; read remote control address from eeprom to act_nec_address
		BANKSEL EEADR
		movlw address
		movwf EEADR
		BANKSEL EECON1
		bsf EECON1, RD
		movf EEDATA, W
		BANKSEL PORTA
		movwf act_nec_address
		BANKSEL EEADR
		incfsz EEADR, F
		BANKSEL EECON1
		bsf EECON1, RD
		movf EEDATA, W
		BANKSEL PORTA
		movwf act_nec_address+1

		btfss PORTA, LEARN_BT
		goto learn

		BANKSEL TRISA
		movlw 0x10
		movwf TRISA
		movlw 0
		movwf TRISB

		movlw (1<<TMR2IE)
		movwf PIE1 ; enable TMR2 interrupt

		BANKSEL PORTA
		clrf PIR1 ; clear interrupt flags
		clrf expire_cnt
		clrf main_flags
		movlw (1<<GIE) | (1<<PEIE)
		movwf INTCON ; enable PEIE + GIE

warm		clrf cur_state
		clrf cur_state+1
		movlw 0xff
		movwf clear_ch
		movwf clear_ch+1

loop		call nec_receive
		btfss NEC_NEW_PACKET
		goto loop

		btfss NEC_REPEAT ; if (!repeat) command = 1
		bsf COMMAND

		btfss COMMAND ; if (!command) goto loop
		goto loop

		; check address bytes for a match
		movf act_nec_address, W
		xorwf nec_packet, W
		bnz loop
		movf act_nec_address+1, W
		xorwf nec_packet+1, W
		bnz loop

		; check command bytes
		movf nec_packet+2, W
		xorwf nec_packet+3, W
		xorlw 0xff
		bnz loop

		; packet integrity ok
		call search_codes
		bnz loop ; code not found

		; code found in lookup table: c_type and c_channel
rx_ok		movlw EXPIRE_TIMER
		movwf expire_cnt
		bsf VALID

		btfsc NEC_REPEAT
		goto loop ; if (repeat) skip (only expire timer is updated)

		; check channel
		movlw NUM_CHANNELS
		subwf c_channel, W
		bc loop ; illegal channel data

		; lookup current channel
		movlw 0x07
		andwf c_channel, W
		btfss c_channel, 3
		goto channel_on_portb
channel_on_porta
		call channel_lookup_a
		movwf cur_ch
		clrf cur_ch+1
		goto channel_done

channel_on_portb
		call channel_lookup_b
		clrf cur_ch
		movwf cur_ch+1

channel_done	bcf INTCON, GIE

		btfsc c_type, 1
		goto state_type23
state_type01	btfsc c_type, 0
		goto state_type1

state_type0	; toggle
		; clear momentary
		movf cur_ch, W
		iorwf clear_ch, F
		movf cur_ch+1, W
		iorwf clear_ch+1, F

		movf cur_ch, W
		xorwf cur_state, F
		movf cur_ch+1, W
		xorwf cur_state+1, F
		goto state_done

state_type1	; off
		movlw 0xff
		xorwf cur_ch, W
		andwf cur_state, F
		movlw 0xff
		xorwf cur_ch+1, W
		andwf cur_state+1, F
		goto state_done

state_type23	btfss c_type, 0
		goto state_type2
state_type3	; set momentary
		movlw 0xff
		xorwf cur_ch, W
		andwf clear_ch, F
		movlw 0xff
		xorwf cur_ch+1, W
		andwf clear_ch+1, F
		goto state_on

state_type2	; on
		; clear momentary
		movf cur_ch, W
		iorwf clear_ch, F
		movf cur_ch+1, W
		iorwf clear_ch+1, F
state_on
		movf cur_ch, W
		iorwf cur_state, F
		movf cur_ch+1, W
		iorwf cur_state+1, F
		goto state_done

state_done	movlw (1<<VALID_LED)
		call state_out
		bsf INTCON, GIE
		goto loop

t2_int_handler	bcf PIR1, TMR2IF
		movf expire_cnt, F
		btfsc STATUS, Z
		return ; do nothing

valid_on	decfsz expire_cnt, F
		return

		; invalidate
		bcf VALID
		bcf COMMAND

		; clear momentary outputs
		movf clear_ch, W
		andwf cur_state, F
		movf clear_ch+1, W
		andwf cur_state+1, F
		movlw 0

state_out	iorwf cur_state, W
		movwf PORTA
		movf cur_state+1, W
		movwf PORTB
		return

learn		
		BANKSEL TRISA
		movlw 0x10
		movwf TRISA
		movlw 0xff
		movwf TRISB

		BANKSEL PORTA
		; check for clear_all
		rrf PORTB, W
		andlw 0x07
		bz lrn_clear_all

loop2		call nec_receive
		btfss NEC_NEW_PACKET
		goto loop2

		; ignore repeat codes
		btfsc NEC_REPEAT ; if (repeat) goto loop2
		goto loop2

		; check command bytes
		movf nec_packet+2, W
		xorwf nec_packet+3, W
		xorlw 0xff
		bnz loop2

		; code received into nec_packet
		; b1-b3: channel mode
		rrf PORTB, W
		andlw 0x07
		movwf lrn_type
		; b4-b7: channel number
		swapf PORTB, W
		andlw 0x0f
		xorlw 0x0f ; invert!
		movwf lrn_channel

		movlw 0x02 ; B1, B3 pushed: clear code
		xorwf lrn_type, W
		bz lrn_clear_one

		; check channel
		movlw NUM_CHANNELS
		subwf lrn_channel, W
		bc loop2 ; illegal channel data

		call button2address
		bnz loop2 ; illegal button combination / no button pressed
		addwf lrn_channel, F ; compute eedata address
		; lrn_channel contains the eeprom data address

		; check if this code is already used
		call search_codes
		bz loop2 ; this code is already used for something, don't store

		movf lrn_channel, W
		BANKSEL EEADR
		movwf EEADR

		; write to data eeprom
		BANKSEL PORTA

		movlw (1<<VALID_LED)
		movwf PORTA

		movf nec_packet+2, W
		call eewrite

		movf act_nec_address, W
		xorwf nec_packet, W
		bnz modify_address
		movf act_nec_address+1, W
		xorwf nec_packet+1, W
		bz same_address

modify_address	; write address to eeprom if different from actual

		BANKSEL EEADR
		movlw address
		movwf EEADR
		BANKSEL PORTA
		movf nec_packet, W
		call eewrite
		movf nec_packet+1, W
		BANKSEL EEADR
		incf EEADR, F
		call eewrite

		movf nec_packet, W
		movwf act_nec_address
		movf nec_packet+1, W
		movwf act_nec_address+1

same_address
		clrf PORTA
		; write done
		goto loop2

button2address	movlw 0x03 ; B3 pushed: type OFF
		xorwf lrn_type, W
		btfsc STATUS, Z
		retlw off_ch

		movlw 0x05; B2 pushed: type ON
		xorwf lrn_type, W
		btfsc STATUS, Z
		retlw on_ch

		movlw 0x01; B2, B3 pushed: toggle
		xorwf lrn_type, W
		btfsc STATUS, Z
		retlw toggle_ch

		movlw 0x06; B1 pushed: momentary
		xorwf lrn_type, W
		btfsc STATUS, Z
		retlw momentary_ch

		retlw 0xff

lrn_clear_one	call search_codes
		bnz loop2 ; not found

		BANKSEL EEADR
		movf EEADR, W
		call erase_address
		BANKSEL EEADR
		decf EEADR, W
		call erase_address
		BANKSEL PORTA
		goto lrn_clear_one

lrn_clear_all	movlw address
		movwf lrn_channel
lrn_clear_2	movf lrn_channel, W
		call erase_address
		incf lrn_channel, F
		movlw end_of_data
		xorwf lrn_channel, W
		bnz lrn_clear_2
		goto loop2

erase_address	
		BANKSEL EEADR
		movwf EEADR

		; write to data eeprom
		bsf EECON1, WREN
		BANKSEL PORTA

		movlw (1<<VALID_LED)
		movwf PORTA

		movlw 0xff
		call eewrite
		clrf PORTA
		; write done
		return

eewrite
		BANKSEL EEDATA
		bsf EECON1, WREN
		movwf EEDATA
		movlw 0x55
		movwf EECON2
		movlw 0xaa
		movwf EECON2
		bsf EECON1, WR
eewr1		btfsc EECON1, WR
		goto eewr1

		bcf EECON1, WREN
		BANKSEL PORTA
		return


		end
