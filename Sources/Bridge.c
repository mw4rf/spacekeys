// Adapted from gechr/WhichSpace (MIT), copyright (c) 2015 George Christou.
// Only the bridged backend is retained; compatibility IDs are never modified.
//
//  WindowSpaceMove.c
//  WhichSpace
//
//  Compiled as C, so the manual retain/release around the bridged operation is
//  explicit rather than fighting ARC over a cast objc_msgSend result.
//

#include "Bridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <string.h>

#define SKYLIGHT_IMAGE_SUFFIX "/SkyLight"
#define BRIDGED_OPERATION_SYMBOL \
    "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation"
#define BRIDGED_OPERATION_CLASS "SLSBridgedMoveWindowsToManagedSpaceOperation"
#define BRIDGED_OPERATION_INIT "initWithWindows:spaceID:"

typedef int64_t (*BridgedOperationFunc)(void *);

static BridgedOperationFunc gPerformBridgedOperation;
static Class gBridgedOperationClass;

#pragma mark - Symbol Lookup

static bool string_has_suffix(const char *string, const char *suffix)
{
    size_t stringLength = strlen(string);
    size_t suffixLength = strlen(suffix);
    if (suffixLength > stringLength) {
        return false;
    }
    return strcmp(string + (stringLength - suffixLength), suffix) == 0;
}

// Applies a dyld slide, which is signed: an image can load below its preferred
// address. Reports whether the result is representable rather than wrapping.
static bool apply_slide(uintptr_t value, intptr_t slide, uintptr_t *result)
{
    if (slide >= 0) {
        return !__builtin_add_overflow(value, (uintptr_t)slide, result);
    }
    // Taken without negating slide directly, so INTPTR_MIN is handled
    uintptr_t magnitude = (uintptr_t)(-(slide + 1)) + 1;
    if (magnitude > value) {
        return false;
    }
    *result = value - magnitude;
    return true;
}

static const struct mach_header_64 *find_image_header(const char *suffix, intptr_t *slide)
{
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (name == NULL || !string_has_suffix(name, suffix)) {
            continue;
        }
        const struct mach_header *header = _dyld_get_image_header(i);
        if (header == NULL || header->magic != MH_MAGIC_64) {
            continue;
        }
        *slide = _dyld_get_image_vmaddr_slide(i);
        return (const struct mach_header_64 *)header;
    }
    return NULL;
}

// Resolves a symbol that dlsym cannot see by walking the image's symbol table.
// The bridged entry point has internal linkage, so it is only reachable this
// way. Every computed address is range-checked against __LINKEDIT first: a
// layout change must yield NULL rather than a fault.
static void *find_local_symbol(const char *imageSuffix, const char *symbolName)
{
    intptr_t slide = 0;
    const struct mach_header_64 *header = find_image_header(imageSuffix, &slide);
    if (header == NULL) {
        return NULL;
    }

    // Load commands are only read within the region the header declares, and
    // each one has to be large enough for the struct it is cast to
    const struct segment_command_64 *linkedit = NULL;
    const struct symtab_command *symtab = NULL;
    uint32_t offset = 0;
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        // Compared before subtracting, so a short declared region cannot wrap
        if (header->sizeofcmds < sizeof(struct load_command) ||
            offset > header->sizeofcmds - sizeof(struct load_command)) {
            return NULL;
        }
        const struct load_command *command =
            (const struct load_command *)((uintptr_t)header + sizeof(struct mach_header_64) + offset);
        if (command->cmdsize < sizeof(struct load_command) ||
            command->cmdsize > header->sizeofcmds - offset) {
            return NULL;
        }
        if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) {
                linkedit = segment;
            }
        } else if (command->cmd == LC_SYMTAB && command->cmdsize >= sizeof(struct symtab_command)) {
            symtab = (const struct symtab_command *)command;
        }
        offset += command->cmdsize;
    }

    if (linkedit == NULL || symtab == NULL || symtab->nsyms == 0 || symtab->strsize == 0) {
        return NULL;
    }

    // Every address below is derived by addition that could wrap on a
    // malformed image, so each step is checked before it is taken
    uintptr_t linkeditStart = 0;
    if (!apply_slide((uintptr_t)linkedit->vmaddr, slide, &linkeditStart)) {
        return NULL;
    }
    uintptr_t linkeditEnd = 0;
    if (__builtin_add_overflow(linkeditStart, (uintptr_t)linkedit->vmsize, &linkeditEnd)) {
        return NULL;
    }
    if (linkeditStart < (uintptr_t)linkedit->fileoff) {
        return NULL;
    }
    uintptr_t base = linkeditStart - (uintptr_t)linkedit->fileoff;

    uintptr_t symbolTable = 0;
    uintptr_t symbolTableEnd = 0;
    uintptr_t stringTable = 0;
    uintptr_t stringTableEnd = 0;
    if (__builtin_add_overflow(base, (uintptr_t)symtab->symoff, &symbolTable) ||
        __builtin_add_overflow(symbolTable, (uintptr_t)symtab->nsyms * sizeof(struct nlist_64), &symbolTableEnd) ||
        __builtin_add_overflow(base, (uintptr_t)symtab->stroff, &stringTable) ||
        __builtin_add_overflow(stringTable, (uintptr_t)symtab->strsize, &stringTableEnd)) {
        return NULL;
    }
    if (symbolTable < linkeditStart || symbolTableEnd > linkeditEnd) {
        return NULL;
    }
    if (stringTable < linkeditStart || stringTableEnd > linkeditEnd) {
        return NULL;
    }

    size_t symbolLength = strlen(symbolName);
    for (uint32_t i = 0; i < symtab->nsyms; ++i) {
        const struct nlist_64 *entry = (const struct nlist_64 *)(symbolTable + i * sizeof(struct nlist_64));
        if (entry->n_un.n_strx == 0 || entry->n_un.n_strx >= symtab->strsize || entry->n_value == 0) {
            continue;
        }
        // The name has to be NUL-terminated inside the string table, otherwise
        // a truncated entry at the very end would match on its prefix alone
        uint32_t available = symtab->strsize - entry->n_un.n_strx;
        if (available <= symbolLength) {
            continue;
        }
        const char *name = (const char *)(stringTable + entry->n_un.n_strx);
        if (memchr(name, '\0', available) == NULL) {
            continue;
        }
        if (strcmp(name, symbolName) == 0) {
            uintptr_t address = 0;
            if (!apply_slide((uintptr_t)entry->n_value, slide, &address)) {
                return NULL;
            }
            return (void *)address;
        }
    }

    return NULL;
}

#pragma mark - Availability

bool WSMoveBridgedIsAvailable(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // dlsym first in case a future release exports it.
        void *symbol = dlsym(RTLD_DEFAULT, BRIDGED_OPERATION_SYMBOL);
        if (symbol == NULL) {
            symbol = find_local_symbol(SKYLIGHT_IMAGE_SUFFIX, BRIDGED_OPERATION_SYMBOL);
        }
        Class class = objc_getClass(BRIDGED_OPERATION_CLASS);
        // A renamed initializer must degrade rather than crash on dispatch.
        if (symbol != NULL && class != NULL &&
            class_getInstanceMethod(class, sel_getUid(BRIDGED_OPERATION_INIT)) != NULL) {
            gPerformBridgedOperation = (BridgedOperationFunc)symbol;
            gBridgedOperationClass = class;
        }
    });
    return gPerformBridgedOperation != NULL && gBridgedOperationClass != NULL;
}

static CFArrayRef create_window_list(uint32_t windowID)
{
    int32_t value = (int32_t)windowID;
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &value);
    if (number == NULL) {
        return NULL;
    }
    const void *values[] = { number };
    CFArrayRef list = CFArrayCreate(kCFAllocatorDefault, values, 1, &kCFTypeArrayCallBacks);
    CFRelease(number);
    return list;
}

bool WSMoveBridged(uint32_t windowID, uint64_t spaceID)
{
    if (!WSMoveBridgedIsAvailable()) {
        return false;
    }

    CFArrayRef windowList = create_window_list(windowID);
    if (windowList == NULL) {
        return false;
    }

    id allocated = ((id (*)(Class, SEL))objc_msgSend)(gBridgedOperationClass, sel_getUid("alloc"));
    if (allocated == NULL) {
        CFRelease(windowList);
        return false;
    }

    id operation = ((id (*)(id, SEL, CFArrayRef, uint64_t))objc_msgSend)(
        allocated, sel_getUid(BRIDGED_OPERATION_INIT), windowList, spaceID
    );
    // A failing initializer has already released the receiver, so the
    // allocation must not be released again here
    if (operation == NULL) {
        CFRelease(windowList);
        return false;
    }

    gPerformBridgedOperation((void *)operation);
    ((void (*)(id, SEL))objc_msgSend)(operation, sel_getUid("release"));
    CFRelease(windowList);
    return true;
}


static int connection_id(void) {
    typedef int (*Fn)(void);
    Fn f = (Fn)dlsym(RTLD_DEFAULT, "SLSMainConnectionID");
    return f ? f() : 0;
}
CFArrayRef SKCopyDisplays(void) {
    typedef CFArrayRef (*Fn)(int);
    Fn f = (Fn)dlsym(RTLD_DEFAULT, "SLSCopyManagedDisplaySpaces");
    return f ? f(connection_id()) : NULL;
}
CFArrayRef SKCopyWindowSpaces(uint32_t window) {
    typedef CFArrayRef (*Fn)(int, int, CFArrayRef);
    Fn f = (Fn)dlsym(RTLD_DEFAULT, "SLSCopySpacesForWindows");
    CFArrayRef list = create_window_list(window);
    if (!f || !list) { if (list) CFRelease(list); return NULL; }
    CFArrayRef result = f(connection_id(), 7, list);
    CFRelease(list);
    return result;
}
AXError SKGetWindowID(AXUIElementRef window, uint32_t *result) {
    typedef AXError (*Fn)(AXUIElementRef, uint32_t *);
    Fn f = (Fn)dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    return f ? f(window, result) : kAXErrorNotImplemented;
}
