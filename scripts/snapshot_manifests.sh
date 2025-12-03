#!/usr/bin/env bash
set -euo pipefail

# Snapshot k8s manifests, terraform and infra scripts into infra-locks/
# Usage: ./scripts/snapshot_manifests.sh [optional-label]

LABEL=${1:-$(date +%Y%m%d-%H%M%S)}
OUTDIR=infra-locks
SNAP=${OUTDIR}/manifests-${LABEL}.tar.gz
CHECK=${OUTDIR}/manifests-${LABEL}.txt

mkdir -p ${OUTDIR}

echo "Creating snapshot ${SNAP} ..."

tar -czf ${SNAP} \
  k8s-manifests/ \
  terraform/ 2>/dev/null || tar -czf ${SNAP} k8s-manifests/

# produce a flat list of files included
echo "Snapshot files:" > ${CHECK}
if [ -d k8s-manifests ]; then
  find k8s-manifests -type f | sort >> ${CHECK}
fi
if [ -d terraform ]; then
  find terraform -type f | sort >> ${CHECK}
fi

echo "Created ${SNAP}"
echo "Checklist at ${CHECK}"

echo "Next steps:"
echo " - Inspect ${SNAP} and copy it to a central storage (GCS/S3) for safekeeping."
echo " - To lock images: replace tags in manifests with image digests (see INFRA_CHANGELOG_AND_LOCKS.md for commands)."

exit 0
