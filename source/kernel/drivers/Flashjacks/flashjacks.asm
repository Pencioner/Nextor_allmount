	; Device-based driver for the FLASHJACKS IDE interface for Nextor
	;
	; By Aquijacks v1.4
	; Based on version 0.1 by Konamiman and 0.15 by Piter Punk

	;output	"sunride_aquijacks.bin"
	
	org		4000h

	ds		256, 0FFh		; 256 dummy bytes


DRV_START:

TESTADD	equ	0F3F5h

;-----------------------------------------------------------------------------
;
; Driver configuration constants
;


;Hot-plug devices support (device-based drivers only):
;   0 for no hot-plug support
;   1 for hot-plug support

DRV_HOTPLUG	equ	1


;Driver version

VER_MAIN	equ	1
VER_SEC		equ	4
VER_REV		equ	1

;This is a very barebones driver. It has important limitations:
;- CHS mode not supported, disks must support LBA mode.
;- 48 bit addresses are not supported
;  (do the Sunrise IDE hardware support them anyway?)
;- ATAPI devices not supported, only ATA disks.


;-----------------------------------------------------------------------------
;
; IDE registers and bit definitions

IDE_BANK	equ	4104h	;bit 0: enable (1) or disable (0) IDE registers
				;bits 5-7: select 16K ROM bank
IDE_DATA	equ	7C00h	;Data registers, this is a 512 byte area
IDE_ERROR	equ	7E01h	;Error register
IDE_FEAT	equ	7E01h	;Feature register
IDE_SECCNT	equ	7E02h	;Sector count
IDE_SECNUM	equ	7E03h	;Sector number (CHS mode)
IDE_LBALOW	equ	7E03h	;Logical sector low (LBA mode)
IDE_CYLOW	equ	7E04h	;Cylinder low (CHS mode)
IDE_LBAMID	equ	7E04h	;Logical sector mid (LBA mode)
IDE_CYHIGH	equ	7E05h	;Cylinder high (CHS mode)
IDE_LBAHIGH	equ	7E05h	;Logical sector high (LBA mode)
IDE_HEAD	equ	7E06h	;bits 0-3: Head (CHS mode), logical sector higher (LBA mode)
IDE_STATUS	equ	7E07h	;Status register
IDE_CMD		equ	7E07h	;Command register
IDE_FLASHJACKS	equ	7E09h	;Registro FlashJacks
IDE_DEVCTRL	equ	7E0Eh	;Device control register

; Bits in the error register

UNC	equ	6	;Uncorrectable Data Error
WP	equ	6	;Write protected
MC	equ	5	;Media Changed
IDNF	equ	4	;ID Not Found
MCR	equ	3	;Media Change Requested
ABRT	equ	2	;Aborted Command
NM	equ	1	;No media

M_ABRT	equ	(1 SHL ABRT)

; Bits in the head register

DEV	equ	4	;Device select: 0=master, 1=slave
LBA	equ	6	;0=use CHS mode, 1=use LBA mode

M_DEV	equ	(1 SHL DEV)
M_LBA	equ	(1 SHL LBA)

; Bits in the status register

BSY	equ	7	;Busy
DRDY	equ	6	;Device ready
DF	equ	5	;Device fault
DRQ	equ	3	;Data request
ERR	equ	0	;Error

M_BSY	equ	(1 SHL BSY)
M_DRDY	equ	(1 SHL DRDY)
M_DF	equ	(1 SHL DF)
M_DRQ	equ	(1 SHL DRQ)
M_ERR	equ	(1 SHL ERR)

; Bits in the device control register register

SRST	equ	2	;Software reset

M_SRST	equ	(1 SHL SRST)


;-----------------------------------------------------------------------------
;
; Standard BIOS and work area entries

CHPUT	equ	00A2h	;Character output
CHGET	equ	009Fh
CLS	equ	00C3h
MSXVER	equ	002Dh


;-----------------------------------------------------------------------------
;
; Work area definition
;
;+0: Device and logical units types for master device
;    bits 0,1: Device type
;              00: No device connected
;              01: ATA hard disk, CHS only
;              10: ATA hard disk, LBA supported
;              11: ATAPI device
;    bits 2,3: Device type for LUN 1 on master device
;              00: Block device
;              01: Other, non removable
;              10: CD-ROM
;              11: Other, removable
;    bits 4,5: Device type for LUN 2 on master device
;    bits 6,7: Device type for LUN 3 on master device
;
;+1: Logical unit types for master device
;    bits 0,1: Device type for LUN 4 on master device
;    bits 2,3: Device type for LUN 5 on master device
;    bits 4,5: Device type for LUN 6 on master device
;    bits 6,7: Device type for LUN 7 on master device
;
;+2,3: Reserved for CHS data for the master device (to be implemented)
;
;+4..+7: Same as +0..+3, for the slave device
;
; Note: Actually, due to driver limitations, currently only the
; "device type" bits are used, and with possible values 00 and 10 only.
; LUN type bits are always 00.


;-----------------------------------------------------------------------------
;
; Error codes for DEV_RW and DEV_FORMAT
;

NCOMP	equ	0FFh
WRERR	equ	0FEh
DISK	equ	0FDh
NRDY	equ	0FCh
DATA	equ	0FAh
RNF	equ	0F9h
WPROT	equ	0F8h
UFORM	equ	0F7h
SEEK	equ	0F3h
IFORM	equ	0F0h
IDEVL	equ	0B5h
IPARM	equ	08Bh

;-----------------------------------------------------------------------------
;
; Routines available on kernel page 0
;

;* Get in A the current slot for page 1. Corrupts F.
;  Must be called by using CALBNK to bank 0:
;  xor a
;  ld ix,GSLOT1
;  call CALBNK

GSLOT1	equ	402Dh


;* This routine reads a byte from another bank.
;  Must be called by using CALBNK to the desired bank,
;  passing the address to be read in HL:
;  ld a,bank
;  ld hl,address
;  ld ix,RDBANK
;  call CALBNK

RDBANK	equ	403Ch


;* This routine temporarily switches kernel bank 0/3,
;  then jumps to CALBAS in MSX BIOS.
;  This is necessary so that kernel bank is correct in case of BASIC error.

CALBAS	equ	403Fh


;* Call a routine in another bank.
;  Must be used if the driver spawns across more than one bank.
;  Input: A = bank
;         IX = routine address
;         AF' = AF for the routine
;         BC, DE, HL, IY = input for the routine

CALBNK	equ	4042h


;* Get in IX the address of the SLTWRK entry for the slot passed in A,
;  which will in turn contain a pointer to the allocated page 3
;  work area for that slot (0 if no work area was allocated).
;  If A=0, then it uses the slot currently switched in page 1.
;  Returns A=current slot for page 1, if A=0 was passed.
;  Corrupts F.
;  Must be called by using CALBNK to bank 0:
;  ld a,slot
;  ex af,af'
;  xor a
;  ld ix,GWORK
;  call CALBNK

GWORK	equ	4045h


;* Call a routine in the driver bank.
;  Input: (BK4_ADD) = routine address
;         AF, BC, DE, HL, IY = input for the routine
;
; Calls a routine in the driver bank. This routine is the same as CALBNK,
; except that the routine address is passed in address BK4_ADD (#F2ED)
; instead of IX, and the bank number is always 5. This is useful when used
; in combination with CALSLT to call a driver routine from outside
; the driver itself.
;
; Note that register IX can't be used as input parameter, it is
; corrupted before reaching the invoked code.

CALDRV	equ	4048h


;-----------------------------------------------------------------------------
;
; Built-in format choice strings
;

NULL_MSG  equ     741Fh	;Null string (disk can't be formatted)
SING_DBL  equ     7420h ;"1-Single side / 2-Double side"


;-----------------------------------------------------------------------------
;
; Driver signature
;
	db	"NEXTOR_DRIVER",0

; Driver flags:
;    bit 0: 0 for drive-based, 1 for device-based
;    bit 1: 1 for hot-plug devices supported (device-based drivers only)

	;db 1+(2*DRV_HOTPLUG)

    db 7

;Reserved byte
	db	0

;Driver name

DRV_NAME:
	db	"Sunrise IDE"
	ds	32-($-DRV_NAME)," "

;Jump table

	jp	DRV_TIMI
	jp	DRV_VERSION
	jp	DRV_INIT
	jp	DRV_BASSTAT
	jp	DRV_BASDEV
        jp      DRV_EXTBIO
        jp      DRV_DIRECT0
        jp      DRV_DIRECT1
        jp      DRV_DIRECT2
        jp      DRV_DIRECT3
        jp      DRV_DIRECT4
        jp  DRV_CONFIG


	ds	12

	jp	DEV_RW
	jp	DEV_INFO
	jp	DEV_STATUS
	jp	LUN_INFO
	jp	DEV_FORMAT
	jp	DEV_CMD
	


;-----------------------------------------------------------------------------
;
; Timer interrupt routine, it will be called on each timer interrupt
; (at 50 or 60Hz), but only if DRV_INIT returns Cy=1 on its first execution.

DRV_TIMI:
	ret


;-----------------------------------------------------------------------------
;
; Driver initialization, it is called twice:
;
; 1) First execution, for information gathering.
;    Input:
;      A = 0
;      B = number of available drives (drive-based drivers only)
;      HL = maximum size of allocatable work area in page 3
;    Output:
;      A = number of required drives (for drive-based driver only)
;      HL = size of required work area in page 3
;      Cy = 1 if DRV_TIMI must be hooked to the timer interrupt, 0 otherwise
;
; 2) Second execution, for work area and hardware initialization.
;    Input:
;      A = 1
;      B = number of allocated drives for this controller
;          (255 if device-based driver, unless 4 is pressed at boot)
;
;    The work area address can be obtained by using GWORK.
;
;    If first execution requests more work area than available,
;    second execution will not be done and DRV_TIMI will not be hooked
;    to the timer interrupt.
;
;    If first execution requests more drives than available,
;    as many drives as possible will be allocated, and the initialization
;    procedure will continue the normal way
;    (for drive-based drivers only. Device-based drivers always
;     get two allocated drives.)

TEMP_WORK	equ	0C000h

DRV_INIT:
	;--- If first execution, just inform that no work area is needed
	;    (the 8 bytes in SLTWRK are enough)

	or	a
	ld	hl,0
	ld	a,2
	ret	z			;Note that Cy is 0 (no interrupt hooking needed)

	;xor a
	;ld (TESTADD),a

	;--- Borra la pantalla. En los MSX1 hay que decirselo ya que no lo tiene implementado de serie.
	
	push	af ; Guarda las variables de inicio.
	push	bc
	push	hl
	;bit	0,a ; Pone a cero el flag Z
	;xor	a ; Pone a cero a
	;call	CLS
	;--- Este m�todo de borrado es mejor. Aportado por Victor.
	ld	a,40 ; 40 columnas
	ld	(0F3AEh),a
	xor	a
	call	005Fh ; Screen 0

	;--- Comprueba el bit de doble reset y lo ejecuta en caso de estar en on.
	call	IDE_ON
	ld      a,(IDE_FLASHJACKS) ; Trae el registro de Flashjacks. 
	and	11110100b ; Anula los bits de freq y deja solo la marca de comprobaci�n y el bit de reset.
	cp	0A4h ;	Comprueba marca de comprobaci�n y bit de reset
	jr	nz,CONTPRG ; No ha detectado una marca correcta del registro flashjacks por lo que no ejecuta nada del reset.
	call	IDE_OFF
	pop	hl ; Retorno de las variables de inicio.
	pop	bc 
	pop	af
	rst	0 ; Fuerza un reset. A partir de aqu� hace un soft reset y no continua con el programa.
CONTPRG:
	call	IDE_OFF
	
	;----------------------------------------------
	;Compruba las teclas F4 y F5 (VDP FREQ y fuerza TURBOCPU)
	push	af
	push	hl
	push	de
	push	bc

	; Compara tecla pulsada
	ld	b,7 ;row 7 	RET 	SELECT 	BS 	STOP 	TAB 	ESC 	F5 	F4
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	in	a,(0A9h)	
	bit	0,a ;F4 -- Si es tecla pulsada turbo va a la rutina de activaci�n del turbo.
	jr	nz,Fin_ini ; Salta si no se pulsa tecla de turbo.
	push	af
	call	putTURBO_CPU ; Ejecuta el turbo CPU.
	pop	af
Fin_ini:pop	bc
	pop	de
	pop	hl
	pop	af
	
	;--- Comienza la escritura en pantalla del driver.	
	ld	de,INFO_S
	call	PRINT
	
	;--- Saca por pantalla el modelo de ordenador.	
	ld	de,MODELO ; Escribre Modelo:
	call	PRINT
	ld      a,(MSXVER) ; Trae el registro de version de MSX de la BIOS
	cp	00h ; Si es un MSX1 realiza un salto a la escritura de MSX1.
	jr	z,IMP_MSX1 
	cp	01h ; Si es un MSX2 realiza un salto a la escritura de MSX2.
	jr	z,IMP_MSX2 
	cp	02h ; Si es un MSX2+ realiza un salto a la escritura de MSX2+.
	jr	z,IMP_MSX2M 
	cp	03h ; Si es un MSX TurboR realiza un salto a la escritura de MSX TurboR.
	jr	z,IMP_MSXR 
	cp	04h ; Si es un OCM realiza un salto a la escritura de OCM.
	jr	z,IMP_OCM 
	jp	NO_DETEC ; Si no es ninguna de las versiones mencionadas, imprime un no detectado.
IMP_MSX1:
	ld	de,M_MSX1
	call	PRINT
	jp	FIN_IMP;
IMP_MSX2:
	ld	de,M_MSX2
	call	PRINT
	jp	FIN_IMP;
IMP_MSX2M:
	ld	de,M_MSX2M
	call	PRINT
	jp	FIN_IMP;
IMP_MSXR:
	ld	de,M_MSXR
	call	PRINT
	jp	FIN_IMP;
IMP_OCM:
	ld	de,M_OCM
	call	PRINT
	jp	FIN_IMP;
NO_DETEC:
	ld	de,M_NDTC
	call	PRINT
FIN_IMP:
	pop	hl ; Retorno de las variables de inicio.
	pop	bc 
	pop	af

	;-- B�squeda de la unidad por pantalla.
	ld	de,SEARCH_S
	call	PRINT

	ld	a,1
	call	MY_GWORK
	call	IDE_ON
	ld	(ix),0			;Assume both devices empty
	ld	(ix+4),0	

        ld      a,M_SRST		;Do a software reset
        ld      (IDE_DEVCTRL),a
        nop     ;Wait 5 us
        xor     a
        ld      (IDE_DEVCTRL),a

WAIT_RESET:
        ld      de,7640			;Timeout after 30 s
WAIT_RESET1:
        ld      a,0
        cp      e
        jr      nz,WAIT_DOT		;Print dots while waiting
        ld      a,46
        call    CHPUT
WAIT_DOT:
	call	CHECK_ESC
	jp	c,INIT_NO_DEV
        ld      b,255
WAIT_RESET2:
        ld      a,(IDE_STATUS)
        and     M_BSY+M_DRDY
        cp      M_DRDY
        jr      z,WAIT_RESET_END        ;Wait for BSY to clear and DRDY to set          
        djnz    WAIT_RESET2
        dec     de
        ld      a,d
        or      e
        jr      nz,WAIT_RESET1
        jp      INIT_NO_DEV
WAIT_RESET_END:

	;--- Do a quick pre-check on MASTER device

	ld	a,0
	ld	(IDE_HEAD),a		;Select device 0
	nop

	call	INIT_PRECHECK_DEV	
	ld	a,(IDE_SECCNT)
	cp	85
	jr	nz,MASTER_CHECK1_END
	ld	a,(IDE_SECNUM)
	cp	170
	jr	nz,MASTER_CHECK1_END

	ld	a,1			;Flag the device
	ld	(ix),a
MASTER_CHECK1_END:
        ld      a,46			;Print dot
        call    CHPUT
       
        ld      a,M_SRST		; Do ANOTHER software reset
        ld      (IDE_DEVCTRL),a
        nop     			;Wait 5 us
        xor     a
        ld      (IDE_DEVCTRL),a
	nop				;Wait 5 us
        ld      a,46			;Print dot
        call    CHPUT

	ld      de,CRLF_S
        call    PRINT

	;--- Get info and show the name for the MASTER

	ld	de,MASTER_S
	call	PRINT

WSKIPMAS:			; If ESC is pressed, ignore this device
        ld      de,624			; Wait 1s to read the keyboard
WSKIPMAS1:
        call    CHECK_ESC
        jr      c,NODEV_MASTER
        ld      b,64
WSKIPMAS2:
	ex	(sp),hl
	ex	(sp),hl
        djnz    WSKIPMAS2
        dec     de
        ld      a,d
        or      e
        jr      nz,WSKIPMAS1

	ld	a,(ix)			;If the device isn't flagged it doesn't exists
	cp	1
	jr	nz,NODEV_MASTER
        ld      a,46			;Print FIRST dot
        call    CHPUT

	call	WAIT_CMD_RDY
	jr	c,NODEV_MASTER
	ld	a,0
	ld	(IDE_HEAD),a		;Select device 0
        ld      a,46			;Print SECOND dot
        call    CHPUT

	ld	a,0ECh			;Send IDENTIFY commad
	call	DO_IDE			
	jr	c,NODEV_MASTER
        ld      a,46			;Print THIRD dot
        call    CHPUT

	call	INIT_CHECK_DEV		;Check if the device is ATA or ATAPI
	jr	c,NODEV_MASTER
        ld      a,46			;Print FOURTH dot
        call    CHPUT

	call	WAIT_CMD_RDY		;Try to select the device
	jr	c,NODEV_MASTER		;this is our last chance to *NOT* detect it
	ld	a,0
	ld	(IDE_HEAD),a		;Select device 0
        ld      a,46			;Print FIFTH dot
        call    CHPUT

	call	INIT_PRINT_NAME

	ld	(ix),2	;ATA device with LBA
	jr	OK_MASTER

NODEV_MASTER:
	call	CHECK_ESC
	jr	c,NODEV_MASTER

	ld	(ix),0	
	ld	de,NODEVS_S
	call	PRINT
	
OK_MASTER:
        ld      a,M_SRST		;Last software reset before we go
        ld      (IDE_DEVCTRL),a		;some times a faulty slave leaves
					;BSY set forever (30s)
        nop     ;Wait 5 us
        xor     a
        ld      (IDE_DEVCTRL),a

	jr	DRV_INIT_END

INIT_NO_DEV:
	call	CHECK_ESC
	jr	c,INIT_NO_DEV

	ld      de,CRLF_S
        call    PRINT
	ld	de,MASTER_S
	call	PRINT
	ld	de,NODEVS_S
	call	PRINT
		
	;--- Fin del procedimiento de inicializaci�n.

DRV_INIT_END:
	ld	(ix+4),0 ; Marca que no hay unidad esclava.
	call	IDE_OFF

	;--- Retardo de espera de 2 Segundos para que se vea el texto de carga del driver en pantalla. 
	;--- Si es un MSXTurboR no lo hace. Este ya tiene retardo de por si en el arranque.
	push	de
	push	bc
	ld      a,(MSXVER) ; Trae el registro de version de MSX de la BIOS
	cp	03h ; Si es un MSX TurboR realiza un salto ya que este equipo es lento de por si al arranque.
	jr	z,ESPERA_FIN ; Omite la espera de 2s para el TurboR
	ld	de,1861	;Contador cargado para 2s
ESPERA_RDY1:
	ld	b,255
ESPERA_RDY2:
	djnz	ESPERA_RDY2	;Bucle ESPERA_RDY2
	dec	de
	ld	a,d
	or	e
	jr	nz,ESPERA_RDY1	;Bucle ESPERA_RDY1 
ESPERA_FIN:
	pop	bc
	pop	de

	;--- Codigo asistencia a la unidad FLASHJACKS. Se ejecuta despues del inicio de NEXTOR.
	call	IDE_ON
	ld      a,(MSXVER) ; Trae el registro de version de MSX de la BIOS
	cp	00h ; Si es un MSX1 salta la operaci�n de forzado del VDP por incompatibilidad del mismo.
	jr	z,DEV_FLASH_FIN 
	
	; Compara tecla pulsada
	ld	b,7 ;row 7 	RET 	SELECT 	BS 	STOP 	TAB 	ESC 	F5 	F4
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	in	a,(0A9h)	
	bit	1,a ;F5 -- Si es tecla pulsada VDP va a la rutina de permutaci�n de frecuencia.
	jp	z,DEV_VDP_FIN ; Salta la gesti�n del VDP para la permutaci�n del VDP por tecla pulsada.
	ld      a,(IDE_FLASHJACKS) ; Trae el registro de Flashjacks. 
	and	11111011b ; Anula el bit de doble reset para comparar el resto.
	cp	0A3h ;	Forzado a 60Hz. 101000 + Bit de Forzado a 1 + Bit de 60 Hz a 1
	jr	z,DEV_FLASH60 ; Salta al forzado a 60 Hz.
	cp	0A2h ;	Forzado a 50Hz. 101000 + Bit de Forzado a 1 + Bit de 50 Hz a 0
	jr	z,DEV_FLASH50 ; Salta al forzado a 50 Hz.
	jp	DEV_FLASH_FIN ; Otras opciones son ignoradas y no hace cambio alguno.

DEV_FLASH50:
	ld	a,02h ; 02h a 50hz y 00h a 60hz
	jp	DEV_FLASHVDP;

DEV_FLASH60:
	ld	a,00h ; 02h a 50hz y 00h a 60hz

DEV_FLASHVDP:
	out	(099h),a ;Salida directa del VPD
	ld	(0ffe8h), a ;Salida por BIOS del VDP registro 9
	ld	a,89h
	out	(099h),a

DEV_FLASH_FIN:
	call	IDE_OFF
	ret ; Devuelve el control.

DEV_VDP_FIN:
	; Ejecuta la permutaci�n del VDP existente
	ld	hl,0ffe8h;VDP register value
	ld	a,(hl)
	xor	2
	ld	(hl),a
	di
	out	(99h),a ;Set VDP Frequency
	ld	a,9+128
	ei
	out	(099h),a
	call	IDE_OFF
	ret ; Devuelve el control.
	
;--- Subroutines for the INIT procedure

;Check if there is any device listening in the bus
;Input: device already selected
;Output: If something is there, IDE_SECCNT=85, IDE_SECNUM=170
;	 Both variables have random values if nothing is there

INIT_PRECHECK_DEV:
	ld	a,85
	ld	(IDE_SECCNT),a
	ld	a,170
	ld	(IDE_SECNUM),a
	ld	a,170
	ld	(IDE_SECCNT),a
	ld	a,85
	ld	(IDE_SECNUM),a
	ld	a,85
	ld	(IDE_SECCNT),a
	ld	a,170
	ld	(IDE_SECNUM),a
	ret

;Check that a device is present and usable.
;Input:  IDENTIFY DEVICE issued successfully.
;Output: Cy=0 for device ok, 1 for no device or not usable.
;        If device ok, 50 first bytes of IDENTIFY device copied to TEMP_WORK.

INIT_CHECK_DEV:
	ld	hl,IDE_DATA
	ld	de,TEMP_WORK
	ld	bc,50*2	;Get the first 50 data words
	ldir

	ld	a,(IDE_STATUS)		;Check status
	cp	01111111b		;Usually this means "no device"
	jr	z,INIT_CHECK_NODEV

	; "At power-up or after reset, the Command Block Registers are initialized 
	;  to the following values:
	;
	; 	REGISTER          VALUE
	; 	1F1 Error         : 01
	; 	1F2 Sector Count  : 01
	; 	1F3 Sector Number : 01
	; 	1F4 Cylinder Low  : 00
	; 	1F5 Cylinder High : 00
	; 	1F6 Drive / Head  : 00"
	;
	; Not all devices respect this. One of my CompactFlash cards never have
	; Sector Count = 01 and Sector Number = 01 after reset.
	;
	;	ld	a,(IDE_SECNUM)		;Test if the device is REALLY here
	;	cp	1
	;	jr	nz,INIT_CHECK_NODEV
	;	ld	a,(IDE_SECCNT)
	;	cp	1
	;	jr	nz,INIT_CHECK_NODEV

	ld	a,(IDE_CYLOW)		;Test for PATAPI devices
	cp	20 
	jr	nz,TEST2_FOR_ATAPI
	ld	a,(IDE_CYHIGH)
	cp	235
	jr	z,INIT_CHECK_NODEV
TEST2_FOR_ATAPI:
	ld	a,(IDE_CYLOW)		;Test for SATAPI devices
	cp	105
	jr	nz,TEST_FOR_ATA
	ld	a,(IDE_CYHIGH)
	cp	150
	jr	z,INIT_CHECK_NODEV

TEST_FOR_ATA:
	ld	a,(IDE_CYLOW)		;Test for PATA devices
	cp	0
	jr	nz,TEST2_FOR_ATA
	ld	a,(IDE_CYHIGH)
	cp	0
	jr	z,TEST_FOR_LBA
TEST2_FOR_ATA:
	ld	a,(IDE_CYLOW)		;Test for SATA devices
	cp	60
	jr	nz,INIT_CHECK_NODEV
	ld	a,(IDE_CYHIGH)
	cp	195
	jr	nz,INIT_CHECK_NODEV
	
TEST_FOR_LBA:
	ld      a,(TEMP_WORK+49*2+1)
	and	2			;LBA supported?
	jr	z,INIT_CHECK_NODEV
	xor	a
	ret

INIT_CHECK_NODEV:
	scf
	ret


;Print a device name.
;Input: 50 first bytes of IDENTIFY device on TEMP_WORK.

INIT_PRINT_NAME:
	ld	hl,TEMP_WORK+27*2
	ld	b,20
DEVNAME_LOOP:
	ld	c,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	call	CHPUT
	ld	a,c
	call	CHPUT
	djnz	DEVNAME_LOOP

	ld	de,CRLF_S
	call	PRINT
	ret


;-----------------------------------------------------------------------------
;
; Obtain driver version
;
; Input:  -
; Output: A = Main version number
;         B = Secondary version number
;         C = Revision number

DRV_VERSION:
	ld	a,VER_MAIN
	ld	b,VER_SEC
	ld	c,VER_REV
	ret


;-----------------------------------------------------------------------------
;
; BASIC expanded statement ("CALL") handler.
; Works the expected way, except that CALBAS in kernel page 0
; must be called instead of CALBAS in MSX BIOS.

DRV_BASSTAT:
	scf
	ret


;-----------------------------------------------------------------------------
;
; BASIC expanded device handler.
; Works the expected way, except that CALBAS in kernel page 0
; must be called instead of CALBAS in MSX BIOS.

DRV_BASDEV:
	scf
	ret


;-----------------------------------------------------------------------------
;
; Extended BIOS hook.
; Works the expected way, except that it must return
; D'=1 if the old hook must be called, D'=0 otherwise.
; It is entered with D'=1.

DRV_EXTBIO:
	ret


;-----------------------------------------------------------------------------
;
; Direct calls entry points.
; Calls to addresses 7450h, 7453h, 7456h, 7459h and 745Ch
; in kernel banks 0 and 3 will be redirected
; to DIRECT0/1/2/3/4 respectively.
; Receives all register data from the caller except IX and AF'.

DRV_DIRECT0:
DRV_DIRECT1:
DRV_DIRECT2:
DRV_DIRECT3:
DRV_DIRECT4:
	ret



;-----------------------------------------------------------------------------
;
; Get driver configuration
;
; Input: ;   A = Configuration index ;   BC, DE, HL = Depends on the configuration
;
; Output: ;   A = 0: Ok ;       1: Configuration not available for the supplied index
;   BC, DE, HL = Depends on the configuration
;
; * Get number of drives at boot time (for device-based drivers only):
;   Input: ;     A = 1 ;     B = 0 for DOS 2 mode, 1 for DOS 1 mode
;   Output: ;     B = number of drives
;
; * Get default configuration for drive
;   Input: ;     A = 2 ;     B = 0 for DOS 2 mode, 1 for DOS 1 mode ;     C = Relative drive number at boot time
;   Output: ;     B = Device index ;     C = LUN index


DRV_CONFIG:
    dec a
    jr  z,.GetNumDrives
    dec a
    jr  z,.GetRelDrvNum
.error:
    ld  a,1         ; Unknown configuration index
    ret

.GetNumDrives:
    bit 5,c         ;Single drive per driver requested?
    ld b,1
    ;ld a,0 ; A already zero here
    ret nz

    ld  b,8   ; num of partitions on my SD hardcoded
    ;xor a ; A already zero here
    ret

.GetRelDrvNum:
    ld b, 1
    ld  c,b
    ;xor a ; A already zero here
    ret


;=====
;=====  BEGIN of DEVICE-BASED specific routines
;=====

;-----------------------------------------------------------------------------
;
; Read or write logical sectors from/to a logical unit
;
;Input:    Cy=0 to read, 1 to write
;          A = Device number, 1 to 7
;          B = Number of sectors to read or write
;          C = Logical unit number, 1 to 7
;          HL = Source or destination memory address for the transfer
;          DE = Address where the 4 byte sector number is stored
;Output:   A = Error code (the same codes of MSX-DOS are used):
;              0: Ok
;              .IDEVL: Invalid device or LUN
;              .NRDY: Not ready
;              .DISK: General unknown disk error
;              .DATA: CRC error when reading
;              .RNF: Sector not found
;              .UFORM: Unformatted disk
;              .WPROT: Write protected media, or read-only logical unit
;              .WRERR: Write error
;              .NCOMP: Incompatible disk
;              .SEEK: Seek error
;          B = Number of sectors actually read/written

DEV_RW:
	
	push	af

	ld	a,b	;Swap B and C
	ld	b,c
	ld	c,a
	pop	af
	push	af
	push	bc
	call	CHECK_DEV_LUN
	pop	bc
	jp	c,DEV_RW_NODEV

	dec	a
	jr	z,DEV_RW2
	ld	a,M_DEV
DEV_RW2:
	ld	b,a

	ld	a,c
	or	a
	jr	nz,DEV_RW_NO0SEC
	pop	af
	xor	a
	ld	b,0
	ret	
DEV_RW_NO0SEC:

	push	de
	pop	ix
	ld	a,(ix+3)
	and	11110000b
	jp	nz,DEV_RW_NOSEC	;Only 28 bit sector numbers supported

	call	IDE_ON

	ld	a,(ix+3)
	or	M_LBA
	or	b
	di ; Se desactivan peticiones de interrupciones para evitar intromisiones.
	ld	(IDE_HEAD),a	;IDE_HEAD must be written first,
	ld	(IDE_HEAD),a	; Se duplica env�o de comando para refrescar sin error la FLASHJACKS.
	ld	a,(ix)		;or the other IDE_LBAxxx and IDE_SECCNT
	ld	(IDE_LBALOW),a	;registers will not get a correct value
	ld	(IDE_LBALOW),a	; Se duplica env�o de comando para refrescar sin error la FLASHJACKS.
	ld	a,(ix+1)	;(blueMSX issue?)
	ld	(IDE_LBAMID),a  ; Se duplica env�o de comando para refrescar sin error la FLASHJACKS.
	ld	(IDE_LBAMID),a
	ld	a,(ix+2)
	ld	(IDE_LBAHIGH),a  ; Se duplica env�o de comando para refrescar sin error la FLASHJACKS.
	ld	(IDE_LBAHIGH),a
	ld	a,c
	ld	(IDE_SECCNT),a  ; Se duplica env�o de comando para refrescar sin error la FLASHJACKS.
	ld	(IDE_SECCNT),a
	
	pop	af
	jr	c,DEV_DO_WR

	;---
	;---  READ
	;---
	
	call	WAIT_CMD_RDY
	jr	c,DEV_RW_ERR
	ld	a,20h
	push	bc	;Save sector count
	call	DO_IDE
	pop	bc
	jr	c,DEV_RW_ERR

	call	DEV_RW_FAULT
	ret	nz

	ld	b,c	;Retrieve sector count
	ex	de,hl
DEV_R_GDATA:
	push	bc
	ld	hl,IDE_DATA
	ld	bc,512

BUCLE_R_GDATA:
	di ; Se desactivan peticiones de interrupciones para evitar intromisiones.
	ld	a,(IDE_STATUS)
	bit	BSY,a
	jr	nz,BUCLE_R_GDATA ; Hace una comprobaci�n al inicio y deja paso cuando la FLASHJACKS informa que puede continuar.
	;ld	a,(hl) ; Esto est� anulado ya que se trata del mismo proceso que hace ldir pero en muchos mas ciclos de reloj. Proceso muy lento.
	;ld	(de),a
	;inc	hl
	;inc	de
	;dec	bc
	;ld	a,b
	;or	c
	;jr	nz,BUCLE_R_GDATA ; Esto est� anulado ya que se trata del mismo proceso que hace ldir pero en muchos mas ciclos de reloj.

	;ldir ; Volcado ultrar�pido. Usar el del LDI(mas abajo) si se reportan anomal�as (Psycho world en DSK es bueno para probarlo).
	;CALL	VOLCADO ; Es un ldir un 21% m�s r�pido.


BUCLE_R2_GDATA:
	ldi  ; 8x LDI + 8x nop Hacemos una espera en cada byte de volcado para dejar a la Flashjacks que se refresque a tiempo.(En un manual de asm es un modo r�pido de copia)
	nop  ; Esto solo es para sistemas ultra r�pidos como el TurboR. Esto hace lectura y ciclo refresco, bucle hasta fin.
	ldi  ; Es el m�todo m�s estable. (pero no el m�s r�pido. Mas r�pido ldir y a�n m�s call VOLCADO) 
	nop  ; Los otros funcionan pero cuando hay algo en el otro slot, provoca fallos. (Ejemplo Music module slot 1 y FlashJacks slot 2)
	ldi
	nop
	ldi
	nop
	ldi
	nop
	ldi
	nop
	ldi
	nop
	ldi
	nop
	jp pe,BUCLE_R2_GDATA

BUCLE_R_FIN:	
	ld	a,(IDE_STATUS)
	bit	BSY,a
	jr	nz,BUCLE_R_FIN ; Hace una comprobaci�n al final y deja paso cuando la FLASHJACKS informa que puede continuar.
	pop	bc
	call	WAIT_IDE
	
	dec	b
	jp	nz,DEV_R_GDATA
	call	IDE_OFF
	xor	a
	ret
	
	;---
	;---  WRITE
	;---

DEV_DO_WR:
	call	WAIT_CMD_RDY
	jr	c,DEV_RW_ERR
	ld	a,30h
	push	bc	;Save sector count
	call	DO_IDE
	pop	bc
	jr	c,DEV_RW_ERR

	ld	b,c	;Retrieve sector count
DEV_W_LOOP:
	push	bc
	ld	de,IDE_DATA
	ld	bc,512
	ldir ; Se deja ldir por mayor estabilidad.
	;CALL	VOLCADO ; Es un ldir un 21% m�s r�pido.(Por estabilidad se quita)
	pop	bc

	call	WAIT_IDE
	jr	c,DEV_RW_ERR

	call	DEV_RW_FAULT
	ret	nz
	
	dec	b	
	jp	nz,DEV_W_LOOP

	call	IDE_OFF
	xor	a
	ret

	;---
	;---  ERROR ON READ/WRITE
	;---

DEV_RW_ERR:
	ld	a,(IDE_ERROR)
	ld	b,a
	call	IDE_OFF
	ld	a,b	

	bit	NM,a	;Not ready
	jr	nz,DEV_R_ERR1
	ld	a,NRDY
	ld	b,0
	ret
DEV_R_ERR1:

	bit	IDNF,a	;Sector not found
	jr	nz,DEV_R_ERR2
	ld	a,RNF
	ld	b,0
	ret
DEV_R_ERR2:

	bit	WP,a	;Write protected
	jr	nz,DEV_R_ERR3
	ld	a,WPROT
	ld	b,0
	ret
DEV_R_ERR3:

	ld	a,DISK	;Other error
	ld	b,0
	ret

	;--- Check for device fault
	;    Output: NZ and A=.DISK on fault

DEV_RW_FAULT:
	ld	a,(IDE_STATUS)
	and	M_DF	;Device fault
	ret	z

	call	IDE_OFF
	ld	a,DISK
	ld	b,0
	or	a
	ret

	;--- Termination points

DEV_RW_NOSEC:
	call	IDE_OFF
	pop	af
	ld	a,RNF
	ld	b,0
	ret

DEV_RW_NODEV:
	call	IDE_OFF
	pop	af
	ld	a,IDEVL
	ld	b,0
	ret

;-----------------------------------------------------------------------------
;
; Device information gathering
;
;Input:   A = Device index, 1 to 7
;         B = Information to return:
;             0: Basic information
;             1: Manufacturer name string
;             2: Device name string
;             3: Serial number string
;         HL = Pointer to a buffer in RAM
;Output:  A = Error code:
;             0: Ok
;             1: Device not available or invalid device index
;             2: Information not available, or invalid information index
;         When basic information is requested,
;         buffer filled with the following information:
;
;+0 (1): Numer of logical units, from 1 to 8. 1 if the device has no logical
;        drives (which is functionally equivalent to having only one).
;+1 (1): Flags, always zero
;
; The strings must be printable ASCII string (ASCII codes 32 to 126),
; left justified and padded with spaces. All the strings are optional,
; if not available, an error must be returned.
; If a string is provided by the device in binary format, it must be reported
; as an hexadecimal, upper-cased string, preceded by the prefix "0x".
; The maximum length for a string is 64 characters;
; if the string is actually longer, the leftmost 64 characters
; should be provided.
;
; In the case of the serial number string, the same rules for the strings
; apply, except that it must be provided right-justified,
; and if it is too long, the rightmost characters must be
; provided, not the leftmost.

DEV_INFO:
	or	a	;Check device index
	jr	z,DEV_INFO_ERR1
	cp	3
	jr	nc,DEV_INFO_ERR1

	call	MY_GWORK

	ld	c,a
	ld	a,b
	or	a
	jr	nz,DEV_INFO_STRING

	;--- Obtain basic information

	ld	a,(ix)
	or	a	;Device available?
	jr	z,DEV_INFO_ERR1

	ld	(hl),1	;One single LUN
	inc	hl
	ld	(hl),0	;Always zero
	xor	a
	ret

	;--- Obtain string information

DEV_INFO_STRING:
	push	hl
	push	bc
	push	hl
	pop	de
	inc	de
	ld	(hl)," "
	ld	bc,64-1
	ldir
	pop	bc
	pop	hl

	call	IDE_ON

	ld	a,c
	dec	a
	jr	z,DEV_INFO_STRING2
	ld	a,M_DEV

DEV_INFO_STRING2:
	ld	c,a	;C=Device flag for the HEAD register
	ld	a,b

	dec	a
	jr	z,DEV_INFO_ERR2	;Manufacturer name

	;--- Device name

	dec	a
	jr	nz,DEV_STRING_NO1

	ld	b,27
	call	DEV_STING_PREPARE
	jr	c,DEV_INFO_ERR1

	ld	b,20
DEV_STRING_LOOP:
	ld	de,(IDE_DATA)
	ld	a,d
	cp	33
	jr	nc,DEVSTRLOOP_1
	cp	126
	jr	c,DEVSTRLOOP_1
	ld	a," "
DEVSTRLOOP_1:
	ld	(hl),a
	inc	hl
	ld	a,e
	cp	33
	jr	nc,DEVSTRLOOP_2
	cp	126
	jr	c,DEVSTRLOOP_2
	ld	a," "
DEVSTRLOOP_2:
	ld	(hl),a
	inc	hl
	djnz	DEV_STRING_LOOP

	call	IDE_OFF
	xor	a
	ret

DEV_STRING_NO1:

	;--- Serial number

	dec	a
	jr	nz,DEV_INFO_ERR2	;Unknown string

	ld	b,10
	call	DEV_STING_PREPARE
	jr	c,DEV_INFO_ERR1

	ld	bc,44
	add	hl,bc	;Since the string is 20 chars long
	ld	b,10
	jr	DEV_STRING_LOOP
	
	;--- Termination with error

DEV_INFO_ERR1:
	call	IDE_OFF
	ld	a,1
	ret

DEV_INFO_ERR2:
	call	IDE_OFF
	ld	a,2
	ret



;Common processing for obtaining a device information string
;Input: B  = Offset of the string in the device information (words)
;       HL = Destination address for the string
;       C  = Device flag for the HEAD register
;Corrupts AF, DE

DEV_STING_PREPARE:
	call	WAIT_CMD_RDY
	ld	a,c		;Issue IDENTIFY DEVICE command
	ld	(IDE_HEAD),a
	ld	a,0ECh
	call	DO_IDE
	ret	c

	push	hl		;Fill destination with spaces
	push	bc
	push	hl
	pop	de
	inc	de
	ld	(hl)," "
	ld	bc,64-1
	ldir
	pop	bc
	pop	hl

DEV_STRING_SKIP:
	ld	de,(IDE_DATA)	;Skip device data until the desired string
	djnz	DEV_STRING_SKIP

	ret


;-----------------------------------------------------------------------------
;
; Obtain device status
;
;Input:   A = Device index, 1 to 7
;         B = Logical unit number, 1 to 7.
;             0 to return the status of the device itself.
;Output:  A = Status for the specified logical unit,
;             or for the whole device if 0 was specified:
;                0: The device or logical unit is not available, or the
;                   device or logical unit number supplied is invalid.
;                1: The device or logical unit is available and has not
;                   changed since the last status request.
;                2: The device or logical unit is available and has changed
;                   since the last status request
;                   (for devices, the device has been unplugged and a
;                    different device has been plugged which has been
;                    assigned the same device index; for logical units,
;                    the media has been changed).
;                3: The device or logical unit is available, but it is not
;                   possible to determine whether it has been changed
;                   or not since the last status request.
;
; Devices not supporting hot-plugging must always return status value 1.
; Non removable logical units may return values 0 and 1.

DEV_STATUS:
	set	0,b	;So that CHECK_DEV_LUN admits B=0

	call	CHECK_DEV_LUN
	ld	e,a
	ld	a,0
	ret	c

	ld	a,1	;Never changed
	ret

	;ld	a,1
	;ret

	ld	a,e
	cp	2
	ld	a,1
	ret	nz

	ld	a,e
	dec	a	;FOR TESTING:
	ld	a,2	;Return "Unchanged" for device 1, "Unknown" for device 2
	ret	z
	ld	a,3
	ret


;-----------------------------------------------------------------------------
;
; Obtain logical unit information
;
;Input:   A  = Device index, 1 to 7.
;         B  = Logical unit number, 1 to 7.
;         HL = Pointer to buffer in RAM.
;Output:  A = 0: Ok, buffer filled with information.
;             1: Error, device or logical unit not available,
;                or device index or logical unit number invalid.
;         On success, buffer filled with the following information:
;
;+0 (1): Medium type:
;        0: Block device
;        1: CD or DVD reader or recorder
;        2-254: Unused. Additional codes may be defined in the future.
;        255: Other
;+1 (2): Sector size, 0 if this information does not apply or is
;        not available.
;+3 (4): Total number of available sectors.
;        0 if this information does not apply or is not available.
;+7 (1): Flags:
;        bit 0: 1 if the medium is removable.
;        bit 1: 1 if the medium is read only. A medium that can dinamically
;               be write protected or write enabled is not considered
;               to be read-only.
;        bit 2: 1 if the LUN is a floppy disk drive.
;+8 (2): Number of cylinders (0, if not a hard disk)
;+10 (1): Number of heads (0, if not a hard disk)
;+11 (1): Number of sectors per track (0, if not a hard disk)

LUN_INFO:
	call	CHECK_DEV_LUN
	jp	c,LUN_INFO_ERROR

	ld	b,a
	call	IDE_ON
	ld	a,b

	push	hl
	pop	ix

	dec	a
	jr	z,LUN_INFO2
	ld	a,M_DEV
LUN_INFO2:
	ld	e,a
	call	WAIT_CMD_RDY	
	jr	c,LUN_INFO_ERROR
	ld	a,e

	ld	(IDE_HEAD),a

	ld	a,0ECh
	call	DO_IDE
	jr	c,LUN_INFO_ERROR

	;Set cylinders, heads, and sectors/track

	ld	hl,(IDE_DATA)	;Skip word 0
	ld	hl,(IDE_DATA)
	ld	(ix+8),l	;Word 1: Cylinders
	ld	(ix+9),h
	ld	hl,(IDE_DATA)	;Skip word 2
	ld	hl,(IDE_DATA)
	ld	(ix+10),l	;Word 3: Heads
	ld	hl,(IDE_DATA)
	ld	hl,(IDE_DATA)	;Skip words 4,5
	ld	hl,(IDE_DATA)
	ld	(ix+11),l	;Word 6: Sectors/track

	;Set maximum sector number

	ld	b,60-7	;Skip until word 60
LUN_INFO_SKIP1:
	ld	de,(IDE_DATA)
	djnz	LUN_INFO_SKIP1

	ld	de,(IDE_DATA)	;DE = Low word
	ld	hl,(IDE_DATA)	;HL = High word

	ld	(ix+3),e
	ld	(ix+4),d
	ld	(ix+5),l
	ld	(ix+6),h

	;Set sector size

	ld	b,117-62	;Skip until word 117
LUN_INFO_SKIP2:
	ld	de,(IDE_DATA)
	djnz	LUN_INFO_SKIP2

	ld	de,(IDE_DATA)	;DE = Low word
	ld	hl,(IDE_DATA)	;HL = High word

	ld	a,h	;If high word not zero, set zero (info not available)
	or	l
	ld	hl,0
	jr	nz,LUN_INFO_SSIZE

	ld	a,d
	or	e
	jr	nz,LUN_INFO_SSIZE
	ld	de,512	;If low word is zero, assume 512 bytes
LUN_INFO_SSIZE:
	ld	(ix+1),e
	ld	(ix+2),d

	;Set other parameters

	ld	(ix),0	;Block device
	ld	(ix+7),0	;Non removable device nor LUN

	call	IDE_OFF
	xor	a
	ret

LUN_INFO_ERROR:
	call	IDE_OFF
	ld	a,1
	ret


;-----------------------------------------------------------------------------
;
; Physical format a device
;
;Input:   A = Device index, 1 to 7
;         B = Logical unit number, 1 to 7
;         C = Format choice, 0 to return choice string
;Output:
;        When C=0 at input:
;        A = 0: Ok, address of choice string returned
;            .IFORM: Invalid device or logical unit number,
;                    or device not formattable
;        HL = Address of format choice string (in bank 0 or 3),
;             only if A=0 returned.
;             Zero, if only one choice is available.
;
;        When C<>0 at input:
;        A = 0: Ok, device formatted
;            Other: error code, same as DEV_RW plus:
;            .IPARM: Invalid format choice
;            .IFORM: Invalid device or logical unit number,
;                    or device not formattable
;        B = Media ID if the device is a floppy disk, zero otherwise
;            (only if A=0 is returned)
;
; Media IDs are:
; F0h: 3.5" Double Sided, 80 tracks per side, 18 sectors per track (1.44MB)
; F8h: 3.5" Single sided, 80 tracks per side, 9 sectors per track (360K)
; F9h: 3.5" Double sided, 80 tracks per side, 9 sectors per track (720K)
; FAh: 5.25" Single sided, 80 tracks per side, 8 sectors per track (320K)
; FBh: 3.5" Double sided, 80 tracks per side, 8 sectors per track (640K)
; FCh: 5.25" Single sided, 40 tracks per side, 9 sectors per track (180K)
; FDh: 5.25" Double sided, 40 tracks per side, 9 sectors per track (360K)
; FEh: 5.25" Single sided, 40 tracks per side, 8 sectors per track (160K)
; FFh: 5.25" Double sided, 40 tracks per side, 8 sectors per track (320K)

DEV_FORMAT:
	ld	a,IFORM
	ret


;-----------------------------------------------------------------------------
;
; Execute direct command on a device
;
;Input:    A = Device number, 1 to 7
;          B = Logical unit number, 1 to 7 (if applicable)
;          HL = Address of input buffer
;          DE = Address of output buffer, 0 if not necessary
;Output:   Output buffer appropriately filled (if applicable)
;          A = Error code:
;              0: Ok
;              1: Invalid device number or logical unit number,
;                 or device not ready
;              2: Invalid or unknown command
;              3: Insufficient output buffer space
;              4-15: Reserved
;              16-255: Device specific error codes
;
; The first two bytes of the input and output buffers must contain the size
; of the buffer, not incuding the size bytes themselves.
; For example, if 16 bytes are needed for a buffer, then 18 bytes must
; be allocated, and the first two bytes of the buffer must be 16, 0.

DEV_CMD:
	ld	a,2
	ret

;=====
;=====  END of DEVICE-BASED specific routines
;=====


;=======================
; Subroutines
;=======================

;-----------------------------------------------------------------------------
;
; Enable or disable the IDE registers

;Note that bank 7 (the driver code bank) must be kept switched

IDE_ON:
	ld	a,1+7*32
	ld	(IDE_BANK),a
	ret

IDE_OFF:
	ld	a,7*32
	ld	(IDE_BANK),a
	ret

;-----------------------------------------------------------------------------
;
; Wait the BSY flag to clear and RDY flag to be set
; if we wait for more than 30s, send a soft reset to IDE BUS
; if the soft reset didn't work after 30s return with error
;
; Input:  Nothing
; Output: Cy=1 if timeout after soft reset 
; Preserves: DE and BC

WAIT_CMD_RDY:
	push	de
	push	bc
	ld	de,8142		;Limit the wait to 30s
WAIT_RDY1:
	ld	b,255
WAIT_RDY2:
	ld	a,(IDE_STATUS)
	and	M_BSY+M_DRDY
	cp	M_DRDY
	jr	z,WAIT_RDY_END	;Wait for BSY to clear and DRDY to set		
	djnz	WAIT_RDY2	;End of WAIT_RDY2 loop
	dec	de
	ld	a,d
	or	e
	jr	nz,WAIT_RDY1	;End of WAIT_RDY1 loop
	scf
WAIT_RDY_END:
	pop	bc
	pop	de
	ret	
	
;-----------------------------------------------------------------------------
;
; Execute a command
;
; Input:  A = Command code
;         Other command registers appropriately set
; Output: Cy=1 if ERR bit in status register set

DO_IDE: di
	ld	(IDE_CMD),a ; Se duplica env�o de comando para refrescar sin error la FLASHJACKS.
	ld	(IDE_CMD),a 

WAIT_IDE:
	nop	; Wait 50us
	nop	; Wait 50us
	ld	a,(IDE_STATUS)
	bit	DRQ,a
	jr	nz,IDE_END
	bit	BSY,a
	jr	nz,WAIT_IDE

IDE_END:
	rrca
	ret

;-----------------------------------------------------------------------------
;
; Read the keyboard matrix to see if ESC is pressed
; Output: Cy = 1 if pressed, 0 otherwise

CHECK_ESC:
	ld	b,7
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	in	a,(0A9h)	
	bit	2,a
	jr	nz,CHECK_ESC_END
	scf
CHECK_ESC_END:
	ret

;-----------------------------------------------------------------------------
;
; Print a zero-terminated string on screen
; Input: DE = String address

PRINT:
	ld	a,(de)
	or	a
	ret	z
	call	CHPUT
	inc	de
	jr	PRINT


;-----------------------------------------------------------------------------
;
; Obtain the work area address for the driver
; Input: A=1  to obtain the work area for the master, 2 for the slave
; Preserves A

MY_GWORK:
	push	af
	xor	a
	EX AF,AF'
	XOR A
	LD IX,GWORK
	call CALBNK
	pop	af
	cp	1
	ret	z
	inc	ix
	inc	ix
	inc	ix
	inc	ix
	ret


;-----------------------------------------------------------------------------
;
; Check the device index and LUN
; Input:  A = device index, B = lun
; Output: Cy=0 if OK, 1 if device or LUN invalid
;         IX = Work area for the device
; Modifies F, C

CHECK_DEV_LUN:
	or	a	;Check device index
	scf
	ret	z
	cp	3
	ccf
	ret	c

	ld	c,a
	ld	a,b	;Check LUN number
	cp	1
	ld	a,c
	scf
	ret	nz

	push	hl
	push	de
	call	MY_GWORK
	pop	de
	pop	hl
	ld	c,a
	ld	a,(ix)
	or	a
	ld	a,c
	scf
	ret	z

	or	a
	ret

;-----------------------------------------------------------------------------
;
; Hace un volcado de 512 bytes.
VOLCADO:
	REPT 512 ; esto es un 21% m�s r�pido que el ldi
	ldi
	ENDM
	ret

;----------------------------------------------------------------------------------
;Turn On Turbo CPU: MSX CIEL, Panasonic 2+,Panasonic Turbo R, special TurboCPU kits
;
;Input:	Nothing
;Output: Nothing 

putTURBO_CPU:
	
CHGTURCIEL	equ	01387h	; CIEL Expert3 bizarre turbo routine

_TURBO3:
;	; Expert 3 CIEL	
;	; Test if the CIEL change-turbo routine signature is in ROM
	ld	hl,CHGTURCIEL
	ld	de,CIELSIGN
	ld	c,2

_CIEL1:	ld	b,3
_CIEL2: ld	a,(hl)
	ld	ixh,a
	ld	a,(de)
	cp	ixh
	jr	nz,NOTCIEL
	inc	hl
	inc	de
	djnz	_CIEL2
	ld	hl,CHGTURCIEL+0Ch
	dec	c
	ld	a,c
	or	a
	jr	nz,_CIEL2
	call	CHGTURCIEL
	db	1	; Padding to make the CIELSIGN inert
CIELSIGN:	DEFB	0A7h,0FAh,093h,013h,0DBh,0B6h

NOTCIEL:			
	
;------------------------------------------------------------------------------			
				;Check for Panasonic 2+
	LD	A,8
	OUT 	(040H),A	;out the manufacturer code 8 (Panasonic) to I/O port 40h
	IN	A,(040H)	;read the value you have just written
	CPL			;complement all bits of the value
	CP	8		;if it does not match the value you originally wrote,
	JR	NZ,Not_WX	;it is not a WX/WSX/FX.
	XOR	A		;write 0 to I/O port 41h
	OUT	(041H),A	;and the mode changes to high-speed clock
	
		
	jr	end_turbo

Not_WX:  ld	a,(0180h)	;Turbo R or Turbo CPU kits with JUMP in 0180h
	cp	0c3h
		;no_turbo
	jr	nz,end_turbo
	ld	a,081h		;ROM Mode... for DRAM Mode-> 82h
	call	0180h

end_turbo:

	ret
;---------------------------------------------------------------


;=======================
; Strings
;=======================

INFO_S:
	db	"FLASHJACKS IDE driver v"
	db	VER_MAIN+"0",".",VER_SEC+"0",".",VER_REV+"0",13,10
	db	"(c) Konamiman  2009",13,10
	db	"(c) Aquijacks  2018",13,10,13,10,0

SEARCH_S:
	db	"Buscando: ",0

NODEVS_S:
	db	"No encontrada",13,10,0
MASTER_S:
	db	"Unidad: ",0
CRLF_S:
	db	13,10,0
MODELO:
	db	"Modelo: ",0
M_MSX1:
	db	"MSX1",13,10,13,10,0
M_MSX2:
	db	"MSX2",13,10,13,10,0
M_MSX2M:
	db	"MSX2+",13,10,13,10,0
M_MSXR:
	db	"MSX TurboR",13,10,13,10,0
M_OCM:
	db	"OCM",13,10,13,10,0
M_NDTC:
	db	"No detectado",13,10,13,10,0


;-----------------------------------------------------------------------------
;
; Padding up to the required driver size

DRV_END:

	ds	3ED0h-(DRV_END - DRV_START)

	end


