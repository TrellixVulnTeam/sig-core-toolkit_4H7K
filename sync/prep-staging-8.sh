#!/bin/bash
# This should only be ran during straight updates during a minor release cadence.
# In the case of point releases, this will need to be changed accordingly so that
# way it can be ran properly.
#
# The point of this script is to basically allow all old versions of a package
# or set of packages to be available during the life of a point release. As it
# currently stands, CentOS has started doing this for both 8 and 8-stream. RHEL
# also does this (and has always done this, except they take it a step further
# and provide everything, even if it's not installable).
#
# Compose dir example: /mnt/repos-staging/mirror/pub/rocky/8.4-RC2

# Source common variables
export RLVER=8
# shellcheck disable=SC2046,1091,1090
source "$(dirname "$0")/common"

echo "** Updating source repos"
for y in "${ALL_REPOS[@]}"; do
  test -d "${STAGING_ROOT}/${RELEASE_DIR}/${y}/source/tree"
  ret_val=$?
  if [ "$ret_val" -eq 0 ]; then
    createrepo --update "${STAGING_ROOT}/${RELEASE_DIR}/${y}/source/tree" \
      "--distro=cpe:/o:rocky:rocky:${REVISION:0:1},Rocky Linux ${REVISION:0:1}"
    test -f /root/bin/sign-repo.sh && /root/bin/sign-repo.sh \
      "${STAGING_ROOT}/${RELEASE_DIR}/${y}/source/tree/repodata/repomd.xml"
  else
    echo "${STAGING_ROOT}/${RELEASE_DIR}/${y}/source/tree does not exist"
  fi
done

# Sync up some stuff
echo "** Updating arch repos as necessary **"
for x in "${ARCHES[@]}"; do
  echo "${x}: Sync up repos that do not use comps/groups"
  # regular repos, no comps
  for y in "${NONMODS_REPOS[@]}"; do
    # os and debug/tree directories
    for z in os debug/tree; do
      test -d "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/${z}"
      ret_val=$?
      if [ "$ret_val" -eq 0 ]; then
        createrepo --update "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/${z}" \
          "--distro=cpe:/o:rocky:rocky:${REVISION:0:1},Rocky Linux ${REVISION:0:1}"
        test -f /root/bin/sign-repo.sh && /root/bin/sign-repo.sh \
          "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/${z}/repodata/repomd.xml"
      else
        echo "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/${z} does not exist"
      fi
    done
  done
  # repos with comps/groups involved, but only debug
  for y in "${MODS_REPOS[@]}"; do
    test -d "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/debug/tree"
    ret_val=$?
    if [ "$ret_val" -eq 0 ]; then
      createrepo --update "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/debug/tree" \
        "--distro=cpe:/o:rocky:rocky:${REVISION:0:1},Rocky Linux ${REVISION:0:1}"
      test -f /root/bin/sign-repo.sh && /root/bin/sign-repo.sh \
        "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/debug/tree/repodata/repomd.xml"
    else
      echo "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/debug/tree does not exist"
    fi
  done

  echo "** Update all repos with comps/groups"
  for y in "${MODS_REPOS[@]}"; do
    echo "${y}: ${x}"
    test -d "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/os"
    ret_val=$?
    if [ "$ret_val" -eq 0 ]; then
      createrepo --update "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/os" \
        --groupfile="/mnt/compose/8/latest-Rocky-8/work/${x}/comps/comps-${y}.${x}.xml" \
        --xz --revision="${REVISION}" \
        "--distro=cpe:/o:rocky:rocky:${REVISION:0:1},Rocky Linux ${REVISION:0:1}" \
        --workers=8 --checksum=sha256
      test -f /root/bin/sign-repo.sh && /root/bin/sign-repo.sh \
        "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/os/repodata/repomd.xml"
    else
      echo "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/os does not exist"
    fi
  done

  echo "** Update modules"
  for y in "${MODS[@]}"; do
    echo "Modules: ${y} ${x}"
    cp "/mnt/compose/8_metadata/${x}/${y}-modules.yaml" /tmp/modules.yaml
    test -d "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/os"
    ret_val=$?
    if [ "$ret_val" -eq 0 ]; then
      modifyrepo --mdtype=modules /tmp/modules.yaml \
        "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/os/repodata" \
        --compress --compress-type=gz
      # This might not be necessary, but it does not hurt incase repomd is modified
      test -f /root/bin/sign-repo.sh && /root/bin/sign-repo.sh \
        "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/os/repodata/repomd.xml"
    else
      echo "${STAGING_ROOT}/${RELEASE_DIR}/${y}/${x}/os does not exist"
    fi

    rm /tmp/modules.yaml
    sleep 1
  done

  echo "** Fix variants"
  TREEINFO_VAR="${STAGING_ROOT}/${RELEASE_DIR}/BaseOS/${x}/os/.treeinfo"
  IMAGES_VAR="${STAGING_ROOT}/${RELEASE_DIR}/BaseOS/${x}/os/images"
  test -f "${TREEINFO_VAR}"
  treeinfo_retval=$?
  test -x /usr/bin/python3
  python_retval=$?
  # There is an awk way to do this, but it was easier to implement python and
  # cat heredoc together. It felt cleaner. This was a trick I had used in a
  # previous life when I had to admin Solaris systems, and I needed a way to
  # add a solaris 10 system into FreeIPA (it was not fun, let me tell you). But
  # the take away is I learned something kind of on the fly and well, it worked.
  # Emails should have stamps.
  if [ "$treeinfo_retval" -eq 0 ] && [ "$python_retval" -eq 0 ]; then
    # shellcheck disable=SC2086
    BOOTISO_CHECKSUM="$(sha256sum ${IMAGES_VAR}/boot.iso | cut -d' ' -f1)"
    # shellcheck disable=SC2086
    EFIBOOT_CHECKSUM="$(sha256sum ${IMAGES_VAR}/efiboot.img | cut -d' ' -f1)"
    # shellcheck disable=SC2086
    INSTALLIMG_CHECKSUM="$(sha256sum ${IMAGES_VAR}/install.img | cut -d' ' -f1)"
    # shellcheck disable=SC2086
    INITRD_CHECKSUM="$(sha256sum ${IMAGES_VAR}/pxeboot/initrd.img | cut -d' ' -f1)"
    # shellcheck disable=SC2086
    VMLINUZ_CHECKSUM="$(sha256sum ${IMAGES_VAR}/pxeboot/vmlinuz | cut -d' ' -f1)"
    cat <<EOF | /usr/bin/python3
from configparser import ConfigParser
config = ConfigParser()
config.read('${TREEINFO_VAR}')
config.set('tree', 'variants', 'BaseOS,AppStream')
config.add_section('variant-AppStream')
config.set('variants-AppStream', 'id', 'AppStream')
config.set('variants-AppStream', 'name', 'AppStream')
config.set('variants-AppStream', 'type', 'variant')
config.set('variants-AppStream', 'uid', 'AppStream')
config.set('variants-AppStream', 'packages', '../../../AppStream/${x}/os/Packages')
config.set('variants-AppStream', 'repository', '../../../AppStream/${x}/os/')
config.add_section('images-${x}')
config.set('images-${x}', 'boot.iso', 'images/boot.iso')
config.set('images-${x}', 'efiboot.img', 'images/efiboot.img')
config.set('images-${x}', 'initrd', 'images/pxeboot/initrd.img')
config.set('images-${x}', 'kernel', 'images/pxeboot/vmlinuz')
config.add_section('stage2')
config.set('stage2', 'mainimage', 'images/install.img')
config.add_section('checksums')
config.set('checksums', 'images/boot.iso', 'sha256:${BOOTISO_CHECKSUM}')
config.set('checksums', 'images/efiboot.img', 'sha256:${EFIBOOT_CHECKSUM}')
config.set('checksums', 'images/install.img', 'sha256:${INSTALLIMG_CHECKSUM}')
config.set('checksums', 'images/pxeboot/initrd.img', 'sha256:${INITRD_CHECKSUM}')
config.set('checksums', 'images/pxeboot/vmlinuz', 'sha256:${VMLINUZ_CHECKSUM}')

with open('${TREEINFO_VAR}', 'w') as configfile:
    config.write(configfile)
EOF
  else
    echo "${TREEINFO_VAR} or python3 does not exist on this system."
  fi
done
