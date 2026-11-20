#!/usr/bin/env python3
"""Generate one weighted MakeHuman FBX for Mixamo's rig mapping."""
import argparse
from pathlib import Path


def fraction(value):
    number = float(value)
    if not 0 <= number <= 1:
        raise argparse.ArgumentTypeError("expected a number between 0 and 1")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--gender", type=fraction, default=0.5)
    parser.add_argument("--age", type=fraction, default=0.5)
    parser.add_argument("--weight", type=fraction, default=0.5)
    parser.add_argument("--height", type=fraction, default=0.5)
    args = parser.parse_args()
    if args.out.suffix.lower() != ".fbx":
        parser.error("--out must end in .fbx")

    from mhcore import new_human

    human = new_human()
    human.set_gender(args.gender).set_age(args.age).set_weight(args.weight).set_height(args.height)
    output = args.out.absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    human.export(str(output), format="fbx", rig="deform")
    if not output.is_file() or output.stat().st_size < 1024:
        raise RuntimeError("MakeHuman did not produce a usable FBX")


if __name__ == "__main__":
    main()
