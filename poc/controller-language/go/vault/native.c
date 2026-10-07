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
static void probe_stage(int *stage, int value) {
    if (stage) *stage = value;
}
static OSStatus snapshot_read(Snapshot *snapshot, int *stage) {
    SecKeychainRef defaultKeychain = NULL;
    CFArrayRef search = NULL;
    probe_stage(stage, 10);
    OSStatus status = SecKeychainCopyDefault(&defaultKeychain);
    if (status != errSecSuccess) goto finish;
    probe_stage(stage, 11);
    status = path_copy(defaultKeychain, &snapshot->defaultPath);
    if (status != errSecSuccess) goto finish;
    probe_stage(stage, 12);
    status = SecKeychainCopySearchList(&search);
    if (status != errSecSuccess) goto finish;
    probe_stage(stage, 13);
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
    probe_stage(stage, 14);
    for (CFIndex i = 0; i < count; i++) {
        CFTypeRef item = CFArrayGetValueAtIndex(search, i);
        if (!item || CFGetTypeID(item) != SecKeychainGetTypeID()) {
            status = errSecInvalidKeychain;
            goto finish;
        }
        status = path_copy((SecKeychainRef)item, &snapshot->searchPaths[i]);
        if (status != errSecSuccess) goto finish;
    }
    probe_stage(stage, 15);
finish:
    if (defaultKeychain) CFRelease(defaultKeychain);
    if (search) CFRelease(search);
    if (status != errSecSuccess) snapshot_release(snapshot);
    return status;
}
static bool private_path(const char *path, int *stage) {
    probe_stage(stage, 0);
    if (!path || geteuid() == 0) return false;
    probe_stage(stage, 1);
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
    probe_stage(stage, 2);
    if (lstat(parent, &info) != 0 || !S_ISDIR(info.st_mode) ||
        info.st_uid != geteuid() || (info.st_mode & 07777) != 0700) return false;
    probe_stage(stage, 3);
    if (!realpath(parent, resolved)) return false;
    probe_stage(stage, 4);
    const char *canonicalPrefix = "/private/tmp/easynet-vault-lab-";
    if (strncmp(resolved, canonicalPrefix, strlen(canonicalPrefix)) != 0 ||
        strchr(resolved + strlen(canonicalPrefix), '/')) return false;
    probe_stage(stage, 5);
    return lstat(path, &info) == -1 && errno == ENOENT;
}
VaultProbe vault_probe(const char *path) {
    VaultProbe result = {false, 0, errSecParam};
    if (!private_path(path, &result.stage)) return result;
    result.path_guard_ok = true;
    Snapshot snapshot = {0};
    result.status = snapshot_read(&snapshot, &result.stage);
    snapshot_release(&snapshot);
    return result;
}
bool vault_has_keychain(Vault *vault) {
    return vault && vault->owned != NULL;
}
void vault_release(Vault *vault) {
    if (!vault) return;
    if (vault->owned) CFRelease(vault->owned);
    snapshot_release(&vault->baseline);
    free(vault);
}
OSStatus vault_unchanged(Vault *vault, bool *equal) {
    if (equal) *equal = false;
    if (!vault || !vault->owned || !equal) {
        if (vault) vault->ready = false;
        return errSecParam;
    }
    Snapshot current = {0};
    OSStatus status = snapshot_read(&current, NULL);
    if (status != errSecSuccess) { vault->ready = false; return status; }
    bool same = vault->baseline.count == current.count &&
        strcmp(vault->baseline.defaultPath, current.defaultPath) == 0;
    for (CFIndex i = 0; same && i < current.count; i++) {
        same = strcmp(vault->baseline.searchPaths[i], current.searchPaths[i]) == 0;
    }
    snapshot_release(&current);
    *equal = same;
    if (!same) vault->ready = false;
    return errSecSuccess;
}
OSStatus vault_create(const char *path, const void *password, UInt32 length,
                      Vault **out, bool *metadataUnchanged) {
    if (!out || !metadataUnchanged) return errSecParam;
    *out = NULL;
    *metadataUnchanged = false;
    if (!private_path(path, NULL) || !password || length == 0) return errSecParam;
    Vault *vault = calloc(1, sizeof(*vault));
    if (!vault) return errSecAllocate;
    OSStatus status = snapshot_read(&vault->baseline, NULL);
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

static OSStatus vault_guard(Vault *vault) {
    return vault && vault->owned && vault->ready ? errSecSuccess : errSecNotAvailable;
}
OSStatus vault_unlock(Vault *vault, const void *password, UInt32 length) {
    OSStatus status = vault_guard(vault);
    if (status != errSecSuccess) return status;
    if (!password || !length) return errSecParam;
    return SecKeychainUnlock(vault->owned, length, password, true);
}
OSStatus vault_is_unlocked(Vault *vault, bool *unlocked) {
    if (unlocked) *unlocked = false;
    if (!unlocked) return errSecParam;
    OSStatus status = vault_guard(vault);
    if (status != errSecSuccess) return status;
    SecKeychainStatus state = 0;
    status = SecKeychainGetStatus(vault->owned, &state);
    if (status == errSecSuccess) *unlocked = (state & kSecUnlockStateStatus) != 0;
    return status;
}
static CFMutableDictionaryRef item_query(Vault *vault, bool adding) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!query) return NULL;
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, CFSTR("easynet.fixture.vault"));
    CFDictionarySetValue(query, kSecAttrAccount, CFSTR("synthetic"));
    CFDictionarySetValue(query, kSecUseAuthenticationUI, kSecUseAuthenticationUIFail);
    if (adding) {
        CFDictionarySetValue(query, kSecUseKeychain, vault->owned);
    } else {
        const void *owned = vault->owned;
        CFArrayRef search = CFArrayCreate(NULL, &owned, 1, &kCFTypeArrayCallBacks);
        if (!search) { CFRelease(query); return NULL; }
        CFDictionarySetValue(query, kSecMatchSearchList, search);
        CFRelease(search);
    }
    return query;
}
static OSStatus item_write(Vault *vault, const void *bytes, UInt32 length, bool update) {
    OSStatus status = vault_guard(vault);
    if (status != errSecSuccess) return status;
    if (!bytes) return errSecParam;
    CFDataRef data = CFDataCreate(NULL, bytes, length);
    if (!data) return errSecAllocate;
    CFMutableDictionaryRef query = item_query(vault, !update);
    if (!query) { CFRelease(data); return errSecAllocate; }
    if (update) {
        const void *keys[] = {kSecValueData};
        const void *values[] = {data};
        CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (!attributes) status = errSecAllocate;
        else { status = SecItemUpdate(query, attributes); CFRelease(attributes); }
    } else {
        CFDictionarySetValue(query, kSecValueData, data);
        status = SecItemAdd(query, NULL);
    }
    CFRelease(query);
    CFRelease(data);
    return status;
}
OSStatus vault_add(Vault *vault, const void *bytes, UInt32 length) {
    return item_write(vault, bytes, length, false);
}
OSStatus vault_update(Vault *vault, const void *bytes, UInt32 length) {
    return item_write(vault, bytes, length, true);
}
OSStatus vault_read_equals(Vault *vault, const void *bytes, UInt32 length,
                          bool *equal, bool *dataReturned) {
    if (equal) *equal = false;
    if (dataReturned) *dataReturned = false;
    if (!bytes || !equal || !dataReturned) return errSecParam;
    OSStatus status = vault_guard(vault);
    if (status != errSecSuccess) return status;
    CFMutableDictionaryRef query = item_query(vault, false);
    if (!query) return errSecAllocate;
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne);
    CFTypeRef returned = NULL;
    status = SecItemCopyMatching(query, &returned);
    CFRelease(query);
    *dataReturned = returned != NULL;
    if (status == errSecSuccess) {
        if (!returned || CFGetTypeID(returned) != CFDataGetTypeID()) status = errSecDecode;
        else {
            CFDataRef data = (CFDataRef)returned;
            CFIndex count = CFDataGetLength(data);
            const UInt8 *contents = CFDataGetBytePtr(data);
            if (count < 0 || (count && !contents)) status = errSecDecode;
            else *equal = count == length && (length == 0 || memcmp(contents, bytes, length) == 0);
        }
    }
    if (returned) CFRelease(returned);
    return status;
}
OSStatus vault_delete(Vault *vault) {
    OSStatus status = vault_guard(vault);
    if (status != errSecSuccess) return status;
    CFMutableDictionaryRef query = item_query(vault, false);
    if (!query) return errSecAllocate;
    status = SecItemDelete(query);
    CFRelease(query);
    return status;
}

OSStatus vault_lock(Vault *vault) {
    OSStatus status = vault_guard(vault);
    if (status != errSecSuccess) return status;
    return SecKeychainLock(vault->owned);
}
OSStatus vault_read_status(Vault *vault, bool *dataReturned, bool *queried) {
    if (dataReturned) *dataReturned = false;
    if (queried) *queried = false;
    if (!dataReturned || !queried) return errSecParam;
    OSStatus status = vault_guard(vault);
    if (status != errSecSuccess) return status;
    CFMutableDictionaryRef query = item_query(vault, false);
    if (!query) return errSecAllocate;
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne);
    CFTypeRef returned = NULL;
    *queried = true;
    status = SecItemCopyMatching(query, &returned);
    CFRelease(query);
    *dataReturned = returned != NULL;
    if (returned) CFRelease(returned);
    return status;
}
