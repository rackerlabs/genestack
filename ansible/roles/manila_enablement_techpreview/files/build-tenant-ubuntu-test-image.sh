#!/bin/bash
# ==========================================================================
# Build an Ubuntu 24.04 Glance image with qemu-guest-agent pre-installed.
#
# Why: the default Ubuntu cloud image does not ship qemu-guest-agent, and
# installing it at boot via cloud-init fails in labs where tenant VMs have
# no working external DNS. Baking the package into the image avoids the
# apt/DNS dependency entirely.
#
# Why offline install: the libguestfs appliance used by virt-customize has
# no working DHCP/DNS in this environment (its /init never brings eth0 up),
# so the usual --install path (apt-get update + install inside the appliance)
# always fails with "Temporary failure resolving ..." — for every host, not
# just the public Ubuntu archive. We work around this by pre-fetching the
# qemu-guest-agent .deb from mirror.rackspace.com on the host (which has
# working networking), copying it into the image, and running dpkg -i
# offline inside the chroot. No appliance network needed.
#
# apt sources in the image are also rewritten to mirror.rackspace.com so
# tenant VMs booted from this image can later apt-install additional
# packages via the Rackspace mirror (reachable from the inner cloud)
# instead of the unreachable public archive.ubuntu.com.
#
# Run on the overseer as ubuntu (sudo is used for apt + virt-customize).
# Idempotent: skips work if the Glance image already exists with the right
# property set.
# ==========================================================================
set -euo pipefail

IMAGE_NAME="Ubuntu 24.04 Test Tenant"
WORK_DIR=/tmp
BASE_IMG="${WORK_DIR}/ubuntu24-base.img"   # pristine download, kept untouched
LOCAL_IMG="${WORK_DIR}/ubuntu24-qga.img"   # working copy — recreated each run
UPSTREAM_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

MIRROR="http://mirror.rackspace.com/ubuntu"
DEB_CACHE="${WORK_DIR}/qga-debs"

# --------------------------------------------------------------------------
# 1) Host prerequisites
# --------------------------------------------------------------------------
if ! command -v virt-customize >/dev/null 2>&1; then
  echo ">>> Installing libguestfs-tools..."
  sudo apt-get update -y
  sudo apt-get install -y libguestfs-tools
fi

cd "${WORK_DIR}"

# --------------------------------------------------------------------------
# 2) If Glance already has the image, nothing to do
# --------------------------------------------------------------------------
source /opt/genestack/scripts/genestack.rc

# genestack.rc may export OS_CLIENT_CONFIG_FILE pointing at a system-wide
# clouds.yaml that doesn't contain the "default" cloud — in which case
# `openstack --os-cloud default ...` fails with "Cloud default was not
# found". Pin to the per-user clouds.yaml (the one the Ansible
# setup-openstack-rc task creates), which the rest of this role relies on.
export OS_CLIENT_CONFIG_FILE="${HOME}/.config/openstack/clouds.yaml"
if [ ! -s "${OS_CLIENT_CONFIG_FILE}" ]; then
  echo "ERROR: ${OS_CLIENT_CONFIG_FILE} is missing or empty." >&2
  echo "       Run setup-openstack-rc.sh first as the current user." >&2
  exit 1
fi

if openstack --os-cloud default image show "${IMAGE_NAME}" -f value -c id >/dev/null 2>&1; then
  EXISTING_QGA=$(openstack --os-cloud default image show "${IMAGE_NAME}" -f json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("properties",{}).get("hw_qemu_guest_agent",""))')
  if [ "${EXISTING_QGA}" = "yes" ]; then
    echo ">>> Glance image '${IMAGE_NAME}' already exists with hw_qemu_guest_agent=yes. Nothing to do."
    exit 0
  fi
  echo ">>> Glance image '${IMAGE_NAME}' exists but hw_qemu_guest_agent != yes; updating property only."
  IMG_ID=$(openstack --os-cloud default image show "${IMAGE_NAME}" -f value -c id)
  openstack --os-cloud default image set "${IMG_ID}" --property hw_qemu_guest_agent=yes
  exit 0
fi

# --------------------------------------------------------------------------
# 3a) Download pristine upstream cloud image (kept untouched)
# --------------------------------------------------------------------------
if [ ! -s "${BASE_IMG}" ]; then
  echo ">>> Downloading upstream Ubuntu 24.04 cloud image..."
  wget -q --show-progress -O "${BASE_IMG}" "${UPSTREAM_URL}"
else
  echo ">>> Reusing pristine base ${BASE_IMG}"
fi

# --------------------------------------------------------------------------
# 3b) Create fresh working copy from pristine base.
# virt-customize modifies in place, so a partially-failed prior run leaves
# the working image in an inconsistent state. Always start from pristine.
# --------------------------------------------------------------------------
echo ">>> Creating working copy from pristine base..."
cp -f "${BASE_IMG}" "${LOCAL_IMG}"

# --------------------------------------------------------------------------
# 3c) Pre-fetch qemu-guest-agent .deb plus any runtime deps not present in
# the base cloud image.
# Preferred source is mirror.rackspace.com, but if the Rackspace mirror's
# Packages index doesn't carry a given package we fall back to the public
# archive. The apt-sources rewrite in step 4 still points tenant VMs at
# mirror.rackspace.com regardless of which mirror we fetched from here.
#
# Deps of qemu-guest-agent on Ubuntu 24.04 (main):
#   - libc6 (>= 2.34)   — present in cloud image
#   - liburing2 (>= 2.3) — NOT present, must be installed alongside
# Passing both .debs to a single `dpkg -i` call lets dpkg resolve the
# ordering between them.
# --------------------------------------------------------------------------
mkdir -p "${DEB_CACHE}"

# Search one mirror for a package across suites + components.
# Echoes the relative Filename: on stdout if found; returns 1 otherwise.
# Packages indices are cached on disk so repeat calls for different
# packages don't re-download the same indices.
find_deb_in_mirror() {
  local mirror_url="$1"
  local pkg="$2"
  local safe_name
  safe_name=$(printf '%s' "${mirror_url}" | tr ':/' '__')
  local suite component idx_file fn
  for suite in noble-updates noble noble-security noble-backports; do
    for component in main universe; do
      idx_file="${DEB_CACHE}/Packages-${safe_name}-${suite}-${component}"
      if [ ! -s "${idx_file}" ]; then
        if ! curl -sfL "${mirror_url}/dists/${suite}/${component}/binary-amd64/Packages.gz" 2>/dev/null \
             | gunzip > "${idx_file}" 2>/dev/null; then
          rm -f "${idx_file}"
          continue
        fi
      fi
      # Sanity-check that the index actually looks like a Packages file.
      [ -s "${idx_file}" ] || continue
      grep -q '^Package: ' "${idx_file}" || continue
      fn=$(awk -v pkg="${pkg}" '
        $1=="Package:" {found=($2==pkg)}
        found && $1=="Filename:" {print $2; exit}
      ' "${idx_file}")
      if [ -n "${fn}" ]; then
        printf '%s' "${fn}"
        return 0
      fi
    done
  done
  return 1
}

NEEDED_PKGS=(qemu-guest-agent liburing2)
DEB_PATHS=()
DEB_NAMES=()

for pkg in "${NEEDED_PKGS[@]}"; do
  FILENAME=""
  MIRROR_USED=""
  for candidate_mirror in "${MIRROR}" "http://archive.ubuntu.com/ubuntu"; do
    echo ">>> Searching ${candidate_mirror} for ${pkg}..."
    if fn=$(find_deb_in_mirror "${candidate_mirror}" "${pkg}"); then
      FILENAME="${fn}"
      MIRROR_USED="${candidate_mirror}"
      echo ">>> Found in ${candidate_mirror}: ${fn}"
      break
    fi
    echo ">>> Not found in ${candidate_mirror}."
  done

  if [ -z "${FILENAME}" ]; then
    echo "ERROR: ${pkg} not found in any mirror" >&2
    echo "Downloaded Packages indices (for diagnostics):" >&2
    for f in "${DEB_CACHE}"/Packages-*; do
      [ -f "$f" ] || continue
      printf "  %s: %s lines, %s Package entries\n" \
        "$(basename "$f")" \
        "$(wc -l <"$f" | tr -d ' ')" \
        "$(grep -c '^Package: ' "$f" 2>/dev/null || echo 0)" >&2
    done
    exit 1
  fi

  deb_url="${MIRROR_USED}/${FILENAME}"
  deb_name=$(basename "${FILENAME}")
  deb_path="${DEB_CACHE}/${deb_name}"
  if [ ! -s "${deb_path}" ]; then
    echo ">>> Downloading ${deb_url}"
    curl -sfL -o "${deb_path}" "${deb_url}"
  else
    echo ">>> Reusing cached ${deb_path}"
  fi
  DEB_PATHS+=("${deb_path}")
  DEB_NAMES+=("${deb_name}")
done

# --------------------------------------------------------------------------
# 4) Inject qemu-guest-agent into the image (offline dpkg) and tune the
#    image for lab use.
#
# No --network / --install: both are unusable here (the appliance has no
# working DHCP, so apt-get can never reach any mirror). We use --copy-in
# to stage the pre-downloaded .deb inside the image and dpkg -i to install
# it offline. Runtime dependencies are already present in the cloud image.
#
# apt sources rewrite:
#   Redirect archive.ubuntu.com / security.ubuntu.com (and any regional
#   mirror like us.archive.ubuntu.com) to mirror.rackspace.com in the
#   Ubuntu 24.04 deb822 source file so tenant VMs booted from this image
#   can apt-install additional packages at runtime via the Rackspace
#   mirror (reachable from the inner cloud) instead of the unreachable
#   public archive.
#
# Disable unattended-upgrades:
#   Tenant VMs in this lab have no reliable external DNS — periodic
#   apt-daily / unattended-upgrades runs just fail repeatedly and can
#   hold the apt lock while cloud-init or users are trying to install
#   packages. Two belts-and-suspenders:
#     - /etc/apt/apt.conf.d/20auto-upgrades set to all "0"; so even if
#       the timers fire, the periodic scripts are no-ops.
#     - apt-daily.timer / apt-daily-upgrade.timer / unattended-upgrades
#       masked so the timers themselves never fire.
#
# --smp / --memsize: the default 1 vCPU / 512MB appliance is slow;
#             bump it so this finishes in reasonable time.
# --selinux-relabel: harmless on Ubuntu, keeps the option available if the
#             same script is ever used on an SELinux-based image.
# --------------------------------------------------------------------------
# Build virt-customize argv: one --copy-in per .deb, single dpkg -i with all.
COPY_IN_ARGS=()
DPKG_TARGETS=""
for i in "${!DEB_PATHS[@]}"; do
  COPY_IN_ARGS+=(--copy-in "${DEB_PATHS[$i]}:/tmp")
  DPKG_TARGETS="${DPKG_TARGETS} /tmp/${DEB_NAMES[$i]}"
done

echo ">>> Running virt-customize (offline dpkg install of qemu-guest-agent + deps)..."
sudo virt-customize -a "${LOCAL_IMG}" \
  --smp 2 \
  --memsize 2048 \
  --run-command 'sed -i -e "s|http://archive.ubuntu.com/ubuntu/\?|http://mirror.rackspace.com/ubuntu/|g" -e "s|http://security.ubuntu.com/ubuntu/\?|http://mirror.rackspace.com/ubuntu/|g" -e "s|http://[a-z0-9.-]*\.archive\.ubuntu\.com/ubuntu/\?|http://mirror.rackspace.com/ubuntu/|g" /etc/apt/sources.list.d/ubuntu.sources' \
  "${COPY_IN_ARGS[@]}" \
  --run-command "dpkg -i${DPKG_TARGETS}" \
  --run-command 'systemctl enable qemu-guest-agent.service' \
  --run-command "rm -f${DPKG_TARGETS}" \
  --write '/etc/apt/apt.conf.d/20auto-upgrades:APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
' \
  --run-command 'systemctl mask apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service 2>/dev/null || true' \
  --selinux-relabel

# --------------------------------------------------------------------------
# 5) Upload to Glance with hw_qemu_guest_agent=yes and shared visibility
# --------------------------------------------------------------------------
echo ">>> Uploading to Glance as '${IMAGE_NAME}'..."
openstack --os-cloud default image create "${IMAGE_NAME}" \
  --file "${LOCAL_IMG}" \
  --disk-format qcow2 --container-format bare \
  --property hw_qemu_guest_agent=yes \
  --shared

echo ">>> Done. Image '${IMAGE_NAME}' is ready."
