#include "native.h"
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
    char *defaultPath;
    char **searchPaths;
    CFIndex count;
} Snapshot;
struct Vault {
    SecKeychainRef owned;
    Snapshot baseline;
    bool ready;
};
static void snapshot_release(Snapshot *snapshot) {
    free(snapshot->defaultPath);
    for (CFIndex i = 0; i < snapshot->count; i++) free(snapshot->searchPaths[i]);
    free(snapshot->searchPaths);
    memset(snapshot, 0, sizeof(*snapshot));
}
static OSStatus path_copy(SecKeychainRef keychain, char **out) {
    char path[PATH_MAX + 1];
    UInt32 length = PATH_MAX;
    if (!keychain) return errSecInvalidKeychain;
    OSStatus status = SecKeychainGetPath(keychain, &length, path);
    if (status != errSecSuccess) return status;
    if (length > PATH_MAX) return errSecParam;
    path[length] = '\0';
    *out = malloc((size_t)length + 1);
    if (!*out) return errSecAllocate;
    memcpy(*out, path, (size_t)length + 1);
    return errSecSuccess;
}
static OSStatus snapshot_read(Snapshot *snapshot) {
    SecKeychainRef defaultKeychain = NULL;
    CFArrayRef search = NULL;
    OSStatus status = SecKeychainCopyDefault(&defaultKeychain);
    if (status != errSecSuccess) goto finish;
    status = path_copy(defaultKeychain, &snapshot->defaultPath);
    if (status != errSecSuccess) goto finish;
    status = SecKeychainCopySearchList(&search);
    if (status != errSecSuccess) goto finish;
    if (!search || CFGetTypeID(search) != CFArrayGetTypeID()) {
        status = errSecParam;
        goto finish;
    }
    CFIndex count = CFArrayGetCount(search);
    if (count < 0 || (size_t)count > SIZE_MAX / sizeof(char *)) {
        status = errSecAllocate;
        goto finish;
    }
    if (count) {
        snapshot->searchPaths = calloc((size_t)count, sizeof(char *));
        if (!snapshot->searchPaths) { status = errSecAllocate; goto finish; }
    }
    snapshot->count = count;
    for (CFIndex i = 0; i < count; i++) {
        CFTypeRef item = CFArrayGetValueAtIndex(search, i);
        if (!item || CFGetTypeID(item) != SecKeychainGetTypeID()) {
            status = errSecInvalidKeychain;
            goto finish;
        }
        status = path_copy((SecKeychainRef)item, &snapshot->searchPaths[i]);
        if (status != errSecSuccess) goto finish;
    }
finish:
    if (defaultKeychain) CFRelease(defaultKeychain);
    if (search) CFRelease(search);
    if (status != errSecSuccess) snapshot_release(snapshot);
    return status;
}
static bool private_path(const char *path) {
    if (!path || geteuid() == 0) return false;
    const char *prefix = "/tmp/easynet-vault-lab-";
    if (strncmp(path, prefix, strlen(prefix)) != 0) {
        prefix = "/private/tmp/easynet-vault-lab-";
        if (strncmp(path, prefix, strlen(prefix)) != 0) return false;
    }
    const char *slash = strrchr(path, '/');
    if (!slash || strcmp(slash + 1, "fixture.keychain") != 0) return false;
    const char *suffix = path + strlen(prefix);
    if (suffix >= slash) return false;
    for (const char *p = suffix; p < slash; p++) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') || *p == '-' || *p == '_')) return false;
    }
    size_t parentLength = (size_t)(slash - path);
    if (parentLength > PATH_MAX) return false;
    char parent[PATH_MAX + 1], resolved[PATH_MAX + 1];
    memcpy(parent, path, parentLength);
    parent[parentLength] = '\0';
    struct stat info;
    if (lstat(parent, &info) != 0 || !S_ISDIR(info.st_mode) ||
        info.st_uid != geteuid() || (info.st_mode & 07777) != 0700) return false;
    if (!realpath(parent, resolved)) return false;
    const char *canonicalPrefix = "/private/tmp/easynet-vault-lab-";
    if (strncmp(resolved, canonicalPrefix, strlen(canonicalPrefix)) != 0 ||
        strchr(resolved + strlen(canonicalPrefix), '/')) return false;
    return lstat(path, &info) == -1 && errno == ENOENT;
}
void vault_release(Vault *vault) {
    if (!vault) return;
    if (vault->owned) CFRelease(vault->owned);
    snapshot_release(&vault->baseline);
    free(vault);
}
OSStatus vault_unchanged(Vault *vault, bool *equal) {
    if (!vault || !vault->owned || !equal) return errSecParam;
    *equal = false;
    Snapshot current = {0};
    OSStatus status = snapshot_read(&current);
    if (status != errSecSuccess) return status;
    bool same = vault->baseline.count == current.count &&
        strcmp(vault->baseline.defaultPath, current.defaultPath) == 0;
    for (CFIndex i = 0; same && i < current.count; i++) {
        same = strcmp(vault->baseline.searchPaths[i], current.searchPaths[i]) == 0;
    }
    snapshot_release(&current);
    *equal = same;
    return errSecSuccess;
}
OSStatus vault_create(const char *path, const void *password, UInt32 length,
                      Vault **out, bool *metadataUnchanged) {
    if (!out || !metadataUnchanged) return errSecParam;
    *out = NULL;
    *metadataUnchanged = false;
    if (!private_path(path) || !password || length == 0) return errSecParam;
    Vault *vault = calloc(1, sizeof(*vault));
    if (!vault) return errSecAllocate;
    OSStatus status = snapshot_read(&vault->baseline);
    if (status != errSecSuccess) { vault_release(vault); return status; }
    status = SecKeychainSetUserInteractionAllowed(false);
    if (status != errSecSuccess) { vault_release(vault); return status; }
    *out = vault;
    status = SecKeychainCreate(path, length, password, false, NULL, &vault->owned);
    if (status != errSecSuccess) return status;
    if (!vault->owned) return errSecInvalidKeychain;
    status = vault_unchanged(vault, metadataUnchanged);
    if (status != errSecSuccess) return status;
    vault->ready = *metadataUnchanged;
    return vault->ready ? errSecSuccess : errSecNotAvailable;
}
