// Stand-in for a Claude Code process during development. It is a non-platform
// binary, so (unlike /bin/sleep) macOS exposes its environment to KERN_PROCARGS2.
//
//   FAKE_IGNORE_TERM=1   ignore SIGTERM (exercises the SIGKILL fallback)
//   FAKE_MEM_MB=512      keep that much memory resident (realistic usage numbers)
//   FAKE_CPU=35          burn roughly that percent of one core
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static char *volatile resident;

static long now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000L + ts.tv_nsec / 1000;
}

int main(void) {
    if (getenv("FAKE_IGNORE_TERM")) signal(SIGTERM, SIG_IGN);

    const char *mem = getenv("FAKE_MEM_MB");
    if (mem) {
        size_t bytes = (size_t)atol(mem) * 1024 * 1024;
        resident = malloc(bytes);
        // Touch every page through a volatile pointer so the optimizer can't drop the writes.
        for (size_t i = 0; resident && i < bytes; i += 4096) resident[i] = 1;
    }

    const char *cpu = getenv("FAKE_CPU");
    int percent = cpu ? atoi(cpu) : 0;
    if (percent <= 0) {
        for (;;) pause();
    }
    const long period = 20000;  // 20 ms duty cycle
    for (;;) {
        long start = now_us();
        volatile unsigned long spin = 0;
        while (now_us() - start < period * percent / 100) spin++;
        if (percent < 100) usleep((useconds_t)(period * (100 - percent) / 100));
    }
}
