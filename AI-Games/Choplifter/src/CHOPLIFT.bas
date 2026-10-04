' CHOPLIFTER — original CVBasic implementation, TI-99/4A first.
' Positions are world pixels. No compound comparisons on the TI backend.
#if TI994A
BANK ROM 128
BANK SELECT 1
#endif
CONST CAPACITY = 16
CONST LANDED = 153
DIM camp_left(4)
DIM camp_open(4)
DIM #camp_x(4)
DIM camp_released(4)
DIM camp_escape(4)
DIM camp_active(4)
' 0 indoors, 1 escaping, 2 waiting, 3 boarding, 4 lost, 5 aboard,
' 6 walking safely to the office (already saved), 7 inside the office.
DIM person_state(64)
DIM #person_x(64)
DIM crowd_cells(32)
DIM crowd_pixels(256)
DIM #shot_x(2)
DIM shot_y(2)
DIM shot_dir(2)
DIM shot_on(2)
DIM shot_ttl(2)
DIM shot_slope(2)
DIM shot_speed(2)
DIM shot_drift(2)

' Sprite ownership: heli 0,1; shots 2,3; tank 4,5; runner 6;
' jet 7; shell 8; drone 9; explosion 10; jet missile 11.
fire_gate=2
ON FRAME GOSUB fire_control
SPRITE FLICKER OFF
DEFINE SPRITE 0,64,sprite_art
DEFINE CHAR 60,1,practice_star
DEFINE CHAR 128,112,tile_art
DEFINE COLOR 128,112,tile_colors
DEFINE COLOR 144,2,flag_colors
' Codes 14-31 are reserved for fire/crowds; 128-239 belong to scenery.
DEFINE VRAM 5104,16,fire_frame0
DEFINE COLOR 126,2,fire_colors
DEFINE COLOR 152,4,office_sign_colors
DEFINE VRAM 4864,192,waiting_art
DEFINE VRAM 13056,192,waiting_colors
DEFINE VRAM 5056,8,pad_fence_art
DEFINE VRAM 13248,8,pad_fence_colors
DEFINE CHAR 240,16,star_bits
DEFINE COLOR 240,16,star_colors
#camp_x(0)=128
#camp_x(1)=384
#camp_x(2)=640
#camp_x(3)=896
best=0
best_practice=0
GOTO title

title:
start_lives=3:practice=0:title_seq=0:title_key=15
GOSUB silence
GOSUB hide_all
GOSUB menu_restore
CLS
PRINT AT 104,"C H O P L I F T E R"
PRINT AT 169,"RESCUE OPERATIONS"
PRINT AT 354,"64 PEOPLE. THREE HELICOPTERS."
PRINT AT 418,"FREE THE CAMPS. FLY THEM HOME."
PRINT AT 482,"JOYSTICK: FLY  TAP FIRE: SHOOT"
PRINT AT 546,"HOLD FIRE: TURN  FRONT: BOMB"
#if TI994A
PRINT AT 610,"LAND: PICK UP   HOLD P: PAUSE"
#else
PRINT AT 610,"LAND: PICK UP   HOLD 0: PAUSE"
#endif
PRINT AT 674,"PRESS FIRE OR 1 TO LAUNCH"
PRINT AT 738,"TI-99/4A  /  CVBASIC  /  2026"
SPRITE 0,71,112,0,15
SPRITE 1,71,128,4,15
GOSUB release_input
title_wait:
WAIT
GOSUB title_code
IF title_seq = 3 THEN GOTO setup838
IF cont1.button THEN GOTO new_game
IF cont1.key = 1 THEN GOTO new_game
GOTO title_wait

title_code:
menu_key=cont1.key
IF menu_key = title_key THEN RETURN
title_key=menu_key
IF menu_key = 15 THEN RETURN
IF menu_key = 8 THEN
    IF title_seq = 2 THEN title_seq=3 ELSE title_seq=1
ELSE
    IF menu_key = 3 THEN
        IF title_seq = 1 THEN title_seq=2 ELSE title_seq=0
    ELSE
        title_seq=0
    END IF
END IF
RETURN

setup838:
GOSUB hide_all
CLS
PRINT AT 232,"PRACTICE FLIGHT"
PRINT AT 326,"HELICOPTERS: 1 TO 9"
PRINT AT 422,"0 CANCELS"
PRINT AT 518,"SAVED COUNTS MARKED *"
GOSUB release_input
title_key=8
setup_wait:
WAIT
menu_key=cont1.key
IF menu_key = 0 THEN GOTO title
IF menu_key = 15 THEN title_key=15
IF title_key <> 15 THEN GOTO setup_wait
GOSUB setup_choice
IF practice THEN GOTO new_game
GOTO setup_wait

setup_choice:
IF menu_key < 1 THEN RETURN
IF menu_key > 9 THEN RETURN
start_lives=menu_key
practice=1
RETURN

new_game:
GOSUB release_input
saved=0
lost=0
aboard=0
lives=start_lives
sorties=0
anim=0
pause_hold=0
pause_latched=0
FOR ini=0 TO 3
    camp_left(ini)=16
    camp_open(ini)=0
    camp_released(ini)=0
    camp_escape(ini)=0
    camp_active(ini)=0
NEXT ini
FOR ini=0 TO 63
    person_state(ini)=0
NEXT ini
#crowd_clock=0
crowd_bank=0
crowd_pose=255
crowd_dirty=1
home_walking=0
delivery_pending=0
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
GOSUB pause_input
IF pause_trigger THEN GOSUB pause_game
anim=anim+dt
GOSUB rotor_tick
GOSUB sound_tick
IF crash_timer THEN GOTO crash_frame
GOSUB fly
IF crash_timer THEN GOTO draw_frame
GOSUB weapon_tick
GOSUB people_tick
GOSUB enemy_tick
IF crash_timer THEN GOTO draw_frame
IF saved+lost = 64 THEN
    IF home_walking = 0 THEN ended=1
END IF
IF ended THEN GOTO result_screen
draw_frame:
GOSUB camera_tick
GOSUB crowd_draw
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
GOSUB silence
rotor_clock=0:rotor_phase=0
fall_speed=0:fall_hold=0
#hx=1408
hy=LANDED
hspeed=0
hdir=0
face=1
turn_phase=2
fire_held=0
fire_turned=0
fire_hold=0
fire_gate=2
crash_timer=0
invuln=120
shot_on(0)=0
shot_on(1)=0
fire_timer=0
transfer_timer=0
tank_on=0
jet_on=0
jet_turn=0
missile_on=0
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
fire_gate=1
fire_held=0:fire_hold=0:fire_turned=0
fire_seen=fire_events
#last=FRAME
RETURN

fly:
IF invuln > dt THEN invuln=invuln-dt ELSE invuln=0
old_y=hy
input_dir=2
IF cont1.left THEN input_dir=1
IF cont1.right THEN input_dir=0
IF cont1.up THEN
    fall_speed=0:fall_hold=0
    IF hy > 25+dt THEN hy=hy-dt ELSE hy=25
ELSE
    IF cont1.down THEN
        IF hy < LANDED THEN
            IF fall_speed = 0 THEN fall_speed=1
            fall_hold=fall_hold+dt
            IF fall_hold >= 24 THEN
                fall_hold=fall_hold-24
                IF fall_speed < 3 THEN fall_speed=fall_speed+1
            END IF
            fall_step=dt
            IF fall_speed > 1 THEN fall_step=fall_step+dt
            IF fall_speed > 2 THEN fall_step=fall_step+dt
            hy=hy+fall_step
            IF hy >= LANDED THEN
                hy=LANDED
                IF fall_speed > 1 THEN invuln=0:GOSUB crash:RETURN
                fall_speed=0:fall_hold=0
            END IF
        END IF
    ELSE
        fall_speed=0:fall_hold=0
    END IF
END IF
IF hy = LANDED THEN
    hspeed=0
ELSE
    IF input_dir < 2 THEN
        IF hdir = input_dir THEN
            IF hspeed < 3 THEN hspeed=hspeed+1
        ELSE
            IF hspeed THEN hspeed=hspeed-1 ELSE hdir=input_dir
        END IF
    ELSE
        IF hspeed THEN hspeed=hspeed-1
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
    IF #hx > 1496 THEN #hx=1496
END IF
RETURN

weapon_tick:
IF fire_timer > dt THEN fire_timer=fire_timer-dt ELSE fire_timer=0
' Retire old/off-screen shots BEFORE accepting a new tap.
FOR wi=0 TO 1
    IF shot_on(wi) THEN
        IF shot_ttl(wi) > dt THEN
            shot_ttl(wi)=shot_ttl(wi)-dt
            GOSUB move_shot
            GOSUB cull_shot
        ELSE
            shot_on(wi)=0
        END IF
    END IF
NEXT wi
fire_request=0
IF fire_seen <> fire_events THEN fire_request=1:fire_seen=fire_events
IF fire_request THEN GOSUB fire_shot
RETURN

fire_control:
' Vblank samples every video frame, even while scenery is being composed.
' Producer counter / consumer acknowledgement preserves taps between updates.
IF fire_gate = 2 THEN RETURN
IF fire_gate THEN
    IF cont1.button = 0 THEN fire_gate=0
    RETURN
END IF
IF cont1.button THEN
    IF fire_held = 0 THEN
        fire_held=1
        fire_hold=0
        fire_turned=0
        ' The first observed held frame starts a fresh hold timer.
        RETURN
    END IF
    fire_hold=fire_hold+1
    ' First turn after 30 held frames; subsequent turns repeat every 18.
    IF fire_hold >= 30 THEN
        fire_hold=fire_hold-18
        fire_turned=1
        turn_phase=turn_phase+1
        turn_phase=turn_phase AND 3
        face=2
        IF turn_phase = 0 THEN face=0
        IF turn_phase = 2 THEN face=1
    END IF
ELSE
    IF fire_held THEN
        IF fire_turned = 0 THEN fire_events=fire_events+1
    END IF
    fire_held=0
    fire_hold=0
    fire_turned=0
END IF
RETURN

fire_shot:
IF hy = LANDED THEN RETURN
IF fire_timer THEN RETURN
FOR wi=0 TO 1
    IF shot_on(wi) = 0 THEN
        shot_on(wi)=1
        shot_ttl(wi)=90
        #shot_x(wi)=#hx+16
        shot_y(wi)=hy+9
        shot_dir(wi)=face
        shot_slope(wi)=0
        ' Snapshot momentum at release, independent of subsequent flight input.
        shot_speed(wi)=hspeed
        shot_drift(wi)=hdir
        IF face < 2 THEN
            IF face = 0 THEN #shot_x(wi)=#hx+28 ELSE #shot_x(wi)=#hx+1
            IF hspeed THEN
                shot_slope(wi)=1
                IF hdir = face THEN shot_slope(wi)=2
            END IF
        END IF
        fire_timer=6
        gun_kind=1:gun_timer=10
        SOUND 1,70,11
        IF face = 2 THEN
            gun_kind=2:gun_timer=24
            SOUND 1,180,10
        END IF
        EXIT FOR
    END IF
NEXT wi
RETURN

cull_shot:
IF #shot_x(wi) < #camera THEN shot_on(wi)=0
#shot_edge=#camera+255
IF #shot_x(wi) > #shot_edge THEN shot_on(wi)=0
RETURN

move_shot:
#sweep_x=#shot_x(wi):sweep_y=shot_y(wi)
#bullet_step=dt+dt
#bullet_step=#bullet_step+#bullet_step
IF shot_dir(wi) = 2 THEN
    shot_y(wi)=shot_y(wi)+dt+dt
    IF shot_speed(wi) THEN
        #bullet_step=dt
        IF shot_speed(wi) > 1 THEN #bullet_step=#bullet_step+dt
        IF shot_speed(wi) > 2 THEN #bullet_step=#bullet_step+dt
        IF shot_drift(wi) THEN
            IF #shot_x(wi) < #bullet_step THEN shot_on(wi)=0:RETURN
            #shot_x(wi)=#shot_x(wi)-#bullet_step
        ELSE
            #shot_x(wi)=#shot_x(wi)+#bullet_step
            IF #shot_x(wi) > 1534 THEN shot_on(wi)=0:RETURN
        END IF
    END IF
ELSE
    IF shot_slope(wi) = 1 THEN
        IF shot_y(wi) <= dt+24 THEN shot_on(wi)=0:RETURN
        shot_y(wi)=shot_y(wi)-dt
    END IF
    IF shot_slope(wi) = 2 THEN shot_y(wi)=shot_y(wi)+dt
    IF shot_dir(wi) THEN
        IF #shot_x(wi) < #bullet_step THEN shot_on(wi)=0:RETURN
        #shot_x(wi)=#shot_x(wi)-#bullet_step
    ELSE
        #shot_x(wi)=#shot_x(wi)+#bullet_step
        IF #shot_x(wi) > 1534 THEN shot_on(wi)=0:RETURN
    END IF
END IF
' Keep ground-crossing bombs alive until collision tests have run.
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
    #hit_x=#tank_x+3:hit_width=26:hit_top=158:hit_bottom=170
    GOSUB shot_hits_box
    IF hit_found THEN
            tank_on=0:#tank_wait=240
            #blast_x=#tank_x+8:blast_y=156
            GOSUB explode
            shot_on(wi)=0
            RETURN
    END IF
END IF
IF jet_on THEN
    #hit_x=#jet_x:hit_width=16:hit_top=jet_y+3:hit_bottom=jet_y+12
    GOSUB shot_hits_box
    IF hit_found THEN
            jet_on=0:#jet_wait=300
            #blast_x=#jet_x:blast_y=jet_y
            GOSUB explode
            shot_on(wi)=0
            RETURN
    END IF
END IF
IF drone_on THEN
    #hit_x=#drone_x+2:hit_width=12:hit_top=drone_y+2:hit_bottom=drone_y+13
    GOSUB shot_hits_box
    IF hit_found THEN
            drone_on=0:#drone_wait=240
            #blast_x=#drone_x:blast_y=drone_y
            GOSUB explode
            shot_on(wi)=0
            RETURN
    END IF
END IF
IF runner_on THEN
    IF shot_y(wi) > 155 THEN
        #ax=#shot_x(wi):#bx=#runner_x+4
        GOSUB distance_x
        IF #distance < 9 THEN
            GOSUB lose_runner
            shot_on(wi)=0
            RETURN
        END IF
    END IF
END IF
IF shot_y(wi) > 155 THEN
    #crowd_shot_x=#shot_x(wi):crowd_radius=9
    GOSUB crowd_hit
    IF crowd_struck THEN shot_on(wi)=0
END IF
IF shot_y(wi) > 171 THEN shot_on(wi)=0
RETURN

shot_hits_box:
' Swept 3x3 projectile bounds; touching a target counts, nearby air does not.
hit_found=0
IF #sweep_x+2 < #hit_x THEN
    IF #shot_x(wi)+2 < #hit_x THEN RETURN
END IF
IF #sweep_x >= #hit_x+hit_width THEN
    IF #shot_x(wi) >= #hit_x+hit_width THEN RETURN
END IF
IF sweep_y+2 < hit_top THEN
    IF shot_y(wi)+2 < hit_top THEN RETURN
END IF
IF sweep_y > hit_bottom THEN
    IF shot_y(wi) > hit_bottom THEN RETURN
END IF
hit_found=1
RETURN

people_tick:
GOSUB escape_tick
IF delivery_pending THEN
    IF home_walking = 0 THEN
        sorties=sorties+1
        delivery_pending=0
        chime_kind=3:chime_timer=36
        SOUND 2,280,11
    END IF
END IF
IF transfer_timer > dt THEN transfer_timer=transfer_timer-dt ELSE transfer_timer=0
IF hy = LANDED THEN
    IF #hx > 1384 THEN
        IF #hx < 1441 THEN
            IF aboard THEN
                IF transfer_timer = 0 THEN
                    GOSUB unload_person
                    IF unload_found = 0 THEN RETURN
                    aboard=aboard-1
                    saved=saved+1
                    hud_dirty=1
                    transfer_timer=12
                    chime_kind=2:chime_timer=10
                    SOUND 2,210,10
                    IF aboard = 0 THEN delivery_pending=1
                END IF
            END IF
        END IF
    END IF
END IF
IF runner_on THEN
    #ax=#hx+16:#bx=#runner_x+4
    GOSUB distance_x
    IF #distance > 180 THEN
        person_state(runner_id)=1
        camp_active(runner_camp)=camp_active(runner_camp)+1
        #person_x(runner_id)=#runner_x AND 65532
        runner_on=0:crowd_dirty=1
        RETURN
    END IF
    IF hy = LANDED THEN
        IF old_y < LANDED THEN
            IF #distance < 13 THEN GOSUB lose_runner:GOSUB squish_sound:RETURN
        END IF
        IF aboard < CAPACITY THEN
            IF #distance < 8 THEN
                camp_left(runner_camp)=camp_left(runner_camp)-1
                person_state(runner_id)=5
                aboard=aboard+1
                runner_on=0
                transfer_timer=12
                chime_kind=1:chime_timer=10
                SOUND 2,360,10
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
            GOSUB choose_runner
        END IF
    END IF
END IF
RETURN

unload_person:
' Each passenger keeps an identity from camp to cabin to the office door.
unload_found=0
FOR ep=0 TO 63
    IF person_state(ep) = 5 THEN
        person_state(ep)=6
        #person_x(ep)=#hx+12
        #person_x(ep)=#person_x(ep) AND 65532
        home_walking=home_walking+1:crowd_dirty=1:unload_found=1
        RETURN
    END IF
NEXT ep
RETURN

home_walk:
IF #person_x(ep) < 1480 THEN
    #person_x(ep)=#person_x(ep)+crowd_step
    IF #person_x(ep) >= 1480 THEN person_state(ep)=7:home_walking=home_walking-1
ELSE
    person_state(ep)=7:home_walking=home_walking-1
END IF
crowd_dirty=1
RETURN

lose_runner:
IF runner_on THEN
    camp_left(runner_camp)=camp_left(runner_camp)-1
    person_state(runner_id)=4
    lost=lost+1
    runner_on=0
    transfer_timer=30
    hud_dirty=1
END IF
RETURN

escape_tick:
' Every burning camp evacuates independently, including off screen/full cabin.
FOR ec=0 TO 3
    IF camp_open(ec) THEN
        IF camp_released(ec) < 16 THEN
            IF camp_escape(ec) > dt THEN
                camp_escape(ec)=camp_escape(ec)-dt
            ELSE
                ep=ec*16+camp_released(ec)
                person_state(ep)=1
                camp_active(ec)=camp_active(ec)+1
                #person_x(ep)=#camp_x(ec)
                camp_released(ec)=camp_released(ec)+1
                camp_escape(ec)=camp_escape(ec)+24-dt
                crowd_dirty=1
            END IF
        END IF
    END IF
NEXT ec
' Staggered clocks give individuals three walking speeds without 64 timers.
IF #crowd_clock >= 60000 THEN #crowd_clock=0
#crowd_clock=#crowd_clock+dt
FOR ec=0 TO 3
    IF camp_active(ec) OR home_walking THEN
        FOR ep=ec*16 TO ec*16+15
            IF person_state(ep) = 1 THEN
                GOSUB person_stride
                IF crowd_step THEN GOSUB escape_walk
            END IF
            IF person_state(ep) = 6 THEN
                GOSUB person_stride
                IF crowd_step THEN GOSUB home_walk
            END IF
        NEXT ep
    END IF
NEXT ec
' Ground contact is an event, not 64 subroutine calls on every flight update.
IF hy = LANDED THEN
    IF old_y < LANDED THEN
        FOR ep=0 TO 63
            IF person_state(ep) = 1 THEN GOSUB crowd_landing
            IF person_state(ep) = 2 THEN GOSUB crowd_landing
        NEXT ep
    END IF
END IF
RETURN

person_stride:
crowd_stride=4+person_kind(ep)
#gait_now=#crowd_clock+ep
#gait_before=#gait_now-dt
#gait_now=#gait_now/crowd_stride
#gait_before=#gait_before/crowd_stride
crowd_step=#gait_now-#gait_before
crowd_step=crowd_step*4
RETURN

escape_walk:
ec=ep/16
escape_lane=(ep AND 15)/2
escape_lane=escape_lane*8
IF ep AND 1 THEN
    #escape_goal=#camp_x(ec)+88-escape_lane
ELSE
    #escape_goal=#camp_x(ec)-88+escape_lane
END IF
IF #person_x(ep) < #escape_goal THEN
    #person_x(ep)=#person_x(ep)+crowd_step
    IF #person_x(ep) > #escape_goal THEN #person_x(ep)=#escape_goal
ELSE
    IF #person_x(ep) > #escape_goal THEN
        #person_x(ep)=#person_x(ep)-crowd_step
        IF #person_x(ep) < #escape_goal THEN #person_x(ep)=#escape_goal
    END IF
END IF
IF #person_x(ep) = #escape_goal THEN
    person_state(ep)=2
    camp_active(ec)=camp_active(ec)-1
END IF
crowd_dirty=1
RETURN

crowd_landing:
IF hy <> LANDED THEN RETURN
IF old_y >= LANDED THEN RETURN
#ax=#hx+16:#bx=#person_x(ep)+4
GOSUB distance_x
IF #distance < 13 THEN GOSUB lose_person:GOSUB squish_sound
RETURN

choose_runner:
IF hy <> LANDED THEN RETURN
#nearest_person=105
nearest_id=255
FOR ep=0 TO 63
    IF person_state(ep) = 2 THEN
        #ax=#hx+16:#bx=#person_x(ep)+4
        GOSUB distance_x
        IF #distance < #nearest_person THEN
            #nearest_person=#distance
            nearest_id=ep
        END IF
    END IF
NEXT ep
IF nearest_id = 255 THEN RETURN
runner_id=nearest_id
runner_camp=runner_id/16
#runner_x=#person_x(runner_id)
person_state(runner_id)=3
runner_on=1:crowd_dirty=1
RETURN

crowd_hit:
' One projectile can hit one exposed person; inside/removed people are skipped.
crowd_struck=0
FOR ep=0 TO 63
    IF person_state(ep) = 1 THEN GOSUB crowd_hit_person
    IF person_state(ep) = 2 THEN GOSUB crowd_hit_person
    IF crowd_struck THEN RETURN
NEXT ep
RETURN

crowd_hit_person:
#ax=#crowd_shot_x:#bx=#person_x(ep)+4
GOSUB distance_x
IF #distance < crowd_radius THEN
    GOSUB lose_person
    crowd_struck=1
END IF
RETURN

lose_person:
ec=ep/16
IF person_state(ep) = 1 THEN camp_active(ec)=camp_active(ec)-1
person_state(ep)=4
camp_left(ec)=camp_left(ec)-1
lost=lost+1
crowd_dirty=1:hud_dirty=1
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
    GOSUB jet_spawn
END IF
IF tank_on THEN GOSUB tank_tick
IF jet_on THEN GOSUB jet_tick
IF missile_on THEN GOSUB missile_tick
IF sorties >= 2 THEN
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

jet_spawn:
' A sortie counts only when the last person in a nonempty cabin has unloaded.
' Keep the launch countdown untouched throughout the first collection.
IF sorties = 0 THEN RETURN
IF #hx >= 1056 THEN RETURN
IF jet_on THEN RETURN
IF #jet_wait > #elapsed THEN
    #jet_wait=#jet_wait-#elapsed
ELSE
    jet_on=1
    jet_dir=1
    jet_turn=0
    jet_passes=0
    jet_ammo=2
    jet_fire=60
    jet_y=88
    #jet_left=24
    IF #hx > 184 THEN #jet_left=#hx-160
    #jet_right=#hx+144
    IF #jet_right > 1016 THEN #jet_right=1016
    #jet_x=#jet_right
    #jet_wait=360
END IF
RETURN

jet_tick:
' Three passes joined by broad 48-frame turns, all west of the neutral strip.
IF jet_turn THEN
    jet_age=jet_age+dt
    IF jet_age >= 48 THEN
        jet_turn=0
        jet_passes=jet_passes+1
        IF jet_dir THEN
            jet_dir=0:#jet_x=#jet_left:jet_y=58
        ELSE
            jet_dir=1:#jet_x=#jet_right:jet_y=88
        END IF
    ELSE
        jet_index=jet_age/3
        jet_offset=jet_arc(jet_index)
        jet_drop=jet_index+jet_index
        IF jet_dir THEN
            #jet_x=#jet_left-jet_offset
            jet_y=88-jet_drop
        ELSE
            #jet_x=#jet_right+jet_offset
            jet_y=58+jet_drop
        END IF
    END IF
ELSE
    #jet_step=dt+dt
    IF jet_dir THEN
        IF #jet_x <= #jet_step THEN jet_on=0:RETURN
        #jet_x=#jet_x-#jet_step
        IF jet_passes < 2 THEN
            IF #jet_x <= #jet_left THEN
                #jet_x=#jet_left:jet_turn=1:jet_age=0
            END IF
        END IF
    ELSE
        #jet_x=#jet_x+#jet_step
        IF #jet_x >= #jet_right THEN
            #jet_x=#jet_right:jet_turn=1:jet_age=0
        END IF
    END IF
END IF
GOSUB jet_attack
#ax=#hx+16:#bx=#jet_x+8
GOSUB distance_x
ay=hy+8:by=jet_y+8
GOSUB distance_y
IF #distance < 23 THEN
    IF ydistance < 11 THEN GOSUB crash
END IF
RETURN

jet_attack:
IF jet_fire > dt THEN jet_fire=jet_fire-dt ELSE jet_fire=0
IF jet_fire THEN RETURN
IF jet_passes = 0 THEN RETURN
IF jet_turn THEN RETURN
IF jet_ammo = 0 THEN RETURN
IF missile_on THEN RETURN
IF #hx >= 1056 THEN RETURN
IF jet_dir THEN
    IF #hx > #jet_x THEN RETURN
ELSE
    IF #hx < #jet_x THEN RETURN
END IF
#ax=#hx:#bx=#jet_x
GOSUB distance_x
IF #distance > 220 THEN RETURN
missile_on=1
missile_ttl=90
missile_dir=jet_dir
#missile_x=#jet_x+8
missile_y=jet_y+8
missile_aim=1
IF hy+8 > missile_y THEN missile_aim=2
IF hy+8 = missile_y THEN missile_aim=0
jet_ammo=jet_ammo-1
jet_fire=60
IF noise_timer = 0 THEN
    noise_kind=2:noise_timer=18
    SOUND 3,5,10
END IF
RETURN

missile_tick:
IF missile_ttl <= dt THEN missile_on=0:RETURN
missile_ttl=missile_ttl-dt
#missile_step=dt+dt+dt
IF missile_dir THEN
    IF #missile_x <= #missile_step THEN missile_on=0:RETURN
    #missile_x=#missile_x-#missile_step
ELSE
    #missile_x=#missile_x+#missile_step
END IF
IF #missile_x >= 1056 THEN missile_on=0:RETURN
IF missile_aim = 1 THEN
    IF missile_y <= dt+24 THEN missile_on=0:RETURN
    missile_y=missile_y-dt
END IF
IF missile_aim = 2 THEN missile_y=missile_y+dt
IF missile_y > 166 THEN missile_on=0:RETURN
#ax=#hx+16:#bx=#missile_x
GOSUB distance_x
ay=hy+8:by=missile_y
GOSUB distance_y
IF #distance < 20 THEN
    IF ydistance < 10 THEN GOSUB crash:missile_on=0
END IF
IF runner_on THEN
    IF missile_y > 153 THEN
        #ax=#runner_x+4:#bx=#missile_x
        GOSUB distance_x
        IF #distance < 10 THEN GOSUB lose_runner:missile_on=0:RETURN
    END IF
END IF
IF missile_y > 153 THEN
    #crowd_shot_x=#missile_x:crowd_radius=10
    GOSUB crowd_hit
    IF crowd_struck THEN missile_on=0
END IF
RETURN

tank_tick:
tank_motion=tank_motion+dt
tank_step=tank_motion/4
tank_motion=tank_motion AND 3
IF #tank_x < #hx THEN
    IF #tank_x < 1024 THEN #tank_x=#tank_x+tank_step
    IF #tank_x > 1024 THEN #tank_x=1024
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
            IF noise_timer = 0 THEN
                noise_kind=1:noise_timer=12
                SOUND 3,6,10
            END IF
            #shell_x=#tank_x+16
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
' Cabin/skids must overlap the visible hull, not an oversized radius.
IF hy+14 >= 163 THEN
    IF #hx+27 >= #tank_x+3 THEN
        IF #hx+4 < #tank_x+29 THEN GOSUB crash
    END IF
END IF
RETURN

tank_pose:
tank_face=2
IF #hx+28 < #tank_x+16 THEN tank_face=1
IF #hx+4 > #tank_x+16 THEN tank_face=0
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
        IF #distance < 8 THEN GOSUB lose_runner:shell_on=0:RETURN
    END IF
END IF
IF shell_y > 153 THEN
    #crowd_shot_x=#shell_x:crowd_radius=8
    GOSUB crowd_hit
    IF crowd_struck THEN shell_on=0
END IF
RETURN

crash:
IF invuln THEN RETURN
IF crash_timer THEN RETURN
lost=lost+aboard
aboard=0
FOR cp=0 TO 63
    IF person_state(cp) = 5 THEN person_state(cp)=4
NEXT cp
lives=lives-1
crash_timer=90
hud_dirty=1
#blast_x=#hx+8:blast_y=hy
GOSUB explode
RETURN

explode:
blast_timer=30
noise_timer=24
noise_kind=3
SOUND 3,6,15
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
IF #newcam > 1280 THEN #newcam=1280
#newcam=#newcam AND 65528
IF #newcam <> #camera THEN
    #camera=#newcam
    terrain_dirty=1
END IF
GOSUB stars_draw
RETURN

game_screen:
GOSUB hide_all
CLS
flag_visible=0
flag_last=255
star_visible=0
PRINT AT 0,"SAVED 00  ABOARD 00  LOST 00"
PRINT AT 32,"CAMP  1  2  3  4  SPARES"
SCREEN ground_row,0,704,32,1
SCREEN ground_row,0,736,32,1
terrain_dirty=1
GOSUB camera_tick
GOSUB crowd_draw
GOSUB hud
RETURN

stars_draw:
' High/middle/low stars move 1/2/3 pixels per eight-pixel terrain step.
star_scroll=#camera/8
IF star_visible THEN
    IF star_scroll = star_old THEN RETURN
    FOR star_i=0 TO 13
        star_pos=star_old
        GOSUB star_position
        VPOKE #star_addr,32
    NEXT star_i
END IF
FOR star_i=0 TO 13
    star_pos=star_scroll
    GOSUB star_position
    star_char=240+(star_pos AND 7)
    IF star_i AND 1 THEN star_char=star_char+8
    VPOKE #star_addr,star_char
NEXT star_i
star_old=star_scroll:star_visible=1
RETURN

star_position:
' Apply the same row-dependent rate when erasing and drawing. Byte wrap is
' intentional: even the fastest layer loops smoothly through screen edges.
IF star_row(star_i) >= 12 THEN
    star_pos=star_pos+star_pos+star_pos
ELSE
    IF star_row(star_i) >= 7 THEN star_pos=star_pos+star_pos
END IF
star_pos=star_x(star_i)-star_pos
GOSUB star_address
RETURN

star_address:
#star_addr=star_row(star_i)*32
#star_addr=#star_addr+star_pos/8
#star_addr=#star_addr+6144
RETURN

terrain:
#mapoff=#camera/8
#mapoff=#mapoff+768
SCREEN world_map,#mapoff,672,32,1
SCREEN ground_row,0,704,32,1
SCREEN ground_row,0,736,32,1
#fence_world=1056
GOSUB fence_boundary
#fence_world=1376
GOSUB fence_boundary
GOSUB flag_position
GOSUB camp_fronts
terrain_dirty=0
RETURN

camp_fronts:
' Open-door overlays use raw name-table addresses, no VDP reads.
FOR tc=0 TO 3
    IF camp_open(tc) THEN
        GOSUB camp_fire
        IF #camp_x(tc) >= #camera THEN
            #relative=#camp_x(tc)-#camera
            IF #relative < 256 THEN
                #tileaddr=#relative/8
                #tileaddr=#tileaddr+6752
                VPOKE #tileaddr,136
                ' Row 20 is committed by crowd_draw, never erased here.
            END IF
        END IF
    END IF
NEXT tc
RETURN

camp_fire:
#fire_world=#camp_x(tc)-24
FOR fire_tile=0 TO 5
    IF #fire_world >= #camera THEN
        #fire_screen=#fire_world-#camera
        IF #fire_screen < 256 THEN
            #fire_addr=#fire_screen/8
            #fire_addr=#fire_addr+6720
            fire_char=126+(fire_tile AND 1)
            VPOKE #fire_addr,fire_char
        END IF
    END IF
    #fire_world=#fire_world+8
NEXT fire_tile
RETURN

crowd_draw:
IF terrain_dirty THEN crowd_dirty=1
crowd_frame=(anim/8) AND 3
IF crowd_frame <> crowd_pose THEN
    crowd_pose=crowd_frame
    crowd_dirty=1
    IF crowd_frame AND 1 THEN
        DEFINE VRAM 5104,16,fire_frame1
    ELSE
        DEFINE VRAM 5104,16,fire_frame0
    END IF
END IF
IF crowd_dirty = 0 THEN RETURN
' Compose in RAM, then blit once: never expose a cleared crowd mid-frame.
#crowd_map=#camera/8
#crowd_map=#crowd_map+576
crowd_mask=0:crowd_shift=0
FOR tc=0 TO 3
    IF camp_open(tc) THEN
        #ax=#camp_x(tc):#bx=#camera+128
        GOSUB distance_x
        #nearest_person=224
        IF camp_active(tc) THEN #nearest_person=336
        IF #distance < #nearest_person THEN
            crowd_mask=crowd_mask OR camp_bits(tc)
            IF camp_active(tc) THEN crowd_shift=1
        END IF
    END IF
NEXT tc
IF home_walking THEN
    IF #camera > 1152 THEN
        crowd_mask=crowd_mask OR 16
        crowd_shift=1
    END IF
END IF
IF crowd_mask = 0 THEN
    GOSUB crowd_commit
    RETURN
END IF
IF crowd_shift = 0 THEN GOSUB waiting_draw:RETURN
FOR cc=0 TO 31
    crowd_cells(cc)=255
NEXT cc
FOR tc=0 TO 3
    IF crowd_mask AND camp_bits(tc) THEN
        FOR cp=tc*16 TO tc*16+15
            IF person_state(cp) = 1 THEN GOSUB crowd_plot
            IF person_state(cp) = 2 THEN GOSUB crowd_plot
        NEXT cp
    END IF
NEXT tc
IF crowd_mask AND 16 THEN
    FOR cp=0 TO 63
        IF person_state(cp) = 6 THEN GOSUB crowd_plot
    NEXT cp
END IF
' Upload into the hidden pattern set; the old row remains intact until SCREEN.
#crowd_color_addr=crowd_bank*8
#crowd_color_addr=#crowd_color_addr+4096
DEFINE VRAM #crowd_color_addr,256,VARPTR crowd_pixels(0)
FOR cc=0 TO 31
    IF crowd_cells(cc) <> 255 THEN
        #crowd_color_addr=cc+crowd_bank
        #crowd_color_addr=#crowd_color_addr*8
        #crowd_color_addr=#crowd_color_addr+12288
        DEFINE VRAM #crowd_color_addr,8,VARPTR person_colors(crowd_cells(cc))
        crowd_cells(cc)=cc+crowd_bank
    ELSE
        #crowd_index=#crowd_map+cc
        crowd_cells(cc)=world_map(#crowd_index)
    END IF
NEXT cc
GOSUB crowd_doors
GOSUB crowd_commit
crowd_bank=64-crowd_bank
RETURN

waiting_draw:
' Settled evacuees occupy distinct world-aligned cells: no pixel compositor.
#if TI994A
ASM mov @cvb__CROWD_MAP,r1
ASM ai r1,cvb_WORLD_MAP
ASM li r2,array_CROWD_CELLS
ASM li r3,32
ASM waiting_copy_loop:
ASM movb *r1+,*r2+
ASM dec r3
ASM jne waiting_copy_loop
#else
FOR cc=0 TO 31
    crowd_cells(cc)=world_map(#crowd_map+cc)
NEXT cc
#endif
#if TI994A
' Scan the 64 state bytes cheaply; only visible waiting people reach plotting.
ASM li r1,array_PERSON_STATE
ASM li r2,array__PERSON_X
ASM clr r3
ASM mov @cvb__CAMERA,r4
ASM movb @cvb_ANIM,r5
ASM srl r5,11
ASM waiting_scan_loop:
ASM clr r0
ASM movb *r1+,r0
ASM mov *r2+,r8
ASM ci r0,512
ASM jne waiting_scan_next
ASM s r4,r8
ASM ci r8,256
ASM jhe waiting_scan_next
ASM srl r8,3
ASM ai r8,array_CROWD_CELLS
ASM mov r3,r6
ASM a r5,r6
ASM andi r6,3
ASM mov r3,r7
ASM ai r7,cvb_WAITING_KIND
ASM movb *r7,r0
ASM srl r0,8
ASM a r6,r0
ASM movb *r8,r6
ASM li r7,33792
ASM cb r6,r7
ASM jne waiting_plain
ASM ai r0,12
ASM waiting_plain:
ASM sla r0,8
ASM movb r0,*r8
ASM waiting_scan_next:
ASM inc r3
ASM ci r3,64
ASM jl waiting_scan_loop
#else
FOR tc=0 TO 3
    IF crowd_mask AND camp_bits(tc) THEN
        FOR cp=tc*16 TO tc*16+15
            IF person_state(cp) = 2 THEN GOSUB waiting_plot
        NEXT cp
    END IF
NEXT tc
#endif
GOSUB crowd_doors
GOSUB crowd_commit
RETURN

crowd_commit:
' Prepare people first. Keep roof/walls and their footings on the same camera
' position: only these four short row blits occur after WAIT, before scanout.
IF terrain_dirty THEN
    #mapoff=#camera/8
    WAIT
    SCREEN world_map,#mapoff,544,32,3,192
END IF
IF crowd_mask THEN
    SCREEN crowd_cells,0,640,32,1
ELSE
    SCREEN world_map,#crowd_map,640,32,1
END IF
IF terrain_dirty THEN GOSUB terrain
crowd_dirty=0
RETURN

#if TI994A
#else
waiting_plot:
IF #person_x(cp) < #camera THEN RETURN
#crowd_rel=#person_x(cp)-#camera
IF #crowd_rel >= 256 THEN RETURN
cc=#crowd_rel/8
crowd_pose_index=anim/8+cp
crowd_pose_index=crowd_pose_index AND 3
crowd_kind=person_kind(cp)
crowd_under=crowd_cells(cc)
crowd_cells(cc)=96+crowd_kind*4+crowd_pose_index
IF crowd_under = 132 THEN crowd_cells(cc)=crowd_cells(cc)+12
RETURN

#endif

crowd_doors:
FOR tc=0 TO 3
    IF camp_open(tc) THEN
        IF #camp_x(tc) >= #camera THEN
            #relative=#camp_x(tc)-#camera
            IF #relative < 256 THEN
                cc=#relative/8
                IF crowd_cells(cc) >= 128 THEN crowd_cells(cc)=136
            END IF
        END IF
    END IF
NEXT tc
RETURN

crowd_plot:
IF #person_x(cp) < #camera THEN
    #crowd_rel=#camera-#person_x(cp)
    IF #crowd_rel = 4 THEN
        GOSUB crowd_glyph
        cc=0:crowd_shift=2:GOSUB crowd_cell
    END IF
    RETURN
END IF
#crowd_rel=#person_x(cp)-#camera
IF #crowd_rel >= 256 THEN RETURN
GOSUB crowd_glyph
cc=#crowd_rel/8
crowd_offset=#crowd_rel AND 4
IF crowd_offset THEN
    crowd_shift=1:GOSUB crowd_cell
    IF cc < 31 THEN
        cc=cc+1
        crowd_shift=2:GOSUB crowd_cell
    END IF
ELSE
    crowd_shift=0:GOSUB crowd_cell
END IF
RETURN

crowd_glyph:
crowd_kind=person_kind(cp)
crowd_pose_index=anim/8+cp
crowd_pose_index=crowd_pose_index AND 3
#crowd_glyph=crowd_kind*8+crowd_pose_index
IF person_state(cp) <> 2 THEN #crowd_glyph=#crowd_glyph+4
#crowd_glyph=#crowd_glyph*8
RETURN

crowd_cell:
#crowd_pixel=cc*8
IF crowd_cells(cc) = 255 THEN GOSUB crowd_background
#crowd_source=#crowd_glyph
IF crowd_shift = 1 THEN #crowd_source=#crowd_source+192
IF crowd_shift = 2 THEN #crowd_source=#crowd_source+384
#if TI994A
ASM mov @cvb__CROWD_SOURCE,r1
ASM ai r1,cvb_PERSON_ROWS
ASM mov @cvb__CROWD_PIXEL,r2
ASM ai r2,array_CROWD_PIXELS
ASM li r3,8
ASM crowd_merge_loop:
ASM movb *r1+,r0
ASM socb r0,*r2+
ASM dec r3
ASM jne crowd_merge_loop
#else
FOR cy=0 TO 7
    crowd_pixels(#crowd_pixel+cy)=crowd_pixels(#crowd_pixel+cy) OR person_rows(#crowd_source+cy)
NEXT cy
#endif
RETURN

crowd_background:
' Prepare once per occupied cell, then combine every overlapping silhouette.
' Office walkers share the existing wall/door palette to preserve the facade.
crowd_cells(cc)=crowd_kind*8
crowd_under=world_map(#crowd_map+cc)
IF crowd_under = 132 THEN crowd_cells(cc)=crowd_cells(cc)+32
IF crowd_under = 133 THEN crowd_cells(cc)=80
IF crowd_under = 156 THEN crowd_cells(cc)=88
IF crowd_under = 157 THEN crowd_cells(cc)=24
#crowd_source=0
IF crowd_under = 133 THEN #crowd_source=8
IF crowd_under = 156 THEN #crowd_source=16
IF crowd_under = 157 THEN #crowd_source=24
#if TI994A
ASM mov @cvb__CROWD_SOURCE,r1
ASM ai r1,cvb_CROWD_BASES
ASM mov @cvb__CROWD_PIXEL,r2
ASM ai r2,array_CROWD_PIXELS
ASM li r3,8
ASM crowd_copy_loop:
ASM movb *r1+,*r2+
ASM dec r3
ASM jne crowd_copy_loop
#else
FOR cb=0 TO 7
    crowd_pixels(#crowd_pixel+cb)=crowd_bases(#crowd_source+cb)
NEXT cb
#endif
RETURN

menu_restore:
DEFINE VRAM 4608,256,menu_font
DEFINE VRAM 12800,256,menu_colors
RETURN

fence_boundary:
' Project a connected fence from the horizon into the foreground. The anchor
' moves with the world; the near posts lean away from the viewport centre.
IF #fence_world < #camera THEN RETURN
#fence_screen=#fence_world-#camera
IF #fence_screen >= 256 THEN RETURN
fence_shape=#fence_screen/32
fence_char=fence_shape+fence_shape
fence_char=fence_char+fence_char+fence_char+fence_char+fence_char
fence_char=fence_char+160
fence_trim=0
IF fence_shape < 4 THEN fence_trim=4-fence_shape
#fence_row=6816
FOR fence_y=0 TO 1
    #fence_col=#fence_screen/8
    FOR fence_i=0 TO 4
        IF #fence_col >= fence_trim THEN
            #fence_draw=#fence_col-fence_trim
            IF #fence_draw < 32 THEN
                #fence_addr=#fence_row+#fence_draw
                ' fire_char is idle here; camp_fronts uses it after both fences.
                fire_char=fence_codes(fence_char-160)
                IF #fence_world = 1376 THEN fire_char=home_fence_codes(fence_char-160)
                IF fire_char THEN VPOKE #fence_addr,fire_char
            END IF
        END IF
        #fence_col=#fence_col+1
        fence_char=fence_char+1
    NEXT fence_i
    #fence_row=#fence_row+32
NEXT fence_y
RETURN

flag_position:
' Clear the old flag footprint. The pole ends directly on the office roof.
IF flag_visible THEN
    #flag_addr=flag_col
    #flag_addr=#flag_addr+6688
    VPOKE #flag_addr,32
    IF flag_col < 31 THEN
        #flag_addr=#flag_addr+1
        VPOKE #flag_addr,32
        #flag_addr=#flag_addr-1
    END IF
    #flag_addr=#flag_addr+32
    VPOKE #flag_addr,32
END IF
flag_visible=0
#flag_screen=1504-#camera
IF #flag_screen < 256 THEN
    flag_visible=1
    flag_col=#flag_screen/8
    #flag_addr=flag_col
    #flag_addr=#flag_addr+6688
    VPOKE #flag_addr,144
    IF flag_col < 31 THEN
        #flag_addr=#flag_addr+1
        VPOKE #flag_addr,145
        #flag_addr=#flag_addr-1
    END IF
    #flag_addr=#flag_addr+32
    VPOKE #flag_addr,146
END IF
RETURN

flag_wave:
IF flag_visible THEN
    flag_phase=anim AND 16
    IF flag_phase <> flag_last THEN
        flag_last=flag_phase
        IF flag_phase THEN
            DEFINE CHAR 144,2,flag_frame1
        ELSE
            DEFINE CHAR 144,2,flag_frame0
        END IF
    END IF
END IF
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
FOR hs=0 TO 7
    hudchar=32
    IF hs+spares > 7 THEN hudchar=140
    #hudaddr=hs
    #hudaddr=#hudaddr+6200
    VPOKE #hudaddr,hudchar
NEXT hs
hudchar=32
IF practice THEN hudchar=60
VPOKE 6152,hudchar
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
GOSUB flag_wave
IF crash_timer THEN
    SPRITE 0,209,0,0,0
    SPRITE 1,209,0,0,0
ELSE
    draw_x=#hx-#camera
    draw_y=hy-1
    GOSUB heli_pose
    SPRITE 0,draw_y,draw_x,draw_pat,15
    draw_x=draw_x+16
    draw_pat=draw_pat+4
    SPRITE 1,draw_y,draw_x,draw_pat,15
END IF
draw_slot=4:draw_on=tank_on:#draw_world=#tank_x:draw_y=155:draw_pat=48:draw_color=3
GOSUB tank_pose
IF tank_face = 0 THEN draw_pat=240
IF tank_face = 2 THEN draw_pat=248
GOSUB world_sprite
draw_slot=5:#draw_world=#tank_x+16:draw_color=3:draw_pat=236
IF tank_face = 0 THEN draw_pat=244
IF tank_face = 2 THEN draw_pat=252
GOSUB world_sprite
draw_slot=6:draw_on=runner_on:#draw_world=#runner_x:draw_y=159:draw_pat=52:draw_color=11
crowd_kind=person_kind(runner_id)
crowd_pose_index=anim/8+runner_id
crowd_pose_index=crowd_pose_index AND 3
draw_pat=crowd_kind*16+188
draw_pat=draw_pat+crowd_pose_index*4
IF crowd_kind = 1 THEN draw_color=15
IF crowd_kind = 2 THEN draw_color=10
GOSUB world_sprite
FOR di=0 TO 1
    draw_slot=di+2:draw_on=shot_on(di):#draw_world=#shot_x(di)
    draw_y=shot_y(di)-1:draw_pat=68:draw_color=11
    GOSUB world_sprite
NEXT di
draw_slot=7:draw_on=jet_on:#draw_world=#jet_x:draw_y=jet_y-1:draw_pat=60:draw_color=7
IF jet_dir = 0 THEN draw_pat=176
IF jet_turn THEN
    draw_pat=180
    IF jet_dir = 0 THEN draw_pat=184
END IF
GOSUB world_sprite
draw_slot=8:draw_on=shell_on:#draw_world=#shell_x:draw_y=shell_y-1:draw_pat=68:draw_color=8
GOSUB world_sprite
draw_slot=9:draw_on=drone_on:#draw_world=#drone_x:draw_y=drone_y-1:draw_pat=64:draw_color=10
GOSUB world_sprite
draw_slot=10:draw_on=blast_timer:#draw_world=#blast_x:draw_y=blast_y-1:draw_pat=72:draw_color=10
IF anim AND 8 THEN draw_pat=76:draw_color=8
GOSUB world_sprite
draw_slot=11:draw_on=missile_on:#draw_world=#missile_x:draw_y=missile_y-1:draw_pat=68:draw_color=8
GOSUB world_sprite
RETURN

heli_pose:
draw_pat=face*16
IF hspeed THEN
    IF hy < LANDED THEN
        IF hdir = 0 THEN draw_pat=draw_pat+80 ELSE draw_pat=draw_pat+128
    END IF
END IF
IF rotor_phase THEN draw_pat=draw_pat+8
RETURN

rotor_tick:
' Four-frame beats, but never skip both poses on a slow update.
rotor_clock=rotor_clock+dt
IF rotor_clock >= 4 THEN
    rotor_clock=rotor_clock-4
    IF rotor_clock >= 4 THEN rotor_clock=0
    rotor_phase=1-rotor_phase
END IF
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
IF gun_timer > dt THEN gun_timer=gun_timer-dt ELSE gun_timer=0
IF chime_timer > dt THEN chime_timer=chime_timer-dt ELSE chime_timer=0
IF noise_timer > dt THEN noise_timer=noise_timer-dt ELSE noise_timer=0
' Tone 0: engine load and blade pulse; quiet idle on the pad.
IF crash_timer THEN
    SOUND 0,0,0
ELSE
    #sfx_pitch=920
    sfx_volume=2
    IF hy < LANDED THEN
        #sfx_pitch=820-hspeed*48
        sfx_volume=5
        IF rotor_phase THEN sfx_volume=3
    END IF
    SOUND 0,#sfx_pitch,sfx_volume
END IF
GOSUB weapon_sound
GOSUB rescue_sound
GOSUB noise_sound
RETURN

weapon_sound:
' Tone 1: player shots take priority over nearby aircraft.
IF gun_timer THEN
    IF gun_kind = 2 THEN
        #sfx_pitch=564-gun_timer*16
        sfx_volume=6+gun_timer/6
    ELSE
        #sfx_pitch=230-gun_timer*16
        sfx_volume=5+gun_timer/2
    END IF
    SOUND 1,#sfx_pitch,sfx_volume
    RETURN
END IF
SOUND 1,0,0
IF crash_timer THEN RETURN
IF jet_on THEN
    #sfx_world=#jet_x:GOSUB sound_distance
    IF #sfx_distance < 256 THEN
        #sfx_pitch=180+#sfx_distance
        sfx_volume=8-#sfx_distance/32
        SOUND 1,#sfx_pitch,sfx_volume
        RETURN
    END IF
END IF
IF drone_on THEN
    #sfx_world=#drone_x:GOSUB sound_distance
    IF #sfx_distance < 192 THEN
        IF anim AND 16 THEN SOUND 1,150,6 ELSE SOUND 1,210,5
    END IF
END IF
RETURN

sound_distance:
IF #sfx_world > #hx THEN #sfx_distance=#sfx_world-#hx ELSE #sfx_distance=#hx-#sfx_world
RETURN

rescue_sound:
' Tone 2: rising board chirp, descending unload chirp, three-note delivery.
IF chime_timer = 0 THEN SOUND 2,0,0:RETURN
IF chime_kind = 3 THEN
    #sfx_pitch=140
    IF chime_timer > 12 THEN #sfx_pitch=210
    IF chime_timer > 24 THEN #sfx_pitch=280
ELSE
    IF chime_kind = 1 THEN
        #sfx_pitch=160+chime_timer*20
    ELSE
        #sfx_pitch=410-chime_timer*20
    END IF
END IF
SOUND 2,#sfx_pitch,10
RETURN

noise_sound:
' Fixed-rate noise avoids coupling effects to the rescue channel's pitch.
IF noise_timer THEN
    IF noise_kind = 4 THEN
        sfx_volume=4+noise_timer
        IF noise_timer > 4 THEN SOUND 3,4,sfx_volume ELSE SOUND 3,6,sfx_volume
        RETURN
    END IF
    sfx_volume=4+noise_timer/3
    IF noise_kind = 3 THEN
        SOUND 3,6,sfx_volume
    ELSE
        IF noise_kind = 2 THEN SOUND 3,5,sfx_volume ELSE SOUND 3,6,sfx_volume
    END IF
    RETURN
END IF
SOUND 3,0,0
IF crash_timer THEN RETURN
IF hy < LANDED THEN
    IF rotor_phase THEN SOUND 3,2,4 ELSE SOUND 3,2,2
END IF
RETURN

squish_sound:
' A short coarse splat for helicopter contact, separate from weapon casualties.
IF noise_kind = 3 THEN
    IF noise_timer THEN RETURN
END IF
noise_kind=4:noise_timer=8
SOUND 3,4,12
RETURN

silence:
fire_gate=2
SOUND 0,0,0
SOUND 1,0,0
SOUND 2,0,0
SOUND 3,0,0
gun_timer=0:chime_timer=0:noise_timer=0
gun_kind=0:chime_kind=0:noise_kind=0
RETURN

release_input:
FOR ri=0 TO 59
    WAIT
    IF cont1.button = 0 THEN
        IF cont1.key = 15 THEN RETURN
    END IF
NEXT ri
RETURN

pause_input:
' Require an explicit pause key for 12 consecutive frames, with a release edge.
' A single unexpected numeric-key sample must never enter the pause loop.
pause_down=0
#if TI994A
IF cont1.key = 80 THEN pause_down=1
#else
IF cont1.key = 0 THEN pause_down=1
#endif
GOSUB pause_qualify
RETURN

pause_qualify:
pause_trigger=0
IF pause_down THEN
    IF pause_latched = 0 THEN
        pause_hold=pause_hold+dt
        IF pause_hold >= 12 THEN
            pause_trigger=1
            pause_latched=1
        END IF
    END IF
ELSE
    pause_hold=0
    pause_latched=0
END IF
RETURN

pause_game:
GOSUB silence
PRINT AT 50,"PAUSED"
GOSUB release_input
#pause_last=FRAME
pause_wait:
WAIT
#pause_now=FRAME
#pause_delta=#pause_now-#pause_last
#pause_last=#pause_now
IF #pause_delta > 6 THEN #pause_delta=6
dt=#pause_delta
GOSUB pause_input
IF pause_trigger THEN GOTO pause_end
IF cont1.button THEN GOTO pause_end
GOTO pause_wait
pause_end:
PRINT AT 50,"SPARES"
GOSUB release_input
fire_gate=1
fire_held=0
fire_hold=0
fire_turned=0
hud_dirty=1
GOSUB clock_reset
dt=2
RETURN

result_screen:
GOSUB silence
GOSUB hide_all
GOSUB menu_restore
CLS
GOSUB best_update
PRINT AT 167,"MISSION COMPLETE"
IF lives = 0 THEN PRINT AT 167,"MISSION ENDED   "
IF saved = 64 THEN PRINT AT 167,"PERFECT RESCUE! "
PRINT AT 263,"PEOPLE SAVED   "
digit_value=saved:#digit_pos=6422:GOSUB digits
IF practice THEN VPOKE 6424,60
PRINT AT 327,"PEOPLE LOST    "
digit_value=lost:#digit_pos=6486:GOSUB digits
PRINT AT 391,"STRANDED       "
digit_value=64-saved-lost:#digit_pos=6550:GOSUB digits
PRINT AT 487,"BEST RESCUE    "
digit_value=best:#digit_pos=6646:GOSUB digits
IF best_practice THEN VPOKE 6648,60
PRINT AT 615,"FIRE OR 1 TO CONTINUE"
GOSUB release_input
result_wait:
WAIT
IF cont1.button THEN GOTO title
IF cont1.key = 1 THEN GOTO title
GOTO result_wait

best_update:
IF saved > best THEN
    best=saved:best_practice=practice
ELSE
    IF saved = best THEN
        IF practice = 0 THEN best_practice=0
    END IF
END IF
RETURN

practice_star:
DATA BYTE 80,32,248,32,80,0,0,0

#if TI994A
BANK 1
#endif
INCLUDE "assets.bas"
