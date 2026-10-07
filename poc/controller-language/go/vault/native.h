#ifndef EASYNET_VAULT_NATIVE_H
#define EASYNET_VAULT_NATIVE_H
#include <Security/Security.h>
#include <stdbool.h>
typedef struct Vault Vault;
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
void vault_release(Vault *vault);
#endif
