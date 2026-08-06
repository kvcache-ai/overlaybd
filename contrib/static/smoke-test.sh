#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 BIN_DIR SERVICE_CONFIG" >&2
    exit 2
fi

bin_dir=$1
service_config=$2
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

mkdir -p \
    "$work_dir/rootfs" \
    "$work_dir/log" \
    "$work_dir/cache/registry" \
    "$work_dir/cache/gzip"
touch "$work_dir/rootfs/hello-from-static-overlaybd"
tar -cf "$work_dir/layer.tar" -C "$work_dir/rootfs" .

jq \
    --arg log "$work_dir/log/overlaybd.log" \
    --arg audit "$work_dir/log/overlaybd-audit.log" \
    --arg cache "$work_dir/cache/registry" \
    --arg gzip "$work_dir/cache/gzip" \
    '.logConfig.logPath = $log | .auditPath = $audit | .cacheConfig.cacheDir = $cache | .gzipCacheConfig.cacheDir = $gzip | .gzipCacheConfig.enable = false | .enableAudit = false' \
    "$service_config" > "$work_dir/service.json"
mkdir -p /etc/overlaybd
cp "$work_dir/service.json" /etc/overlaybd/overlaybd.json

jq -n \
    --arg data "$work_dir/upper.data" \
    --arg index "$work_dir/upper.index" \
    --arg result "$work_dir/result.txt" \
    '{lowers: [], upper: {data: $data, index: $index}, resultFile: $result}' > "$work_dir/image.json"

"$bin_dir/overlaybd-create" --mkfs "$work_dir/upper.data" "$work_dir/upper.index" 1
"$bin_dir/overlaybd-apply" --service_config_path "$work_dir/service.json" "$work_dir/layer.tar" "$work_dir/image.json"
"$bin_dir/overlaybd-resize" --config "$work_dir/image.json" --size 2 --service_config_path "$work_dir/service.json"
"$bin_dir/overlaybd-commit" "$work_dir/upper.data" "$work_dir/upper.index" "$work_dir/layer.commit"
test -s "$work_dir/layer.commit"
