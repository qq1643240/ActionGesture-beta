#import "ActionGestureHelper.h"
#import "AGShortcutActions.h"

#import <objc/runtime.h>
#import <roothide.h>

NSString *const AGGestureSingle = @"single";
NSString *const AGGestureDouble = @"double";
NSString *const AGGestureLong = @"long";

typedef void (*AGButtonEventIMP)(SBRingerHardwareButton *,
                                 SEL,
                                 id<AGHardwareButtonEvent>);

@interface AGGestureConfiguration : NSObject
@property (nonatomic) BOOL hasSection;
@property (nonatomic) BOOL hasArchive;
@property (nonatomic, copy, nullable) NSString *sectionIdentifier;
@property (nonatomic, copy, nullable) NSData *configuredActionArchive;
@end

@implementation AGGestureConfiguration
@end

@interface ActionGestureHelper ()
@property (nonatomic, readwrite) NSBundle *settingsBundle;
@property (nonatomic) AGButtonEventIMP originalButtonDown;
@property (nonatomic) AGButtonEventIMP originalButtonLongPress;
@property (nonatomic) AGButtonEventIMP originalButtonUp;
@property (nonatomic) NSMutableDictionary<NSString *, NSDictionary *> *systemActionCache;
@property (nonatomic) BOOL snapshotScheduled;
@property (nonatomic, copy, nullable) NSString *pendingSnapshotGesture;
@property (nonatomic) BOOL suppressSystemActionSnapshots;

- (id)preferenceValueForKey:(NSString *)key;
- (void)setPreferenceValue:(nullable id)value forKey:(NSString *)key;
- (NSString *)storageKeyForGesture:(NSString *)gesture suffix:(NSString *)suffix;
- (AGGestureConfiguration *)configurationForGesture:(NSString *)gesture synchronize:(BOOL)synchronize;
- (void)storeConfiguration:(AGGestureConfiguration *)configuration forGesture:(NSString *)gesture synchronize:(BOOL)synchronize;
- (AGGestureConfiguration *)currentNativeConfiguration;
- (BOOL)configurationIsNoAction:(AGGestureConfiguration *)configuration;
- (NSTimeInterval)fallbackReloadDelay;
- (BOOL)applyConfiguration:(AGGestureConfiguration *)configuration;
@end

@implementation ActionGestureHelper

+ (instancetype)sharedHelper {
    static ActionGestureHelper *helper;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ helper = [[self alloc] init]; });
    return helper;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentGesture = AGGestureSingle;
        _systemActionCache = [NSMutableDictionary dictionaryWithCapacity:3];
        _settingsBundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/ActionButtonSettings.bundle"];
    }
    return self;
}

- (id)preferenceValueForKey:(NSString *)key {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.huami.actiongesture")));
}

- (void)setPreferenceValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CFSTR("com.huami.actiongesture"));
}

- (NSString *)storageKeyForGesture:(NSString *)gesture suffix:(NSString *)suffix {
    return [NSString stringWithFormat:@"native.%@.%@", gesture, suffix];
}

- (NSUserDefaults *)springBoardDefaults {
    return [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.springboard"];
}

- (BOOL)isKnownGesture:(NSString *)gesture {
    return [gesture isEqualToString:AGGestureSingle] ||
           [gesture isEqualToString:AGGestureDouble] ||
           [gesture isEqualToString:AGGestureLong];
}

- (void)loadEditorState {
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    NSString *gesture = [self preferenceValueForKey:@"editorGesture"];
    self.currentGesture = [self isKnownGesture:gesture] ? gesture : AGGestureSingle;
}

- (void)saveCurrentGesture:(NSString *)gesture {
    if (![self isKnownGesture:gesture]) return;
    self.currentGesture = gesture;
    [self setPreferenceValue:gesture forKey:@"editorGesture"];
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
}

- (NSTimeInterval)fallbackReloadDelay {
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    id value = [self preferenceValueForKey:@"fallbackReloadDelayMs"];
    double milliseconds = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 80.0;
    if (milliseconds < 0) milliseconds = 0;
    if (milliseconds > 500) milliseconds = 500;
    return milliseconds / 1000.0;
}

- (AGGestureConfiguration *)configurationForGesture:(NSString *)gesture synchronize:(BOOL)synchronize {
    if (![self isKnownGesture:gesture]) return nil;
    if (synchronize) CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    if (![[self preferenceValueForKey:[self storageKeyForGesture:gesture suffix:@"initialized"]] boolValue]) return nil;

    AGGestureConfiguration *configuration = [AGGestureConfiguration new];
    configuration.hasSection = [[self preferenceValueForKey:[self storageKeyForGesture:gesture suffix:@"hasSection"]] boolValue];
    configuration.hasArchive = [[self preferenceValueForKey:[self storageKeyForGesture:gesture suffix:@"hasArchive"]] boolValue];
    id section = [self preferenceValueForKey:[self storageKeyForGesture:gesture suffix:@"section"]];
    id archive = [self preferenceValueForKey:[self storageKeyForGesture:gesture suffix:@"archive"]];
    if ([section isKindOfClass:NSString.class]) configuration.sectionIdentifier = section;
    if ([archive isKindOfClass:NSData.class]) configuration.configuredActionArchive = archive;
    return configuration;
}

- (BOOL)hasStoredConfigurationForGesture:(NSString *)gesture {
    return [self configurationForGesture:gesture synchronize:YES] != nil;
}

- (AGGestureConfiguration *)currentNativeConfiguration {
    NSUserDefaults *defaults = [self springBoardDefaults];
    id section = [defaults objectForKey:@"SBSystemActionSelectedSectionIdentifier"];
    id archive = [defaults objectForKey:@"SBSystemActionConfiguredActionArchive"];
    AGGestureConfiguration *configuration = [AGGestureConfiguration new];
    configuration.hasSection = [section isKindOfClass:NSString.class];
    configuration.hasArchive = [archive isKindOfClass:NSData.class];
    configuration.sectionIdentifier = configuration.hasSection ? section : nil;
    configuration.configuredActionArchive = configuration.hasArchive ? archive : nil;
    return configuration;
}

- (BOOL)configurationIsNoAction:(AGGestureConfiguration *)configuration {
    if (!configuration) return NO;
    // No section means NoAction. If a section exists, its identifier is
    // authoritative; unknown non-empty identifiers remain native actions.
    return !configuration.hasSection ||
           [AGShortcutActions isNoActionSectionIdentifier:
                                  configuration.sectionIdentifier];
}

- (BOOL)currentNativeConfigurationIsNoAction {
    return [self configurationIsNoAction:[self currentNativeConfiguration]];
}

- (void)storeConfiguration:(AGGestureConfiguration *)configuration forGesture:(NSString *)gesture synchronize:(BOOL)synchronize {
    if (!configuration || ![self isKnownGesture:gesture]) return;
    [self setPreferenceValue:@YES forKey:[self storageKeyForGesture:gesture suffix:@"initialized"]];
    [self setPreferenceValue:@(configuration.hasSection) forKey:[self storageKeyForGesture:gesture suffix:@"hasSection"]];
    [self setPreferenceValue:@(configuration.hasArchive) forKey:[self storageKeyForGesture:gesture suffix:@"hasArchive"]];
    [self setPreferenceValue:configuration.hasSection ? configuration.sectionIdentifier : nil forKey:[self storageKeyForGesture:gesture suffix:@"section"]];
    [self setPreferenceValue:configuration.hasArchive ? configuration.configuredActionArchive : nil forKey:[self storageKeyForGesture:gesture suffix:@"archive"]];
    if (synchronize) CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
}

- (void)snapshotNativeConfigurationForGesture:(NSString *)gesture {
    [self storeConfiguration:[self currentNativeConfiguration] forGesture:gesture synchronize:YES];
}

- (BOOL)applyConfiguration:(AGGestureConfiguration *)configuration {
    if (!configuration) return NO;
    NSUserDefaults *defaults = [self springBoardDefaults];
    BOOL wasSuppressingSnapshots = self.suppressSystemActionSnapshots;
    self.suppressSystemActionSnapshots = YES;
    BOOL synchronized = NO;
    @try {
        if (configuration.hasSection && configuration.sectionIdentifier) {
            [defaults setObject:configuration.sectionIdentifier forKey:@"SBSystemActionSelectedSectionIdentifier"];
        } else {
            [defaults removeObjectForKey:@"SBSystemActionSelectedSectionIdentifier"];
        }
        if (configuration.hasArchive && configuration.configuredActionArchive) {
            [defaults setObject:configuration.configuredActionArchive forKey:@"SBSystemActionConfiguredActionArchive"];
        } else {
            [defaults removeObjectForKey:@"SBSystemActionConfiguredActionArchive"];
        }
        synchronized = [defaults synchronize];
    } @finally {
        self.suppressSystemActionSnapshots = wasSuppressingSnapshots;
    }
    return synchronized;
}

- (BOOL)applyNativeConfigurationForGesture:(NSString *)gesture {
    return [self applyConfiguration:[self configurationForGesture:gesture synchronize:YES]];
}

- (void)beginSuppressingSystemActionSnapshots {
    self.suppressSystemActionSnapshots = YES;
}

- (void)endSuppressingSystemActionSnapshots {
    self.suppressSystemActionSnapshots = NO;
}

- (void)systemActionPreferenceDidChangeForKey:(NSString *)key {
    if (self.suppressSystemActionSnapshots) return;
    if (![key isEqualToString:@"SBSystemActionSelectedSectionIdentifier"] &&
        ![key isEqualToString:@"SBSystemActionConfiguredActionArchive"]) return;

    NSString *gesture = self.currentGesture;
    dispatch_block_t scheduleSnapshot = ^{
        self.pendingSnapshotGesture = gesture;
        if (self.snapshotScheduled) return;
        self.snapshotScheduled = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *pendingGesture = self.pendingSnapshotGesture;
            self.pendingSnapshotGesture = nil;
            self.snapshotScheduled = NO;
            [self snapshotNativeConfigurationForGesture:pendingGesture];

            AGGestureConfiguration *currentConfiguration = [self currentNativeConfiguration];
            if (![self configurationIsNoAction:currentConfiguration]) {
                [AGShortcutActions disableShortcutForAssignmentIdentifier:pendingGesture];
            }
        });
    };
    if (NSThread.isMainThread) scheduleSnapshot();
    else dispatch_async(dispatch_get_main_queue(), scheduleSnapshot);
}

- (NSBundle *)localizationBundle {
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundle = [NSBundle bundleWithPath:jbroot(@"/Library/Application Support/ActionGesture.bundle")];
    });
    return bundle;
}

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:nil];
}

- (NSString *)titleForGesture:(NSString *)gesture {
    if ([gesture isEqualToString:AGGestureDouble]) return [self localizedStringForKey:@"gesture.double"];
    if ([gesture isEqualToString:AGGestureLong]) return [self localizedStringForKey:@"gesture.long"];
    return [self localizedStringForKey:@"gesture.single"];
}

- (NSString *)symbolForGesture:(NSString *)gesture {
    if ([gesture isEqualToString:AGGestureDouble]) return @"hand.tap.fill";
    if ([gesture isEqualToString:AGGestureLong]) return @"hand.point.up.left.fill";
    return @"hand.tap";
}

- (SBSystemActionAbstractDataSource *)dataSourceForButton:(SBRingerHardwareButton *)button {
    Ivar controlIvar = class_getInstanceVariable(object_getClass(button), "_systemActionControl");
    if (!controlIvar) return nil;
    SBSystemActionControl *control = object_getIvar(button, controlIvar);
    Ivar dataSourceIvar = class_getInstanceVariable(object_getClass(control), "_dataSource");
    if (!dataSourceIvar) return nil;

    SBSystemActionAbstractDataSource *dataSource = object_getIvar(control, dataSourceIvar);
    for (NSUInteger depth = 0; dataSource && depth < 4; depth++) {
        Ivar innerDataSourceIvar = class_getInstanceVariable(object_getClass(dataSource), "_innerDataSource");
        if (!innerDataSourceIvar) break;
        SBSystemActionAbstractDataSource *innerDataSource = object_getIvar(dataSource, innerDataSourceIvar);
        if (!innerDataSource) break;
        dataSource = innerDataSource;
    }
    return dataSource;
}

- (BOOL)prepareSpringBoardRuntime {
    Method downMethod = class_getInstanceMethod(objc_getClass("SBRingerHardwareButton"), @selector(performActionsForButtonDown:));
    Method longPressMethod = class_getInstanceMethod(objc_getClass("SBRingerHardwareButton"), @selector(performActionsForButtonLongPress:));
    Method upMethod = class_getInstanceMethod(objc_getClass("SBRingerHardwareButton"), @selector(performActionsForButtonUp:));
    if (!objc_getClass("SBRingerHardwareButton") ||
        !objc_getClass("SBSystemActionControl") ||
        !objc_getClass("SBLinkSystemAction") ||
        !downMethod || !longPressMethod || !upMethod ||
        !class_getInstanceVariable(objc_getClass("SBRingerHardwareButton"), "_systemActionControl") ||
        !class_getInstanceVariable(objc_getClass("SBSystemActionControl"), "_dataSource") ||
        !class_getInstanceMethod(objc_getClass("SBLinkSystemAction"), @selector(initWithConfiguredAction:))) return NO;

    self.originalButtonDown = (AGButtonEventIMP)method_getImplementation(downMethod);
    self.originalButtonLongPress = (AGButtonEventIMP)method_getImplementation(longPressMethod);
    self.originalButtonUp = (AGButtonEventIMP)method_getImplementation(upMethod);
    return self.originalButtonDown && self.originalButtonLongPress && self.originalButtonUp;
}

- (BOOL)canHandleButton:(SBRingerHardwareButton *)button {
    return self.originalButtonDown && self.originalButtonLongPress && self.originalButtonUp &&
           [[self dataSourceForButton:button] respondsToSelector:@selector(setSelectedSystemAction:)];
}

- (SBLinkSystemAction *)systemActionForAssignmentIdentifier:(NSString *)assignmentIdentifier configuration:(AGGestureConfiguration *)configuration {
    if (!configuration.hasArchive || !configuration.configuredActionArchive) return nil;
    NSDictionary *cachedAction = self.systemActionCache[assignmentIdentifier];
    if ([cachedAction[@"archive"] isEqualToData:configuration.configuredActionArchive]) return cachedAction[@"action"];

    NSError *error = nil;
    WFConfiguredStaccatoAction *configuredAction = nil;
    @try {
        configuredAction = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:configuration.configuredActionArchive error:&error];
    } @catch (__unused NSException *exception) {
        return nil;
    }
    if (!configuredAction || error) return nil;
    SBLinkSystemAction *systemAction = [(SBLinkSystemAction *)[objc_getClass("SBLinkSystemAction") alloc] initWithConfiguredAction:configuredAction];
    if (!systemAction) return nil;
    self.systemActionCache[assignmentIdentifier] = @{@"archive": configuration.configuredActionArchive, @"action": systemAction};
    return systemAction;
}

- (BOOL)selectConfiguration:(AGGestureConfiguration *)configuration assignmentIdentifier:(NSString *)assignmentIdentifier onButton:(SBRingerHardwareButton *)button {
    SBSystemActionAbstractDataSource *dataSource = [self dataSourceForButton:button];
    if (![dataSource respondsToSelector:@selector(setSelectedSystemAction:)]) return NO;
    if (!configuration.hasArchive) {
        [dataSource setSelectedSystemAction:nil];
        return YES;
    }
    SBLinkSystemAction *systemAction = [self systemActionForAssignmentIdentifier:assignmentIdentifier configuration:configuration];
    if (!systemAction) return NO;
    [dataSource setSelectedSystemAction:systemAction];
    return YES;
}

- (BOOL)reloadSelectedActionOnButton:(SBRingerHardwareButton *)button {
    SBSystemActionAbstractDataSource *dataSource = [self dataSourceForButton:button];
    if (![dataSource respondsToSelector:@selector(updateSelectedAction)]) return NO;
    [dataSource updateSelectedAction];
    return YES;
}

- (BOOL)replayNativeActionOnButton:(SBRingerHardwareButton *)button event:(id<AGHardwareButtonEvent>)event {
    if (!self.originalButtonDown || !self.originalButtonLongPress || !self.originalButtonUp || !button || !event) return NO;
    self.originalButtonDown(button, @selector(performActionsForButtonDown:), event);
    self.originalButtonLongPress(button, @selector(performActionsForButtonLongPress:), event);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        self.originalButtonUp(button, @selector(performActionsForButtonUp:), event);
    });
    return YES;
}

- (BOOL)executeGesture:(NSString *)gesture onButton:(SBRingerHardwareButton *)button event:(id<AGHardwareButtonEvent>)event {
    if (!button || !event || ![self isKnownGesture:gesture]) return NO;
    AGGestureConfiguration *configuration = [self configurationForGesture:gesture synchronize:YES];
    if (!configuration) {
        [self snapshotNativeConfigurationForGesture:gesture];
        configuration = [self configurationForGesture:gesture synchronize:YES];
    }
    if (!configuration) return NO;

    // This is the only custom branch. NoAction consumes the hardware event;
    // every non-NoAction configuration keeps Huami's original select/replay
    // path, including Silent Mode and the other native system actions.
    if ([self configurationIsNoAction:configuration]) {
        NSString *shortcut = [AGShortcutActions shortcutForAssignmentIdentifier:gesture];
        if ([shortcut isEqualToString:AGShortcutOff]) return YES;
        (void)[AGShortcutActions launchShortcut:shortcut];
        return YES;
    }

    BOOL selected = [self selectConfiguration:configuration assignmentIdentifier:gesture onButton:button];
    if (!selected) {
        BOOL applied = [self applyConfiguration:configuration];
        if (applied) {
            NSTimeInterval delay = [self fallbackReloadDelay];
            __weak SBRingerHardwareButton *weakButton = button;
            __weak ActionGestureHelper *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ActionGestureHelper *strongSelf = weakSelf;
                SBRingerHardwareButton *strongButton = weakButton;
                if (strongSelf && strongButton) [strongSelf reloadSelectedActionOnButton:strongButton];
            });
        }
        selected = applied;
    }
    return selected && [self replayNativeActionOnButton:button event:event];
}

- (void)replayNativeTapOnButton:(SBRingerHardwareButton *)button downEvent:(id<AGHardwareButtonEvent>)downEvent upEvent:(id<AGHardwareButtonEvent>)upEvent {
    if (!self.originalButtonDown || !self.originalButtonUp || !button || !downEvent || !upEvent) return;
    self.originalButtonDown(button, @selector(performActionsForButtonDown:), downEvent);
    self.originalButtonUp(button, @selector(performActionsForButtonUp:), upEvent);
}

@end
