"""Reproduce motion measurements from longplay 7YxKf8D7w8U (570x360).

Requires Pillow and ffmpeg. Video/frames stay in the supplied scratch directory;
only derived measurements belong in the repository. Round attribution was
checked against timer resets, scores and reserve hats; see level-review.md.
"""
import argparse
import csv
from collections import defaultdict
from pathlib import Path
import statistics
import subprocess
import sys

from PIL import Image, ImageChops

# Two seconds at ten samples/second. Levels 7/8, 11/12 and 15/16 distinguish
# the cart and plane changes; later witnesses check that the last tiers persist.
WITNESSES = [(1, 28), (2, 64), (3, 115), (4, 145), (5, 206), (6, 270),
             (7, 334), (8, 417), (9, 480), (10, 549), (11, 615), (12, 685),
             (13, 756), (14, 812), (15, 870), (16, 912), (17, 1005),
             (18, 1094), (19, 1200), (20, 1231), (21, 1321)]


def native(path):
    path = str(Path(path).resolve())
    if sys.platform == 'cygwin':
        return subprocess.check_output(['cygpath', '-w', path], text=True).strip()
    return path


def groups(columns, gap):
    out = []
    for x in columns:
        if not out or x - out[-1][-1] > gap:
            out.append([x])
        else:
            out[-1].append(x)
    return [(xs[0], xs[-1]) for xs in out]


def objects(image):
    if image.size != (570, 360):
        raise ValueError('This measurement is calibrated to the 570x360 longplay')
    r, g, b = image.split()
    def gt(channel, n):
        return channel.point([0] * (n + 1) + [255] * (255 - n))
    def lt(channel, n):
        return channel.point([255] * n + [0] * (256 - n))
    def both(a, b, c):
        return ImageChops.multiply(ImageChops.multiply(a, b), c)
    masks = {'cart': both(gt(r, 180), gt(g, 180), gt(b, 180)),
             'ball': both(gt(r, 150), lt(g, 140), lt(b, 125)),
             'plane': both(gt(r, 205), gt(g, 195), lt(b, 145))}
    result = []
    for kind, mask in masks.items():
        for floor, base in enumerate((286, 226, 166, 106)):
            if kind == 'plane' and floor == 3:
                continue
            y0, y1 = (base - 53, base - 28) if kind == 'plane' else (base - 42, base - 1)
            region = mask.crop((0, y0, 570, y1))
            pixels = region.load()
            columns = [x for x in range(570)
                       if sum(pixels[x, y] > 0 for y in range(y1 - y0)) >= 3]
            # The propeller can be disconnected from the yellow fuselage.
            for x0, x1 in groups(columns, 8 if kind == 'plane' else 3):
                if not 8 <= x1 - x0 <= 39:
                    continue
                box = region.crop((x0, 0, x1 + 1, y1 - y0)).getbbox()
                if not box:
                    continue
                height = box[3] - box[1]
                if kind == 'cart' and not (9 <= height <= 20 and y0 + box[3] >= base - 5):
                    continue  # tall pillars and short flashing actor fragments
                if kind == 'ball' and height > 20:
                    continue
                result.append((kind, floor, (x0 + x1) / 2))
    return result


def fit(track):
    ts, xs = zip(*track)
    mt, mx = statistics.mean(ts), statistics.mean(xs)
    slope = sum((t - mt) * (x - mx) for t, x in track) / sum((t - mt) ** 2 for t in ts)
    residual = max(abs(x - mx - slope * (t - mt)) for t, x in track)
    return slope, residual


def tracks(frames):
    active, finished = [], []
    for t, observations in frames:
        used, following = set(), []
        for kind, floor, points in active:
            last = points[-1][1]
            candidates = [(abs(x - last), i, x) for i, (k, f, x) in enumerate(observations)
                          if i not in used and (k, f) == (kind, floor) and abs(x - last) < 110]
            if candidates:
                _, index, x = min(candidates)
                extended = points + [(t, x)]
                if len(extended) < 3 or fit(extended)[1] <= 3:
                    used.add(index)
                    following.append((kind, floor, extended))
                    continue
            finished.append((kind, floor, points))
        following.extend((kind, floor, [(t, x)]) for i, (kind, floor, x) in enumerate(observations)
                         if i not in used)
        active = following
    finished += active
    for kind, floor, points in finished:
        if len(points) < 4:
            continue
        speed, error = fit(points)
        if abs(speed) >= 40:  # exclude frozen hazards and stationary white fragments
            yield kind, floor, points, speed, error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('video')
    parser.add_argument('scratch', type=Path)
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--csv', type=Path, required=True)
    args = parser.parse_args()
    args.scratch.mkdir(parents=True, exist_ok=True)
    rows = []
    for level, start in WITNESSES:
        folder = args.scratch / ('motion-%04d' % start)
        folder.mkdir(exist_ok=True)
        subprocess.run([args.ffmpeg, '-y', '-loglevel', 'error', '-ss', str(start),
                        '-i', native(args.video), '-t', '2', '-vf', 'fps=10',
                        native(folder / 'f%03d.png')], check=True)
        frames = []
        for i, path in enumerate(sorted(folder.glob('f*.png'))):
            with Image.open(path) as image:
                frames.append((start + i / 10, objects(image.convert('RGB'))))
        for kind, floor, points, speed, residual in tracks(frames):
            rows.append([level, kind, floor + 1, '%.1f' % points[0][0],
                         '%.1f' % points[-1][0], len(points), '%.2f' % abs(speed),
                         '%.2f' % residual])
        print('measured level', level, flush=True)
    with args.csv.open('w', newline='') as out:
        writer = csv.writer(out)
        writer.writerow(['level', 'kind', 'floor', 'start_s', 'end_s', 'samples',
                         'capture_px_per_s', 'max_fit_error_px'])
        writer.writerows(rows)
    grouped = defaultdict(list)
    for level, kind, _, _, _, _, speed, _ in rows:
        grouped[level, kind].append(float(speed))
    for key, values in sorted(grouped.items()):
        print(key, 'tracks', len(values), 'median px/s', round(statistics.median(values), 2))


if __name__ == '__main__':
    main()
