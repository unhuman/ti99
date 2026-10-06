"""Build an isolated TI scrolling benchmark; never alter production source.

Run with Cygwin Python, then run the cart with tools/run-bench.ps1 (its own
Classic99 instance at Normal CPU speed; it starts the cart and captures the
finished screen). Each case reports the video frames taken by 32 updates
(lower is better), listed on rows 3-9 when finished.

Component cases (call people/camera/crowd/sprite routines directly, dt=2,
scrolling 8 px per update; comparable with the 2026-10-03 figures):
  0 empty world near home   1 64 waiting people off-screen
  2 visible waiting crowd   3 visible evacuating crowd (32 walkers)
Full-loop cases (the real main_loop, including its WAIT and frame-delta logic;
only the joystick-reading `fly` is replaced by an 8-px-per-update westward
flight with the helicopter invulnerable):
  4 open terrain, no enemies   5 waiting crowd + tank, jet, drone and shots
  6 evacuating crowd, no enemies

--stub ROUTINE (repeatable) makes a routine return immediately, to attribute
cost by difference. A stubbed build is a measurement, not a playable game.

--micro times single routines instead, as frames per 64 calls with no WAIT
(divide by 64 for frames per call; 1 frame is ~50,000 TMS9900 cycles):
  0 stars_draw per scroll step   1 terrain rows and overlays
  2 settled-crowd row            3 moving-crowd compositor (32 walkers)
  4 escape_tick (32 walkers)     5 draw_actors, all actors on
  6 draw_actors, all off         7 enemy_tick + weapon_tick
  8 sound, rotor, pause input, flight   9 crowd_commit incl. its WAIT
"""
import argparse
from pathlib import Path
from build import ROOT, build_ti

BENCH = '''
GOTO bench_start
bench_start:
DIM #bench_result(7)
bench_case=0
bench_setup:
FOR ini=0 TO 63
    person_state(ini)=0
NEXT ini
FOR ini=0 TO 3
    camp_open(ini)=0:camp_released(ini)=16:camp_active(ini)=0:camp_left(ini)=16
NEXT ini
tank_on=0:jet_on=0:drone_on=0:shell_on=0:missile_on=0:runner_on=0
shot_on(0)=0:shot_on(1)=0:home_walking=0:blast_timer=0
#hx=2012
bench_crowd=0
IF bench_case = 1 THEN bench_crowd=1
IF bench_case = 2 THEN bench_crowd=1:#hx=384
IF bench_case = 3 THEN bench_crowd=2:#hx=512
IF bench_case = 4 THEN #hx=1500
IF bench_case = 5 THEN bench_crowd=1:#hx=512
IF bench_case = 6 THEN bench_crowd=2:#hx=512
IF bench_crowd = 1 THEN GOSUB bench_waiting
IF bench_crowd = 2 THEN GOSUB bench_walkers
IF bench_case = 5 THEN GOSUB bench_enemies
hy=80:old_y=80:runner_on=0:hspeed=3:hdir=1:dt=2:invuln=255
terrain_dirty=1
GOSUB camera_tick
GOSUB crowd_draw
bench_i=0
#bench_start=FRAME
#last=FRAME
IF bench_case >= 4 THEN GOTO main_loop
FOR bench_i=0 TO 31
    #hx=#hx-8
    anim=anim+2
    GOSUB people_tick
    GOSUB camera_tick
    GOSUB crowd_draw
    GOSUB draw_actors
NEXT bench_i
GOTO bench_record

bench_tick:
bench_i=bench_i+1
IF bench_i < 32 THEN GOTO main_loop
bench_record:
#bench_result(bench_case)=FRAME-#bench_start
bench_case=bench_case+1
IF bench_case < 7 THEN GOTO bench_setup
GOSUB silence
GOSUB hide_all
FOR bench_case=0 TO 6
    #bench_pos=bench_case
    #bench_pos=#bench_pos*32
    #bench_pos=#bench_pos+96
    PRINT AT #bench_pos,"CASE ",bench_case,": ",#bench_result(bench_case),"     "
NEXT bench_case
PRINT AT 352,"BENCH DONE"
bench_done:
WAIT
GOTO bench_done
'''

HELPERS = '''
bench_waiting:
' Every person settled at their waiting spot, as after a full evacuation
' (the spot escape_walk/walk_camp stop at: camp_x +/- (88 - lane)).
FOR ep=0 TO 63
    person_state(ep)=2
    ec=ep/16
    escape_lane=(ep AND 15)/2
    escape_lane=escape_lane*8
    #person_x(ep)=#camp_x(ec)-88+escape_lane
    IF ep AND 1 THEN #person_x(ep)=#camp_x(ec)+88-escape_lane
NEXT ep
FOR ini=0 TO 3
    camp_open(ini)=1
NEXT ini
RETURN

bench_walkers:
' Camps 1 and 2 have just released everyone: 32 walkers leave the doors.
FOR ep=16 TO 47
    person_state(ep)=1
    ec=ep/16
    #person_x(ep)=#camp_x(ec)
NEXT ep
camp_active(1)=16:camp_active(2)=16
camp_open(1)=1:camp_open(2)=1
RETURN

bench_enemies:
tank_on=1:#tank_x=#hx-100:#tank_wait=30
jet_on=1:jet_dir=1:jet_turn=0:jet_passes=1:jet_ammo=2:jet_fire=0:jet_y=88
#jet_left=#hx-160:#jet_right=#hx+144:#jet_x=#hx+100
drone_on=1:#drone_x=#hx+60:drone_y=40
FOR wi=0 TO 1
    shot_on(wi)=1:shot_ttl(wi)=90:shot_y(wi)=90:shot_dir(wi)=1
    shot_slope(wi)=0:shot_speed(wi)=0:shot_drift(wi)=1
    #shot_x(wi)=#hx+wi*16
NEXT wi
RETURN

bench_fly:
' Stand-in for the joystick: cruise west one camera step per update.
invuln=255
hy=80:old_y=80:hspeed=3:hdir=1
#move=8
GOSUB move_heli
RETURN
'''


MICRO = '''
GOTO micro_start
micro_start:
DIM #bench_result(10)
' Shared scene near camps 0-2: camps open, everyone waiting, enemies on.
bench_case=0
GOSUB bench_waiting
#hx=512:hy=80:old_y=80:hspeed=3:hdir=1:dt=2:invuln=255
GOSUB bench_enemies
GOSUB camera_tick
terrain_dirty=1
GOSUB crowd_draw
' 0: stars, one camera step per call.
#bench_start=FRAME
FOR bench_i=0 TO 63
    #camera=#camera-8
    GOSUB stars_draw
NEXT bench_i
#bench_result(0)=FRAME-#bench_start
' 1: terrain rows and overlays (fences, flag, camp fires) per scroll.
#camera=400
#bench_start=FRAME
FOR bench_i=0 TO 63
    #camera=#camera-4
    GOSUB terrain
NEXT bench_i
#bench_result(1)=FRAME-#bench_start
' 2: settled-crowd row (waiting_draw), recomposed per call, no scenery copy.
#camera=400
#bench_start=FRAME
FOR bench_i=0 TO 63
    #camera=#camera-4:crowd_dirty=1:terrain_dirty=0
    GOSUB crowd_draw
NEXT bench_i
#bench_result(2)=FRAME-#bench_start
' 3: moving-crowd compositor with 32 walkers spread around camps 1-2.
GOSUB bench_walkers
FOR ep=16 TO 47
    #person_x(ep)=#person_x(ep)+(ep AND 15)*4-32
NEXT ep
#camera=400
#bench_start=FRAME
FOR bench_i=0 TO 15
    #camera=#camera-8:crowd_dirty=1:terrain_dirty=0
    GOSUB crowd_draw
NEXT bench_i
#bench_result(3)=(FRAME-#bench_start)*4
' 4: walking logic for those 32 walkers (16 calls, dt=2).
#bench_start=FRAME
FOR bench_i=0 TO 15
    GOSUB escape_tick
NEXT bench_i
#bench_result(4)=(FRAME-#bench_start)*4
' 5/6: sprites with every actor on, then every actor off.
GOSUB bench_enemies
runner_on=1:runner_id=16:#runner_x=#hx+40:blast_timer=30:missile_on=1:shell_on=1
#missile_x=#hx-30:missile_y=90:#shell_x=#hx+20:shell_y=120
#bench_start=FRAME
FOR bench_i=0 TO 63
    GOSUB draw_actors
NEXT bench_i
#bench_result(5)=FRAME-#bench_start
tank_on=0:jet_on=0:drone_on=0:runner_on=0:blast_timer=0:missile_on=0:shell_on=0
shot_on(0)=0:shot_on(1)=0
#bench_start=FRAME
FOR bench_i=0 TO 63
    GOSUB draw_actors
NEXT bench_i
#bench_result(6)=FRAME-#bench_start
' 7: enemies and weapons with tank, jet and drone active.
GOSUB bench_enemies
#bench_start=FRAME
FOR bench_i=0 TO 63
    GOSUB enemy_tick
    GOSUB weapon_tick
NEXT bench_i
#bench_result(7)=FRAME-#bench_start
' 8: sound, flight and pause input (per-update fixed costs).
#bench_start=FRAME
FOR bench_i=0 TO 63
    GOSUB sound_tick
    GOSUB rotor_tick
    GOSUB pause_input
    GOSUB bench_fly
NEXT bench_i
#bench_result(8)=FRAME-#bench_start
' 9: synchronised scenery commit (WAIT + rows 17-20) for comparison.
' (Reset the camera: earlier cases walked it down toward zero.)
#camera=400
#bench_start=FRAME
FOR bench_i=0 TO 15
    #camera=#camera-8:terrain_dirty=1:crowd_mask=0
    GOSUB crowd_commit
NEXT bench_i
#bench_result(9)=(FRAME-#bench_start)*4
GOSUB silence
GOSUB hide_all
CLS
PRINT AT 0,"FRAMES PER 64 CALLS"
FOR bench_case=0 TO 9
    #bench_pos=bench_case
    #bench_pos=#bench_pos*32
    #bench_pos=#bench_pos+64
    PRINT AT #bench_pos,"CASE ",bench_case,": ",#bench_result(bench_case),"     "
NEXT bench_case
PRINT AT 416,"BENCH DONE"
micro_done:
WAIT
GOTO micro_done
'''


def sub(text, old, new, count=1):
    """Replace exactly `count` occurrences or fail: a silent miss would
    benchmark the wrong program and still print plausible numbers."""
    found = text.count(old)
    if found < count:
        raise RuntimeError(f'Benchmark patch target missing: {old!r}')
    return text.replace(old, new, count)


def cut(text, label, next_label, body='RETURN'):
    """Replace everything from `label:` up to `next_label:` with one body line."""
    first = text.index(f'\n{label}:\n')
    last = text.index(f'\n{next_label}:\n', first)
    return text[:first]+f'\n{label}:\n{body}\n'+text[last:]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', type=Path, default=ROOT/'src/CHOPLIFT.bas')
    parser.add_argument('--assets', type=Path, default=ROOT/'src/assets.bas')
    parser.add_argument('--stub', action='append', default=[],
                        help='routine label to stub out with an immediate RETURN')
    parser.add_argument('--out', default='profile', help='folder under build/')
    parser.add_argument('--micro', action='store_true',
                        help='time single routines (frames per 64 calls) instead of whole updates')
    parser.add_argument('--review', action='store_true',
                        help='no benchmark: the real game, starting airborne over camps 1-2 '
                             'as they begin to evacuate, jets enabled and nine helicopters')
    parser.add_argument('--calm', action='store_true',
                        help='with --review: no tank and no jets, to watch crowds and boarding')
    args = parser.parse_args()
    source = args.source.read_text(encoding='utf-8')
    if args.review:
        # Initial conditions only; every routine is the production one.
        source = sub(source, 'GOTO title\n', 'start_lives=9\nGOTO new_game\n')
        source = sub(source, '#hx=1920\nhy=LANDED\n', '#hx=640\nhy=96\n')
        source = sub(source, 'GOSUB new_heli\nGOSUB game_screen\nGOSUB clock_reset\n',
                     'camp_open(1)=1:camp_open(2)=1' + ('' if args.calm else ':sorties=1') + '\n'
                     'GOSUB new_heli\nGOSUB game_screen\nGOSUB clock_reset\n')
        if args.calm:
            source = sub(source, '#tank_wait=150\n#jet_wait', '#tank_wait=60000\n#jet_wait')
        out = ROOT/'build'/args.out; out.mkdir(parents=True, exist_ok=True)
        (out/'PROFILE.bas').write_text(source, encoding='utf-8', newline='\n')
        (out/'assets.bas').write_bytes(args.assets.read_bytes())
        used, unopt, _ = build_ti(out, 'PROFILE', 'CHOP REVIEW')
        print(f'Review cart (not a benchmark), fixed code {used}/24336:', out/'PROFILE_8.bin')
        return
    source = sub(source, 'GOTO title\n', 'start_lives=3\nGOTO new_game\n')
    bench = MICRO if args.micro else BENCH
    source = sub(source, '\nmain_loop:\n', bench+HELPERS+'\nmain_loop:\n')
    source = sub(source, '\nGOSUB fly\n', '\nGOSUB bench_fly\n')
    if not args.micro:
        source = sub(source, 'IF hud_dirty THEN GOSUB hud\nGOTO main_loop\n',
                     'IF hud_dirty THEN GOSUB hud\nGOTO bench_tick\n')
    # Remove code the benchmark never reaches so instrumentation fits the
    # fixed-code budget: the title/setup UI and pause.
    source = cut(source, 'title', 'new_game', 'GOTO new_game')
    source = cut(source, 'pause_game', 'practice_star')
    source = cut(source, 'menu_restore', 'fence_boundary')
    if args.micro:
        # The helicopter is invulnerable throughout: crash code never runs.
        source = cut(source, 'crash', 'crash_tick')
        source = cut(source, 'crash_tick', 'explode')
        source = cut(source, 'crash_draw', 'heli_draw')
    for label in args.stub:
        source = sub(source, f'\n{label}:\n', f'\n{label}:\nRETURN\n')
    out = ROOT/'build'/args.out; out.mkdir(parents=True, exist_ok=True)
    (out/'PROFILE.bas').write_text(source, encoding='utf-8', newline='\n')
    (out/'assets.bas').write_bytes(args.assets.read_bytes())
    # Same compile/assemble/short-branch/pack path as the production cart, so
    # the benchmark times the code that ships.
    used, unopt, _ = build_ti(out, 'PROFILE', 'CHOP PROFILE')
    path = out/'PROFILE_8.bin'
    print(f'Benchmark fixed code {used}/24336; stubs: {args.stub or "none"}')
    print('Benchmark only; restore the production cartridge after capture:', path)


if __name__ == '__main__': main()
