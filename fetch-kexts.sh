#!/bin/bash
# 从各项目官方 Release 下载驱动到 boards/8F06/EFI/OC/Kexts
cd "$(dirname "$0")" || exit 1
exec python3 ./fetch-kexts.py
