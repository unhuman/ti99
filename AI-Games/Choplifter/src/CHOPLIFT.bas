' CHOPLIFTER — original CVBasic implementation, TI-99/4A first.
' Positions are world pixels. No compound comparisons on the TI backend.
#if TI994A
BANK ROM 128
BANK SELECT 1
#endif
CONST CAPACITY = 16
CONST LANDED = 152
DIM camp_left(4)
DIM camp_open(4)
DIM #camp_x(4)
DIM #shot_x(2)
DIM shot_y(2)
DIM shot_dir(2)
DIM shot_on(2)

' Sprite ownership: heli 0,1; tank 2; runner 3; shots 4,5;
' jet 6; shell 7; drone 8; explosion 9. Unused slots stay hidden.
SPRITE FLICKER OFF
DEFINE SPRITE 0,20,sprite_art
DEFINE CHAR 128,16,tile_art
DEFINE COLOR 128,16,tile_colors
#camp_x(0)=128
#camp_x(1)=384
#camp_x(2)=640
#camp_x(3)=896
best=0
GOTO title

title:
GOSUB silence
GOSUB hide_all
CLS
PRINT AT 104,"C H O P L I F T E R"
PRINT AT 169,"RESCUE OPERATIONS"
PRINT AT 354,"64 PEOPLE. THREE HELICOPTERS."
PRINT AT 418,"FREE THE CAMPS. FLY THEM HOME."
PRINT AT 482,"JOYSTICK: FLY     FIRE: SHOOT"
PRINT AT 546,"HOVER + FIRE: SHOOT DOWN"
PRINT AT 610,"LAND TO PICK UP     0: PAUSE"
PRINT AT 674,"PRESS FIRE OR 1 TO LAUNCH"
PRINT AT 738,"TI-99/4A  /  CVBASIC  /  2026"
SPRITE 0,71,112,0,15
SPRITE 1,71,128,4,15
GOSUB release_input
title_wait:
WAIT
IF cont1.button THEN GOTO new_game
IF cont1.key = 1 THEN GOTO new_game
GOTO title_wait

new_game:
GOSUB release_input
saved=0
lost=0
aboard=0
lives=3
sorties=0
anim=0
FOR ini=0 TO 3
    camp_left(ini)=16
    camp_open(ini)=0
NEXT ini
runner_on=0
ended=0
GOSUB new_heli
GOSUB game_screen
GOSUB clock_reset

main_loop:
WAIT
#now=FRAME
#elapsed=#now-#last
IF #elapsed < 2 THEN GOTO main_loop
#last=#now
IF #elapsed > 6 THEN #elapsed=6
dt=#elapsed
IF cont1.key = 0 THEN GOSUB pause_game
anim=anim+dt
GOSUB sound_tick
IF crash_timer THEN GOTO crash_frame
GOSUB fly
GOSUB weapon_tick
GOSUB people_tick
GOSUB enemy_tick
IF crash_timer THEN GOTO draw_frame
IF saved+lost = 64 THEN ended=1
IF ended THEN GOTO result_screen
draw_frame:
GOSUB camera_tick
GOSUB draw_actors
IF hud_dirty THEN GOSUB hud
GOTO main_loop

crash_frame:
IF crash_timer > dt THEN
    crash_timer=crash_timer-dt
ELSE
    crash_timer=0
    IF lives = 0 THEN GOTO result_screen
    GOSUB new_heli
    GOSUB game_screen
    GOSUB clock_reset
END IF
GOTO draw_frame

new_heli:
#hx=1192
hy=LANDED
hspeed=0
hdir=0
face=2
crash_timer=0
invuln=120
shot_on(0)=0
shot_on(1)=0
fire_timer=0
transfer_timer=0
tank_on=0
jet_on=0
drone_on=0
shell_on=0
tank_motion=0
drone_motion=0
blast_timer=0
#tank_wait=150
#jet_wait=360
#drone_wait=240
#camera=65535
hud_dirty=1
RETURN

clock_reset:
#last=FRAME
RETURN

fly:
IF invuln > dt THEN invuln=invuln-dt ELSE invuln=0
old_y=hy
input_dir=2
IF cont1.left THEN input_dir=1
IF cont1.right THEN input_dir=0
IF cont1.up THEN
    IF hy > 25+dt THEN hy=hy-dt ELSE hy=25
END IF
IF cont1.down THEN
    hy=hy+dt
    IF hy > LANDED THEN hy=LANDED
END IF
IF hy = LANDED THEN
    hspeed=0
    face=2
ELSE
    IF input_dir < 2 THEN
        IF hdir = input_dir THEN
            IF hspeed < 3 THEN hspeed=hspeed+1
        ELSE
            IF hspeed THEN hspeed=hspeed-1 ELSE hdir=input_dir
        END IF
        face=input_dir
    ELSE
        IF hspeed THEN hspeed=hspeed-1
        IF hspeed = 0 THEN face=2
    END IF
END IF
#move=hspeed*dt
GOSUB move_heli
RETURN

move_heli:
IF hdir THEN
    IF #hx > #move+16 THEN #hx=#hx-#move ELSE #hx=16
ELSE
    #hx=#hx+#move
    IF #hx > 1240 THEN #hx=1240
END IF
RETURN

weapon_tick:
IF fire_timer > dt THEN fire_timer=fire_timer-dt ELSE fire_timer=0
IF cont1.button THEN
    IF fire_timer = 0 THEN
        FOR wi=0 TO 1
            IF shot_on(wi) = 0 THEN
                shot_on(wi)=1
                #shot_x(wi)=#hx+16
                shot_y(wi)=hy+9
                shot_dir(wi)=face
                fire_timer=15
                gun_timer=5
                SOUND 1,90,7
                EXIT FOR
            END IF
        NEXT wi
    END IF
END IF
FOR wi=0 TO 1
    IF shot_on(wi) THEN GOSUB move_shot
NEXT wi
RETURN

move_shot:
#bullet_step=dt+dt
#bullet_step=#bullet_step+#bullet_step
IF shot_dir(wi) = 2 THEN
    shot_y(wi)=shot_y(wi)+dt+dt
ELSE
    IF shot_dir(wi) THEN
        IF #shot_x(wi) < #bullet_step THEN shot_on(wi)=0:RETURN
        #shot_x(wi)=#shot_x(wi)-#bullet_step
    ELSE
        #shot_x(wi)=#shot_x(wi)+#bullet_step
        IF #shot_x(wi) > 1278 THEN shot_on(wi)=0:RETURN
    END IF
END IF
IF shot_y(wi) > 166 THEN shot_on(wi)=0:RETURN
' Swept horizontal hit window includes maximum 24-pixel step.
IF shot_y(wi) > 142 THEN
    FOR wc=0 TO 3
        IF camp_open(wc) = 0 THEN
            #ax=#shot_x(wi):#bx=#camp_x(wc)
            GOSUB distance_x
            IF #distance < 32 THEN
                camp_open(wc)=1
                terrain_dirty=1
                shot_on(wi)=0
                #blast_x=#camp_x(wc):blast_y=144
                GOSUB explode
                RETURN
            END IF
        END IF
    NEXT wc
END IF
IF tank_on THEN
    IF shot_y(wi) > 151 THEN
        #ax=#shot_x(wi):#bx=#tank_x+8
        GOSUB distance_x
        IF #distance < 20 THEN
            tank_on=0:#tank_wait=240
            #blast_x=#tank_x:blast_y=152
            GOSUB explode
            shot_on(wi)=0
            RETURN
        END IF
    END IF
END IF
IF jet_on THEN
    #ax=#shot_x(wi):#bx=#jet_x+8
    GOSUB distance_x
    ay=shot_y(wi):by=jet_y+8
    GOSUB distance_y
    IF #distance < 24 THEN
        IF ydistance < 10 THEN
            jet_on=0:#jet_wait=300
            #blast_x=#jet_x:blast_y=jet_y
            GOSUB explode
            shot_on(wi)=0
        END IF
    END IF
END IF
IF drone_on THEN
    #ax=#shot_x(wi):#bx=#drone_x+8
    GOSUB distance_x
    ay=shot_y(wi):by=drone_y+8
    GOSUB distance_y
    IF #distance < 16 THEN
        IF ydistance < 12 THEN
            drone_on=0:#drone_wait=240
            #blast_x=#drone_x:blast_y=drone_y
            GOSUB explode
            shot_on(wi)=0
        END IF
    END IF
END IF
IF runner_on THEN
    IF shot_y(wi) > 155 THEN
        #ax=#shot_x(wi):#bx=#runner_x+4
        GOSUB distance_x
        IF #distance < 9 THEN
            GOSUB lose_runner
            shot_on(wi)=0
        END IF
    END IF
END IF
RETURN

people_tick:
IF transfer_timer > dt THEN transfer_timer=transfer_timer-dt ELSE transfer_timer=0
IF hy = LANDED THEN
    IF #hx > 1170 THEN
        IF #hx < 1233 THEN
            IF aboard THEN
                IF transfer_timer = 0 THEN
                    aboard=aboard-1
                    saved=saved+1
                    hud_dirty=1
                    transfer_timer=12
                    chime_timer=7
                    SOUND 2,180,10
                    IF aboard = 0 THEN sorties=sorties+1
                END IF
            END IF
        END IF
    END IF
END IF
IF runner_on THEN
    #ax=#hx+16:#bx=#runner_x+4
    GOSUB distance_x
    IF #distance > 180 THEN runner_on=0:RETURN
    IF hy = LANDED THEN
        IF old_y < LANDED THEN
            IF #distance < 13 THEN GOSUB lose_runner:RETURN
        END IF
        IF aboard < CAPACITY THEN
            IF #distance < 8 THEN
                camp_left(runner_camp)=camp_left(runner_camp)-1
                aboard=aboard+1
                runner_on=0
                transfer_timer=12
                chime_timer=7
                SOUND 2,260,9
                hud_dirty=1
                RETURN
            END IF
            IF #distance < 104 THEN
                IF #runner_x+4 < #hx+16 THEN
                    #runner_x=#runner_x+dt
                ELSE
                    #runner_x=#runner_x-dt
                END IF
            END IF
        END IF
    END IF
ELSE
    IF transfer_timer = 0 THEN
        IF aboard < CAPACITY THEN
            FOR pc=0 TO 3
                IF camp_open(pc) THEN
                    IF camp_left(pc) THEN
                        #ax=#hx+16:#bx=#camp_x(pc)
                        GOSUB distance_x
                        IF #distance < 110 THEN
                            runner_camp=pc
                            #runner_x=#camp_x(pc)+12
                            runner_on=1
                            EXIT FOR
                        END IF
                    END IF
                END IF
            NEXT pc
        END IF
    END IF
END IF
RETURN

lose_runner:
IF runner_on THEN
    camp_left(runner_camp)=camp_left(runner_camp)-1
    lost=lost+1
    runner_on=0
    transfer_timer=30
    hud_dirty=1
END IF
RETURN

enemy_tick:
IF #hx < 1060 THEN
    IF tank_on = 0 THEN
        IF #tank_wait > #elapsed THEN
            #tank_wait=#tank_wait-#elapsed
        ELSE
            tank_on=1
            IF #hx > 180 THEN #tank_x=#hx-160 ELSE #tank_x=#hx+180
            #tank_wait=150
        END IF
    END IF
    IF jet_on = 0 THEN
        IF #jet_wait > #elapsed THEN
            #jet_wait=#jet_wait-#elapsed
        ELSE
            jet_on=1
            #jet_x=1050
            jet_y=hy
            IF jet_y > 120 THEN jet_y=72
            IF jet_y < 40 THEN jet_y=40
            #jet_wait=360
        END IF
    END IF
END IF
IF tank_on THEN GOSUB tank_tick
IF jet_on THEN
    #jet_step=dt+dt+dt
    IF #jet_x > #jet_step THEN #jet_x=#jet_x-#jet_step ELSE jet_on=0
    #ax=#hx+16:#bx=#jet_x+8
    GOSUB distance_x
    ay=hy+8:by=jet_y+8
    GOSUB distance_y
    IF #distance < 23 THEN
        IF ydistance < 11 THEN GOSUB crash
    END IF
END IF
IF saved >= 32 THEN
    IF drone_on = 0 THEN
        IF #drone_wait > #elapsed THEN
            #drone_wait=#drone_wait-#elapsed
        ELSE
            drone_on=1
            #drone_x=1056
            drone_y=32
        END IF
    END IF
END IF
IF drone_on THEN
    IF #drone_x < #hx THEN #drone_x=#drone_x+dt ELSE #drone_x=#drone_x-dt
    drone_motion=drone_motion+dt
    drone_step=drone_motion/2
    drone_motion=drone_motion AND 1
    IF drone_y < hy THEN
        drone_y=drone_y+drone_step
        IF drone_y > hy THEN drone_y=hy
    ELSE
        IF drone_y > hy THEN
            drone_y=drone_y-drone_step
            IF drone_y < hy THEN drone_y=hy
        END IF
    END IF
    #ax=#hx+16:#bx=#drone_x+8
    GOSUB distance_x
    ay=hy+8:by=drone_y+8
    GOSUB distance_y
    IF #distance < 18 THEN
        IF ydistance < 12 THEN GOSUB crash
    END IF
END IF
IF shell_on THEN GOSUB shell_tick
RETURN

tank_tick:
tank_motion=tank_motion+dt
tank_step=tank_motion/4
tank_motion=tank_motion AND 3
IF #tank_x+8 < #hx THEN
    IF #tank_x < 1038 THEN #tank_x=#tank_x+tank_step
ELSE
    IF #tank_x > 8 THEN #tank_x=#tank_x-tank_step
END IF
IF #tank_wait > #elapsed THEN
    #tank_wait=#tank_wait-#elapsed
ELSE
    IF shell_on = 0 THEN
        #ax=#hx:#bx=#tank_x
        GOSUB distance_x
        IF #distance < 220 THEN
            shell_on=1
            #shell_x=#tank_x+8
            shell_y=156
            shell_dir=0
            IF #hx < #tank_x THEN shell_dir=1
            shell_rise=1
            IF hy > 130 THEN shell_rise=0
            #tank_wait=140
            IF saved >= 16 THEN #tank_wait=100
        END IF
    END IF
END IF
#ax=#hx+16:#bx=#tank_x+8
GOSUB distance_x
IF hy > 140 THEN
    IF #distance < 23 THEN GOSUB crash
END IF
RETURN

shell_tick:
#shell_step=dt+dt
IF shell_dir THEN
    IF #shell_x > #shell_step THEN #shell_x=#shell_x-#shell_step ELSE shell_on=0:RETURN
ELSE
    #shell_x=#shell_x+#shell_step
END IF
IF #shell_x > 1060 THEN shell_on=0:RETURN
IF shell_rise THEN
    IF shell_y > dt+24 THEN shell_y=shell_y-dt ELSE shell_on=0:RETURN
END IF
#ax=#hx+16:#bx=#shell_x
GOSUB distance_x
ay=hy+8:by=shell_y
GOSUB distance_y
IF #distance < 17 THEN
    IF ydistance < 9 THEN GOSUB crash:shell_on=0
END IF
IF runner_on THEN
    IF shell_y > 153 THEN
        #ax=#runner_x+4:#bx=#shell_x
        GOSUB distance_x
        IF #distance < 8 THEN GOSUB lose_runner:shell_on=0
    END IF
END IF
RETURN

crash:
IF invuln THEN RETURN
IF crash_timer THEN RETURN
lost=lost+aboard
aboard=0
lives=lives-1
crash_timer=90
hud_dirty=1
#blast_x=#hx+8:blast_y=hy
GOSUB explode
RETURN

explode:
blast_timer=30
noise_timer=24
SOUND 3,7,12
RETURN

distance_x:
IF #ax > #bx THEN #distance=#ax-#bx ELSE #distance=#bx-#ax
RETURN
distance_y:
IF ay > by THEN ydistance=ay-by ELSE ydistance=by-ay
RETURN

camera_tick:
#newcam=0
IF #hx > 112 THEN #newcam=#hx-112
IF #newcam > 1024 THEN #newcam=1024
#newcam=#newcam AND 65528
IF #newcam <> #camera THEN
    #camera=#newcam
    terrain_dirty=1
END IF
IF terrain_dirty THEN GOSUB terrain
RETURN

game_screen:
GOSUB hide_all
CLS
PRINT AT 0,"SAVED 00  ABOARD 00  LOST 00"
PRINT AT 32,"CAMP  1  2  3  4    RESERVES"
PRINT AT 736,"HOME >  LAND ON H TO UNLOAD"
SCREEN ground_row,0,704,32,1
terrain_dirty=1
GOSUB camera_tick
GOSUB hud
RETURN

terrain:
#mapoff=#camera/8
SCREEN world_map,#mapoff,544,32,5,160
' Open-door overlays use raw name-table addresses, no VDP reads.
FOR tc=0 TO 3
    IF camp_open(tc) THEN
        IF #camp_x(tc) >= #camera THEN
            #relative=#camp_x(tc)-#camera
            IF #relative < 256 THEN
                #tileaddr=#relative/8
                #tileaddr=#tileaddr+6752
                VPOKE #tileaddr,136
                #tileaddr=#tileaddr+32
                VPOKE #tileaddr,136
            END IF
        END IF
    END IF
NEXT tc
terrain_dirty=0
RETURN

hud:
digit_value=saved:#digit_pos=6150:GOSUB digits
digit_value=aboard:#digit_pos=6161:GOSUB digits
digit_value=lost:#digit_pos=6170:GOSUB digits
FOR hc=0 TO 3
    #hudaddr=hc+hc+hc
    #hudaddr=#hudaddr+6182
    hudchar=49+hc
    IF camp_open(hc) THEN hudchar=111
    IF camp_left(hc) = 0 THEN hudchar=45
    VPOKE #hudaddr,hudchar
NEXT hc
spares=0
IF lives > 0 THEN spares=lives-1
FOR hs=0 TO 1
    hudchar=32
    IF hs+spares > 1 THEN hudchar=140
    #hudaddr=hs
    #hudaddr=#hudaddr+6206
    VPOKE #hudaddr,hudchar
NEXT hs
IF aboard = CAPACITY THEN
    PRINT AT 736,"CABIN FULL!  RETURN TO HOME >   "
ELSE
    IF #hx > 1072 THEN
        PRINT AT 736,"LAND ON H PAD TO UNLOAD        "
    ELSE
        PRINT AT 736,"HOVER+FIRE: DOWN  LAND: RESCUE  "
    END IF
END IF
hud_dirty=0
RETURN

digits:
digit_char=48+digit_value/10
VPOKE #digit_pos,digit_char
#digit_pos=#digit_pos+1
digit_char=48+digit_value%10
VPOKE #digit_pos,digit_char
RETURN

draw_actors:
IF crash_timer THEN
    SPRITE 0,209,0,0,0
    SPRITE 1,209,0,0,0
ELSE
    draw_x=#hx-#camera
    draw_y=hy-1
    draw_pat=face*16
    IF anim AND 8 THEN draw_pat=draw_pat+8
    SPRITE 0,draw_y,draw_x,draw_pat,15
    draw_x=draw_x+16
    draw_pat=draw_pat+4
    SPRITE 1,draw_y,draw_x,draw_pat,15
END IF
draw_slot=2:draw_on=tank_on:#draw_world=#tank_x:draw_y=155:draw_pat=48:draw_color=3
GOSUB world_sprite
draw_slot=3:draw_on=runner_on:#draw_world=#runner_x:draw_y=159:draw_pat=52:draw_color=11
IF anim AND 8 THEN draw_pat=56
GOSUB world_sprite
FOR di=0 TO 1
    draw_slot=di+4:draw_on=shot_on(di):#draw_world=#shot_x(di)
    draw_y=shot_y(di)-1:draw_pat=68:draw_color=11
    GOSUB world_sprite
NEXT di
draw_slot=6:draw_on=jet_on:#draw_world=#jet_x:draw_y=jet_y-1:draw_pat=60:draw_color=7
GOSUB world_sprite
draw_slot=7:draw_on=shell_on:#draw_world=#shell_x:draw_y=shell_y-1:draw_pat=68:draw_color=8
GOSUB world_sprite
draw_slot=8:draw_on=drone_on:#draw_world=#drone_x:draw_y=drone_y-1:draw_pat=64:draw_color=10
GOSUB world_sprite
draw_slot=9:draw_on=blast_timer:#draw_world=#blast_x:draw_y=blast_y-1:draw_pat=72:draw_color=10
IF anim AND 8 THEN draw_pat=76:draw_color=8
GOSUB world_sprite
RETURN

world_sprite:
IF draw_on THEN
    IF #draw_world >= #camera THEN
        #screen_x=#draw_world-#camera
        IF #screen_x < 256 THEN
            draw_x=#screen_x
            SPRITE draw_slot,draw_y,draw_x,draw_pat,draw_color
            RETURN
        END IF
    ELSE
        #screen_x=#camera-#draw_world
        IF #screen_x < 16 THEN
            draw_x=32-#screen_x
            draw_color=draw_color+128
            SPRITE draw_slot,draw_y,draw_x,draw_pat,draw_color
            RETURN
        END IF
    END IF
END IF
SPRITE draw_slot,209,0,0,0
RETURN

hide_all:
FOR hi=0 TO 31
    SPRITE hi,209,0,0,0
NEXT hi
RETURN

sound_tick:
IF blast_timer > dt THEN blast_timer=blast_timer-dt ELSE blast_timer=0
IF gun_timer > dt THEN gun_timer=gun_timer-dt ELSE gun_timer=0:SOUND 1,0,0
IF chime_timer > dt THEN chime_timer=chime_timer-dt ELSE chime_timer=0:SOUND 2,0,0
IF noise_timer > dt THEN noise_timer=noise_timer-dt ELSE noise_timer=0:SOUND 3,0,0
IF crash_timer THEN
    SOUND 0,0,0
ELSE
    IF hy < LANDED THEN
        IF anim AND 4 THEN SOUND 0,800,3 ELSE SOUND 0,650,2
    ELSE
        SOUND 0,0,0
    END IF
END IF
RETURN

silence:
SOUND 0,0,0
SOUND 1,0,0
SOUND 2,0,0
SOUND 3,0,0
gun_timer=0:chime_timer=0:noise_timer=0
RETURN

release_input:
FOR ri=0 TO 59
    WAIT
    IF cont1.button = 0 THEN
        IF cont1.key = 15 THEN RETURN
    END IF
NEXT ri
RETURN

pause_game:
GOSUB silence
PRINT AT 736,"PAUSED - PRESS 0 OR FIRE       "
GOSUB release_input
pause_wait:
WAIT
IF cont1.key = 0 THEN GOTO pause_end
IF cont1.button THEN GOTO pause_end
GOTO pause_wait
pause_end:
GOSUB release_input
hud_dirty=1
GOSUB clock_reset
RETURN

result_screen:
GOSUB silence
GOSUB hide_all
CLS
IF saved > best THEN best=saved
PRINT AT 167,"MISSION COMPLETE"
IF lives = 0 THEN PRINT AT 167,"MISSION ENDED   "
IF saved = 64 THEN PRINT AT 167,"PERFECT RESCUE! "
PRINT AT 263,"PEOPLE SAVED   "
digit_value=saved:#digit_pos=6422:GOSUB digits
PRINT AT 327,"PEOPLE LOST    "
digit_value=lost:#digit_pos=6486:GOSUB digits
PRINT AT 391,"STRANDED       "
digit_value=64-saved-lost:#digit_pos=6550:GOSUB digits
PRINT AT 487,"BEST RESCUE    "
digit_value=best:#digit_pos=6646:GOSUB digits
PRINT AT 615,"FIRE OR 1 TO CONTINUE"
GOSUB release_input
result_wait:
WAIT
IF cont1.button THEN GOTO title
IF cont1.key = 1 THEN GOTO title
GOTO result_wait

#if TI994A
BANK 1
#endif
INCLUDE "assets.bas"
