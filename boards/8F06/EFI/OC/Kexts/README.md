# Kexts

此目录**故意留空**，不随仓库分发第三方驱动二进制，原因见 `../../LICENSES.md`：

- `VoodooI2C` 是 GPL-3.0，`BlueToolFixup`（BrcmPatchRAM）是 GPL-2.0，
  分发二进制必须同时提供源码或书面要约；
- 其余驱动的许可证各不相同，逐个核实成本高。

请在仓库根目录运行：

```bash
./fetch-kexts.sh
```

脚本会从各项目的**官方 GitHub Release** 下载指定版本并放进本目录。
