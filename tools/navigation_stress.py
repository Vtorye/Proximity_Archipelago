"""Run Godot road benchmarks and write frame metrics and profiles."""

import argparse
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
SCENE = "res://tests/navigation_stress.tscn"
MAPS = ("flat", "412", "104729", "92183")


def run_report(godot, arguments, destination, marker):
    with destination.open("w", encoding="utf-8") as log:
        result = subprocess.run(
            [godot, "--path", str(ROOT), *arguments],
            cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
            timeout=90, check=False,
        )
    content = destination.read_text(encoding="utf-8", errors="replace")
    if result.returncode or any(
        line.lstrip().startswith(("SCRIPT ERROR:", "ERROR:")) for line in content.splitlines()
    ):
        raise SystemExit(f"Godot returned {result.returncode} or logged an error. See {destination}")
    for line in content.splitlines():
        if line.startswith(marker):
            return json.loads(line[len(marker):])
    raise SystemExit(f"Missing {marker.strip()} report in {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot 4.7.2 command or absolute path")
    parser.add_argument("--out", type=Path, default=ROOT / ".godot/navigation-stress")
    parser.add_argument("--couriers", type=int, choices=(30, 60), nargs="+", default=(30, 60))
    parser.add_argument("--maps", choices=MAPS, nargs="+", default=MAPS)
    options = parser.parse_args()
    out = options.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    rows = [
        "| Couriers | Map seed | p95 ms | p99 ms | Max ms | Frames ≥100 ms | Roads finished | Searches / repairs |",
        "|---:|---|---:|---:|---:|---:|---:|---:|",
    ]
    summary = out / "summary.md"
    summary.write_text("\n".join(rows) + "\n", encoding="utf-8")
    for couriers in options.couriers:
        for map_seed in options.maps:
            case = "0" if couriers == 30 else "1"
            seed_argument = [] if map_seed == "flat" else [f"seed={map_seed}"]
            destination = out / f"{couriers}-{map_seed}.log"
            print(f"Running {couriers} couriers / {map_seed}", flush=True)
            report = run_report(
                options.godot,
                ["--resolution", "640x360", "--disable-vsync", "--max-fps", "60",
                 "--quit-after", "3600", SCENE, "--", case, "profile", *seed_argument],
                destination, "NAV STRESS ",
            )
            expected_seed = -1 if map_seed == "flat" else int(map_seed)
            if (report["couriers"], report["map_seed"]) != (couriers, expected_seed):
                raise SystemExit(f"Wrong benchmark configuration in {destination}")
            frames = report["build_frames"]
            row = (
                f"| {couriers} | {map_seed} | {frames['p95_ms']:.1f} | "
                f"{frames['p99_ms']:.1f} | {frames['max_ms']:.1f} | "
                f"{frames['over_100_ms']}/{frames['count']} | "
                f"{report['roads_finished']}/{report['roads_queued']} | "
                f"{report['searches']}/{report['field_repairs']} |"
            )
            with summary.open("a", encoding="utf-8") as stream:
                print(row, file=stream)
            print(row, flush=True)


if __name__ == "__main__":
    main()
