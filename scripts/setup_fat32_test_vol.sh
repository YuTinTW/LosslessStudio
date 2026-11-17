#!/bin/bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOL_DIR="${PROJ_DIR}/reports/portability-20261117/test-volumes"
DMG_PATH="${VOL_DIR}/fat_test.dmg"
MOUNT_POINT="${VOL_DIR}/mnt"

mkdir -p "${VOL_DIR}" "${MOUNT_POINT}"

# 檢查是否已掛載
if mount | grep -F "on ${MOUNT_POINT} " >/dev/null; then
    echo "FAT32 測試卷軸已掛載於 ${MOUNT_POINT}"
    exit 0
fi

if [ ! -f "${DMG_PATH}" ]; then
    echo "建立專案內 FAT32 測試磁碟映像檔: ${DMG_PATH}..."
    hdiutil create -size 30m -fs MS-DOS -volname TESTFAT "${DMG_PATH}" >/dev/null
fi

hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" >/dev/null
echo "成功掛載 FAT32 測試卷軸至 ${MOUNT_POINT}"
