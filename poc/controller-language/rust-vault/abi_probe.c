#include "../go/vault/native.h"
#include <stddef.h>
#include <stdint.h>

_Static_assert(sizeof(OSStatus) == 4, "OSStatus must be 32 bits");
_Static_assert((OSStatus)-1 < 0, "OSStatus must be signed");
_Static_assert(sizeof(UInt32) == 4, "UInt32 must be 32 bits");
_Static_assert((UInt32)-1 > 0, "UInt32 must be unsigned");

uint64_t abi_value(uint32_t index) {
    static const uint64_t values[] = {
        sizeof(bool), _Alignof(bool), sizeof(OSStatus), _Alignof(OSStatus),
        (OSStatus)-1 < 0, sizeof(UInt32), _Alignof(UInt32), (UInt32)-1 > 0,
        sizeof(VaultProbe), _Alignof(VaultProbe),
        offsetof(VaultProbe, path_guard_ok), offsetof(VaultProbe, stage),
        offsetof(VaultProbe, status),
    };
    return index < sizeof(values) / sizeof(values[0]) ? values[index] : UINT64_MAX;
}

bool abi_echo_bool(bool value) { return value; }
void abi_flip_bool(bool *value) { if (value) *value = !*value; }
VaultProbe abi_return_probe(void) { return (VaultProbe){true, 42, (OSStatus)-50}; }
OSStatus abi_echo_status(OSStatus value) { return value; }
UInt32 abi_echo_u32(UInt32 value) { return value; }
