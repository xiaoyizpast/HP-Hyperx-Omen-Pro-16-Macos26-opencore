#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <i386/proc_reg.h>
#include <sys/sysctl.h>
#include <architecture/i386/pio.h>
#include <string.h>
#include <stdio.h>
#include <mach/kmod.h>

#define EC_DATA 0x62
#define EC_STS  0x66
#define IBF     0x02
#define OBF     0x01

static bool gManual = false;
static char gBuf[160];
static char gSet[32];

static int ec_wait(int mask, int want, int loops) {
    for (int i = 0; i < loops; i++) {
        if ((inb(EC_STS) & mask) == want) return 0;
        IODelay(15);
    }
    return -1;
}

static int ec_drain(void) {
    for (int i = 0; i < 8000; i++) {
        if ((inb(EC_STS) & OBF) == 0) return 0;
        (void)inb(EC_DATA);
        IODelay(15);
    }
    return -1;
}

static int ec_cmd(UInt8 cmd) {
    if (ec_drain()) return -1;
    if (ec_wait(IBF, 0, 8000)) return -2;
    outb(EC_STS, cmd);          /* command goes to 0x66 */
    return 0;
}

static int ec_data(UInt8 d) {
    if (ec_wait(IBF, 0, 8000)) return -3;
    outb(EC_DATA, d);           /* address/value goes to 0x62 */
    return 0;
}

static int ec_read(UInt8 addr, UInt8 *val) {
    if (ec_cmd(0x80)) return -4;
    if (ec_data(addr)) return -5;
    if (ec_wait(OBF, OBF, 8000)) return -6;
    *val = inb(EC_DATA);
    return 0;
}

static int ec_write(UInt8 addr, UInt8 val) {
    if (ec_cmd(0x81)) return -4;
    if (ec_data(addr)) return -5;
    if (ec_data(val)) return -6;
    return 0;
}

static char gWrite[32];
static char gWriteResult[64];

static int ecwrite SYSCTL_HANDLER_ARGS
{
    int err = sysctl_handle_string(oidp, gWrite, sizeof(gWrite), req);
    if (err) return err;
    if (req->newptr == 0) return 0;

    unsigned int addr = 0, val = 0;
    if (sscanf(gWrite, "%x:%x", &addr, &val) != 2) {
        snprintf(gWriteResult, sizeof(gWriteResult), "format: AA:VV (hex)");
        return 0;
    }
    /* 白名单：模式 0x95，PL1 0x30，TGP 0x96，风扇目标 0x34/0x35，手动位 0x62 */
    int allowed = (addr == 0x95 || addr == 0x30 || addr == 0x96 ||
                   addr == 0x34 || addr == 0x35 || addr == 0x62);
    if (!allowed || val > 0xFF) {
        snprintf(gWriteResult, sizeof(gWriteResult), "denied %02X:%02X", addr, val);
        return 0;
    }
    int rc = ec_write((UInt8)addr, (UInt8)val);
    UInt8 rb = 0; ec_read((UInt8)addr, &rb);
    snprintf(gWriteResult, sizeof(gWriteResult), "write %02X=%02X rc=%d readback=%02X",
             addr, val, rc, rb);
    return 0;
}

static IOACPIPlatformDevice *gWMI = nullptr;
static char gPl[32];
static char gPlRes[128];

static IOACPIPlatformDevice *getWMI(void)
{
    if (gWMI) return gWMI;
    OSDictionary *m = IOService::serviceMatching("IOACPIPlatformDevice");
    if (!m) return nullptr;
    m->setObject("IONameMatch", OSString::withCString("WMID"));
    IOService *svc = IOService::copyMatchingService(m);
    m->release();
    if (svc) gWMI = OSDynamicCast(IOACPIPlatformDevice, svc);
    return gWMI;
}

static int wmipl SYSCTL_HANDLER_ARGS
{
    int err = sysctl_handle_string(oidp, gPl, sizeof(gPl), req);
    if (err) return err;
    if (req->newptr == 0) {
        snprintf(gPlRes, sizeof(gPlRes), "write 40-130 (W)");
        return 0;
    }
    int v = 0;
    if (sscanf(gPl, "%d", &v) != 1 || v < 40 || v > 130) {
        snprintf(gPlRes, sizeof(gPlRes), "range 40-130");
        return 0;
    }
    IOACPIPlatformDevice *wmi = getWMI();
    if (!wmi) {
        snprintf(gPlRes, sizeof(gPlRes), "WMID not found");
        return 0;
    }
    UInt8 buf[0x14] = {
        'S','E','C','U',
        0x08, 0x00, 0x02, 0x00,      /* 0x00020008 */
        0x29, 0x00, 0x00, 0x00,      /* commandType 0x29 */
        0x04, 0x00, 0x00, 0x00,      /* data size 4 */
        (UInt8)v, (UInt8)v, 0xFF, 0xFF /* PL2, PL1, PL4, TPP */
    };
    OSData *data = OSData::withBytes(buf, sizeof(buf));
    OSNumber *n0 = OSNumber::withNumber((UInt32)0, 32);
    OSNumber *n2 = OSNumber::withNumber((UInt32)2, 32);
    OSObject *params[3] = { n0, n2, data };
    OSObject *result = nullptr;
    IOReturn r = wmi->evaluateObject("WMAA", &result, params, 3);
    snprintf(gPlRes, sizeof(gPlRes), "WMAA(%dW) rc=0x%x result=%s",
             v, r, result ? "yes" : "none");
    if (result) result->release();
    if (data) data->release();
    if (n0) n0->release();
    if (n2) n2->release();
    return 0;
}

static int cpufreq SYSCTL_HANDLER_ARGS
{
    /* APERF/MPERF 比值 × 标称频率，估算当前核心频率 */
    UInt64 m0 = rdmsr64(0xE7);
    UInt64 a0 = rdmsr64(0xE8);
    IODelay(50000);
    UInt64 m1 = rdmsr64(0xE7);
    UInt64 a1 = rdmsr64(0xE8);
    double ratio = (m1 > m0) ? (double)(a1 - a0) / (double)(m1 - m0) : 0.0;
    double mhz = ratio * 2500.0;
    char out[48];
    snprintf(out, sizeof(out), "%.0f", mhz);
    return sysctl_handle_string(oidp, out, sizeof(out), req);
}

static int cpupower SYSCTL_HANDLER_ARGS
{
    /* AMD RAPL: 0xC0010299 单位, 0xC001029B 封装能量 */
    UInt32 lo = 0, hi = 0;
    rdmsr(0xC0010299, lo, hi);
    UInt32 unit = (lo >> 8) & 0x1F;
    UInt64 e0 = rdmsr64(0xC001029B);
    IODelay(100000);
    UInt64 e1 = rdmsr64(0xC001029B);
    double joules = (double)(e1 - e0) / (double)(1u << unit);
    double watts = joules / 0.1;
    char out[48];
    snprintf(out, sizeof(out), "%.1f", watts);
    return sysctl_handle_string(oidp, out, sizeof(out), req);
}

static char gDump[1200];

static void dump_range(int base, char *out, size_t outsz)
{
    size_t pos = 0;
    for (int row = 0; row < 8; row++) {
        int addr = base + row * 16;
        pos += snprintf(out + pos, outsz - pos, "%02X:", addr);
        for (int c = 0; c < 16; c++) {
            UInt8 v = 0xFF;
            ec_read((UInt8)(addr + c), &v);
            pos += snprintf(out + pos, outsz - pos, " %02X", v);
        }
        pos += snprintf(out + pos, outsz - pos, "\n");
    }
}

static int ecdump0 SYSCTL_HANDLER_ARGS
{
    dump_range(0x00, gDump, sizeof(gDump));
    return sysctl_handle_string(oidp, gDump, sizeof(gDump), req);
}

static int ecdump1 SYSCTL_HANDLER_ARGS
{
    dump_range(0x80, gDump, sizeof(gDump));
    return sysctl_handle_string(oidp, gDump, sizeof(gDump), req);
}

static int ecfan_read SYSCTL_HANDLER_ARGS
{
    UInt8 f1l=0, f1h=0, f2l=0, f2h=0, cpu=0, ctrl=0, s1=0, s2=0, t2=0, gpu=0;
    int e = 0;
    e |= ec_read(0xB0, &f1l);
    e |= ec_read(0xB1, &f1h);
    e |= ec_read(0xB2, &f2l);
    e |= ec_read(0xB3, &f2h);
    e |= ec_read(0x57, &cpu);
    e |= ec_read(0x62, &ctrl);
    e |= ec_read(0x34, &s1);
    e |= ec_read(0x35, &s2);
    e |= ec_read(0x47, &t2);
    e |= ec_read(0xB7, &gpu);
    UInt32 f1 = (UInt32)f1l | ((UInt32)f1h << 8);
    UInt32 f2 = (UInt32)f2l | ((UInt32)f2h << 8);
    if (gManual && f1 == 0) {
        ec_write(0x62, ctrl & ~1);
        gManual = false;
    }
    snprintf(gBuf, sizeof(gBuf),
             "fan1=%u fan2=%u cpu=%u gpu=%u t2=%u ctrl=0x%02x srp1=%u srp2=%u manual=%d err=%d",
             (unsigned)f1, (unsigned)f2, cpu, gpu, t2, ctrl, s1, s2, gManual ? 1 : 0, e);
    return sysctl_handle_string(oidp, gBuf, sizeof(gBuf), req);
}

static int ecfan_set SYSCTL_HANDLER_ARGS
{
    int err = sysctl_handle_string(oidp, gSet, sizeof(gSet), req);
    if (err) return err;
    if (req->newptr == 0) return 0;

    UInt8 ctrl = 0;
    ec_read(0x62, &ctrl);

    if (strcmp(gSet, "auto") == 0) {
        ec_write(0x62, 0x00);
        ec_write(0x34, 0xFF);
        ec_write(0x35, 0xFF);
        gManual = false;
        return 0;
    }
    int pct = 0;
    if (sscanf(gSet, "%d", &pct) != 1) return EINVAL;
    if (pct < 30) pct = 30;
    if (pct > 100) pct = 100;
    UInt8 krpm = (UInt8)((pct * 55) / 100);
    if (krpm < 16) krpm = 16;

    /* 只在尚未进入手动模式时才切换，避免反复写 0x62 把 EC 状态切乱 */
    if ((ctrl & 0x01) == 0) {
        ec_write(0x62, 0x00);
        IODelay(20000);
        ec_write(0x62, 0x0E);
        IODelay(50000);
    }
    ec_write(0x34, krpm);
    ec_write(0x35, krpm);
    IODelay(20000);
    ec_write(0x34, krpm);
    ec_write(0x35, krpm);
    gManual = true;
    return 0;
}

SYSCTL_PROC(_kern, OID_AUTO, ecfan, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_ANYBODY,
            0, 0, ecfan_read, "A", "EC fan read");
SYSCTL_PROC(_kern, OID_AUTO, wmipl, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_ANYBODY,
            0, 0, wmipl, "A", "HP WMI PL1/PL2 set");
SYSCTL_PROC(_kern, OID_AUTO, ecwrite, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_ANYBODY,
            0, 0, ecwrite, "A", "EC write AA:VV (whitelisted)");
SYSCTL_PROC(_kern, OID_AUTO, cpupower, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_ANYBODY,
            0, 0, cpupower, "A", "CPU package power W");
SYSCTL_PROC(_kern, OID_AUTO, cpufreq, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_ANYBODY,
            0, 0, cpufreq, "A", "CPU frequency MHz");
SYSCTL_PROC(_kern, OID_AUTO, ecdump0, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_ANYBODY,
            0, 0, ecdump0, "A", "EC dump 0x00-0x7F");
SYSCTL_PROC(_kern, OID_AUTO, ecdump1, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_ANYBODY,
            0, 0, ecdump1, "A", "EC dump 0x80-0xFF");
SYSCTL_PROC(_kern, OID_AUTO, ecfan_set, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_ANYBODY,
            0, 0, ecfan_set, "A", "EC fan set");

class ECFanPMIO : public IOService {
    OSDeclareDefaultStructors(ECFanPMIO)
public:
    virtual bool start(IOService *provider) override;
    virtual void stop(IOService *provider) override;
};

OSDefineMetaClassAndStructors(ECFanPMIO, IOService)

bool ECFanPMIO::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    sysctl_register_oid(&sysctl__kern_cpupower);
    sysctl_register_oid(&sysctl__kern_cpufreq);
    sysctl_register_oid(&sysctl__kern_ecfan);
    sysctl_register_oid(&sysctl__kern_ecfan_set);
    sysctl_register_oid(&sysctl__kern_ecwrite);
    sysctl_register_oid(&sysctl__kern_ecdump0);
    sysctl_register_oid(&sysctl__kern_ecdump1);
    registerService();
    return true;
}

void ECFanPMIO::stop(IOService *provider)
{
    sysctl_unregister_oid(&sysctl__kern_ecwrite);
    sysctl_unregister_oid(&sysctl__kern_ecdump1);
    sysctl_unregister_oid(&sysctl__kern_ecdump0);
    sysctl_unregister_oid(&sysctl__kern_ecfan_set);
    sysctl_unregister_oid(&sysctl__kern_cpupower);
    sysctl_unregister_oid(&sysctl__kern_cpufreq);
    sysctl_unregister_oid(&sysctl__kern_ecfan);
    IOService::stop(provider);
}

extern "C" {
static kern_return_t ecfan_kmod_start(kmod_info_t *ki, void *d) { return KERN_SUCCESS; }
static kern_return_t ecfan_kmod_stop(kmod_info_t *ki, void *d) { return KERN_SUCCESS; }
KMOD_EXPLICIT_DECL(ecfanpmio, "0.1", ecfan_kmod_start, ecfan_kmod_stop);
}
