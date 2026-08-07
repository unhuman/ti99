import io
p = 'RALLYX.bas'
s = io.open(p, encoding='utf-8').read()

def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:70])
    s = s.replace(old, new)

# ---- data goes in its own bank -----------------------------------------
sub("""	BANK 5
""", """	BANK 6
	INCLUDE "title.bas"

	BANK 5
""")

# ---- boot: factor the panel labels out so a game start can redraw them --
sub("""	PRINT AT 24,"1UP"
	PRINT AT 88,"HI"
	WAIT
	PRINT AT 664,"FUEL"
	WAIT
	GOSUB prt_hi
	WAIT
""", """	GOSUB panel_draw
""")

# ---- the title screen ---------------------------------------------------
sub("""title:
	' Title is silent -- music belongs to the round, not the attract screen.
	GOSUB eng_off
	GOSUB mus_off
	SOUND 0,,0
	SOUND 1,,0
	GOSUB t_draw""",
"""title:
	' Title is silent -- music belongs to the round, not the attract screen.
	GOSUB eng_off
	GOSUB mus_off
	SOUND 0,,0
	SOUND 1,,0
	GOSUB hide_spr
	GOSUB t_setup
	GOSUB t_draw""")

# ---- leaving the title: put everything back ----------------------------
sub("""	rnd = rnd0
	' rc3 is the challenging-stage phase""",
"""	GOSUB t_teardown
	rnd = rnd0
	' rc3 is the challenging-stage phase""")

# ---- the new drawing code ----------------------------------------------
sub("""t_draw:
	PRINT AT 359,"* RALLY-X *"
	PRINT AT 424,"PRESS FIRE"
	GOSUB t_mus
	PRINT AT 544,"2026 UNHUMAN AND CLAUDE"
	RETURN""",
"""	' --- title screen -----------------------------------------------------
	' Modelled on the X68000 port: the RALLY-X logo over a TAN field, with a
	' legend naming each thing you will meet, drawn with the game's OWN art
	' rather than mock-ups -- the flag, smoke, BANG and rock characters are
	' the real ones, and the two cars are the real sprites.
	'
	' The whole 32x24 screen goes tan, panel included, so the title is not a
	' picture sitting in a black frame. That means the printable font has to
	' be recoloured (it is white-on-black by default, which is right for the
	' in-game panel and unreadable here) and the panel has to be rebuilt on
	' the way out -- see t_teardown.
t_setup:
	BORDER 10
	sfch = 113		' road char: solid tan, and already defined
	GOSUB screen_fill
	DEFINE COLOR 32,64,font_tan
	' The logo borrows the RADAR canvas codes, which the title has no use
	' for. round_init re-uploads the real canvas on every round, so the
	' restore path already exists and is exercised constantly.
	BANK SELECT 6
	DEFINE CHAR 144,49,title_pat
	WAIT
	DEFINE COLOR 144,49,title_col
	WAIT
	' logo: 15 x 4 chars, centred on the 32-column screen (col 8), row 2
	RESTORE title_map
	FOR tly = 0 TO 3
	#va = $1800 + tly * 32.
	#va = #va + 264		' row 2 (2*32=64) + col 8, plus the 8*32 above
	FOR tlx = 0 TO 14
	READ BYTE t
	#vb = #va + tlx
	VPOKE #vb,t
	NEXT tlx
	WAIT
	NEXT tly
	BANK SELECT 5
	RETURN

	' Back to a playfield: font readable on black again, panel rebuilt, and
	' the radar canvas restored over the logo's borrowed codes.
t_teardown:
	BORDER 1
	DEFINE COLOR 32,64,font_norm
	sfch = 32		' space -- black, now the font is white-on-black
	GOSUB screen_fill
	BANK SELECT 5
	DEFINE CHAR 144,112,radar_zero
	WAIT
	DEFINE COLOR 144,112,radar_base
	WAIT
	GOSUB panel_draw
	GOSUB radar_canvas
	RETURN

	' fill all 32x24 with sfch, one row per frame -- 32 cells is already a
	' sizeable buffered burst and bursts past the budget are dropped silently
screen_fill:
	FOR sfr = 0 TO 23
	#va = $1800 + sfr * 32.
	FOR sfc = 0 TO 31
	#vb = #va + sfc
	VPOKE #vb,sfch
	NEXT sfc
	WAIT
	NEXT sfr
	RETURN

	' the fixed panel furniture (col 24+), needed at boot AND after a title
panel_draw:
	PRINT AT 24,"1UP"
	PRINT AT 88,"HI"
	WAIT
	PRINT AT 664,"FUEL"
	WAIT
	GOSUB prt_hi
	WAIT
	RETURN

	' a 2x2 art cell straight onto the screen at (tir,tic) -- the overlay
	' quadrant order is TL, TR, BL, BR = ob+0..3, same as put_cell uses
t_icon:
	#va = $1800 + tir * 32.
	#va = #va + tic
	VPOKE #va,ob
	#vb = #va + 1
	t = ob + 1
	VPOKE #vb,t
	#vb = #va + 32
	t = ob + 2
	VPOKE #vb,t
	#vb = #vb + 1
	t = ob + 3
	VPOKE #vb,t
	RETURN

t_draw:
	PRINT AT 264,"PRESS FIRE"
	GOSUB t_mus
	' LEGEND, in the arcade port's two columns. Icons are the game's real
	' characters; the two cars are real sprites, parked here because nothing
	' else is using slots 0 and 1 on the title.
	ob = 0			' F flag
	tir = 13
	tic = 3
	GOSUB t_icon
	PRINT AT 429,"FLAG"
	ob = 16			' BANG burst, frame 1
	tic = 18
	GOSUB t_icon
	PRINT AT 444,"BANG"
	WAIT
	ob = SMOKECH
	tir = 16
	tic = 3
	GOSUB t_icon
	PRINT AT 525,"SMOKE"
	ob = ROCKCH
	tic = 18
	GOSUB t_icon
	PRINT AT 540,"ROCK"
	WAIT
	PRINT AT 621,"MY CAR"
	PRINT AT 636,"RED CAR"
	SPRITE 0,151,24,8,5		' player car, heading East
	SPRITE 1,151,144,8,9		' red car
	PRINT AT 736,"2026 UNHUMAN AND CLAUDE"
	RETURN""")

# music-toggle line moves with the new layout
sub("""	IF musen = 1 THEN PRINT AT 454,"1 MUSIC ON " ELSE PRINT AT 454,"1 MUSIC OFF\"""",
    """	IF musen = 1 THEN PRINT AT 330,"1 MUSIC ON " ELSE PRINT AT 330,"1 MUSIC OFF\"""")
io.open(p, 'w', encoding='utf-8').write(s)
print("title screen implemented")
