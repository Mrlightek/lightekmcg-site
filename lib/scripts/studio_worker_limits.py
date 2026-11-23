#!/usr/bin/env python3
"""Clamp Studio CPU budgets to the Docker daemon's available CPU count."""
import argparse
import math
import os
import subprocess
from pathlib import Path


MIB = 1024**2
SITE_RESERVE_MIB = 1280
AVAILABLE_RESERVE_MIB = 512
MIN_BLENDER_MIB = 768


class BlenderCapacityError(ValueError):
    pass


def cpu_limit(requested=None):
    budget=float(os.environ.get('STUDIO_WORKER_CPUS','2') if requested is None else requested)
    if not math.isfinite(budget) or budget<0.01:
        raise ValueError('Studio worker CPUs must be a finite number of at least 0.01')
    available=int(subprocess.check_output(['docker','info','--format','{{.NCPU}}'],text=True,timeout=10).strip())
    if available<1:raise ValueError('Docker did not report a positive CPU count')
    return format(min(budget,available),'.10g')


def blender_memory_limit(requested):
    """Budget physical memory on the Linux Docker host and keep RAM for the site."""
    amount, unit = int(requested[:-1]), requested[-1]
    requested_mib = amount * {"g": 1024, "m": 1}[unit]
    if requested_mib <= 0:
        raise ValueError("Blender memory must be positive")

    total, memory_limit, swap_limit = subprocess.check_output(
        ["docker", "info", "--format", "{{.MemTotal}} {{.MemoryLimit}} {{.SwapLimit}}"],
        text=True, timeout=10,
    ).split()
    if (memory_limit, swap_limit) != ("true", "true"):
        raise BlenderCapacityError("The Blender worker needs Docker memory and swap limits.")

    available = next(
        int(line.split()[1]) // 1024
        for line in Path("/proc/meminfo").read_text().splitlines()
        if line.startswith("MemAvailable:")
    )
    budget = min(requested_mib, int(total) // MIB - SITE_RESERVE_MIB, available - AVAILABLE_RESERVE_MIB)
    if budget < min(requested_mib, MIN_BLENDER_MIB):
        raise BlenderCapacityError(
            "This server has insufficient RAM for Blender while keeping the site running. "
            "Retry when memory is available or use a larger Studio worker."
        )
    return f"{budget}m"


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--requested')
    mode.add_argument('--blender-memory')
    args=parser.parse_args()
    try:
        print(blender_memory_limit(args.blender_memory) if args.blender_memory else cpu_limit(args.requested))
    except BlenderCapacityError as error:
        parser.exit(75, str(error)+'\n')
    except (ValueError, KeyError, StopIteration, OSError, subprocess.SubprocessError) as error:
        resource = "Blender memory" if args.blender_memory else "Studio worker CPU"
        parser.exit(1, f'Unable to determine {resource} budget: {error}\n')
