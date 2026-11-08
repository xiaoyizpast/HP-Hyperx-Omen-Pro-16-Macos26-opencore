#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    int set = (argc > 1);
    float target = set ? (float)atof(argv[1]) : 0;
    io_iterator_t iter;
    io_service_t svc;
    CFMutableDictionaryRef m = IOServiceMatching("IODisplayConnect");
    if (IOServiceGetMatchingServices(kIOMainPortDefault, m, &iter) != KERN_SUCCESS) {
        fprintf(stderr, "no IODisplayConnect\n"); return 1;
    }
    int found = 0;
    while ((svc = IOIteratorNext(iter))) {
        CFDataRef edid = IODisplayCreateInfoDictionary(svc, kIODisplayOnlyPreferredName);
        (void)edid;
        float v = 0;
        if (IODisplayGetFloatParameter(svc, kNilOptions, CFSTR(kIODisplayBrightnessKey), &v) == kIOReturnSuccess) {
            found++;
            printf("display: brightness=%.3f\n", v);
            if (set) {
                kern_return_t kr = IODisplaySetFloatParameter(svc, kNilOptions, CFSTR(kIODisplayBrightnessKey), target);
                printf("  set -> %.3f : %s\n", target, kr == kIOReturnSuccess ? "ok" : "failed");
            }
        } else {
            printf("display: no brightness parameter\n");
        }
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);
    if (!found) fprintf(stderr, "no brightness-capable display found\n");
    return 0;
}
