#ifndef EASYNET_VAULT_NATIVE_H
#define EASYNET_VAULT_NATIVE_H
#include <Security/Security.h>
#include <stdbool.h>
typedef struct Vault Vault;
typedef struct {
    bool path_guard_ok;
    int stage;
    OSStatus status;
} VaultProbe;
VaultProbe vault_probe(const char *path);
bool vault_has_keychain(Vault *vault);
OSStatus vault_create(const char *path, const void *password, UInt32 length,
                      Vault **out, bool *metadataUnchanged);
OSStatus vault_unchanged(Vault *vault, bool *equal);
OSStatus vault_unlock(Vault *vault, const void *password, UInt32 length);
OSStatus vault_is_unlocked(Vault *vault, bool *unlocked);
OSStatus vault_add(Vault *vault, const void *bytes, UInt32 length);
OSStatus vault_update(Vault *vault, const void *bytes, UInt32 length);
OSStatus vault_read_equals(Vault *vault, const void *bytes, UInt32 length,
                          bool *equal, bool *dataReturned);
OSStatus vault_delete(Vault *vault);
OSStatus vault_lock(Vault *vault);
OSStatus vault_read_status(Vault *vault, bool *dataReturned, bool *queried);
void vault_release(Vault *vault);
#endif
