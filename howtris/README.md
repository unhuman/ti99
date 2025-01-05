# Howtris XB
This is to be compiled with Harry Wilhelm's Compiler:
http://atariage.com/forums/topic/224905-xb-game-developers-package/

HOWTRIXB.TXT = file to be compiled
HOWTRIXB-BeforeXB256.TXT = original version before being compiled

TetrisMusic.txt = file of music
TetrisMusicForSoundList.txt = replacement of constants above for generation of Sound List
                              Note in-game sounds at bottom of file


Sound List Notes: from docs: XB256.pdf
SLCompiler has a problem with this data - SL Data is limited to 640 bytes, but this data is 1051

Take TetrisMusicForSoundList.txt
paste that
save it to a merge file: save dskX.tetsl2-m,merge

run slcompiler
dskx.tetsl2-m is the input
dskx.tetsl2.txt is the output

Go to assembler
dskx.tetsl2.txt is the input
dskx.tetsl2.obj is the output

Go to XB
CALL LINK("XB256",1051)        (size of sound table)
NEW
call load("DSkx.tetsl2.obj")
CALL LINK(“ST2VDP”,2)        - note CALL LINK(“ST2VDP”,1) does not work b/c memory is not enough
    BUMP  7215
    DROP  7191
    MUSIC 6176

CALL LINK("PLAY",ADDRESS)

