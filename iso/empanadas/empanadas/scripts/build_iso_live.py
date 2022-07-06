# builds ISO's

import argparse

from empanadas.common import *
from empanadas.util import Checks
from empanadas.util import IsoBuild

parser = argparse.ArgumentParser(description="Live ISO Compose")

parser.add_argument('--release', type=str, help="Major Release Version or major-type (eg 9-beta)", required=True)
parser.add_argument('--arch', type=str, help="Architecture")
parser.add_argument('--isolation', type=str, help="Mock Isolation")
parser.add_argument('--local-compose', action='store_true', help="Compose Directory is Here")
parser.add_argument('--image', action='store_true', help="Compose Directory is Here")
parser.add_argument('--logger', type=str)
parser.add_argument('--live-iso-mode', type=str, default='local')
results = parser.parse_args()
rlvars = rldict[results.release]
major = rlvars['major']

a = IsoBuild(
        rlvars,
        config,
        major=major,
        arch=results.arch,
        isolation=results.isolation,
        extra_iso_mode=results.live_iso_mode,
        image=results.image,
        compose_dir_is_here=results.local_compose,
        logger=results.logger
)

def run():
    a.run_build_extra_iso()
