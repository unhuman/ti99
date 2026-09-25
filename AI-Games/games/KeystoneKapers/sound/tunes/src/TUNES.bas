	' ======================================================================
	' KEYSTONE TUNES -- a music bench for Keystone Kapers
	' ======================================================================
	' The third bench beside `testsounds` and `colecosounds`. Those audition
	' sound EFFECTS; this one auditions candidate SONGS, as variations to
	' choose between before any of them goes into the game.
	'
	' The songs are not written here. assets/gentunes.py turns a list of
	' bars (a chord and eight melody eighths each) into MUSIC rows, writing
	' the bass walk, the off-beat comping and the drums from the chord, and
	' emits src/songs.bas. A variation is a new list of bars.
	'
	' NOT src/tunes.bas: Windows filesystems are case-insensitive, so a
	' generated tunes.bas IS this file, and the first build overwrote it.
	'
	' PLAY FULL: melody, comp and bass on the three tone channels, drums on
	' the noise channel. Nothing here uses SOUND while a tune plays -- with
	' PLAY FULL the player owns every channel and a SOUND write is stomped.
	'
	' Dual target: TI-99/4A and ColecoVision, same SN76489 either way.
	'
	' PAGES. Twelve tunes a page, keyed 1-9 then A-C, so the keys mean the
	' same slot on every page. N/P or joystick right/left turn the page.
	' FIRE plays the next tune across all pages and turns the page to
	' follow, which is how the ColecoVision (keypad 0-9 only) reaches all
	' of them. The tune count, the PLAY dispatch and the menu pages are all
	' GENERATED into songs.bas with the tunes, so none of it can drift.

	CONST PAGESZ = 12
	CONST NONE = 255

	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	SOUND 3,,0
	PLAY FULL

	' TI RAM comes up holding whatever it held and CVBasic clears nothing,
	' so every piece of state is set here. klast = 15 is cont1.key's
	' "nothing", so the first real press is an edge.
	klast = 15
	blast = 0
	jlast = 0
	cur = NONE
	shown = 0
	pg = 0
	GOSUB song_init
	GOSUB draw_menu

	' WAIT FOR RELEASE: the keypress that picked this cart from the TI menu
	' is still down on the first pass, and would start a tune on boot.
	' Capped at two seconds so a stuck line cannot hang the bench.
	wt = 0
boot_rel:
	WAIT
	wt = wt + 1
	IF wt > 120 THEN GOTO main
	IF cont1.key <> 15 THEN GOTO boot_rel

main:
	WAIT
	' The status line follows the player, so an EVENT cue that ends on its
	' own MUSIC STOP reads as STOPPED, and loses its ">", without a keypress.
	p = 0
	IF MUSIC.PLAYING THEN p = 1
	IF p <> shown THEN
		shown = p
		IF p = 0 THEN GOSUB clear_mark
		GOSUB show_status
	END IF

	' FIRE: the next tune, across pages.
	b = 0
	IF cont1.button THEN b = 1
	IF b <> blast THEN
		blast = b
		IF b = 1 THEN
			GOSUB clear_mark
			IF cur = NONE THEN cur = 0 ELSE cur = cur + 1
			IF cur >= ntune THEN cur = 0
			GOSUB follow_cur
			GOSUB start_tune
		END IF
	END IF

	' Joystick left/right turns the page. Edge-triggered.
	j = 0
	IF cont1.right THEN j = 1
	IF cont1.left THEN j = 2
	IF j <> jlast THEN
		jlast = j
		IF j = 1 THEN GOSUB page_next
		IF j = 2 THEN GOSUB page_prev
	END IF

	k = cont1.key
	IF k = klast THEN GOTO main
	klast = k
	IF k = 0 THEN GOSUB stop_tune : GOTO main
	IF k = 78 THEN GOSUB page_next : GOTO main	' N
	IF k = 80 THEN GOSUB page_prev : GOTO main	' P
	' 1-9 are slots 0-8, A-C (65-67, TI keyboard) are slots 9-11.
	sl = NONE
	IF k >= 1 THEN
		IF k <= 9 THEN sl = k - 1
	END IF
	IF k >= 65 THEN
		IF k <= 67 THEN sl = k - 56
	END IF
	IF sl = NONE THEN GOTO main
	GOSUB page_base
	nk = pb + sl
	IF nk < ntune THEN
		GOSUB clear_mark
		cur = nk
		GOSUB start_tune
	END IF
	GOTO main

start_tune:
	GOSUB play_cur
	GOSUB show_mark
	shown = 1
	GOSUB show_status
	RETURN

stop_tune:
	GOSUB clear_mark
	PLAY OFF
	SOUND 0,,0
	SOUND 1,,0
	SOUND 2,,0
	SOUND 3,,0
	PLAY FULL
	shown = 0
	GOSUB show_status
	RETURN

	' pb = pg * 12, by adding: 3pg, then doubled twice.
page_base:
	pb = pg + pg
	pb = pb + pg
	pb = pb + pb
	pb = pb + pb
	RETURN

page_next:
	pg = pg + 1
	IF pg >= npage THEN pg = 0
	GOTO page_show
page_prev:
	IF pg = 0 THEN pg = npage - 1 ELSE pg = pg - 1
page_show:
	GOSUB draw_page
	GOSUB show_mark
	RETURN

	' Turn to the page holding cur, if it is not the one on screen.
follow_cur:
	cp = 0
	cb = cur
fc_loop:
	IF cb < PAGESZ THEN GOTO fc_done
	cb = cb - PAGESZ
	cp = cp + 1
	GOTO fc_loop
fc_done:
	IF cp <> pg THEN
		pg = cp
		GOSUB draw_page
	END IF
	RETURN

draw_menu:
	CLS
	PRINT AT 34,"KEYSTONE TUNES"
	PRINT AT 546,"KEY PLAYS  0 STOPS"
	PRINT AT 578,"N P OR LEFT RIGHT: PAGE"
	PRINT AT 610,"FIRE PLAYS THE NEXT"
	GOSUB draw_page
show_status:
	IF shown = 1 THEN PRINT AT 674,"PLAYING " ELSE PRINT AT 674,"STOPPED "
	RETURN

	' The ">" beside the playing tune, only when its page is on screen.
	' Row 4 is slot 0. slot * 32 reaches 352, so the offset is a 16-bit
	' #var built by doubling -- a multiply read straight back is the MPY
	' high-word trap in CLAUDE.md 3A.
show_mark:
	mk = 62				' ">"
	GOTO mark_put
clear_mark:
	mk = 32				' a space
mark_put:
	IF cur = NONE THEN RETURN
	GOSUB page_base
	IF cur < pb THEN RETURN
	sl = cur - pb
	IF sl >= PAGESZ THEN RETURN
	#mr = sl
	#mr = #mr + #mr
	#mr = #mr + #mr
	#mr = #mr + #mr
	#mr = #mr + #mr
	#mr = #mr + #mr			' slot * 32, one screen row
	#ma = 6144
	#ma = #ma + 128			' row 4, col 0
	#ma = #ma + #mr
	VPOKE #ma,mk
	RETURN

	INCLUDE "songs.bas"
