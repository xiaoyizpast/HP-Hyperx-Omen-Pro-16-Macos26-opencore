# 免责声明 / Disclaimer

## 一、内容来源

本仓库的所有配置、SSDT、脚本与文档，均来自**互联网公开资料**（各驱动作者的项目主页、
社区教程、论坛讨论）以及**我个人的收集、整理与实机调试**。

- 我不是任何驱动的作者，也不代表任何项目
- 所有驱动的版权与著作权归各自作者所有，链接见 [DRIVERS.md](DRIVERS.md)
- 我**不保证**内容的准确性、完整性或适用于你的硬件
- 仓库中的配置是我这台机器的实测结果，换机型/换 BIOS 版本可能完全不同

## 二、硬件风险警告（重要）

> **以下为原文引用，内容来自社区报告，我未做独立验证：**
>
> 我们注意到，在运行 NullMoth 的 Nvdia 显卡驱动的设备上，有用户报告存在一定概率从硬件上
> 物理损坏显卡，报告者集中在 30-50 系产品，初步推测是 GPU Firmware（GSP）接管相关问题，
> 建议谨慎使用此开源驱动，此项报告来自 10 月，不确定是否修复，我不对任何个人损失负责。

补充说明：

- 该报告**未经我本人复现或验证**，我无法确认其真实性、范围或当前状态
- 本仓库**不包含** NullMoth 驱动的任何文件，也不会替你安装它
- 如果你决定使用该驱动，请自行评估风险，并优先关注其官方仓库的最新状态与 issue
- NullMoth 驱动是这套方案里**唯一能让 NVIDIA 显卡在 macOS 26 上工作**的方案，
  但它属于逆向/实验性质，请务必谨慎

## 三、责任限制

在适用法律允许的最大范围内：

- 使用本仓库内容造成的任何**直接或间接损失**（包括但不限于：数据丢失、系统无法启动、
  硬件损坏、保修失效、时间损失），**由使用者自行承担**
- 我不提供任何形式的担保（明示或暗示），包括适销性与特定用途适用性
- 如果你不同意以上条款，请不要使用本仓库的任何内容

## 四、致谢与敬意

**对 NullMoth 团队致以最崇高的敬意。**

在苹果早已放弃 NVIDIA、官方驱动停留在多年前的情况下，是他们让 30/40/50 系显卡
在 macOS 上重新拥有了 Metal 加速。这项工作没有任何商业回报，却要面对逆向工程、
固件行为、社区质疑与硬件风险的全部压力。

同样感谢 OpenCore、Lilu、VirtualSMC、WhateverGreen、VoodooI2C、WTLMtk 等所有
开源项目的作者——没有他们，这台机器不可能跑起来。

---

# English Summary

## Source of content

Everything here (config, SSDTs, scripts, docs) comes from **public internet sources**
(project repositories, community guides, forums) plus **my own collection, cleanup and
on-device debugging**. I am not the author of any driver; all rights belong to their
respective authors (see [DRIVERS.md](DRIVERS.md)). No accuracy or fitness is guaranteed.

## Hardware risk warning

> **Quoted from a community report, not independently verified by me:**
>
> Users have reported a **certain probability of physical GPU damage** on devices running the NullMoth
> NVIDIA driver, mostly on 30–50 series cards. The suspected cause is GPU firmware (GSP)
> takeover. Treat this open-source driver with caution. The report dates from October and
> it is unknown whether it has been fixed. I accept no responsibility for any personal loss.

This repository does **not** contain or install the NullMoth driver.

## Limitation of liability

To the maximum extent permitted by law, any direct or indirect loss arising from the use of
this repository (data loss, unbootable system, hardware damage, voided warranty, lost time)
is **borne by the user**. No warranty of any kind is provided.

## Respect

**Deepest respect to the NullMoth team.** They gave 30/40/50-series cards Metal acceleration
on macOS long after Apple dropped NVIDIA — with no commercial reward, and under the full
weight of reverse engineering, firmware behaviour, community scrutiny and hardware risk.

Thanks also to OpenCore, Lilu, VirtualSMC, WhateverGreen, VoodooI2C, WTLMtk and every other
open-source project that made this machine possible.
