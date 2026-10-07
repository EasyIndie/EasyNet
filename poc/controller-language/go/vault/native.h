#ifndef EASYNET_VAULT_NATIVE_H
#define EASYNET_VAULT_NATIVE_H
#include <Security/Security.h>
#include <stdbool.h>
typedef struct Vault Vault;
OSStatus vault_create(const char *path, const void *password, UInt32 length,
                      Vault **out, bool *metadataUnchanged);
OSStatus vault_unchanged(Vault *vault, bool *equal);
void vault_release(Vault *vault);
#endif
