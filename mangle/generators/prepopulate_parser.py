#!/usr/bin/env python3
import os
import os.path
import json
import dnf
import createrepo_c as cr
from common import *

REPOS = switcher.rlver((os.environ['RLVER']))

# Source packages we do not ship or are rocky branded
IGNORES = [
        'insights-client',
        'rhc',
        'centos-indexhtml',
        'centos-logos',
        'centos-stream-release',
        'redhat-indexhtml',
        'redhat-logos',
        'redhat-release'
]

def warningcb(warning_type, message):
    print("WARNING: %s" % message)
    return True

repo_prepop = {}
for k in REPOS:
    repo_prepop[k] = {}
    for arch in REPOS[k]:
        PRIMARY_XML_PATH   = None
        FILELISTS_XML_PATH = None
        OTHER_XML_PATH     = None
        REPO_PATH          = k + '/' + arch
        repomd = cr.Repomd()
        cr.xml_parse_repomd(os.path.join(REPO_PATH, "repodata/repomd.xml"), repomd, warningcb)
        for record in repomd.records:
            if record.type == "primary":
                PRIMARY_XML_PATH = os.path.join(REPO_PATH, record.location_href)
            elif record.type == "filelists":
                FILELISTS_XML_PATH = os.path.join(REPO_PATH, record.location_href)
            elif record.type == "other":
                OTHER_XML_PATH = os.path.join(REPO_PATH, record.location_href)

        package_iterator = cr.PackageIterator(primary_path=PRIMARY_XML_PATH, filelists_path=FILELISTS_XML_PATH, other_path=OTHER_XML_PATH, warningcb=warningcb)
        repo_prepop[k][arch] = {}
        for pkg in package_iterator:
            name = pkg.name + '.' + pkg.arch
            subject = dnf.subject.Subject(pkg.rpm_sourcerpm)
            possible_nevra = subject.get_nevra_possibilities()
            srcname = possible_nevra[0].name
            # Ignore packages (by source) that we do not ship
            if srcname in IGNORES:
                continue

            # Create the initial list if the package (by source) does not exist
            if srcname not in repo_prepop[k][arch]:
                repo_prepop[k][arch][srcname] = []

            # Avoids duplicate entries - This is especially helpful for modules
            if name not in repo_prepop[k][arch][srcname]:
                repo_prepop[k][arch][srcname].append(name)

            # Sorts the list items
            repo_prepop[k][arch][srcname].sort()

entry_point = open('/tmp/prepopulate.json', 'w+')
json.dump(repo_prepop, entry_point, indent=2, sort_keys=True)
entry_point.close()