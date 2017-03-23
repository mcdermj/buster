#import "MASShortcutValidator.h"

@implementation MASShortcutValidator

+ (instancetype) sharedValidator
{
    static dispatch_once_t once;
    static MASShortcutValidator *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (BOOL) isShortcutValid: (MASShortcut*) shortcut
{
    NSUInteger modifiers = [shortcut modifierFlags];
    
    if(modifiers != 0)
        return NO;
    
    return YES;
}

- (BOOL) isShortcut: (MASShortcut*) shortcut alreadyTakenInMenu: (NSMenu*) menu explanation: (NSString**) explanation
{
    NSString *keyEquivalent = [shortcut keyCodeStringForKeyEquivalent];
    NSUInteger flags = [shortcut modifierFlags];

    for (NSMenuItem *menuItem in menu.itemArray) {
        if (menuItem.hasSubmenu && [self isShortcut:shortcut alreadyTakenInMenu:[menuItem submenu] explanation:explanation]) return YES;
        
        BOOL equalFlags = (MASPickCocoaModifiers(menuItem.keyEquivalentModifierMask) == flags);
        BOOL equalHotkeyLowercase = [menuItem.keyEquivalent.lowercaseString isEqualToString:keyEquivalent];
        
        // Check if the cases are different, we know ours is lower and that shift is included in our modifiers
        // If theirs is capitol, we need to add shift to their modifiers
        if (equalHotkeyLowercase && ![menuItem.keyEquivalent isEqualToString:keyEquivalent]) {
            equalFlags = (MASPickCocoaModifiers(menuItem.keyEquivalentModifierMask | NSEventModifierFlagShift) == flags);
        }
        
        if (equalFlags && equalHotkeyLowercase) {
            if (explanation) {
                *explanation = NSLocalizedString(@"This shortcut cannot be used because it is already used by the menu item ‘%@’.",
                                                     @"Message for alert when shortcut is already used");
                *explanation = [NSString stringWithFormat:*explanation, menuItem.title];
            }
            return YES;
        }
    }
    return NO;
}

- (BOOL) isShortcutAlreadyTakenBySystem: (MASShortcut*) shortcut explanation: (NSString**) explanation
{
    CFArrayRef globalHotKeys;
    if (CopySymbolicHotKeys(&globalHotKeys) == noErr) {

        // Enumerate all global hotkeys and check if any of them matches current shortcut
        for (CFIndex i = 0, count = CFArrayGetCount(globalHotKeys); i < count; i++) {
            CFDictionaryRef hotKeyInfo = CFArrayGetValueAtIndex(globalHotKeys, i);
            CFNumberRef code = CFDictionaryGetValue(hotKeyInfo, kHISymbolicHotKeyCode);
            CFNumberRef flags = CFDictionaryGetValue(hotKeyInfo, kHISymbolicHotKeyModifiers);
            CFNumberRef enabled = CFDictionaryGetValue(hotKeyInfo, kHISymbolicHotKeyEnabled);

            if (([(__bridge NSNumber *)code unsignedIntegerValue] == [shortcut keyCode]) &&
                ([(__bridge NSNumber *)flags unsignedIntegerValue] == [shortcut carbonFlags]) &&
                ([(__bridge NSNumber *)enabled boolValue])) {

                if (explanation) {
                    *explanation = NSLocalizedString(@"This combination cannot be used because it is already used by a system-wide "
                                                     @"keyboard shortcut.\nIf you really want to use this key combination, most shortcuts "
                                                     @"can be changed in the Keyboard & Mouse panel in System Preferences.",
                                                     @"Message for alert when shortcut is already used by the system");
                }
                return YES;
            }
        }
        CFRelease(globalHotKeys);
    }
    return [self isShortcut:shortcut alreadyTakenInMenu:[NSApp mainMenu] explanation:explanation];
}

@end
