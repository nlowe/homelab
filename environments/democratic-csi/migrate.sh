#!/usr/bin/env bash
set -euo pipefail

for pv in $(kubectl get pv --no-headers | grep iscsi | awk '{print $1}'); do
    echo "Migrating ${pv}"

    echo "  Saving PV"
    kubectl get pv $pv -o yaml >"${pv}.yaml.orig"

    echo "  Preparing new maninfest for $pv"
    yq -y -r 'del(.metadata.resourceVersion) | .spec.csi.volumeAttributes.portal="iscsi.storage.home.nlowe.dev" | .spec.csi.volumeAttributes.portals="iscsi.storage.home.nlowe.dev"' "${pv}.yaml.orig" > "${pv}.yaml"

    echo "  Setting policy to retain"
    kubectl patch pv $pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

    echo "  Deleting $pv"
    kubectl delete pv "${pv}" --wait=false
    kubectl patch pv "${pv}" -p '{"metadata":{"finalizers": null }}' &>/dev/null || true

    echo "  Recreating $pv"
    kubectl create -f "${pv}.yaml"
done
