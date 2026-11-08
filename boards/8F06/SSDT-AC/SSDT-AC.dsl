/*
 * SSDT-AC (v2): HP 8F06 交流电状态
 * 原 _PSR 读 H2RA(0xFE700000+0x340) 的 R400，macOS 下读不到真实值。
 * 改用标准 EC RAM 0x40 bit0（与 R400 镜像：插电=1，拔电=0）。
 * 配套：ACPI Patch  _PSR -> XPSR，_Q20 -> XQ20
 */
DefinitionBlock ("", "SSDT", 2, "HP8F06", "SSDTAC", 0x00000010)
{
    External (_SB_.PCI0.SBRG.EC0, DeviceObj)
    External (_SB_.PCI0.SBRG.EC0_.XQ20, MethodObj)
    External (_SB_.ACAD, DeviceObj)

    Scope (\_SB.PCI0.SBRG.EC0)
    {
        OperationRegion (ECR2, EmbeddedControl, Zero, 0xFF)
        Field (ECR2, ByteAcc, Lock, Preserve)
        {
            Offset (0x40),
            PS40,   8
        }

        Name (ACDS, 0xFF)

        Method (_Q20, 0, Serialized)
        {
            XQ20 ()

            Local0 = Zero
            If ((PS40 & One))
            {
                Local0 = One
            }

            If ((Local0 != ACDS))
            {
                ACDS = Local0
                Notify (\_SB.ACAD, 0x80)
            }
        }
    }

    Scope (\_SB.ACAD)
    {
        Method (_PSR, 0, NotSerialized)
        {
            If ((\_SB.PCI0.SBRG.EC0.PS40 & One))
            {
                Return (One)
            }

            Return (Zero)
        }
    }
}
