import io
p = 'RALLYX.bas'
s = io.open(p, encoding='utf-8').read()

s = s.replace("""	' SOUND CHANNEL BUDGET -- everything here depends on this split:
	'   0,1  background music (the CVBasic music player, SIMPLE mode)
	'   2    flag blip, round jingle, game-over sting
	'   3    engine buzz, and the crash boom that overrides it
	' SIMPLE keeps the player off channel 2, NO DRUMS keeps it off channel 3
	' (the noise channel) -- without NO DRUMS the drum track would fight the
	' engine for the same register.
	PLAY SIMPLE NO DRUMS""",
"""	' SOUND CHANNEL BUDGET -- everything here depends on this split:
	'   0,1  background music (OUR player, see mus_tick)
	'   2    flag blip, round jingle, game-over sting
	'   3    engine buzz, and the crash boom that overrides it
	'
	' We drive the music ourselves rather than using PLAY. CVBasic's PSG
	' music player writes the volume registers FROM ITS OWN TABLES every
	' vblank, so a game cannot turn it down -- and worse, while it is
	' compiled in it keeps writing the channels and drowns anything the game
	' puts there, which is exactly why the engine could not be heard.
	' Removing every PLAY statement is what leaves CVBASIC_MUSIC_PLAYER at 0.
	#musf = VARPTR mus_freq(0)
	#muss = VARPTR mus_song(0)""")

s = s.replace("\tPLAY music_bg\t\t' music runs during the round only, not the title",
              "\tGOSUB mus_start\t\t' music runs during the round only, not the title")
s = s.replace("\tPLAY OFF\n", "\tGOSUB mus_off\n")

anchor = "\t' --- engine ------------------------------------------------------------"
assert s.count(anchor) == 1
s = s.replace(anchor, """	' --- music --------------------------------------------------------------
	' Two voices on channels 0 and 1 at a FIXED, deliberately low volume so
	' the engine and the effects stay on top. 64 steps at MUSTICK frames is
	' about ten seconds before it comes round again.
mus_start:
	mup = 0
	mut = 1
	RETURN
mus_off:
	mut = 0
	SOUND 0,,0
	SOUND 1,,0
	RETURN
mus_tick:
	IF mut = 0 THEN RETURN		' stopped
	mut = mut - 1
	IF mut > 0 THEN RETURN
	mut = MUSTICK
	#mua = #muss + mup + mup
	mun = PEEK(#mua)
	#mua = #mua + 1
	mub = PEEK(#mua)
	IF mun > 0 THEN musv = MUSVOL : GOSUB mus_mel
	IF mub > 0 THEN musv = MUSBAS : GOSUB mus_bas
	mup = mup + 1
	IF mup >= 64 THEN mup = 0
	RETURN
	' note index -> 16-bit divider (stored hi,lo), then sound it
mus_mel:
	#mua = #musf + mun + mun
	mhi = PEEK(#mua)
	#mua = #mua + 1
	mlo = PEEK(#mua)
	#mf = mhi * 256.
	#mf = #mf + mlo
	SOUND 0,#mf,musv
	RETURN
mus_bas:
	#mua = #musf + mub + mub
	mhi = PEEK(#mua)
	#mua = #mua + 1
	mlo = PEEK(#mua)
	#mf = mhi * 256.
	#mf = #mf + mlo
	SOUND 1,#mf,musv
	RETURN

""" + anchor)

s = s.replace("\t' engine note follows the car's state\n\tGOSUB eng_tick",
              "\t' engine note follows the car's state\n\tGOSUB eng_tick\n\n"
              "\t' background music, one step every MUSTICK frames\n\tGOSUB mus_tick")

s = s.replace("\tCONST POPFR = 110\t' frames the flag-value popup stays up (~2 s)",
              "\tCONST POPFR = 110\t' frames the flag-value popup stays up (~2 s)\n"
              "\tCONST MUSTICK = 9\t' frames per music step (~6.7 steps/sec)\n"
              "\tCONST MUSVOL = 6\t' melody volume -- low on purpose, the engine\n"
              "\tCONST MUSBAS = 5\t' and the effects have to cut through it")
s = s.replace("\tIF engc = 1 THEN SOUND 3,1,11 ELSE SOUND 3,2,8",
              "\tIF engc = 1 THEN SOUND 3,1,11 ELSE SOUND 3,2,8")
s = s.replace("\tIF engc = 1 THEN SOUND 3,1,5 ELSE SOUND 3,2,3",
              "\tIF engc = 1 THEN SOUND 3,1,11 ELSE SOUND 3,2,8")

start = s.index("\t' Background music -- MUST live in bank 0.")
end = s.index("\tMUSIC REPEAT", start) + len("\tMUSIC REPEAT\n")
s = s[:start] + '\tINCLUDE "music.bas"\n' + s[end:]

io.open(p, 'w', encoding='utf-8').write(s)
assert "PLAY " not in s and "music_bg" not in s and "\tMUSIC " not in s
for probe in ("mus_tick:", "GOSUB mus_start", "GOSUB mus_tick", "CONST MUSVOL = 6",
              'INCLUDE "music.bas"', "SOUND 3,1,11", "#musf = VARPTR"):
    assert probe in s, probe
print("custom player re-applied for real this time")
