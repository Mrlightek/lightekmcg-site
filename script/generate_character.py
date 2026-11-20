#!/usr/bin/env python3
"""Generate a dressed, rigged MakeHuman FBX for Mixamo."""
import argparse
from pathlib import Path


def fraction(value):
    number = float(value)
    if not 0 <= number <= 1:
        raise argparse.ArgumentTypeError("use a number between 0 and 1")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    for name in ("gender", "height", "muscle"):
        parser.add_argument(f"--{name}", type=fraction, default=0.5)
    args = parser.parse_args()
    if args.output.suffix.lower() != ".fbx":
        parser.error("--output must end in .fbx")

    from mhcore import new_human

    human = new_human()
    human.set_gender(args.gender).set_age(0.5).set_weight(0.6)
    human.set_height(args.height).set_muscle(args.muscle)
    for kind, equip in (("clothes", human.equip_clothes), ("hair", human.equip_hair),
                        ("eyes", human.equip_eyes), ("skins", human.set_skin)):
        options = sorted(human.list_available(kind))
        if kind == "clothes" and not options:
            raise RuntimeError("MakeHuman has no clothing assets installed")
        if options:
            equip(options[0])
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    human.export(str(output), format="fbx", rig="deform")
    if not output.is_file() or output.stat().st_size < 1024:
        raise RuntimeError("MakeHuman did not write a usable FBX")
    print(f"[makehuman] Wrote {output}")


if __name__ == "__main__":
    main()
