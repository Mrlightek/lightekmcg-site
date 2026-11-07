#!/usr/bin/env python3
"""Clamp Studio CPU budgets to the Docker daemon's available CPU count."""
import argparse
import math
import os
import subprocess


def cpu_limit(requested=None):
    budget=float(os.environ.get('STUDIO_WORKER_CPUS','2') if requested is None else requested)
    if not math.isfinite(budget) or budget<0.01:
        raise ValueError('Studio worker CPUs must be a finite number of at least 0.01')
    available=int(subprocess.check_output(['docker','info','--format','{{.NCPU}}'],text=True,timeout=10).strip())
    if available<1:raise ValueError('Docker did not report a positive CPU count')
    return format(min(budget,available),'.10g')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--requested');args=parser.parse_args()
    try:print(cpu_limit(args.requested))
    except (ValueError,OSError,subprocess.SubprocessError) as error:
        parser.exit(1,'Unable to determine Studio worker CPU budget: '+str(error)+'\n')
