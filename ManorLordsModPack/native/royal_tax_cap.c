/* Runtime patch for Manor Lords build 26185246, x64. No game files are edited. */
typedef unsigned char Byte;
typedef unsigned int Dword;
typedef unsigned long long U64;
typedef void *Ptr;
#define DLLIMPORT __declspec(dllimport)
DLLIMPORT Ptr GetModuleHandleW(const unsigned short *);
DLLIMPORT Ptr GetCurrentProcess(void);
DLLIMPORT Ptr VirtualAlloc(Ptr, U64, Dword, Dword);
DLLIMPORT int VirtualFree(Ptr, U64, Dword);
DLLIMPORT int VirtualProtect(Ptr, U64, Dword, Dword *);
DLLIMPORT int FlushInstructionCache(Ptr, const void *, U64);

static const Byte calculation[] = {
    0x48,0x8d,0x15,0xa7,0x88,0x41,0x03, 0x48,0x8d,0x4c,0x24,0x40,
    0x44,0x8b,0x80,0x90,0,0,0, 0x44,0x0f,0xaf,0x07, 0x45,0x89,0x07
};
static const Byte payment[] = {
    0x8b,0x96,0x90,0x10,0,0, 0x48,0x8b,0xce, 0xf7,0xda, 0xe8,0xa2,0x4e,0xe7,0xff
};
/* Compare r8d with 500, replace only if larger, then store the tax at [r15]. */
static const Byte clamp[] = {
    0x41,0x81,0xf8,0xf4,0x01,0,0, 0x7e,0x06, 0x41,0xb8,0xf4,0x01,0,0,
    0x45,0x89,0x07
};
static int applied;

static int matches(const Byte *a, const Byte *b, U64 size) {
    for (U64 i = 0; i < size; ++i) if (a[i] != b[i]) return 0;
    return 1;
}
static void copy(Byte *out, const Byte *in, U64 size) {
    for (U64 i = 0; i < size; ++i) out[i] = in[i];
}
static void writeAddress(Byte *out, const void *address) {
    U64 value = (U64)address;
    for (int i = 0; i < 8; ++i) out[i] = (Byte)(value >> (8 * i));
}
static void jumpTo(Byte *out, const void *address) {
    const Byte jump[] = {0xff,0x25,0,0,0,0};
    copy(out, jump, sizeof jump);
    writeAddress(out + sizeof jump, address);
}

/* Called as ApplyRoyalTaxCap(true). Return the supplied true only on success. */
__declspec(dllexport) int ApplyRoyalTaxCap(void *luaState) {
    (void)luaState;
    if (applied) return 1;
    Byte *base = GetModuleHandleW(0);
    const Byte imageTimestamp[] = {0xba,0xc1,0x36,0x68};
    const Byte imageSize[] = {0,0xd0,0xdf,0x09};
    if (!base || !matches(base + 0x218, imageTimestamp, sizeof imageTimestamp)
        || !matches(base + 0x260, imageSize, sizeof imageSize)) return 0;

    Byte *site = base + 0x4b5fad2;
    if (!matches(site, calculation, sizeof calculation)
        || !matches(base + 0x4cbf4ee, payment, sizeof payment)) return 0;

    Byte *stub = VirtualAlloc(0, 64, 0x3000, 0x04);
    if (!stub) return 0;
    /* Replay the overwritten instructions, replacing the RIP-relative lea. */
    stub[0] = 0x48;
    stub[1] = 0xba; /* mov rdx, address */
    writeAddress(stub + 2, base + 0x7f78380);
    copy(stub + 10, calculation + 7, 16);
    copy(stub + 26, clamp, sizeof clamp);
    jumpTo(stub + 26 + sizeof clamp, site + sizeof calculation);

    Dword oldProtection, ignored;
    if (!VirtualProtect(stub, 64, 0x20, &oldProtection)
        || !FlushInstructionCache(GetCurrentProcess(), stub, 64)
        || !VirtualProtect(site, sizeof calculation, 0x40, &oldProtection)) {
        VirtualFree(stub, 0, 0x8000);
        return 0;
    }
    jumpTo(site, stub);
    for (U64 i = 14; i < sizeof calculation; ++i) site[i] = 0x90;
    FlushInstructionCache(GetCurrentProcess(), site, sizeof calculation);
    VirtualProtect(site, sizeof calculation, oldProtection, &ignored);
    applied = 1;
    return 1;
}
