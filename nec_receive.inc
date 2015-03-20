;**********************************************************************
;                                                                     *
;    Filename:	    nec_receive.inc                                   *
;    Date:                                                            *
;    File Version:                                                    *
;                                                                     *
;    Author:        el@jap.hu                                         *
;                   http://jap.hu/electronic/                         *
;**********************************************************************

	EXTERN nec_receive
	EXTERN nec_flags, nec_packet

#define NEC_NEW_PACKET nec_flags, 0
#define NEC_REPEAT nec_flags, 1
