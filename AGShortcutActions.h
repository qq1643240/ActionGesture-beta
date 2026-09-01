#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const AGShortcutOff;
FOUNDATION_EXPORT NSString *const AGShortcutWeChatScan;
FOUNDATION_EXPORT NSString *const AGShortcutWeChatPay;
FOUNDATION_EXPORT NSString *const AGShortcutAlipayScan;
FOUNDATION_EXPORT NSString *const AGShortcutAlipayPay;

typedef void (^AGShortcutSelectionHandler)(NSString *shortcut);

/// Standalone shortcut module. It does not hook button events and does not
/// modify Apple's native Action Button implementation.
@interface AGShortcutActions : NSObject

+ (BOOL)isKnownShortcut:(nullable NSString *)shortcut;
+ (NSArray<NSString *> *)allShortcuts;
+ (NSString *)titleForShortcut:(NSString *)shortcut;
+ (NSString *)symbolForShortcut:(NSString *)shortcut;

/// assignmentIdentifier is the same stable key used for one gesture/action
/// assignment, for example "single" or "single.portrait".
+ (NSString *)shortcutForAssignmentIdentifier:(NSString *)assignmentIdentifier;
+ (void)saveShortcut:(NSString *)shortcut
 assignmentIdentifier:(NSString *)assignmentIdentifier;
+ (void)disableShortcutForAssignmentIdentifier:(NSString *)assignmentIdentifier;

/// iOS 17 may retain an old archive after the selected section is cleared.
/// Pass the section identifier from the already-resolved configuration for the
/// exact gesture/direction being executed. This module never reads SpringBoard
/// preferences and therefore cannot mix configurations between gestures.
+ (BOOL)isNoActionSectionIdentifier:(nullable NSString *)sectionIdentifier;

/// Returns a menu containing the five shortcut choices. When enabled is NO,
/// only the disabled "关闭" item is shown.
+ (UIMenu *)menuForAssignmentIdentifier:(NSString *)assignmentIdentifier
                                enabled:(BOOL)enabled
                      selectionHandler:(nullable AGShortcutSelectionHandler)handler;

/// Launches only the four explicit URL shortcuts. The caller should invoke
/// this only when nativeActionIsNoAction returns YES.
+ (BOOL)launchShortcut:(NSString *)shortcut;

@end

NS_ASSUME_NONNULL_END
