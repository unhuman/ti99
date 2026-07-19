	'
	' crashbug -- minimal reproducer for a suspected CVBasic TMS9900
	' code-generation / layout bug.
	'
	' It does nothing but paint the screen from a DATA opcode stream in a
	' GOSUB'd routine (many VPOKEs, an ON GOTO dispatch, backward GOTOs to
	' a common loop head), then -- if that routine RETURNS -- the main loop
	' fills row 0 with solid blocks as an "init returned OK" marker.
	'
	' A large PADDING DATA block at the end pushes the program into the 3rd
	' cart bank. At certain sizes the paint routine is silently corrupted
	' partway through: it never returns, so row 0 stays BLANK and only a
	' partial pattern is drawn. Below ~2 banks it always works.
	'
	CLS
	BORDER 1
	VDP(1) = $E2
	DEFINE CHAR 128,1,cpat
	DEFINE COLOR 128,1,ccol

	GOSUB build

top:
	WAIT
	' Marker: build() returned -> paint a full row 0 (24 solid blocks).
	#va = $1800
	FOR i = 1 TO 24
		VPOKE #va,128
		#va = #va + 1
	NEXT i
	GOTO top

	'
	' ---- build(): DATA-driven VPOKE painter (the suspect construct) ----
	'
build:
	RESTORE bdata
bnext:
	READ BYTE op
	IF op = 0 THEN RETURN
	IF op = 1 THEN
		' horizontal run
		READ BYTE r
		READ BYTE c
		READ BYTE n
		#va = $1800 + r * 32 + c
		FOR i = 1 TO n
			VPOKE #va,128
			#va = #va + 1
		NEXT i
		GOTO bnext
	END IF
	IF op = 2 THEN
		' vertical run
		READ BYTE c
		READ BYTE r
		READ BYTE n
		#va = $1800 + r * 32 + c
		FOR i = 1 TO n
			VPOKE #va,128
			#va = #va + 32
		NEXT i
		GOTO bnext
	END IF
	' op = 5: single-cell object, dispatched by a 12-way ON GOTO
	' (CVBasic ON GOTO is 0-based, so subtract 1).
	READ BYTE t
	t = t - 1
	ON t GOTO ha,hb,hc,hd,he,hf,hg,hh,hi,hj,hk,hl
	GOTO bnext

ha:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hb:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hc:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hd:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
he:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hf:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hg:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hh:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hi:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hj:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hk:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext
hl:
	READ BYTE r
	READ BYTE c
	#va = $1800 + r * 32 + c
	VPOKE #va,128
	GOTO bnext

	'
	' ---- The opcode stream: paints a lattice + some single cells ----
	'
bdata:
	DATA BYTE 1, 4,2,28
	DATA BYTE 1, 8,2,28
	DATA BYTE 1, 12,2,28
	DATA BYTE 1, 16,2,28
	DATA BYTE 1, 20,2,28
	DATA BYTE 2, 6,4,17
	DATA BYTE 2, 14,4,17
	DATA BYTE 2, 22,4,17
	DATA BYTE 5,1, 5,10
	DATA BYTE 5,2, 6,12
	DATA BYTE 5,3, 7,14
	DATA BYTE 5,4, 9,16
	DATA BYTE 5,5, 10,18
	DATA BYTE 5,6, 11,20
	DATA BYTE 5,7, 13,10
	DATA BYTE 5,8, 14,12
	DATA BYTE 5,9, 15,14
	DATA BYTE 5,10, 17,16
	DATA BYTE 5,11, 18,18
	DATA BYTE 5,12, 19,20
	DATA BYTE 0

cpat:
	DATA BYTE 255,255,255,255,255,255,255,255
ccol:
	DATA BYTE 241,241,241,241,241,241,241,241
