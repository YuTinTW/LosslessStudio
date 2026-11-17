#!/bin/bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOL_DIR="${PROJ_DIR}/reports/portability-20261117/test-volumes"
DMG_PATH="${VOL_DIR}/fat_test.dmg"
MOUNT_POINT="${VOL_DIR}/mnt"

if mount | grep -F "on ${MOUNT_POINT} " >/dev/null; then
    echo "卸載 FAT32 測試卷軸: ${MOUNT_POINT}..."
    hdiutil detach "${MOUNT_POINT}" -force >/dev/null || true
fi

if [ -f "${DMG_PATH}" ]; then
    rm -f "${DMG_PATH}"
fi
echo "FAT32 專案內測試卷軸環境清理完成。"
