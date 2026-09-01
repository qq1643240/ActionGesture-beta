#import "AGShortcutActions.h"
#import <objc/runtime.h>

NSString *const AGShortcutOff = @"off";
NSString *const AGShortcutWeChatScan = @"wechat.scan";
NSString *const AGShortcutWeChatPay = @"wechat.pay";
NSString *const AGShortcutAlipayScan = @"alipay.scan";
NSString *const AGShortcutAlipayPay = @"alipay.pay";

static NSString *const AGShortcutPreferencesDomain = @"com.huami.actiongesture";
static NSString *const AGShortcutStoragePrefix = @"shortcut.assignment.";

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openURL:(NSURL *)url;
@end

@implementation AGShortcutActions

+ (NSArray<NSString *> *)allShortcuts {
    return @[AGShortcutOff, AGShortcutWeChatScan, AGShortcutWeChatPay,
             AGShortcutAlipayScan, AGShortcutAlipayPay];
}

+ (BOOL)isKnownShortcut:(NSString *)shortcut {
    return [shortcut isKindOfClass:NSString.class] &&
        [[self allShortcuts] containsObject:shortcut];
}

+ (NSString *)storageKeyForAssignmentIdentifier:(NSString *)identifier {
    return [AGShortcutStoragePrefix stringByAppendingString:identifier ?: @""];
}

+ (NSString *)shortcutForAssignmentIdentifier:(NSString *)identifier {
    if (!identifier.length) return AGShortcutOff;
    CFPreferencesAppSynchronize((__bridge CFStringRef)AGShortcutPreferencesDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)[self storageKeyForAssignmentIdentifier:identifier],
        (__bridge CFStringRef)AGShortcutPreferencesDomain));
    return [self isKnownShortcut:value] ? value : AGShortcutOff;
}

+ (void)saveShortcut:(NSString *)shortcut
 assignmentIdentifier:(NSString *)identifier {
    if (!identifier.length || ![self isKnownShortcut:shortcut]) return;
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)[self storageKeyForAssignmentIdentifier:identifier],
        (__bridge CFPropertyListRef)shortcut,
        (__bridge CFStringRef)AGShortcutPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)AGShortcutPreferencesDomain);
}

+ (void)disableShortcutForAssignmentIdentifier:(NSString *)identifier {
    [self saveShortcut:AGShortcutOff assignmentIdentifier:identifier];
}

+ (NSString *)titleForShortcut:(NSString *)shortcut {
    NSDictionary *titles = @{
        AGShortcutOff: @"关闭",
        AGShortcutWeChatScan: @"微信扫码",
        AGShortcutWeChatPay: @"微信付款",
        AGShortcutAlipayScan: @"支付宝扫一扫",
        AGShortcutAlipayPay: @"支付宝付款码"
    };
    return titles[shortcut] ?: titles[AGShortcutOff];
}

+ (NSString *)symbolForShortcut:(NSString *)shortcut {
    if ([shortcut hasSuffix:@"scan"]) return @"qrcode.viewfinder";
    if ([shortcut hasSuffix:@"pay"]) return @"creditcard";
    return @"bolt.slash";
}

+ (BOOL)isNoActionSectionIdentifier:(NSString *)sectionIdentifier {
    if (![sectionIdentifier isKindOfClass:NSString.class] || !sectionIdentifier.length) {
        return YES;
    }
    NSString *identifier = sectionIdentifier.lowercaseString;
    return [identifier containsString:@"none"] ||
           [identifier containsString:@"noaction"] ||
           [identifier containsString:@"no_action"] ||
           [identifier containsString:@"noop"] ||
           [identifier containsString:@"disabled"];
}

+ (UIMenu *)menuForAssignmentIdentifier:(NSString *)identifier
                                enabled:(BOOL)enabled
                      selectionHandler:(AGShortcutSelectionHandler)handler {
    if (!enabled) {
        UIAction *off = [UIAction actionWithTitle:[self titleForShortcut:AGShortcutOff]
                                             image:[UIImage systemImageNamed:[self symbolForShortcut:AGShortcutOff]]
                                        identifier:nil
                                           handler:^(__unused UIAction *action) {}];
        off.state = UIMenuElementStateOn;
        off.attributes = UIMenuElementAttributesDisabled;
        return [UIMenu menuWithTitle:@"快捷动作" children:@[off]];
    }

    NSString *selected = [self shortcutForAssignmentIdentifier:identifier];
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    for (NSString *shortcut in [self allShortcuts]) {
        UIAction *item = [UIAction actionWithTitle:[self titleForShortcut:shortcut]
                                             image:[UIImage systemImageNamed:[self symbolForShortcut:shortcut]]
                                        identifier:nil
                                           handler:^(__unused UIAction *action) {
            [self saveShortcut:shortcut assignmentIdentifier:identifier];
            if (handler) handler(shortcut);
        }];
        item.state = [shortcut isEqualToString:selected]
            ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:item];
    }
    return [UIMenu menuWithTitle:@"快捷动作" children:items];
}

+ (NSURL *)URLForShortcut:(NSString *)shortcut {
    if ([shortcut isEqualToString:AGShortcutWeChatScan]) {
        return [NSURL URLWithString:@"weixin://scanqrcode"];
    }
    if ([shortcut isEqualToString:AGShortcutWeChatPay]) {
        return [NSURL URLWithString:@"weixin://widget/pay"];
    }
    if ([shortcut isEqualToString:AGShortcutAlipayScan]) {
        return [NSURL URLWithString:@"alipay://platformapi/startapp?appId=10000007"];
    }
    if ([shortcut isEqualToString:AGShortcutAlipayPay]) {
        return [NSURL URLWithString:@"alipay://platformapi/startapp?appId=20000056"];
    }
    return nil;
}

+ (BOOL)launchShortcut:(NSString *)shortcut {
    NSURL *url = [self URLForShortcut:shortcut];
    if (!url) return NO;
    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)]
        ? [workspaceClass defaultWorkspace] : nil;
    if (![workspace respondsToSelector:@selector(openURL:)]) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [workspace openURL:url];
    });
    return YES;
}

@end
