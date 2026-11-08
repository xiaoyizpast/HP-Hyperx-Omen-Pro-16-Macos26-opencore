#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
int main(void) {
    CGDirectDisplayID ids[16]; uint32_t n = 0;
    if (CGGetOnlineDisplayList(16, ids, &n) != kCGErrorSuccess) return 1;
    for (uint32_t i = 0; i < n; i++) {
        printf("id=%u builtin=%d active=%d\n", ids[i], CGDisplayIsBuiltin(ids[i]), CGDisplayIsActive(ids[i]));
    }
    return 0;
}
