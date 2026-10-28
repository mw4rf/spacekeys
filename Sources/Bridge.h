#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <ApplicationServices/ApplicationServices.h>
bool WSMoveBridgedIsAvailable(void);
bool WSMoveBridged(uint32_t windowID, uint64_t spaceID);
CFArrayRef _Nullable SKCopyDisplays(void) CF_RETURNS_RETAINED;
CFArrayRef _Nullable SKCopyWindowSpaces(uint32_t window) CF_RETURNS_RETAINED;
AXError SKGetWindowID(AXUIElementRef _Nonnull window, uint32_t * _Nonnull result);
