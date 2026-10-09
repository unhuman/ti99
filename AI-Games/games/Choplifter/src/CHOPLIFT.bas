' CHOPLIFTER — original CVBasic implementation, TI-99/4A first.
' 2026 UNHUMAN AND AI C&C
' Positions are world pixels. No compound comparisons on the TI backend.
#if TI994A
BANK ROM 128
BANK SELECT 1
#endif
CONST CAPACITY = 16
CONST LANDED = 153
CONST HOME_LANDED = 160
' People chase a helicopter landed or at least this low (sprite y) over them.
CONST CHASE_Y = 113
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
DIM tank_on(2)
DIM #tank_x(2)

' Sprite ownership: heli 0,1; tank shell 2; jet missile 3; player shots 4,5;
' tank 0 halves 6,7; tank 1 halves 8,9; jet 10; air mine 11; explosion core
' 12, its three debris clusters 13-15 and an air burst's falling chunk 16.
' SPRITE FLICKER is on: the vblank copy starts one slot later each frame, so
' a crowded scanline drops a different sprite each frame instead of always
' the same one. A crash hides the helicopter and every other actor: only its
' flames (0,1) and the explosion (12-15) are drawn until it is over.
' #vaddr is shared address scratch: raw VRAM for VPOKE, relative name-table
' offset for SCREEN. Compute and use it in one routine, never across a GOSUB
' (Coleco RAM is nearly full).

' boot: opens the code segment tools/build.py hands to the short-branch pass
' (cvb_BOOT..BANK_0_FREE). Keep CONST and DIM above it: they emit EQU lines.
boot:
fire_gate=2
ON FRAME GOSUB fire_control
SPRITE FLICKER ON
' Art uploaded only at power-on lives in the TI's boot bank (assets_boot.bas);
' everything read while playing stays in the permanently selected data bank.
#if TI994A
BANK SELECT 2
#endif
DEFINE SPRITE 0,64,sprite_art
DEFINE CHAR 128,112,tile_art
DEFINE COLOR 128,112,tile_colors
' Codes 14-31 are reserved for fire/crowds; 128-239 belong to scenery.
DEFINE COLOR 126,2,fire_colors
' Codes 1-13 are the HUD band's (assets/generate.py HUD_CHARS), in the top
' screen third only: patterns at 8, colours at 8192+8.
DEFINE VRAM 8,104,hud_art
DEFINE VRAM 8200,104,hud_colors
' Codes 14-22 of the top third are the moon's (assets/generate.py MOON).
DEFINE VRAM 112,72,moon_art
DEFINE VRAM 8304,72,moon_colors
' Bottom-third characters 120-125: pad-fence cell, foothills and low horizon.
DEFINE VRAM 5056,48,low_art
DEFINE VRAM 13248,48,low_colors
DEFINE CHAR 240,16,star_bits
DEFINE COLOR 240,16,star_colors
#if TI994A
BANK SELECT 1
#endif
DEFINE COLOR 144,2,flag_colors
DEFINE CHAR 60,1,practice_star
DEFINE VRAM 5104,16,fire_frame0
#camp_x(0)=128
#camp_x(1)=384
#camp_x(2)=640
#camp_x(3)=896
best=0
best_practice=0
' Medium until the player picks another on the title screen; it then stays
' picked from game to game.
difficulty=1
GOTO title

new_game:
GOSUB release_input
saved=0
lost=0
aboard=0
lives=start_lives
sorties=0
' threat indexes the enemy tables: five levels (completed deliveries, up to
' 4) for each difficulty, so it starts at 5 * difficulty.
threat=difficulty+difficulty
threat=threat+threat+difficulty
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
GOSUB first_camp
crowd_bank=0
crowd_pose=255
crowd_dirty=1
home_walking=0
wave_id=255
last_out=255
delivery_pending=0
board_count=0
ended=0
GOSUB new_heli
GOSUB show_sortie
GOSUB clock_reset
' FIRST SORTIE waits for UP; start its tune only after that first lift.
chime_kind=3:chime_timer=191

main_loop:
' TI updates at most 30 times a second. Coleco's faster loop targets 20 and
' advances the game clock at 2/3 video speed; keep the remainder across passes.
' A busy pass starts the next one immediately. Scrolling still synchronises
' its scenery copy in crowd_commit.
#now=FRAME
#elapsed=#now-#last
#if TI994A
IF #elapsed < 2 THEN WAIT:GOTO main_loop
#else
IF #elapsed < 3 THEN WAIT:GOTO main_loop
#endif
#last=#now
#if TI994A
IF #elapsed > 6 THEN #elapsed=6
dt=#elapsed
#else
IF #elapsed > 9 THEN #elapsed=9
dt=#elapsed
pace_rem=pace_rem+dt+dt
dt=pace_rem/3
pace_rem=pace_rem-dt-dt-dt
#elapsed=dt
#endif
' BACK (FCTN-9) or REDO (FCTN-8) abandons the mission for the title. This is
' the top level of the loop, never inside a GOSUB, so no return is left behind.
GOSUB back_key
IF back_pressed THEN GOTO title
GOSUB pause_input
IF pause_trigger THEN GOSUB pause_game
IF back_pressed THEN GOTO title
anim=anim+dt
GOSUB rotor_tick
GOSUB sound_tick
IF crash_timer THEN GOTO crash_frame
' A threat that touched the helicopter last update has been drawn touching
' it; only now does it explode (hits_heli).
IF crash_pending THEN GOSUB crash:GOTO draw_frame
GOSUB fly
IF crash_timer THEN GOTO draw_frame
GOSUB weapon_tick
GOSUB people_tick
GOSUB enemy_tick
IF crash_timer THEN GOTO draw_frame
IF saved+lost = 64 THEN
    IF home_walking = 0 THEN ended=1
END IF
IF ended THEN GOTO mission_over
draw_frame:
GOSUB camera_tick
' A scrolling update draws the sprites inside crowd_commit, just before the
' vblank that moves the scenery (actors_drawn); otherwise draw them here.
actors_drawn=0
GOSUB crowd_draw
IF actors_drawn = 0 THEN GOSUB draw_actors
IF hud_dirty THEN GOSUB hud
GOTO main_loop

mission_over:
' A perfect rescue (all 64 saved) earns a fireworks display over the home
' before the results. The view moves home first if the helicopter has flown
' off while the last passenger walked in.
IF saved = 64 THEN
    IF #camera <> 1792 THEN
        #hx=1904:#move=0:GOSUB move_heli
        hy=land_y:hspeed=0
        #camera=65535
        GOSUB game_screen
    END IF
    GOSUB show_fireworks
END IF
GOTO result_screen

show_fireworks:
' The display's code and tables live in the boot bank (bank 2 on the TI): it
' is selected around the call from here, the fixed area, never from banked
' code (CLAUDE.md), and the data bank is given back afterwards.
#if TI994A
BANK SELECT 2
#endif
GOSUB fireworks
#if TI994A
BANK SELECT 1
#endif
RETURN

show_sortie:
' Draw the home scene first, then the overlay from the boot bank. Clear only
' its sky cells and restore their stars; a second full redraw would flash.
GOSUB game_screen
#if TI994A
BANK SELECT 2
#endif
GOSUB sortie_overlay
#if TI994A
BANK SELECT 1
#endif
GOSUB stars_draw
RETURN

crash_frame:
' Camps keep releasing people and walkers keep walking while the wreck falls
' and burns. old_y follows the wreck, so its impact is no landing on anyone.
old_y=hy
GOSUB escape_tick
GOSUB crash_tick
IF crash_timer = 0 THEN
    IF lives = 0 THEN GOTO result_screen
    GOSUB new_heli
    GOSUB show_sortie
    GOSUB clock_reset
END IF
GOTO draw_frame

new_heli:
GOSUB silence
rotor_clock=0:rotor_phase=0
fall_speed=0:fall_hold=0
' A new helicopter stands in the middle of the landing pad.
#hx=1888
hy=HOME_LANDED
hspeed=0
hdir=0
#move=0:GOSUB move_heli
face=1
turn_phase=2
fire_held=0
#if TI994A
fire_turned=0
fire_hold=0
#endif
fire_gate=2
crash_timer=0
crash_pending=0
invuln=120
shot_on(0)=0
shot_on(1)=0
fire_timer=0
transfer_timer=0
tank_on(0)=0
tank_on(1)=0
sink_clock=0
jet_on=0
jet_turn=0
missile_on=0
drone_on=0
shell_on=0
tank_motion=0
drone_motion=0
blast_timer=0
#tank_wait=150
#jet_wait=#jet_delay(threat)
#drone_wait=#drone_delay(threat)
#camera=65535
hud_dirty=1
RETURN

clock_reset:
fire_gate=1
IF crash_timer THEN fire_gate=2
fire_held=0
#if TI994A
fire_hold=0:fire_turned=0
#else
pace_rem=0
#endif
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
        IF hy < land_y THEN
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
            IF hy >= land_y THEN
                hy=land_y
                IF fall_speed > 1 THEN invuln=0:GOSUB crash:RETURN
                fall_speed=0:fall_hold=0
            END IF
        END IF
    ELSE
        fall_speed=0:fall_hold=0
        ' Without vertical thrust the helicopter sinks 1 px every 6 frames
        ' (10 px/s), including while it flies sideways.
        IF hy < land_y THEN
            sink_clock=sink_clock+dt
            IF sink_clock >= 6 THEN
                sink_clock=sink_clock-6
                hy=hy+1
            END IF
        END IF
    END IF
END IF
IF hy = land_y THEN
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
    IF #hx > 2008 THEN #hx=2008
END IF
' The visible x, #hv: the camera follows in 8-pixel steps (camera_tick), and
' while it follows the helicopter is drawn - and hit, and fires - at screen
' x 112, #hx rounded down to 8, instead of sawtoothing 0-7 px against the
' scenery as it scrolls. At either end of the world the camera stops and the
' helicopter is drawn where it is.
#hv=#hx
IF #hx > 112 THEN
    IF #hx < 1904 THEN #hv=#hx AND 65528
END IF
' The post-office apron is seven pixels nearer, east of the fence's last ink.
land_y=LANDED
IF #hv >= 1840 THEN land_y=HOME_LANDED
IF hy > land_y THEN hy=land_y:hspeed=0
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
' First the rotor's chop (chop_period frames a beat, set by sound_tick; 0 for
' none), timed here every video frame so the beat stays steady however long
' an update takes: low white noise restarted on each beat, its volume falling
' away frame by frame (chop_air on the wing, chop_ground idling on the pad).
' Volume and noise-type writes are single bytes, and sound_tick fences its
' own writes with sound_busy, so this never lands between the two bytes of a
' main-loop frequency write. A noise effect (noise_timer) has the channel.
IF chop_period THEN
    chop_frame=chop_frame+1
    IF chop_frame >= chop_period THEN chop_frame=0
    IF noise_timer = 0 THEN
        IF sound_busy = 0 THEN
            IF chop_frame = 0 THEN SOUND 3,6
            IF hy = land_y THEN
                SOUND 3,,chop_ground(chop_frame)
            ELSE
                SOUND 3,,chop_air(chop_frame)
            END IF
        END IF
    END IF
END IF
IF fire_gate = 2 THEN RETURN
' SPACE (TI) or the ColecoVision right button turns one step per press.
#if TI994A
IF cont1.key = 32 THEN
#else
IF cont1.button2 THEN
#endif
    IF turn_key = 0 THEN
        turn_key=1
        IF hy < land_y THEN GOSUB turn_step
    END IF
ELSE
    turn_key=0
END IF
IF fire_gate THEN
    IF cont1.button = 0 THEN fire_gate=0
    RETURN
END IF
#if TI994A
IF cont1.button THEN
    IF fire_held = 0 THEN
        fire_held=1
        fire_hold=0
        fire_turned=0
        ' The first observed held frame starts a fresh hold timer.
        RETURN
    END IF
    ' The helicopter cannot turn while it is on the ground.
    IF hy = land_y THEN fire_hold=0:RETURN
    fire_hold=fire_hold+1
    ' First turn after 18 held frames (0.3 s; a tap is shorter); subsequent
    ' turns repeat every 15.
    IF fire_hold >= 18 THEN
        fire_hold=fire_hold-15
        fire_turned=1
        GOSUB turn_step
    END IF
ELSE
    IF fire_held THEN
        IF fire_turned = 0 THEN fire_events=fire_events+1
    END IF
    fire_held=0
    fire_hold=0
    fire_turned=0
END IF
#else
' ColecoVision's left button fires on release, even after a long hold;
' the right button above is the only turn control.
IF cont1.button THEN
    fire_held=1
ELSE
    IF fire_held THEN fire_events=fire_events+1
    fire_held=0
END IF
#endif
RETURN

turn_step:
' One turn: right, front, left, front, right ... (turn_phase 0-3).
turn_phase=turn_phase+1
turn_phase=turn_phase AND 3
face=2
IF turn_phase = 0 THEN face=0
IF turn_phase = 2 THEN face=1
RETURN

fire_shot:
IF hy = land_y THEN RETURN
IF fire_timer THEN RETURN
FOR wi=0 TO 1
    IF shot_on(wi) = 0 THEN
        shot_on(wi)=1
        shot_ttl(wi)=90
        #shot_x(wi)=#hv+16
        shot_y(wi)=hy+9
        shot_dir(wi)=face
        shot_slope(wi)=0
        ' Snapshot momentum at release, independent of subsequent flight input.
        shot_speed(wi)=hspeed
        shot_drift(wi)=hdir
        IF face < 2 THEN
            IF face = 0 THEN #shot_x(wi)=#hv+28 ELSE #shot_x(wi)=#hv+1
            IF hspeed THEN
                shot_slope(wi)=1
                IF hdir = face THEN shot_slope(wi)=2
            END IF
        END IF
        fire_timer=6
        IF face = 2 THEN
            gun_kind=2:gun_timer=24
            SOUND 1,180,10
        ELSE
            ' A shot cracks once; the bomb alone keeps the falling whistle.
            gun_kind=1:gun_timer=3
            SOUND 1,180,10
            GOSUB squish_sound
        END IF
        EXIT FOR
    END IF
NEXT wi
RETURN

cull_shot:
IF #shot_x(wi) < #camera THEN shot_on(wi)=0
IF #shot_x(wi) > #camera+255 THEN shot_on(wi)=0
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
            IF #shot_x(wi) > 2046 THEN shot_on(wi)=0:RETURN
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
        IF #shot_x(wi) > 2046 THEN shot_on(wi)=0:RETURN
    END IF
END IF
' Bombs (front view) only destroy tanks, which sit on the foreground plane
' below the crowd row; strafing (side views) opens barracks and downs jets
' and air mines. Keep ground-crossing bombs alive until these tests have run.
IF shot_dir(wi) = 2 THEN
    FOR ti=0 TO 1
        IF tank_on(ti) THEN
            #hit_x=#tank_x(ti)+3:hit_width=26:hit_top=177:hit_bottom=189
            GOSUB shot_hits_box
            IF hit_found THEN
                tank_on(ti)=0:#tank_wait=240
                #blast_x=#tank_x(ti)+8:blast_y=176
                GOSUB explode_ground
                shot_on(wi)=0
                RETURN
            END IF
        END IF
    NEXT ti
    GOTO shot_people
END IF
' A barrack is struck where its drawn hut is: the shot (3x3) touching
' x-16..x+15 at or below the roof line (y 153).
IF shot_y(wi) > 150 THEN
    FOR wc=0 TO 3
        IF camp_open(wc) = 0 THEN
            #ax=#shot_x(wi)+1:#bx=#camp_x(wc)
            GOSUB distance_x
            IF #distance < 17 THEN
                camp_open(wc)=1
                terrain_dirty=1
                shot_on(wi)=0
                #blast_x=#camp_x(wc)-8:blast_y=148
                GOSUB explode_ground
                RETURN
            END IF
        END IF
    NEXT wc
END IF
IF jet_on THEN
    ' The jet as drawn (jet_box): its fuselage, then its wings and tail.
    GOSUB jet_body
    GOSUB shot_hits_box
    IF hit_found = 0 THEN
        GOSUB jet_wings
        GOSUB shot_hits_box
    END IF
    IF hit_found THEN
        jet_on=0:#jet_wait=#jet_delay(threat)
        #blast_x=#jet_x:blast_y=jet_y
        GOSUB explode_air
        shot_on(wi)=0
        RETURN
    END IF
END IF
IF drone_on THEN
    #hit_x=#drone_x+3:hit_width=9:hit_top=drone_y+3:hit_bottom=drone_y+11
    GOSUB shot_hits_box
    IF hit_found THEN
        drone_on=0:#drone_wait=#drone_delay(threat)
        #blast_x=#drone_x:blast_y=drone_y
        GOSUB explode_air
        shot_on(wi)=0
        RETURN
    END IF
END IF
shot_people:
' A sideways shot crossing the crowd row can hit a person, and stops at the
' ground. Bombs fall on the tanks' plane, in front of the crowd: they pass
' people by and burst below the tanks' tracks.
IF shot_dir(wi) < 2 THEN
    IF shot_y(wi) > 155 THEN
        IF shot_y(wi) < 172 THEN
            #crowd_shot_x=#shot_x(wi):crowd_radius=9
            GOSUB crowd_hit
            IF crowd_struck THEN GOTO shot_burst
        END IF
    END IF
END IF
IF shot_y(wi) > 171 THEN
    IF shot_dir(wi) < 2 THEN GOTO shot_miss
    IF shot_y(wi) > 185 THEN GOTO shot_miss
END IF
RETURN

shot_miss:
' The ground and no target.
crowd_struck=0
shot_burst:
' A shot or bomb ends in a person (crowd_struck) or on the ground: a bomb
' bursts small, a shot puffs tiny, with the spray only for a person, where it
' is but no lower than the ground's surface.
shot_on(wi)=0
#ax=#shot_x(wi)-7:ay=shot_y(wi)-7
IF ay > 176 THEN ay=176
IF shot_dir(wi) = 2 THEN
    IF crowd_struck THEN GOTO burst_small
    GOTO burst_small_core
END IF
IF crowd_struck THEN GOTO burst_tiny
GOTO burst_tiny_core

hits_heli:
' Does a threat's box (#hit_x..#hit_x+hit_width-1, hit_top..hit_bottom)
' touch the helicopter as drawn at its visible x (#hv)? Its cabin, nose and
' skids fill rows 5-14 and, in the side views, its tail boom rows 8-9; the
' columns of each depend on the facing (heli_box). The rotor blade, the mast,
' the tail rotor and the sprite's empty corners do not count. A hit is not a
' crash yet: the main loop crashes on the next update, so the frame between
' shows the threat touching the helicopter.
hit_found=0
IF invuln THEN RETURN
IF hit_bottom < hy+5 THEN RETURN
IF hit_top > hy+14 THEN RETURN
hit_k=face+face
hit_k=hit_k+hit_k
#ax=#hv+heli_box(hit_k):#bx=#hv+heli_box(hit_k+1)
GOSUB hits_span
IF hit_found THEN RETURN
IF face = 2 THEN RETURN
IF hit_bottom < hy+8 THEN RETURN
IF hit_top > hy+9 THEN RETURN
#ax=#hv+heli_box(hit_k+2):#bx=#hv+heli_box(hit_k+3)
hits_span:
' Columns #ax..#bx (inclusive) against the threat's box.
IF #hit_x+hit_width <= #ax THEN RETURN
IF #hit_x > #bx THEN RETURN
hit_found=1
crash_pending=1
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
        ' Each completed delivery raises the threat a level, up to 4 within
        ' the chosen difficulty's row (new_game starts it at 5 * difficulty).
        IF sorties <= 4 THEN threat=threat+1
        delivery_pending=0
        chime_kind=3:chime_timer=36
        SOUND 2,280,11
    END IF
END IF
IF transfer_timer > dt THEN transfer_timer=transfer_timer-dt ELSE transfer_timer=0
' Unloading needs the whole helicopter (all 32 pixels) on the landing pad,
' the flat back of the pad west of the building: 1872 <= #hv <= 1912.
IF hy = land_y THEN
    IF #hv >= 1872 THEN
        IF #hv <= 1912 THEN
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
                    IF aboard = 0 THEN delivery_pending=1:last_out=ep
                END IF
            END IF
        END IF
    END IF
END IF
GOSUB board_tick
RETURN

unload_person:
' Each passenger keeps an identity from camp to cabin to the office door.
unload_found=0
FOR ep=0 TO 63
    IF person_state(ep) = 5 THEN
        person_state(ep)=6
        ' Begin under the cabin, then walk out toward the office.
        #person_x(ep)=#hv+12
        #person_x(ep)=#person_x(ep) AND 65532
        home_walking=home_walking+1:crowd_dirty=1:unload_found=1
        RETURN
    END IF
NEXT ep
RETURN

escape_tick:
' Every burning camp lets its people out independently, including off screen
' or with the cabin full: one every 16 frames while fewer than six of them are
' outside, as in the Apple II original, where only a handful are out at a time
' and more come out as others are picked up. camp_active counts a camp's
' people outside: running about or standing (1, 2), chasing (3), homing (8).
FOR ec=0 TO 3
    IF camp_open(ec) THEN
        IF camp_escape(ec) > dt THEN
            camp_escape(ec)=camp_escape(ec)-dt
        ELSE
            IF camp_released(ec) < 16 THEN
                IF camp_active(ec) < 6 THEN
                    ep=ec*16+camp_released(ec)
                    person_state(ep)=1
                    camp_active(ec)=camp_active(ec)+1
                    #person_x(ep)=#camp_x(ec)
                    camp_released(ec)=camp_released(ec)+1
                    camp_escape(ec)=camp_escape(ec)+16-dt
                    crowd_dirty=1
                END IF
            END IF
        END IF
    END IF
NEXT ec
' Staggered clocks give individuals three walking speeds without 64 timers.
IF #crowd_clock >= 60000 THEN #crowd_clock=0
#crowd_clock=#crowd_clock+dt
' The walk also notes which camps have anyone in view (crowd_seen), for the
' crowd renderer and boarding. #distance: the camp from the view's centre.
crowd_seen=0
FOR ec=0 TO 3
    IF camp_active(ec) OR home_walking THEN
        #ax=#camp_x(ec):#bx=#camera+128
        GOSUB distance_x
#if TI994A
        GOSUB walk_camp
#else
        FOR ep=ec*16 TO ec*16+15
            GOSUB walk_person
        NEXT ep
#endif
    END IF
NEXT ec
IF home_walking THEN GOSUB wave_tick
' Ground contact is an event, not 64 subroutine calls on every flight update.
IF hy = land_y THEN
    IF old_y < land_y THEN
        FOR ep=0 TO 63
            IF person_state(ep) = 1 THEN GOSUB crowd_landing
            IF person_state(ep) = 2 THEN GOSUB crowd_landing
            IF person_state(ep) = 3 THEN GOSUB crowd_landing
            IF person_state(ep) = 8 THEN GOSUB crowd_landing
        NEXT ep
    END IF
END IF
RETURN

#if TI994A
walk_camp:
' Native walk of camp ec's people outside and walking home. The portable
' walk_person below is the same rule for one person (a test holds them equal):
' - Anyone outside (1 running about, 2 standing, 3 chasing, 8 homing) within
'   16 px of the view marks the camp in crowd_seen.
' - Homing (8): a pixel a frame back to the hut, then running about again.
' - Running about (1, 2), only with the camp within 400 px of the view's
'   centre (#distance; further out nobody sees them, so they stand still):
'   standing, they wave (the standing poses); one standing within 40 px of
'   the door of a helicopter landed or low over them (CHASE_Y, 113 here; not
'   crashing) stays there, waiting to get in, while runners pass beneath; a standing one sets off when its goal moves on (every 128
'   frames from its phase); a runner steps 4 px a stride to its goal and
'   stands there: for index i in the camp, camp_x - 128 + roam_goal(8 * (i
'   AND 1) + (((clock + roam_phase(i)) / 128 + 3 * (i / 2)) AND 7)), so even
'   and odd people never share a spot (ROAM_GOALS in assets/generate.py).
' - Walking home (6) to the office door (1960), except the one waving.
' Strides crossed = (clock+p)/stride - (clock+p-dt)/stride, 4 px each.
ASM jmp walk_start
' walk_steps: r7 = pixels to step this update (0 for none); uses r0, r1, r9.
ASM walk_steps:
ASM mov r3,r9
ASM ai r9,cvb_PERSON_KIND
ASM movb *r9,r9
ASM srl r9,8
ASM ai r9,4
ASM mov r2,r1
ASM a r3,r1
ASM clr r0
ASM div r9,r0
ASM mov r0,r7
ASM mov r2,r1
ASM a r3,r1
ASM s r4,r1
ASM clr r0
ASM div r9,r0
ASM s r0,r7
ASM sla r7,2
ASM andi r7,255
ASM b *r11
' walk_goal: r0 = person r3's goal; uses r1, r9.
ASM walk_goal:
ASM mov r3,r9
ASM andi r9,15
ASM mov r9,r1
ASM ai r1,cvb_ROAM_PHASE
ASM movb *r1,r1
ASM srl r1,8
ASM a r2,r1
ASM srl r1,7
ASM andi r9,14
ASM a r9,r1
ASM srl r9,1
ASM a r9,r1
ASM andi r1,7
ASM mov r3,r9
ASM andi r9,1
ASM sla r9,3
ASM a r9,r1
ASM ai r1,cvb_ROAM_GOAL
ASM movb *r1,r0
ASM srl r0,8
ASM ai r0,-128
ASM a r5,r0
ASM b *r11
' r2 clock, r3 person, r4 dt, r5 camp x, r6 -> its x, r8 its x, r9 state.
ASM walk_start:
ASM movb @cvb_EC,r3
ASM srl r3,8
ASM sla r3,4
ASM mov @cvb__CROWD_CLOCK,r2
ASM movb @cvb_DT,r4
ASM srl r4,8
ASM mov r3,r5
ASM srl r5,3
ASM ai r5,array__CAMP_X
ASM mov *r5,r5
ASM walk_loop:
ASM mov r3,r9
ASM ai r9,array_PERSON_STATE
ASM movb *r9,r9
ASM srl r9,8
ASM mov r3,r6
ASM a r3,r6
ASM ai r6,array__PERSON_X
ASM mov *r6,r8
ASM ci r9,6
ASM jne walk_not_six
ASM b @walk_six
ASM walk_not_six:
ASM ci r9,3
ASM jeq walk_seen
ASM ci r9,8
ASM jeq walk_seen
ASM ci r9,1
ASM jl walk_skip
ASM ci r9,2
ASM jh walk_skip
ASM mov @cvb__DISTANCE,r0
ASM ci r0,400
ASM jl walk_seen
ASM walk_skip:
ASM b @walk_next
ASM walk_seen:
ASM mov r8,r0
ASM s @cvb__CAMERA,r0
ASM ai r0,16
ASM ci r0,288
ASM jhe walk_unseen
ASM mov r3,r1
ASM srl r1,4
ASM ai r1,cvb_CAMP_BITS
ASM movb *r1,r1
ASM socb r1,@cvb_CROWD_SEEN
ASM walk_unseen:
ASM ci r9,3
ASM jeq walk_skip
ASM ci r9,8
ASM jne walk_roamer
ASM b @walk_homing
ASM walk_roamer:
ASM ci r9,2
ASM jne walk_roam
ASM movb @cvb_CRASH_TIMER,r0
ASM jne walk_roam
ASM movb @cvb_HY,r0
ASM srl r0,8
ASM ci r0,113
ASM jl walk_roam
ASM mov @cvb__HV,r0
ASM ai r0,12
ASM s r8,r0
ASM abs r0
ASM ci r0,40
ASM jl walk_skip
ASM walk_roam:
ASM ci r9,1
ASM jeq walk_run
' Standing: only once its clock has crossed a 128-frame mark.
ASM mov r3,r1
ASM andi r1,15
ASM ai r1,cvb_ROAM_PHASE
ASM movb *r1,r1
ASM srl r1,8
ASM a r2,r1
ASM andi r1,127
ASM c r1,r4
ASM jhe walk_skip
ASM bl @walk_goal
ASM c r8,r0
ASM jeq walk_skip
ASM li r1,256
ASM jmp walk_state
ASM walk_run:
ASM bl @walk_steps
ASM mov r7,r7
ASM jeq walk_next
ASM li r0,256
ASM movb r0,@cvb_CROWD_DIRTY
ASM bl @walk_goal
ASM c r8,r0
ASM jhe walk_back
ASM a r7,r8
ASM c r8,r0
ASM jle walk_store
ASM mov r0,r8
ASM jmp walk_store
ASM walk_back:
ASM jeq walk_store
ASM s r7,r8
ASM c r8,r0
ASM jhe walk_store
ASM mov r0,r8
ASM walk_store:
ASM mov r8,*r6
ASM c r8,r0
ASM jne walk_next
ASM li r1,512
' walk_state: the new state in r1's high byte.
ASM walk_state:
ASM mov r3,r9
ASM ai r9,array_PERSON_STATE
ASM movb r1,*r9
ASM li r0,256
ASM movb r0,@cvb_CROWD_DIRTY
ASM walk_next:
ASM inc r3
ASM mov r3,r0
ASM andi r0,15
ASM jeq walk_done
ASM b @walk_loop
' Homing: a pixel a frame to the hut, then running about again.
ASM walk_homing:
ASM li r0,256
ASM movb r0,@cvb_CROWD_DIRTY
ASM c r8,r5
ASM jhe walk_westward
ASM a r4,r8
ASM c r8,r5
ASM jl walk_keep
ASM jmp walk_arrive
ASM walk_westward:
ASM s r4,r8
ASM c r8,r5
ASM jh walk_keep
ASM walk_arrive:
ASM mov r5,*r6
ASM li r1,256
ASM jmp walk_state
ASM walk_keep:
ASM mov r8,*r6
ASM jmp walk_next
' Walking home to the office, except the one waving (wave_id).
ASM walk_six:
ASM movb @cvb_WAVE_ID,r0
ASM srl r0,8
ASM c r0,r3
ASM jeq walk_next
ASM bl @walk_steps
ASM mov r7,r7
ASM jeq walk_next
ASM li r0,256
ASM movb r0,@cvb_CROWD_DIRTY
ASM ci r8,1960
ASM jhe walk_inside
ASM a r7,r8
ASM mov r8,*r6
ASM ci r8,1960
ASM jl walk_next
ASM walk_inside:
ASM li r1,1792
ASM movb @cvb_HOME_WALKING,r0
ASM ai r0,-256
ASM movb r0,@cvb_HOME_WALKING
ASM jmp walk_state
ASM walk_done:
RETURN
#else
walk_person:
' Person ep of camp ec: the portable twin of walk_camp (the same rules).
IF person_state(ep) = 6 THEN GOTO walk_office
IF person_state(ep) = 3 THEN GOTO walk_seen
IF person_state(ep) = 8 THEN GOTO walk_seen
IF person_state(ep) = 0 THEN RETURN
IF person_state(ep) > 2 THEN RETURN
IF #distance >= 400 THEN RETURN
walk_seen:
#crowd_rel=#person_x(ep)-#camera
#crowd_rel=#crowd_rel+16
IF #crowd_rel < 288 THEN crowd_seen=crowd_seen OR camp_bits(ec)
IF person_state(ep) = 3 THEN RETURN
IF person_state(ep) = 8 THEN GOTO walk_homing
IF person_state(ep) = 2 THEN
    IF crash_timer = 0 THEN
        IF hy >= CHASE_Y THEN
            #crowd_rel=#hv+12
            IF #crowd_rel > #person_x(ep) THEN
                #crowd_rel=#crowd_rel-#person_x(ep)
            ELSE
                #crowd_rel=#person_x(ep)-#crowd_rel
            END IF
            IF #crowd_rel < 40 THEN RETURN
        END IF
    END IF
    escape_lane=ep AND 15
    #crowd_rel=#crowd_clock+roam_phase(escape_lane)
    escape_lane=#crowd_rel AND 127
    IF escape_lane >= dt THEN RETURN
    GOSUB roam_target
    IF #person_x(ep) <> #escape_goal THEN person_state(ep)=1:crowd_dirty=1
    RETURN
END IF
GOSUB person_stride
IF crowd_step = 0 THEN RETURN
crowd_dirty=1
GOSUB roam_target
IF #person_x(ep) < #escape_goal THEN
    #person_x(ep)=#person_x(ep)+crowd_step
    IF #person_x(ep) > #escape_goal THEN #person_x(ep)=#escape_goal
ELSE
    IF #person_x(ep) > #escape_goal THEN
        #person_x(ep)=#person_x(ep)-crowd_step
        IF #person_x(ep) < #escape_goal THEN #person_x(ep)=#escape_goal
    END IF
END IF
IF #person_x(ep) = #escape_goal THEN person_state(ep)=2
RETURN

walk_homing:
crowd_dirty=1
IF #person_x(ep) < #camp_x(ec) THEN
    #person_x(ep)=#person_x(ep)+dt
    IF #person_x(ep) < #camp_x(ec) THEN RETURN
ELSE
    #person_x(ep)=#person_x(ep)-dt
    IF #person_x(ep) > #camp_x(ec) THEN RETURN
END IF
#person_x(ep)=#camp_x(ec)
person_state(ep)=1
RETURN

walk_office:
IF ep = wave_id THEN RETURN
GOSUB person_stride
IF crowd_step THEN GOSUB home_walk
RETURN

roam_target:
' #escape_goal: person ep's goal, as in walk_camp's walk_goal.
escape_lane=ep AND 15
#escape_goal=#crowd_clock+roam_phase(escape_lane)
#escape_goal=#escape_goal/128
escape_lane=escape_lane AND 14
#escape_goal=#escape_goal+escape_lane
escape_lane=escape_lane/2
#escape_goal=#escape_goal+escape_lane
escape_lane=#escape_goal AND 7
IF ep AND 1 THEN escape_lane=escape_lane+8
#escape_goal=#camp_x(ec)+roam_goal(escape_lane)
#escape_goal=#escape_goal-128
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

home_walk:
IF #person_x(ep) < 1960 THEN
    #person_x(ep)=#person_x(ep)+crowd_step
    IF #person_x(ep) >= 1960 THEN person_state(ep)=7:home_walking=home_walking-1
ELSE
    person_state(ep)=7:home_walking=home_walking-1
END IF
crowd_dirty=1
RETURN
#endif

wave_tick:
' Some rescued people stop just short of the home to wave at the helicopter
' before going in: one in four, and always the last one out of the cabin
' (last_out), who cuts short anyone else's wave. One waves at a time, for 90
' frames, at x=1932 (on the ground 4 px short of the building, for
' contrast), then steps past the spot (1932-1939, which no walk step can
' jump) so nobody waves twice. The walk skips wave_id and the crowd
' draws it with the standing poses, whose arm goes up and down.
IF wave_id < 64 THEN
    IF wave_time > dt THEN wave_time=wave_time-dt ELSE GOSUB wave_end
END IF
FOR ep=0 TO 63
    IF person_state(ep) = 6 THEN
        IF #person_x(ep) >= 1932 THEN
            IF #person_x(ep) < 1940 THEN GOSUB wave_choose
        END IF
    END IF
NEXT ep
RETURN

wave_end:
#person_x(wave_id)=1940
wave_id=255
crowd_dirty=1
RETURN

wave_choose:
IF ep = wave_id THEN RETURN
IF ep = last_out THEN
    IF wave_id < 64 THEN GOSUB wave_end
ELSE
    IF wave_id < 64 THEN RETURN
    IF ep AND 3 THEN RETURN
END IF
wave_id=ep
wave_time=90
#person_x(ep)=1932
crowd_dirty=1
RETURN

crowd_landing:
' escape_tick calls this only on the first grounded update.
#ax=#hv+16:#bx=#person_x(ep)+4
GOSUB distance_x
IF #distance < 13 THEN GOSUB lose_person:GOSUB squish_sound
RETURN

board_tick:
' Boarding, as in the Apple II original. With the helicopter landed, or low
' over them (CHASE_Y), the nearest person outside within 104 px of its door
' (running about or standing; a homing one only when it lands within 24 px)
' starts chasing it (3), one more each update, up to six or the free seats.
' Once as many chase as may, anyone chasing farther than the nearest one
' waiting gives up (board_run). Only camps with someone in view (crowd_seen)
' are searched: anyone within reach of the door is in view.
#board_door=#hv+12
board_seats=CAPACITY-aboard
IF board_seats > 6 THEN board_seats=6
nearest_id=255
IF hy >= CHASE_Y THEN
    #nearest_person=104
    #bx=#board_door
    FOR ec=0 TO 3
        IF crowd_seen AND camp_bits(ec) THEN
            FOR ep=ec*16 TO ec*16+15
                GOSUB board_candidate
            NEXT ep
        END IF
    NEXT ec
    IF nearest_id < 255 THEN
        IF board_count < board_seats THEN
            person_state(nearest_id)=3
            board_count=board_count+1
            crowd_dirty=1
            ' A free place was taken: nobody gives up this update.
            nearest_id=255
        END IF
    END IF
END IF
IF board_count = 0 THEN RETURN
FOR ep=0 TO 63
    IF person_state(ep) = 3 THEN GOSUB board_run
NEXT ep
RETURN

board_candidate:
' Person ep, if it could chase and is nearer the door (#bx) than the best yet.
' One standing under a hovering helicopter (within 24 px) stays where it is:
' chasers stop there 10-17 px from the door, and up to 3 more on the grid.
IF person_state(ep) = 8 THEN
    IF hy <> land_y THEN RETURN
    #ax=#person_x(ep):GOSUB distance_x
    IF #distance >= 24 THEN RETURN
ELSE
    IF person_state(ep) = 0 THEN RETURN
    IF person_state(ep) > 2 THEN RETURN
    #ax=#person_x(ep):GOSUB distance_x
    IF hy <> land_y THEN
        IF #distance < 24 THEN RETURN
    END IF
END IF
IF #distance >= #nearest_person THEN RETURN
#nearest_person=#distance
nearest_id=ep
RETURN

board_run:
' A chaser runs for the door at a pixel a frame, never past the DMZ fence
' (x 1472). It gives up and runs home (8) with the helicopter more than 180 px
' away, or when someone nearer is waiting (nearest_id) and as many chase as
' may. With the cabin full it stops and waves it off; under a hovering
' helicopter it stops 10-17 px from the door, so some stand right where it
' would land, as in the original.
ec=ep/16
#ax=#person_x(ep):#bx=#board_door
GOSUB distance_x
IF #distance > 180 THEN GOTO chase_home
IF nearest_id < 255 THEN
    IF #distance > #nearest_person THEN GOTO chase_home
END IF
IF aboard >= CAPACITY THEN GOTO chase_stop
IF hy <> land_y THEN
    #ax=ep AND 7
    #ax=#ax+10
    IF #distance < #ax THEN GOTO chase_stop
ELSE
    IF #distance < 8 THEN
        camp_left(ec)=camp_left(ec)-1
        camp_active(ec)=camp_active(ec)-1
        person_state(ep)=5
        aboard=aboard+1
        board_count=board_count-1
        chime_kind=1:chime_timer=10
        SOUND 2,360,10
        hud_dirty=1:crowd_dirty=1
        RETURN
    END IF
END IF
IF #person_x(ep) < #board_door THEN
    #person_x(ep)=#person_x(ep)+dt
    IF #person_x(ep) > 1472 THEN #person_x(ep)=1472
ELSE
    #person_x(ep)=#person_x(ep)-dt
END IF
crowd_dirty=1
RETURN

chase_stop:
person_state(ep)=2
GOTO chase_end
chase_home:
person_state(ep)=8
chase_end:
' Back on the 4-pixel walking grid.
#person_x(ep)=#person_x(ep) AND 65532
board_count=board_count-1
crowd_dirty=1
RETURN

crowd_hit:
' One projectile can hit one exposed person; inside/removed people are skipped.
crowd_struck=0
FOR ep=0 TO 63
    IF person_state(ep) = 1 THEN GOSUB crowd_hit_person
    IF person_state(ep) = 2 THEN GOSUB crowd_hit_person
    IF person_state(ep) = 3 THEN GOSUB crowd_hit_person
    IF person_state(ep) = 8 THEN GOSUB crowd_hit_person
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
' Everyone this can happen to is outside (1, 2, 3 or 8).
ec=ep/16
camp_active(ec)=camp_active(ec)-1
IF person_state(ep) = 3 THEN board_count=board_count-1
person_state(ep)=4
camp_left(ec)=camp_left(ec)-1
lost=lost+1
crowd_dirty=1:hud_dirty=1
RETURN

enemy_tick:
' Enemies act while the helicopter is west of the DMZ fence (x=1488).
' A shell fired this update (tank_tick) first moves on the next one, so it is
' always drawn at the muzzle before it can do anything.
IF #hx < 1488 THEN GOSUB jet_spawn
IF shell_on THEN GOSUB shell_tick
GOSUB tank_tick
IF jet_on THEN GOSUB jet_tick
IF missile_on THEN GOSUB missile_tick
IF sorties >= 2 THEN
    IF drone_on = 0 THEN
        IF #drone_wait > #elapsed THEN
            #drone_wait=#drone_wait-#elapsed
        ELSE
            IF #hx < 1488 THEN
                ' An air mine drifts in at mid height from out of view, never
                ' from the top of the screen and never on top of the
                ' helicopter: from beyond the east edge, or the west edge when
                ' the east one is past the DMZ fence (x 1472).
                drone_on=1
                #drone_x=#camera+264
                IF #drone_x > 1472 THEN #drone_x=#camera-24
                drone_y=88
            END IF
        END IF
    END IF
END IF
IF drone_on THEN
    ' It drifts toward the helicopter on both axes, in quarter pixels: 15,
    ' 30 or 45 px/s (easy, medium, hard), and stops at the DMZ fence.
    drone_motion=drone_motion+dt
    IF difficulty THEN drone_motion=drone_motion+dt
    IF difficulty = 2 THEN drone_motion=drone_motion+dt
    drone_step=drone_motion/4
    drone_motion=drone_motion AND 3
    #ax=#hv+8
    IF #drone_x < #ax THEN
        #drone_x=#drone_x+drone_step
        IF #drone_x > 1472 THEN #drone_x=1472
    ELSE
        IF #drone_x > #ax THEN #drone_x=#drone_x-drone_step
    END IF
    IF drone_y < hy THEN
        drone_y=drone_y+drone_step
        IF drone_y > hy THEN drone_y=hy
    ELSE
        IF drone_y > hy THEN
            drone_y=drone_y-drone_step
            IF drone_y < hy THEN drone_y=hy
        END IF
    END IF
    ' The mine's drawn ball and spikes: x+3..11, y+3..11.
    #hit_x=#drone_x+3:hit_width=9:hit_top=drone_y+3:hit_bottom=drone_y+11
    GOSUB hits_heli
END IF
RETURN

jet_spawn:
' A sortie counts only when the last person in a nonempty cabin has unloaded.
' Keep the launch countdown untouched throughout the first collection.
IF sorties = 0 THEN RETURN
IF #hx >= 1488 THEN RETURN
IF jet_on THEN RETURN
IF #jet_wait > #elapsed THEN
    #jet_wait=#jet_wait-#elapsed
ELSE
    jet_on=1
    jet_dir=1
    jet_turn=0
    jet_passes=0
    jet_ammo=jet_missiles(threat)
    jet_fire=jet_reload(difficulty)
    jet_y=88
    #jet_left=24
    IF #hx > 184 THEN #jet_left=#hx-160
    #jet_right=#hx+144
    IF #jet_right > 1448 THEN #jet_right=1448
    #jet_x=#jet_right
    #jet_wait=#jet_delay(threat)
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
    #bullet_step=dt+dt
    IF jet_dir THEN
        IF #jet_x <= #bullet_step THEN jet_on=0:RETURN
        #jet_x=#jet_x-#bullet_step
        IF jet_passes < 2 THEN
            IF #jet_x <= #jet_left THEN
                #jet_x=#jet_left:jet_turn=1:jet_age=0
            END IF
        ELSE
            ' Departing after its last pass: gone once wholly off camera, so
            ' the next jet's countdown does not depend on the world's width.
            IF #jet_x+16 < #camera THEN jet_on=0:RETURN
        END IF
    ELSE
        #jet_x=#jet_x+#bullet_step
        IF #jet_x >= #jet_right THEN
            #jet_x=#jet_right:jet_turn=1:jet_age=0
        END IF
    END IF
END IF
GOSUB jet_attack
GOSUB jet_body
GOSUB hits_heli
IF hit_found THEN RETURN
GOSUB jet_wings
GOSUB hits_heli
RETURN

jet_body:
' The jet as drawn (sprites 15 and 44, from jet_y): a fuselage across all
' 16 columns, rows 6-9 ...
#hit_x=#jet_x:hit_width=16:hit_top=jet_y+6:hit_bottom=jet_y+9
RETURN

jet_wings:
' ... and its wings and tail fin, rows 3-12: columns 6-14 flying west, 1-9
' flying east (the mirror image).
#hit_x=#jet_x+6
IF jet_dir = 0 THEN #hit_x=#jet_x+1
hit_width=9:hit_top=jet_y+3:hit_bottom=jet_y+12
RETURN

jet_attack:
IF jet_fire > dt THEN jet_fire=jet_fire-dt ELSE jet_fire=0
IF jet_fire THEN RETURN
IF jet_passes = 0 THEN RETURN
IF jet_turn THEN RETURN
IF jet_ammo = 0 THEN RETURN
IF missile_on THEN RETURN
IF #hx >= 1488 THEN RETURN
' Only a jet on screen fires.
IF #jet_x+8 < #camera THEN RETURN
IF #jet_x+8 >= #camera+256 THEN RETURN
IF jet_dir THEN
    IF #hv > #jet_x THEN RETURN
ELSE
    IF #hv < #jet_x THEN RETURN
END IF
' Jets fire only straight ahead along their line of flight: air-to-air
' missiles at a helicopter in the air, bombs at one on the ground. A missile
' leaves the nose level and flies on at the jet's 2 px/frame plus 2 of its
' own, so the jet fires only with the helicopter ahead and in line (centres
' within 10, 16 or 24 px of height: easy, medium, hard). A bomb keeps the
' jet's 2 px/frame and falls 2 px/frame, landing as far ahead as it falls:
' it is released with the landed helicopter that far ahead (within one
' update's travel).
#ax=#hv+16:#bx=#jet_x+8
GOSUB distance_x
ay=hy+8:by=jet_y+8
GOSUB distance_y
IF hy = land_y THEN
    IF #distance > ydistance+12 THEN RETURN
    IF #distance+12 < ydistance THEN RETURN
    missile_aim=2
ELSE
    IF #distance > 220 THEN RETURN
    IF ydistance >= jet_aim(difficulty) THEN RETURN
    missile_aim=0
END IF
missile_on=1
missile_ttl=30
missile_dir=jet_dir
#missile_x=#jet_x+8
missile_y=jet_y+8
jet_ammo=jet_ammo-1
jet_fire=jet_reload(difficulty)
IF noise_timer = 0 THEN
    noise_kind=2:noise_timer=18
    SOUND 3,5,10
END IF
RETURN

missile_tick:
' A missile flies level at 4 px/frame for half a second (missile_ttl), then
' noses down 2 px/frame; a bomb drifts on at 2 px/frame and falls 2. Either
' bursts on the ground, in the crowd, at the DMZ fence or at the world's
' west edge: none just vanishes.
IF missile_ttl > dt THEN missile_ttl=missile_ttl-dt ELSE missile_ttl=0
#bullet_step=dt+dt
IF missile_aim = 0 THEN #bullet_step=#bullet_step+#bullet_step
IF missile_dir THEN
    IF #missile_x <= #bullet_step THEN GOTO missile_miss
    #missile_x=#missile_x-#bullet_step
ELSE
    #missile_x=#missile_x+#bullet_step
END IF
IF #missile_x >= 1488 THEN GOTO missile_miss
IF missile_aim = 2 THEN
    missile_y=missile_y+dt+dt
ELSE
    IF missile_ttl = 0 THEN missile_y=missile_y+dt+dt
END IF
' Drawn shapes: a missile 11x3 centred on x,y; a bomb 4x6 (x-2..x+1, y-3..y+2).
IF missile_aim = 2 THEN
    #hit_x=#missile_x-2:hit_width=4:hit_top=missile_y-3:hit_bottom=missile_y+2
ELSE
    #hit_x=#missile_x-5:hit_width=11:hit_top=missile_y-1:hit_bottom=missile_y+1
END IF
GOSUB hits_heli
IF missile_y > 153 THEN
    #crowd_shot_x=#missile_x:crowd_radius=10
    GOSUB crowd_hit
    IF crowd_struck THEN GOTO missile_burst
END IF
IF missile_y > 166 THEN GOTO missile_miss
RETURN

missile_miss:
' The ground, the fence or the world's edge, and no target.
crowd_struck=0
missile_burst:
' Its spray only when it hit someone (crowd_struck).
missile_on=0
#ax=#missile_x-8:ay=missile_y-8
IF crowd_struck THEN GOTO burst_small
GOTO burst_small_core

tank_tick:
' Tanks drive on the foreground plane (rows 22-23), below the barracks and
' the crowd row, so they never share scanlines with a landed helicopter and
' only bombs reach them. One tank until the first delivery, then up to two.
' They crawl toward the helicopter at 15 px/s, never past x=1424 (its east
' end 1455: the DMZ fence leans up to 32 px west at the tanks' plane when it
' is near the west edge of the view), and one stops 40 px short of the
' other. A single timer (#tank_wait, counting only
' while the helicopter is west of the fence) spaces arrivals and shells: when
' it runs out a missing tank arrives, or else the first tank on screen that
' can reach the helicopter lobs a shell. One shell is in the air at a time.
tank_motion=tank_motion+dt
tank_step=tank_motion/4
tank_motion=tank_motion AND 3
FOR ti=0 TO 1
    IF tank_on(ti) THEN GOSUB tank_move
NEXT ti
IF #hx >= 1488 THEN RETURN
IF #tank_wait > #elapsed THEN #tank_wait=#tank_wait-#elapsed:RETURN
#tank_wait=0
ti=0
IF tank_on(0) = 0 THEN GOTO tank_spawn
IF sorties THEN
    ti=1
    IF tank_on(1) = 0 THEN GOTO tank_spawn
END IF
IF shell_on THEN RETURN
FOR ti=0 TO 1
    IF tank_on(ti) THEN GOSUB tank_aim
    IF shell_on THEN RETURN
NEXT ti
RETURN

tank_spawn:
' Behind the helicopter (160 px west), or 180 px east near the west end or
' when the other tank is already on the west side.
tank_on(ti)=1
#tank_wait=150
#ax=#hx+180
IF #ax > 1424 THEN #ax=1424
IF #hx > 180 THEN
    tj=1-ti
    IF tank_on(tj) = 0 THEN
        #ax=#hx-160
    ELSE
        IF #tank_x(tj) >= #hx THEN #ax=#hx-160
    END IF
END IF
#tank_x(ti)=#ax
RETURN

tank_move:
' Crawl toward the helicopter unless the other tank is within 40 px ahead.
#ax=#tank_x(ti)
tj=1-ti
#bx=#tank_x(tj)
IF #ax < #hx THEN
    IF tank_on(tj) THEN
        IF #bx > #ax THEN
            IF #bx < #ax+40 THEN RETURN
        END IF
    END IF
    #ax=#ax+tank_step
    IF #ax > 1424 THEN #ax=1424
ELSE
    IF tank_on(tj) THEN
        IF #bx < #ax THEN
            IF #bx+40 > #ax THEN RETURN
        END IF
    END IF
    IF #ax > 8 THEN #ax=#ax-tank_step
END IF
#tank_x(ti)=#ax
RETURN

tank_aim:
' Tank ti lobs a shell at the helicopter's centre, from its barrel tip, but
' only while the tank is on screen and the helicopter is on or just above the
' ground (research: tanks cannot hit a helicopter that stays airborne).
' shell_arc is a short 32-pixel arc under gravity: find the frame of its fall
' that reaches the helicopter's height, then the horizontal speed (1/16 px
' per frame) that arrives with it. Needing more than tank_speed (2.5, 3 or 3.5
' px per frame: easy, medium, hard; a reach of about 90, 105 or 120 px on the
' ground), the turret holds its fire.
IF hy < 137 THEN RETURN
#bx=#tank_x(ti)+15
IF #bx < #camera THEN RETURN
IF #bx >= #camera+256 THEN RETURN
GOSUB tank_pose
IF tank_face = 1 THEN #bx=#tank_x(ti)
IF tank_face = 0 THEN #bx=#tank_x(ti)+29
#ax=#hv+16
GOSUB distance_x
IF #distance >= 128 THEN RETURN
FOR shell_t=20 TO 36
    IF shell_arc(shell_t) >= hy+8 THEN EXIT FOR
NEXT shell_t
#distance=#distance*16
#distance=#distance+shell_t/2
#distance=#distance/shell_t
IF #distance > tank_speed(difficulty) THEN RETURN
shell_vx=#distance
shell_dir=0
IF #ax < #bx THEN shell_dir=1
#shell_x=#bx
shell_y=176
shell_t=0
shell_frac=0
shell_on=1
IF noise_timer = 0 THEN
    noise_kind=1:noise_timer=12
    SOUND 3,6,10
END IF
#tank_wait=tank_reload(threat)
RETURN

tank_pose:
' Tank ti faces the helicopter, or shows its front when it is overhead.
tank_face=2
IF #hv+28 < #tank_x(ti)+16 THEN tank_face=1
IF #hv+4 > #tank_x(ti)+16 THEN tank_face=0
RETURN

shell_tick:
' A lob lasts 36 frames: shell_arc gives its height on each frame, and the
' aimed horizontal speed keeps a 1/16-pixel remainder. It bursts on landing
' on the crowd plane, so no shell crosses the map.
' Advance by the frames elapsed, but never past the burst on frame 36.
shell_n=36-shell_t
IF shell_n > dt THEN shell_n=dt
shell_t=shell_t+shell_n
shell_y=shell_arc(shell_t)
#bullet_step=0
FOR shell_k=1 TO shell_n
    shell_frac=shell_frac+shell_vx
    #bullet_step=#bullet_step+shell_frac/16
    shell_frac=shell_frac AND 15
NEXT shell_k
IF shell_dir THEN
    IF #shell_x < #bullet_step THEN shell_on=0:RETURN
    #shell_x=#shell_x-#bullet_step
ELSE
    #shell_x=#shell_x+#bullet_step
    IF #shell_x >= 1488 THEN shell_on=0:RETURN
END IF
' Harmless for its first 8 frames: a shell fired under a low helicopter
' passes through it visibly instead of striking before anyone sees it.
IF shell_t >= 8 THEN
    #hit_x=#shell_x:hit_width=3:hit_top=shell_y:hit_bottom=shell_y+2
    GOSUB hits_heli
END IF
IF shell_t = 36 THEN
    #crowd_shot_x=#shell_x:crowd_radius=8
    GOSUB crowd_hit
    shell_on=0
    #ax=#shell_x-7:ay=shell_y-7
    IF crowd_struck THEN GOTO burst_small
    GOTO burst_small_core
END IF
RETURN

distance_x:
IF #ax > #bx THEN #distance=#ax-#bx ELSE #distance=#bx-#ax
RETURN
camera_tick:
#newcam=0
IF #hx > 112 THEN #newcam=#hx-112
IF #newcam > 1792 THEN #newcam=1792
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
' Rows 0-2: the HUD band and its capsules, its counts filled in at once (the
' template's 00 placeholders never reach a frame on their own).
SCREEN hud_rows,0,0,32,3
GOSUB hud
' The moon stands still in the sky (rows 5-7, columns 26-28): no star row
' crosses it and nothing scrolls the sky.
SCREEN moon_cells,0,186,3,3,3
SCREEN ground_row,0,736,32,1
terrain_dirty=1
GOSUB camera_tick
GOSUB crowd_draw
RETURN

stars_draw:
' High/middle/low stars (rows 3-6, 7-11, 12-16) move 1/2/3 pixels per
' eight-pixel terrain step. Byte wrap is intentional: even the fastest layer
' loops smoothly through screen edges. One pass per star: each star owns its
' sky row, so clearing its old cell cannot touch another star, and the old cell
' is cleared only when the star has left it. star_row ends with row 0.
star_scroll=#camera/8
IF star_visible THEN
    IF star_scroll = star_old THEN RETURN
ELSE
    ' A freshly cleared screen has nothing to erase.
    star_old=star_scroll
END IF
#if TI994A
' Native star pass. Each name-table write sets the VDP address with
' interrupts held off, exactly as the runtime's WRTVRM does.
ASM movb @cvb_STAR_SCROLL,r4
ASM srl r4,8
ASM movb @cvb_STAR_OLD,r5
ASM srl r5,8
ASM li r1,cvb_STAR_X
ASM li r2,cvb_STAR_ROW
ASM clr r3
ASM stars_loop:
ASM movb *r2+,r8
ASM srl r8,8
ASM ci r8,0
ASM jeq stars_done
ASM mov r4,r6
ASM mov r5,r7
ASM ci r8,7
ASM jl stars_layer
ASM a r4,r6
ASM a r5,r7
ASM ci r8,12
ASM jl stars_layer
ASM a r4,r6
ASM a r5,r7
ASM stars_layer:
ASM movb *r1+,r0
ASM srl r0,8
ASM s r0,r6
ASM neg r6
ASM andi r6,255
ASM s r0,r7
ASM neg r7
ASM andi r7,255
ASM sla r8,5
ASM ai r8,6144
ASM srl r7,3
ASM mov r6,r0
ASM srl r0,3
ASM c r0,r7
ASM jeq stars_kept
ASM a r8,r7
ASM ori r7,16384
ASM limi 0
ASM swpb r7
ASM movb r7,@VDPWADR
ASM swpb r7
ASM movb r7,@VDPWADR
ASM li r7,8192
ASM movb r7,@VDPWDATA
ASM limi 2
ASM stars_kept:
ASM a r8,r0
ASM ori r0,16384
ASM andi r6,7
ASM ai r6,240
ASM mov r3,r7
ASM andi r7,1
ASM jeq stars_even
ASM ai r6,8
ASM stars_even:
ASM swpb r6
ASM limi 0
ASM swpb r0
ASM movb r0,@VDPWADR
ASM swpb r0
ASM movb r0,@VDPWADR
ASM movb r6,@VDPWDATA
ASM limi 2
ASM inc r3
ASM jmp stars_loop
ASM stars_done:
#else
FOR star_i=0 TO 31
    IF star_row(star_i) = 0 THEN EXIT FOR
    star_pos=star_scroll:star_cell=star_old
    IF star_row(star_i) >= 7 THEN star_pos=star_pos+star_scroll:star_cell=star_cell+star_old
    IF star_row(star_i) >= 12 THEN star_pos=star_pos+star_scroll:star_cell=star_cell+star_old
    star_pos=star_x(star_i)-star_pos
    star_cell=star_x(star_i)-star_cell
    star_cell=star_cell/8
    #vaddr=star_row(star_i)*32
    #vaddr=#vaddr+6144
    IF star_cell <> star_pos/8 THEN
        #vaddr=#vaddr+star_cell
        VPOKE #vaddr,32
        #vaddr=#vaddr-star_cell
    END IF
    star_cell=star_pos/8
    #vaddr=#vaddr+star_cell
    star_char=240+(star_pos AND 7)
    IF star_i AND 1 THEN star_char=star_char+8
    VPOKE #vaddr,star_char
NEXT star_i
#endif
star_old=star_scroll:star_visible=1
RETURN

terrain:
' Runs straight after crowd_commit's vblank-synchronised copy of rows 17-20.
' Overlays on those rows go first (flag, camp fires and doors), so they land
' before the beam reaches row 17; otherwise an open camp shows its closed
' roof and door for a frame after each scroll. Lower rows follow.
GOSUB flag_position
GOSUB camp_fronts
#mapoff=#camera/8
#mapoff=#mapoff+1024
SCREEN world_map,#mapoff,672,32,1
' Row 22 (the pad's front half near home) also erases the previous fence
' stamp. Row 23 is drawn once by game_screen: nothing else ever writes it, so
' scrolling does not recopy it.
#mapoff=#mapoff+256
SCREEN world_map,#mapoff,704,32,1
#fence_world=1488
GOSUB fence_boundary
#fence_world=1808
GOSUB fence_boundary
terrain_dirty=0
RETURN

camp_fronts:
' A shot-open barrack keeps its ragged hole on row 19 (134 and 136).
' When no people are visible, crowd_commit copies the unmodified map row 20;
' stamp the fire there as well. Otherwise crowd_doors puts it in crowd_cells.
' Raw name-table addresses, no VDP reads.
FOR tc=0 TO 3
    IF camp_open(tc) THEN
        #fire_world=#camp_x(tc)-8
        FOR fire_tile=0 TO 1
            IF #fire_world >= #camera THEN
                #vaddr=#fire_world-#camera
                IF #vaddr < 256 THEN
                    #vaddr=#vaddr/8
                    #vaddr=#vaddr+6752
                    VPOKE #vaddr,134+fire_tile+fire_tile
                    IF crowd_mask = 0 THEN VPOKE #vaddr+32,126+fire_tile
                END IF
            END IF
            #fire_world=#fire_world+8
        NEXT fire_tile
    END IF
NEXT tc
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
#crowd_map=#crowd_map+768
' The camps with anyone in view (crowd_seen, from the walk) and the walkers
' going home near the home: everyone outside goes through the compositor.
crowd_mask=crowd_seen
IF home_walking THEN
    IF #camera > 1632 THEN crowd_mask=crowd_mask OR 16
END IF
IF crowd_mask = 0 THEN
    GOSUB crowd_commit
    RETURN
END IF
' 255 marks a cell no silhouette has touched yet.
#if TI994A
ASM li r0,array_CROWD_CELLS
ASM li r1,65280
ASM li r2,32
ASM compose_clear:
ASM movb r1,*r0+
ASM dec r2
ASM jne compose_clear
#else
FOR cc=0 TO 31
    crowd_cells(cc)=255
NEXT cc
#endif
FOR tc=0 TO 3
    IF crowd_mask AND camp_bits(tc) THEN
#if TI994A
        cp=tc*16:crowd_mode=0
        GOSUB compose_block
#else
        FOR cp=tc*16 TO tc*16+15
            IF person_state(cp) = 1 THEN GOSUB crowd_plot
            IF person_state(cp) = 2 THEN GOSUB crowd_plot
            IF person_state(cp) = 3 THEN GOSUB crowd_plot
            IF person_state(cp) = 8 THEN GOSUB crowd_plot
        NEXT cp
#endif
    END IF
NEXT tc
IF crowd_mask AND 16 THEN
#if TI994A
    FOR tc=0 TO 3
        cp=tc*16:crowd_mode=6
        GOSUB compose_block
    NEXT tc
#else
    FOR cp=0 TO 63
        IF person_state(cp) = 6 THEN GOSUB crowd_plot
    NEXT cp
#endif
END IF
' Upload into the hidden pattern set; the old row remains intact until SCREEN.
#crowd_color_addr=crowd_bank*8
#crowd_color_addr=#crowd_color_addr+4096
DEFINE VRAM #crowd_color_addr,256,VARPTR crowd_pixels(0)
' Occupied cells get their 8-byte palette in the hidden colour set and name
' their own pattern; the others show the scenery code underneath.
#if TI994A
ASM movb @cvb_CROWD_BANK,r4
ASM srl r4,8
ASM mov @cvb__CROWD_MAP,r5
ASM ai r5,cvb_WORLD_MAP
ASM li r2,array_CROWD_CELLS
ASM clr r3
ASM paint_loop:
ASM clr r0
ASM movb *r2,r0
ASM ci r0,65280
ASM jeq paint_scenery
ASM srl r0,8
ASM ai r0,cvb_PERSON_COLORS
ASM mov r0,r1
ASM mov r3,r0
ASM a r4,r0
ASM sla r0,3
ASM ai r0,12288
ASM ori r0,16384
ASM limi 0
ASM swpb r0
ASM movb r0,@VDPWADR
ASM swpb r0
ASM movb r0,@VDPWADR
ASM movb *r1+,@VDPWDATA
ASM movb *r1+,@VDPWDATA
ASM movb *r1+,@VDPWDATA
ASM movb *r1+,@VDPWDATA
ASM movb *r1+,@VDPWDATA
ASM movb *r1+,@VDPWDATA
ASM movb *r1+,@VDPWDATA
ASM movb *r1+,@VDPWDATA
ASM limi 2
ASM mov r3,r0
ASM a r4,r0
ASM swpb r0
ASM movb r0,*r2
ASM jmp paint_next
ASM paint_scenery:
ASM mov r5,r1
ASM a r3,r1
ASM movb *r1,*r2
ASM paint_next:
ASM inc r2
ASM inc r3
ASM ci r3,32
ASM jl paint_loop
#else
FOR cc=0 TO 31
    IF crowd_cells(cc) <> 255 THEN
        #crowd_color_addr=cc+crowd_bank
        #crowd_color_addr=#crowd_color_addr*8
        #crowd_color_addr=#crowd_color_addr+12288
        DEFINE VRAM #crowd_color_addr,8,VARPTR person_colors(crowd_cells(cc))
        crowd_cells(cc)=cc+crowd_bank
    ELSE
        crowd_cells(cc)=world_map(#crowd_map+cc)
    END IF
NEXT cc
#endif
GOSUB crowd_doors
GOSUB crowd_commit
crowd_bank=64-crowd_bank
RETURN

crowd_commit:
' Prepare people first. Keep roof/walls and their footings on the same camera
' position: only these four short row blits occur after WAIT, before scanout.
' SCREEN stride is byte-sized; use word offsets for the 256-column map.
IF terrain_dirty THEN
    ' Sprites first, helicopter last, then the WAIT: the vblank that ends it
    ' copies the new sprite positions and the scenery follows at once, so the
    ' helicopter never sits at its old screen place over scrolled scenery.
    GOSUB draw_actors
    actors_drawn=1
    #mapoff=#camera/8
    WAIT
    SCREEN world_map,#mapoff,544,32,1
    #mapoff=#mapoff+256
    SCREEN world_map,#mapoff,576,32,1
    #mapoff=#mapoff+256
    SCREEN world_map,#mapoff,608,32,1
END IF
IF crowd_mask THEN
    SCREEN crowd_cells,0,640,32,1
ELSE
    SCREEN world_map,#crowd_map,640,32,1
    ' Even without a terrain scroll, a crowd redraw must restore the fire.
    IF terrain_dirty = 0 THEN GOSUB camp_fronts
END IF
IF terrain_dirty THEN GOSUB terrain
crowd_dirty=0
RETURN

crowd_doors:
' A blown-out barrack burns inside its two middle columns (126 and 127, the
' animated fire), except where someone stands in front.
FOR tc=0 TO 3
    IF camp_open(tc) THEN
        #fire_world=#camp_x(tc)-8
        FOR fire_tile=0 TO 1
            IF #fire_world >= #camera THEN
                #relative=#fire_world-#camera
                IF #relative < 256 THEN
                    cc=#relative/8
                    IF crowd_cells(cc) >= 128 THEN crowd_cells(cc)=126+fire_tile
                END IF
            END IF
            #fire_world=#fire_world+8
        NEXT fire_tile
    END IF
NEXT tc
RETURN

#if TI994A
compose_block:
' Native compositor for the 16 people from cp. crowd_mode 0 plots everyone
' outside (states 1-3 and 8); otherwise only that state (6).
' The same rules as the portable crowd_plot/crowd_glyph/crowd_cell/
' crowd_background: 4-pixel positions, pre-shifted glyph rows (+192 right
' half, +384 left half) ORed into crowd_pixels, and each cell's background
' and palette chosen by the first person drawn into it.
ASM jmp compose_start
' compose_cell: r7 cell, r8 shift offset, r9 glyph offset, r2 kind*8.
ASM compose_cell:
ASM mov r7,r0
ASM ai r0,array_CROWD_CELLS
ASM clr r1
ASM movb *r0,r1
ASM ci r1,65280
ASM jne compose_merge
ASM mov @cvb__CROWD_MAP,r1
ASM a r7,r1
ASM ai r1,cvb_WORLD_MAP
ASM movb *r1,r1
ASM srl r1,8
ASM ci r1,133
ASM jeq compose_wall
ASM ci r1,156
ASM jeq compose_window
ASM ci r1,157
ASM jeq compose_door
ASM ci r1,132
ASM jne compose_ground
ASM mov r2,r1
ASM ai r1,32
ASM jmp compose_palette
ASM compose_ground:
ASM mov r2,r1
ASM compose_palette:
ASM swpb r1
ASM movb r1,*r0
ASM li r1,cvb_CROWD_BASES
ASM jmp compose_base
ASM compose_wall:
ASM li r1,20480
ASM movb r1,*r0
ASM li r1,cvb_CROWD_BASES
ASM ai r1,8
ASM jmp compose_base
ASM compose_window:
ASM li r1,22528
ASM movb r1,*r0
ASM li r1,cvb_CROWD_BASES
ASM ai r1,16
ASM jmp compose_base
ASM compose_door:
ASM li r1,6144
ASM movb r1,*r0
ASM li r1,cvb_CROWD_BASES
ASM ai r1,24
ASM compose_base:
ASM mov r7,r0
ASM sla r0,3
ASM ai r0,array_CROWD_PIXELS
ASM movb *r1+,*r0+
ASM movb *r1+,*r0+
ASM movb *r1+,*r0+
ASM movb *r1+,*r0+
ASM movb *r1+,*r0+
ASM movb *r1+,*r0+
ASM movb *r1+,*r0+
ASM movb *r1+,*r0+
ASM compose_merge:
ASM mov r9,r1
ASM a r8,r1
ASM ai r1,cvb_PERSON_ROWS
ASM mov r7,r0
ASM sla r0,3
ASM ai r0,array_CROWD_PIXELS
ASM socb *r1+,*r0+
ASM socb *r1+,*r0+
ASM socb *r1+,*r0+
ASM socb *r1+,*r0+
ASM socb *r1+,*r0+
ASM socb *r1+,*r0+
ASM socb *r1+,*r0+
ASM socb *r1+,*r0+
ASM b *r11
' Main scan: r3 person, r4 camera, r5 anim/8, r6 mode.
ASM compose_start:
ASM movb @cvb_CP,r3
ASM srl r3,8
ASM mov @cvb__CAMERA,r4
ASM movb @cvb_ANIM,r5
ASM srl r5,11
ASM movb @cvb_CROWD_MODE,r6
ASM srl r6,8
ASM compose_loop:
ASM mov r3,r0
ASM ai r0,array_PERSON_STATE
ASM clr r1
ASM movb *r0,r1
ASM srl r1,8
ASM mov r6,r6
ASM jne compose_only
ASM ci r1,8
ASM jeq compose_take
ASM ci r1,1
ASM jl compose_next
ASM ci r1,3
ASM jh compose_next
ASM jmp compose_take
ASM compose_only:
ASM c r1,r6
ASM jne compose_next
ASM compose_take:
ASM mov r3,r2
ASM ai r2,cvb_PERSON_KIND
ASM movb *r2,r2
ASM srl r2,8
ASM sla r2,3
ASM mov r3,r9
ASM a r5,r9
ASM andi r9,3
ASM a r2,r9
ASM ci r1,2
ASM jeq compose_still
ASM movb @cvb_WAVE_ID,r0
ASM srl r0,8
ASM c r0,r3
ASM jeq compose_still
ASM ai r9,4
ASM compose_still:
ASM sla r9,3
ASM mov r3,r0
ASM a r3,r0
ASM ai r0,array__PERSON_X
ASM mov *r0,r0
ASM c r0,r4
ASM jhe compose_visible
ASM mov r4,r1
ASM s r0,r1
ASM ci r1,4
ASM jne compose_next
ASM clr r7
ASM li r8,384
ASM bl @compose_cell
ASM jmp compose_next
ASM compose_visible:
ASM s r4,r0
ASM ci r0,256
ASM jhe compose_next
ASM mov r0,r7
ASM srl r7,3
ASM andi r0,4
ASM jeq compose_whole
ASM li r8,192
ASM bl @compose_cell
ASM ci r7,31
ASM jeq compose_next
ASM inc r7
ASM li r8,384
ASM bl @compose_cell
ASM jmp compose_next
ASM compose_whole:
ASM clr r8
ASM bl @compose_cell
ASM compose_next:
ASM inc r3
ASM mov r3,r0
ASM andi r0,15
ASM jne compose_loop
RETURN
#else
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
' Standing people (2) and the one waving at the home use the standing poses.
IF person_state(cp) <> 2 THEN
    IF cp <> wave_id THEN #crowd_glyph=#crowd_glyph+4
END IF
#crowd_glyph=#crowd_glyph*8
RETURN

crowd_cell:
#crowd_pixel=cc*8
IF crowd_cells(cc) = 255 THEN GOSUB crowd_background
#crowd_source=#crowd_glyph
IF crowd_shift = 1 THEN #crowd_source=#crowd_source+192
IF crowd_shift = 2 THEN #crowd_source=#crowd_source+384
FOR cy=0 TO 7
    crowd_pixels(#crowd_pixel+cy)=crowd_pixels(#crowd_pixel+cy) OR person_rows(#crowd_source+cy)
NEXT cy
RETURN

crowd_background:
' Prepare once per occupied cell, then combine every overlapping silhouette.
' A hut wall, mound, home window or doorway keeps its scenery under a walker
' (CROWD_BASES and PERSON_COLORS in assets/generate.py).
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
FOR cb=0 TO 7
    crowd_pixels(#crowd_pixel+cb)=crowd_bases(#crowd_source+cb)
NEXT cb
RETURN
#endif

menu_restore:
' The crowd's pixel buffer is idle on menu screens: fill it with the font
' colour (white on black) rather than keep 256 identical bytes in ROM.
FOR ini=0 TO 127
    crowd_pixels(ini)=241
    crowd_pixels(ini+128)=241
NEXT ini
' The font itself is in the TI's boot bank, selected around its upload here
' in the fixed area (the vblank handler reads only fixed tables).
#if TI994A
BANK SELECT 2
#endif
DEFINE VRAM 4608,256,menu_font
#if TI994A
BANK SELECT 1
#endif
DEFINE VRAM 12800,256,VARPTR crowd_pixels(0)
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
                #vaddr=#fence_row+#fence_draw
                ' fire_char is idle here; camp_fronts uses it after both fences.
                fire_char=fence_codes(fence_char-160)
                IF #fence_world = 1808 THEN fire_char=home_fence_codes(fence_char-160)
                IF fire_char THEN VPOKE #vaddr,fire_char
            END IF
        END IF
        #fence_col=#fence_col+1
        fence_char=fence_char+1
    NEXT fence_i
    #fence_row=#fence_row+32
NEXT fence_y
RETURN

flag_position:
' Clear the old flag footprint. The pole meets the stub drawn into the home's
' roof character (139), so it stands on the roof.
IF flag_visible THEN
    #vaddr=flag_col
    #vaddr=#vaddr+6688
    VPOKE #vaddr,32
    IF flag_col < 31 THEN
        #vaddr=#vaddr+1
        VPOKE #vaddr,32
        #vaddr=#vaddr-1
    END IF
    #vaddr=#vaddr+32
    VPOKE #vaddr,32
END IF
flag_visible=0
#relative=1976-#camera
IF #relative < 256 THEN
    flag_visible=1
    flag_col=#relative/8
    #vaddr=flag_col
    #vaddr=#vaddr+6688
    VPOKE #vaddr,144
    IF flag_col < 31 THEN
        #vaddr=#vaddr+1
        VPOKE #vaddr,145
        #vaddr=#vaddr-1
    END IF
    #vaddr=#vaddr+32
    VPOKE #vaddr,146
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
' The band's capsules (row 1), left to right: the dead (red dot), those on
' board (cyan) and the saved (bright green), then the spare helicopters (the
' reserves, not the one flying) right-justified in the fourth capsule's
' columns 25-28, so at most four show. A practice game's star (code 13)
' stands on the band after the saved capsule (else the band, code 1).
digit_value=lost:#digit_pos=6180:GOSUB digits
digit_value=aboard:#digit_pos=6187:GOSUB digits
digit_value=saved:#digit_pos=6194:GOSUB digits
spares=0
IF lives > 0 THEN spares=lives-1
FOR hs=0 TO 3
    hudchar=32
    IF hs+spares > 3 THEN hudchar=140
    #vaddr=hs
    #vaddr=#vaddr+6201
    VPOKE #vaddr,hudchar
NEXT hs
hudchar=1
IF practice THEN hudchar=13
VPOKE 6197,hudchar
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
IF crash_timer THEN GOSUB crash_draw:RETURN
' Fixed sprite slots (see the header); SPRITE FLICKER rotates the order the
' VDP sees them in, so on an overloaded scanline (four per line) every sprite
' takes its turn. Inactive actors skip their pose work; sprite_off hides each
' slot once.
draw_slot=2
IF shell_on THEN
    #draw_world=#shell_x:draw_y=shell_y-1:draw_pat=68:draw_color=8
    GOSUB world_sprite
ELSE
    GOSUB sprite_off
END IF
draw_slot=3
IF missile_on THEN
    ' Missile-shaped, nose first (sprite 47 east, 48 west), or a bomb (49);
    ' each is centred on #missile_x and missile_y.
    IF missile_aim = 2 THEN
        #draw_world=#missile_x-2:draw_y=missile_y-4:draw_pat=196
    ELSE
        IF missile_dir THEN
            #draw_world=#missile_x-10:draw_pat=192
        ELSE
            #draw_world=#missile_x-5:draw_pat=188
        END IF
        draw_y=missile_y-2
    END IF
    draw_color=15
    GOSUB world_sprite
ELSE
    GOSUB sprite_off
END IF
FOR di=0 TO 1
    draw_slot=di+4
    IF shot_on(di) THEN
        #draw_world=#shot_x(di):draw_y=shot_y(di)-1:draw_pat=68:draw_color=11
        GOSUB world_sprite
    ELSE
        GOSUB sprite_off
    END IF
NEXT di
' Tanks on the foreground plane: tracks on y=189, under the crowd row.
FOR ti=0 TO 1
    draw_slot=ti+ti+6
    IF tank_on(ti) THEN
        GOSUB tank_pose
        #draw_world=#tank_x(ti):draw_y=174:draw_pat=48:draw_color=3
        IF tank_face = 0 THEN draw_pat=240
        IF tank_face = 2 THEN draw_pat=248
        GOSUB world_sprite
        draw_slot=draw_slot+1
        #draw_world=#tank_x(ti)+16:draw_color=3:draw_pat=236
        IF tank_face = 0 THEN draw_pat=244
        IF tank_face = 2 THEN draw_pat=252
        GOSUB world_sprite
    ELSE
        GOSUB sprite_off
        draw_slot=draw_slot+1
        GOSUB sprite_off
    END IF
NEXT ti
draw_slot=10
IF jet_on THEN
    #draw_world=#jet_x:draw_y=jet_y-1:draw_pat=60:draw_color=7
    IF jet_dir = 0 THEN draw_pat=176
    IF jet_turn THEN
        draw_pat=180
        IF jet_dir = 0 THEN draw_pat=184
    END IF
    GOSUB world_sprite
ELSE
    GOSUB sprite_off
END IF
draw_slot=11
IF drone_on THEN
    #draw_world=#drone_x:draw_y=drone_y-1:draw_pat=64:draw_color=6
    GOSUB world_sprite
ELSE
    GOSUB sprite_off
END IF
GOSUB blast_draw
' The helicopter last: on a scrolling update the vblank WAIT follows at once.
draw_slot=0:draw_color=15
GOSUB heli_draw
RETURN

blast_draw:
' The burst: a core (slot 12) and three debris clusters (13-15), placed,
' shaped and coloured from ROM tables by its kind and age (blast_end minus
' blast_timer, one row per two frames), so no particle needs RAM. Offsets
' are stored +64. di (idle once draw_actors' shot loop is done) steps
' through the three clusters' rows, 68 apart (BLAST_ROWS in the generator).
' A burst on bare ground has no spray: its debris pattern is 0.
IF blast_timer = 0 THEN
    FOR draw_slot=12 TO 16
        GOSUB sprite_off
    NEXT draw_slot
    RETURN
END IF
blast_row=blast_end-blast_timer
blast_row=blast_row/2
#draw_world=#blast_x
draw_y=blast_y+blast_cdy(blast_row)
draw_pat=blast_cpat(blast_row):draw_color=blast_ccol(blast_row)
draw_slot=12
GOSUB blast_sprite
' An air burst (rows 0-17) also drops a burning chunk straight down (slot
' 16), so it reads as a burst in the sky, not on the ground. blast_fall is
' how far it has fallen (no bias); below the screen it is hidden.
draw_slot=16
IF blast_end = 36 THEN
    draw_y=blast_fall(blast_row)
    IF draw_y < 191-blast_y THEN
        draw_y=draw_y+blast_y
        draw_y=draw_y-1
        draw_pat=blast_fpat(blast_row):draw_color=blast_fcol(blast_row)
        GOSUB world_sprite
    ELSE
        GOSUB sprite_off
    END IF
ELSE
    GOSUB sprite_off
END IF
draw_pat=blast_dpat(blast_row)
IF draw_pat = 0 THEN
    FOR draw_slot=13 TO 15
        GOSUB sprite_off
    NEXT draw_slot
    RETURN
END IF
di=blast_row
FOR draw_slot=13 TO 15
    #draw_world=#blast_x+blast_dx(di)
    #draw_world=#draw_world-64
    draw_y=blast_y+blast_dy(di)
    draw_color=blast_dcol(blast_row)
    GOSUB blast_sprite
    di=di+68
NEXT draw_slot
RETURN

blast_sprite:
' Undo the +64 (and the VDP's y+1). A particle below the screen is hidden:
' a y of 208 would end the sprite list.
draw_y=draw_y-65
IF draw_y > 190 THEN
    IF draw_y < 209 THEN GOTO sprite_off
END IF
GOTO world_sprite

heli_draw:
draw_x=#hv-#camera
draw_y=hy-1
GOSUB heli_pose
SPRITE draw_slot,draw_y,draw_x,draw_pat,draw_color
draw_x=draw_x+16
draw_pat=draw_pat+4
draw_slot=draw_slot+1
SPRITE draw_slot,draw_y,draw_x,draw_pat,draw_color
RETURN

heli_pose:
draw_pat=face*16
IF hspeed THEN
    IF hy < land_y THEN
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
' Draw an active actor at its world position, or hide it when off camera.
' #sprite_shown has one bit per slot (#sprite_bit) so hidden slots stay free.
#slot_bit=#sprite_bit(draw_slot)
IF #draw_world >= #camera THEN
    #screen_x=#draw_world-#camera
    IF #screen_x < 256 THEN
        draw_x=#screen_x
        SPRITE draw_slot,draw_y,draw_x,draw_pat,draw_color
        #sprite_shown=#sprite_shown OR #slot_bit
        RETURN
    END IF
ELSE
    #screen_x=#camera-#draw_world
    IF #screen_x < 16 THEN
        draw_x=32-#screen_x
        draw_color=draw_color+128
        SPRITE draw_slot,draw_y,draw_x,draw_pat,draw_color
        #sprite_shown=#sprite_shown OR #slot_bit
        RETURN
    END IF
END IF
GOSUB sprite_off
RETURN

sprite_off:
' Hide a world-actor slot once; while it stays hidden this is one bit test.
' (Word AND into a variable first: a bare IF #word AND n can test one byte.)
#slot_bit=#sprite_bit(draw_slot)
#slot_bit=#slot_bit AND #sprite_shown
IF #slot_bit THEN
    SPRITE draw_slot,209,0,0,0
    #sprite_shown=#sprite_shown XOR #slot_bit
END IF
RETURN

hide_all:
FOR ini=0 TO 31
    SPRITE ini,209,0,0,0
NEXT ini
#sprite_shown=0
RETURN

sound_tick:
IF blast_timer > dt THEN blast_timer=blast_timer-dt ELSE blast_timer=0
IF gun_timer > dt THEN gun_timer=gun_timer-dt ELSE gun_timer=0
IF chime_timer > dt THEN chime_timer=chime_timer-dt ELSE chime_timer=0
' The first-takeoff tune uses half-beats; its final delivery-style flourish
' keeps the ordinary chime timing.
IF chime_timer > 36 THEN chime_timer=chime_timer-dt
IF noise_timer > dt THEN noise_timer=noise_timer-dt ELSE noise_timer=0
' fire_control writes the rotor's chop between video frames: keep it off the
' chip while this routine writes it.
sound_busy=1
' Tone 0: a steady engine hum, higher under horizontal load and quiet on the
' pad. The rotor's chop on the noise channel quickens with speed: a beat every
' 12 frames idling on the pad, 9 hovering, 8, 7 and 6 cruising faster.
IF crash_timer THEN
    chop_period=0
    SOUND 0,0,0
ELSE
    #sfx_pitch=920
    sfx_volume=2
    chop_period=12
    IF hy < land_y THEN
        #sfx_pitch=820-hspeed*48
        sfx_volume=4
        chop_period=9-hspeed
        ' Descending too fast to land on: the engine strains with a pulsing,
        ' higher whine (a smaller divisor is a higher note).
        IF fall_speed > 1 THEN
            #sfx_pitch=430
            IF fall_speed > 2 THEN #sfx_pitch=330
            sfx_volume=7
            IF anim AND 4 THEN sfx_volume=11
        END IF
    END IF
    SOUND 0,#sfx_pitch,sfx_volume
END IF
GOSUB weapon_sound
GOSUB rescue_sound
GOSUB noise_sound
sound_busy=0
RETURN

weapon_sound:
' Tone 1: player shots take priority over nearby aircraft.
IF gun_timer THEN
    IF gun_kind = 2 THEN
        #sfx_pitch=564-gun_timer*16
        sfx_volume=6+gun_timer/6
    ELSE
        #sfx_pitch=180
        sfx_volume=5+gun_timer
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
' Tone 2: first-takeoff tune, boarding/unloading chirps, delivery chime.
IF chime_timer = 0 THEN SOUND 2,0,0:RETURN
IF chime_kind = 3 THEN
    ' One byte per beat; periods are doubled. The first sortie plays all
    ' twelve beats, while the short delivery chime plays its final three.
    #sfx_pitch=takeoff_notes(chime_timer/16)
    #sfx_pitch=#sfx_pitch+#sfx_pitch
ELSE
    #sfx_pitch=chime_timer*20
    IF chime_kind = 1 THEN
        #sfx_pitch=#sfx_pitch+160
    ELSE
        #sfx_pitch=410-#sfx_pitch
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
' No effect playing: the rotor's chop has the channel (fire_control); with no
' rotor (a crash) it is silent.
IF chop_period = 0 THEN SOUND 3,0,0
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
' The chop first, so the vblank handler cannot sound it again after this.
chop_period=0
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
' In the sky below the HUD band, on row 4, which no star uses.
PRINT AT 141,"PAUSED"
GOSUB release_input
' The main loop's frame clock is idle while paused (clock_reset restarts it).
#last=FRAME
pause_wait:
WAIT
#now=FRAME
#elapsed=#now-#last
#last=#now
IF #elapsed > 6 THEN #elapsed=6
dt=#elapsed
GOSUB pause_input
IF pause_trigger THEN GOTO pause_end
IF cont1.button THEN GOTO pause_end
' BACK/REDO leaves the pause; the main loop then returns to the title.
GOSUB back_key
IF back_pressed THEN GOTO pause_end
GOTO pause_wait
pause_end:
PRINT AT 141,"      "
GOSUB release_input
fire_gate=1
fire_held=0
#if TI994A
fire_hold=0
fire_turned=0
#endif
hud_dirty=1
GOSUB clock_reset
dt=2
#elapsed=2
RETURN

back_key:
' BACK (FCTN-9) or REDO (FCTN-8) on the TI, read from the keyboard matrix:
' CVBasic's key scan stops at FCTN, and a bare FCTN can look like a joystick
' button (CLAUDE.md). Keypad * (10) or # (11) on ColecoVision.
back_pressed=0
#if TI994A
' Keep the interrupt's keyboard scan out of this short CRU transaction.
ASM limi 0
ASM li r12,>0024
ASM clr r0
ASM ldcr r0,3
ASM src r12,7
ASM li r12,>0006
ASM stcr r2,8
ASM li r1,>1000
ASM czc r1,r2
ASM jne back_key_done
' Column 1 row 3 is 9 (BACK); column 2 row 3 is 8 (REDO).
ASM li r12,>0024
ASM li r0,>0100
ASM ldcr r0,3
ASM src r12,7
ASM li r12,>0006
ASM stcr r2,8
ASM li r1,>0800
ASM czc r1,r2
ASM jeq back_key_hit
ASM li r12,>0024
ASM li r0,>0200
ASM ldcr r0,3
ASM src r12,7
ASM li r12,>0006
ASM stcr r2,8
ASM czc r1,r2
ASM jne back_key_done
ASM back_key_hit:
ASM li r0,>0100
ASM movb r0,@cvb_BACK_PRESSED
ASM back_key_done:
ASM limi 2
' The compiler caches back_pressed in r0 across ASM: reload value and flags.
ASM movb @cvb_BACK_PRESSED,r0
#else
IF cont1.key = 10 THEN back_pressed=1
IF cont1.key = 11 THEN back_pressed=1
#endif
RETURN

practice_star:
DATA BYTE 80,32,248,32,80,0,0,0

takeoff_notes:
' Three brisk 4/4 bars in C: C-D-E-G, E-G-A-G, D-E-G-C.
' Indexed backward from the timer; each byte is half a PSG period.
DATA BYTE 54,72,85,95,72,64,72,85,72,85,95,107

' The rotor's chop, by frame of its beat (fire_control reads them in the
' vblank handler, so they stay in the fixed area): a sharp attack dying away,
' quieter idling on the pad. A short beat (fast flight) cuts the decay short.
chop_air:
DATA BYTE 12,9,7,5,4,3,2,2,1,1,1,1
chop_ground:
DATA BYTE 7,5,4,3,2,2,1,1,1,1,1,1

' One bit per world-actor sprite slot (0-16), for #sprite_shown. Slot 16
' (an air burst's falling chunk) shares bit 0 with slot 0: the helicopter's
' slots 0 and 1 are drawn with SPRITE directly and never use the mask.
#sprite_bit:
DATA 1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768,1

#if TI994A
BANK 1
#endif
' Helicopter hit boxes (hits_heli), four columns per facing (right, left,
' front): the cabin, nose and skids first..last, then the tail boom
' first..last (none in the front view). Read while playing, like the enemy
' tables below, from the permanently selected data bank.
heli_box:
DATA BYTE 11,28,2,12,3,20,19,29,9,24,0,0
' Enemy tables.
' threat = 5 * difficulty + level, where the level is the completed
' deliveries (0-4, capped): easy, medium and hard rows of five. The second
' tank arrives after the first delivery, and otherwise counts stay at one jet
' and one air mine. Delays are video frames. The byte tables are padded to
' an even length.
tank_reload:
DATA BYTE 200,180,160,140,120,140,125,110,95,80,100,90,80,70,60,0
jet_missiles:
DATA BYTE 1,1,2,2,2,2,2,3,3,4,3,3,4,4,5,0
#jet_delay:
DATA 480,440,400,360,320,360,320,280,240,200,270,240,210,180,150
#drone_delay:
DATA 360,320,280,240,200,240,210,180,150,120,180,160,140,120,100
' How enemies fire, by difficulty (easy, medium, hard): frames between a
' jet's missiles, how far out of line (px) it still fires, and a tank
' shell's top speed in 1/16 px per frame (its reach).
' The title's secret HOWIE: TI key codes, or the ColecoVision keypad's
' phone spelling of it (4-6-9-4-3).
howie_keys:
#if TI994A
DATA BYTE 72,79,87,73,69,0
#else
DATA BYTE 4,6,9,4,3,0
#endif
' The title's difficulty brackets: cyan (7) on black, all eight rows.
bracket_colors:
DATA BYTE 113,113,113,113,113,113,113,113
jet_reload:
DATA BYTE 90,60,40,0
jet_aim:
DATA BYTE 10,16,24,0
tank_speed:
DATA BYTE 40,48,56,0

' The crash routines below run only after a crash: they share the data
' bank, which stays selected, to keep the fixed area's unoptimised image
' below >FFFE (CLAUDE.md section 3A). So do the camps' occasional events.

distance_y:
' Used by the occasional missile aim; the data bank stays selected in play.
IF ay > by THEN ydistance=ay-by ELSE ydistance=by-ay
RETURN

first_camp:
' The barrack nearest home (camp 3) is already burning when a mission
' starts, as in the Apple II original, with its first six people out.
' Put them at their distinct first wandering goals, not all at the doorway.
camp_open(3)=1:camp_released(3)=6:camp_active(3)=6
FOR ep=48 TO 53
    person_state(ep)=1
    #person_x(ep)=#camp_x(3)+first_out(ep-48)
    #person_x(ep)=#person_x(ep)-128
NEXT ep
RETURN

crash:
' The helicopter is gone the moment it crashes: it and every other actor are
' hidden, a burst plays where it was, and its burning wreck (crash_draw)
' falls and burns out before a new one appears at the pad.
crash_pending=0
IF invuln THEN RETURN
IF crash_timer THEN RETURN
GOSUB silence
GOSUB hide_all
DEFINE SPRITE 13,2,crash_flames
lost=lost+aboard
aboard=0
FOR cp=0 TO 63
    IF person_state(cp) = 5 THEN person_state(cp)=4
NEXT cp
lives=lives-1
crash_timer=90
hud_dirty=1
shell_on=0:missile_on=0
#blast_x=#hv+8:blast_y=hy
IF hy < land_y THEN GOTO explode_air
GOTO explode_ground

crash_tick:
' Hold the burn timer during the fall; the final life also reaches the
' ground. On the ground the fire burns down in stages: full flames, then
' lower and narrower ones from 60 and from 40 frames before the end, embers
' from 24, and nothing at all for the last 12 (crash_draw).
IF hy < land_y THEN
    #move=hspeed*dt
    GOSUB move_heli
    hy=hy+dt+dt
    IF hy >= land_y THEN
        hy=land_y
        hspeed=0
        #blast_x=#hv+8:blast_y=hy
        GOSUB explode_ground
    END IF
ELSE
    IF crash_timer > 60 THEN
        IF crash_timer <= 60+dt THEN DEFINE SPRITE 13,2,crash_burn2
    END IF
    IF crash_timer > 40 THEN
        IF crash_timer <= 40+dt THEN DEFINE SPRITE 13,2,crash_burn3
    END IF
    IF crash_timer > 24 THEN
        IF crash_timer <= 24+dt THEN DEFINE SPRITE 13,2,crash_embers
    END IF
    IF crash_timer > dt THEN crash_timer=crash_timer-dt ELSE crash_timer=0
END IF
IF crash_timer > 24 THEN
    IF noise_timer < 6 THEN noise_timer=6
END IF
RETURN

' Bursts (blast_draw), biggest first: air and ground (36 frames), small (20)
' and tiny (12), each of the last two with its spray (a hit) or core only (bare
' ground). blast_end selects the kind's rows in the blast_* tables and
' blast_timer counts its frames down.
explode_air:
' A big burst in the air (a jet, an air mine, the helicopter hit in flight):
' its debris arcs out and falls on past it.
blast_end=36
GOTO explode_big
explode_ground:
' A big burst on the ground (a tank, a barrack, the wreck landing): its
' debris arcs out, comes down at the burst's level and smoulders there.
blast_end=72
explode_big:
blast_timer=36
noise_timer=24
noise_kind=3
SOUND 3,6,15
RETURN

' A bomb, missile or shell bursts small where it ends, at #ax,ay (the burst
' sprite's top left): with its spray of dirt and sparks when it hit someone
' (burst_small), only the core's flash and smoke on bare ground
' (burst_small_core). A shot puffs tiny, the same way (burst_tiny,
' burst_tiny_core). blast_row carries the kind's blast_end to burst_play.
burst_small:
blast_row=92:GOTO burst_play
burst_small_core:
blast_row=112:GOTO burst_play
burst_tiny:
blast_row=124:GOTO burst_play
burst_tiny_core:
blast_row=136
burst_play:
' A burst never cuts short a bigger one still playing (a smaller blast_end).
IF blast_timer THEN
    IF blast_end < blast_row THEN RETURN
END IF
#blast_x=#ax:blast_y=ay
blast_end=blast_row
IF blast_row < 124 THEN
    blast_timer=20
    IF noise_timer < 12 THEN
        noise_kind=3:noise_timer=12
        SOUND 3,6,11
    END IF
ELSE
    blast_timer=12
    IF noise_timer < 6 THEN
        noise_kind=3:noise_timer=6
        SOUND 3,6,8
    END IF
END IF
RETURN

crash_draw:
' The helicopter itself is never drawn after a crash: its burning wreck is
' (flames in slots 0 and 1, falling with it, then embers where it lies), with
' the burst over it. The last 12 frames show nothing, so all of it is over
' and erased before a new helicopter appears at the pad.
GOSUB blast_draw
IF crash_timer <= 12 THEN
    SPRITE 0,209,0,0,0
    SPRITE 1,209,0,0,0
    RETURN
END IF
draw_x=#hv-#camera+6
draw_y=hy-1
draw_pat=52+rotor_phase*4
' The two halves swap yellow (10) and red (8) every 8 frames: the fire
' flickers between the colours as well as between its two shapes.
draw_color=10
IF anim AND 8 THEN draw_color=8
SPRITE 0,draw_y,draw_x,draw_pat,draw_color
draw_x=draw_x+10
draw_pat=108-draw_pat
draw_color=18-draw_color
SPRITE 1,draw_y,draw_x,draw_pat,draw_color
RETURN
' Cold results code shares the permanently selected data bank on TI.

result_screen:
GOSUB silence
GOSUB hide_all
GOSUB menu_restore
CLS
GOSUB best_update
PRINT AT 72,"MISSION COMPLETE"
IF lives = 0 THEN PRINT AT 72," MISSION REPORT "
IF saved = 64 THEN PRINT AT 72,"PERFECT RESCUE! "
' The skill level played; a practice (838) game marks it, and its saved
' count, with the small star (character 60) right after.
PRINT AT 231,"SKILL LEVEL    "
#vaddr=6394
IF difficulty = 0 THEN PRINT AT 246,"EASY"
IF difficulty = 1 THEN PRINT AT 246,"MEDIUM":#vaddr=6396
IF difficulty = 2 THEN PRINT AT 246,"HARD"
IF practice THEN VPOKE #vaddr,60
PRINT AT 295,"PEOPLE SAVED   "
digit_value=saved:#digit_pos=6454:GOSUB digits
IF practice THEN VPOKE 6456,60
PRINT AT 359,"PEOPLE LOST    "
digit_value=lost:#digit_pos=6518:GOSUB digits
PRINT AT 423,"STRANDED       "
digit_value=64-saved-lost:#digit_pos=6582:GOSUB digits
PRINT AT 487,"BEST RESCUE    "
digit_value=best:#digit_pos=6646:GOSUB digits
IF best_practice THEN VPOKE 6648,60
PRINT AT 741,"PRESS FIRE TO CONTINUE"
GOSUB release_input
result_wait:
WAIT
IF cont1.button THEN GOTO title
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

' The title and the hidden practice setup are cold code too.
title:
start_lives=3:practice=0:title_seq=0:title_key=15
GOSUB silence
GOSUB hide_all
GOSUB menu_restore
' The difficulty line's brackets are cyan on black, so the chosen level
' stands out from the white text. (Characters 91 and 93 appear on no other
' screen; the crowd recolours its cells in play and menu_restore resets the
' bottom third.)
DEFINE COLOR 91,1,bracket_colors
DEFINE COLOR 93,1,bracket_colors
CLS
PRINT AT 135,"C H O P L I F T E R"
PRINT AT 200,"RESCUE OPERATIONS"
PRINT AT 386,"FREE 64 PEOPLE. FLY THEM HOME."
GOSUB title_level
PRINT AT 644,"2026 UNHUMAN AND AI C&C"
PRINT AT 742,"PRESS FIRE TO START"
#hx=0:rotor_clock=0:rotor_phase=0
GOSUB title_heli
GOSUB release_input
title_wait:
WAIT
GOSUB title_heli
GOSUB title_code
IF title_seq = 3 THEN GOTO setup838
IF title_seq = 15 THEN GOTO title_fireworks
IF cont1.button THEN GOTO new_game
GOTO title_wait

title_fireworks:
' HOWIE: the perfect-rescue display, as if the game had just been won: all
' 64 saved and inside, the helicopter home on its pad. Nothing is recorded,
' and it returns to the title.
saved=64:lost=0:aboard=0:lives=start_lives:practice=0
FOR ini=0 TO 63
    person_state(ini)=7
NEXT ini
FOR ini=0 TO 3
    camp_open(ini)=1:camp_left(ini)=0:camp_released(ini)=16:camp_active(ini)=0
NEXT ini
home_walking=0:wave_id=255:board_count=0:delivery_pending=0
GOSUB new_heli
GOSUB game_screen
GOSUB show_fireworks
GOTO title

title_heli:
' The helicopter circles the name clockwise at 2 px a frame on a 528-pixel
' loop (#hx is the distance round it): banked side views eastbound along the
' top and westbound along the bottom, the front view down the east side and up
' the west side. The loop clears the text: x 8-247, y 8-79.
#hx=#hx+2
IF #hx >= 528 THEN #hx=0
dt=1:GOSUB rotor_tick
hy=0:hspeed=1
IF #hx < 208 THEN
    face=0:hdir=0
    draw_x=#hx+8:draw_y=7
ELSE
    IF #hx < 264 THEN
        face=2:hspeed=0
        draw_x=216:draw_y=#hx-201
    ELSE
        IF #hx < 472 THEN
            face=1:hdir=1
            #relative=480-#hx
            draw_x=#relative:draw_y=63
        ELSE
            face=2:hspeed=0
            #relative=535-#hx
            draw_x=8:draw_y=#relative
        END IF
    END IF
END IF
GOSUB heli_pose
SPRITE 0,draw_y,draw_x,draw_pat,15
draw_x=draw_x+16
draw_pat=draw_pat+4
SPRITE 1,draw_y,draw_x,draw_pat,15
RETURN

title_code:
' Keys act on a new press only. The joystick reads as keys 20 (LEFT) and 21
' (RIGHT), so it shares the same edge test.
menu_key=cont1.key
IF cont1.left THEN menu_key=20
IF cont1.right THEN menu_key=21
IF menu_key = title_key THEN RETURN
title_key=menu_key
IF menu_key = 15 THEN RETURN
' HOWIE (on the ColecoVision keypad its phone spelling, 4-6-9-4-3) plays the
' perfect-rescue fireworks: title_seq is 10 plus the letters matched, and 15
' when the word is complete.
IF title_seq >= 10 THEN
    IF menu_key = howie_keys(title_seq-10) THEN
        title_seq=title_seq+1
        RETURN
    END IF
    title_seq=0
END IF
IF menu_key = howie_keys(0) THEN title_seq=11:RETURN
IF menu_key = 8 THEN
    IF title_seq = 2 THEN title_seq=3 ELSE title_seq=1
ELSE
    IF menu_key = 3 THEN
        IF title_seq = 1 THEN title_seq=2 ELSE title_seq=0
    ELSE
        title_seq=0
    END IF
END IF
' Difficulty: 1, 2 or 3, or LEFT/RIGHT to step (a 3 that continues an 8-3
' sequence is not a choice).
IF title_seq THEN RETURN
IF menu_key = 20 THEN
    IF difficulty THEN difficulty=difficulty-1
END IF
IF menu_key = 21 THEN
    IF difficulty < 2 THEN difficulty=difficulty+1
END IF
IF menu_key >= 1 THEN
    IF menu_key <= 3 THEN difficulty=menu_key-1
END IF
title_level:
' The difficulty line: the chosen level in brackets.
IF difficulty = 0 THEN PRINT AT 482,"[1 EASY]  2 MEDIUM   3 HARD "
IF difficulty = 1 THEN PRINT AT 482," 1 EASY  [2 MEDIUM]  3 HARD "
IF difficulty = 2 THEN PRINT AT 482," 1 EASY   2 MEDIUM  [3 HARD]"
RETURN

setup838:
' The hidden practice setup only asks for the number of helicopters; a digit
' 1-9 starts the game. There is no way back to the title from here.
GOSUB hide_all
CLS
PRINT AT 359,"HELICOPTERS (1-9)?"
GOSUB release_input
title_key=8
setup_wait:
WAIT
menu_key=cont1.key
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

INCLUDE "assets.bas"
#if TI994A
BANK 2
#endif
' The fireworks and sortie overlay run with this bank (the TI's boot bank)
' selected by fixed-area wrappers.

sortie_overlay:
' Character 23 is a two-pixel solid line in the middle screen third only.
' Each line spans the visible text above or below it.
DEFINE VRAM 2232,8,hud_art
DEFINE VRAM 10424,8,sortie_bar_colors
ini=start_lives-lives
IF ini > 2 THEN ini=3
ini=ini*16
#if TI994A
' The 14 visible text bytes are followed by bar width and column. Copy the
' same bar across three rows, then the title overwrites its middle copy.
ASM movb @cvb_INI,r0
ASM srl r0,8
ASM ai r0,cvb_SORTIE_TITLES+14
ASM movb *r0+,r6
ASM movb *r0,r8
ASM srl r8,8
ASM ai r8,6464
ASM li r9,cvb_SORTIE_BAR_CELLS
ASM li r4,>0300
ASM clr r5
ASM bl @jsr
ASM data CPYBLK
' Inline ASM changed r0; CVBasic still assumes it holds ini*16 for SCREEN.
ASM movb @cvb_INI,r0
#else
draw_color=sortie_titles(ini+14)
#vaddr=sortie_titles(ini+15)
#vaddr=#vaddr+320
SCREEN sortie_bar_cells,0,#vaddr,draw_color,3,0
#endif
SCREEN sortie_titles,ini,361,14,1
IF ini = 48 THEN VPOKE 6515,start_lives-lives+49
draw_color=15
ini=0
sortie_wait:
draw_slot=0
GOSUB heli_draw
WAIT
IF cont1.up THEN hy=land_y-1:GOTO sortie_clear
dt=1:GOSUB rotor_tick
IF lives = start_lives THEN GOTO sortie_wait
ini=ini+1
IF ini < 90 THEN GOTO sortie_wait
sortie_clear:
' One narrow name-table copy removes the whole panel; stride zero reuses
' the same 14 spaces on all three rows, then stars_draw fills covered stars.
SCREEN sortie_blank_cells,0,329,14,3,0
star_visible=0
RETURN

fireworks:
' A fireworks display over the home (the view at its east end): the script
' is FW_SCRIPT in assets/generate.py. Every video frame, each firework is
' drawn from its phase, the frames since its start: a rocket rising from
' behind the home along its slanted path (x from fw_px at #fw_path, y from
' fw_rise, the climb every rocket shares) for fw_climb_len frames, trailing three embers at its earlier positions and
' whistling higher as it climbs, then its burst at the path's end with a
' crack: a core and five spark clusters in its group of six sprite slots
' (fw_slot), one table row per two frames, coloured from its scheme (fw_ramp:
' four shades, white to dark). Then the group is hidden.
' FIRE ends the show after its first second. The helicopter stands on the
' pad. Every variable used is one the game leaves idle by now: the frame
' clock (#last, #elapsed), the draw scratch, ini, di, ay, by, blast_row, #ax,
' #bx, #distance, sfx_volume and #sfx_pitch.
GOSUB silence
GOSUB hide_all
draw_slot=0:draw_color=15
GOSUB heli_draw
#last=FRAME
fireworks_loop:
WAIT
#elapsed=FRAME-#last
IF #elapsed >= 630 THEN GOTO fireworks_end
IF #elapsed >= 60 THEN
    IF cont1.button THEN GOTO fireworks_end
END IF
sfx_volume=0:#sfx_pitch=0
FOR ini=0 TO 29
    GOSUB firework_draw
NEXT ini
IF #sfx_pitch THEN SOUND 1,#sfx_pitch,6 ELSE SOUND 1,0,0
SOUND 3,6,sfx_volume
GOTO fireworks_loop
fireworks_end:
GOSUB silence
GOSUB hide_all
RETURN

firework_draw:
' Firework ini at #elapsed frames into the show.
IF #elapsed < #fw_start(ini) THEN RETURN
#distance=#elapsed-#fw_start(ini)
' Long over and hidden (the generator checks FW_DONE), so the finale's
' thirty cost little.
IF #distance >= 80 THEN RETURN
draw_slot=fw_slot(ini)
blast_row=fw_climb_len(ini)
IF #distance < blast_row THEN
    ' Climbing: the head (pattern 200, sprite 50) where its path is now, and
    ' embers (216, sprite 54) where it was 2, 4 and 6 frames ago, fading.
    #ax=#fw_path(ini)
    SPRITE draw_slot,fw_rise(#distance),fw_px(#ax+#distance),200,15
    FOR di=1 TO 3
        blast_row=draw_slot+di
        IF #distance >= di+di THEN
            #bx=#distance-di-di
            SPRITE blast_row,fw_rise(#bx),fw_px(#ax+#bx),216,fw_trail(di)
        ELSE
            SPRITE blast_row,209,0,0,0
        END IF
    NEXT di
    #sfx_pitch=#distance+#distance
    #sfx_pitch=320-#sfx_pitch
    RETURN
END IF
' The burst, at the path's end.
#ax=#fw_path(ini)+blast_row
draw_x=fw_px(#ax):by=fw_rise(blast_row)
#distance=#distance-blast_row
IF #distance >= 32 THEN
    ' Over: hide the group for 8 frames (the loop can take more than one),
    ' after which another firework may have it (the generator checks).
    IF #distance < 40 THEN
        FOR di=0 TO 5
            blast_row=draw_slot+di
            SPRITE blast_row,209,0,0,0
        NEXT di
    END IF
    RETURN
END IF
blast_row=#distance/2
' A fresh burst cracks, loudest at first.
IF blast_row < 4 THEN
    di=15-blast_row-blast_row-blast_row
    IF di > sfx_volume THEN sfx_volume=di
END IF
blast_row=blast_row+fw_kind(ini)
di=fw_ramp(ini)
draw_pat=fw_cpat(blast_row)
IF draw_pat THEN
    draw_color=fw_colors(di+fw_cshade(blast_row))
    SPRITE draw_slot,by,draw_x,draw_pat,draw_color
ELSE
    SPRITE draw_slot,209,0,0,0
END IF
draw_pat=fw_ppat(blast_row)
draw_color=fw_colors(di+fw_pshade(blast_row))
#ax=blast_row
#ax=#ax+#ax+#ax+#ax+#ax
FOR ay=1 TO 5
    draw_y=by+fw_dy(#ax)
    draw_y=draw_y-64
    #bx=draw_x+fw_dx(#ax)
    #bx=#bx-64
    blast_row=draw_slot+ay
    SPRITE blast_row,draw_y,#bx,draw_pat,draw_color
    #ax=#ax+1
NEXT ay
RETURN

INCLUDE "assets_boot.bas"
