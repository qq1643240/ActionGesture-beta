#import <UIKit/UIKit.h>

#import "ActionGestureHelper.h"
#import "AGShortcutActions.h"

%group ActionGestureOfficialSettings

%hook NSUserDefaults

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    %orig;
    [[ActionGestureHelper sharedHelper] systemActionPreferenceDidChangeForKey:defaultName];
}

- (void)removeObjectForKey:(NSString *)defaultName {
    %orig;
    [[ActionGestureHelper sharedHelper] systemActionPreferenceDidChangeForKey:defaultName];
}

%end

%hook ActionButtonSettings

%new
- (void)ag_installSelectors {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSString *gestureTitle = [helper titleForGesture:helper.currentGesture];
    UIButton *gestureButton = [self ag_selectorButtonWithTitle:gestureTitle
                                                           menu:[self ag_gestureMenu]
                                             accessibilityLabel:[NSString stringWithFormat:[helper localizedStringForKey:@"accessibility.current"], gestureTitle]];

    NSString *assignmentIdentifier = helper.currentGesture;
    NSString *shortcutTitle = [AGShortcutActions titleForShortcut:[AGShortcutActions shortcutForAssignmentIdentifier:assignmentIdentifier]];
    UIButton *shortcutButton = [self ag_selectorButtonWithTitle:shortcutTitle
                                                            menu:nil
                                              accessibilityLabel:@"快捷动作"];
    __weak UIButton *weakShortcutButton = shortcutButton;
    shortcutButton.menu = [AGShortcutActions menuForAssignmentIdentifier:assignmentIdentifier
                                                                   enabled:[helper currentNativeConfigurationIsNoAction]
                                                         selectionHandler:^(NSString *shortcut) {
        // Updating only this compact button is intentional. Replacing the
        // ActionButtonSettings controller made each menu choice noticeably slow.
        UIButton *button = weakShortcutButton;
        if (!button) return;
        UIButtonConfiguration *configuration = [button.configuration copy];
        configuration.attributedTitle = [[NSAttributedString alloc]
            initWithString:[AGShortcutActions titleForShortcut:shortcut]
                attributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold],
                    NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.94]
                }];
        button.configuration = configuration;
    }];

    UIStackView *selectors = [[UIStackView alloc] initWithArrangedSubviews:@[ gestureButton, shortcutButton ]];
    selectors.axis = UILayoutConstraintAxisHorizontal;
    selectors.alignment = UIStackViewAlignmentCenter;
    selectors.spacing = 5.0;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:selectors];
}

%new
- (UIButton *)ag_selectorButtonWithTitle:(NSString *)title
                                    menu:(nullable UIMenu *)menu
                      accessibilityLabel:(NSString *)accessibilityLabel {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
    configuration.attributedTitle = [[NSAttributedString alloc]
        initWithString:title
            attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold],
                NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.94]
            }];
    configuration.image = [UIImage systemImageNamed:@"chevron.up.chevron.down"];
    configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:7.5 weight:UIImageSymbolWeightSemibold scale:UIImageSymbolScaleSmall];
    configuration.imagePlacement = NSDirectionalRectEdgeTrailing;
    configuration.imagePadding = 4.0;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(4.5, 8.0, 4.5, 7.0);
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.buttonSize = UIButtonConfigurationSizeSmall;
    configuration.baseForegroundColor = [UIColor colorWithWhite:1.0 alpha:0.78];
    configuration.baseBackgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    button.configuration = configuration;
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    button.accessibilityLabel = accessibilityLabel;
    return button;
}

%new
- (UIMenu *)ag_gestureMenu {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray arrayWithCapacity:3];
    for (NSString *gesture in @[ AGGestureSingle, AGGestureDouble, AGGestureLong ]) {
        __weak ActionButtonSettings *weakSelf = self;
        UIAction *action = [UIAction actionWithTitle:[helper titleForGesture:gesture]
                                                image:[UIImage systemImageNamed:[helper symbolForGesture:gesture]]
                                           identifier:nil
                                              handler:^(__unused UIAction *selectedAction) {
            [weakSelf ag_switchToGesture:gesture];
        }];
        action.state = [gesture isEqualToString:helper.currentGesture] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:[helper localizedStringForKey:@"menu.title"]
                           image:nil
                      identifier:nil
                         options:UIMenuOptionsSingleSelection
                        children:actions];
}

%new
- (void)ag_switchToGesture:(NSString *)gesture {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (![helper isKnownGesture:gesture] || [gesture isEqualToString:helper.currentGesture]) return;
    [helper snapshotNativeConfigurationForGesture:helper.currentGesture];
    if (![helper hasStoredConfigurationForGesture:gesture]) {
        [helper snapshotNativeConfigurationForGesture:gesture];
    }
    [helper saveCurrentGesture:gesture];
    [helper applyNativeConfigurationForGesture:gesture];
    [self ag_replaceController];
}

%new
- (void)ag_replaceController {
    UINavigationController *navigationController = self.navigationController;
    NSUInteger index = [navigationController.viewControllers indexOfObjectIdenticalTo:self];
    if (!navigationController || index == NSNotFound) return;
    ActionButtonSettings *replacement = [[[self class] alloc] initWithNibName:nil bundle:[ActionGestureHelper sharedHelper].settingsBundle];
    replacement.title = self.title;
    NSMutableArray<UIViewController *> *controllers = [navigationController.viewControllers mutableCopy];
    controllers[index] = replacement;
    [navigationController setViewControllers:controllers animated:NO];
}

- (void)viewDidLoad {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    [helper beginSuppressingSystemActionSnapshots];
    [helper applyNativeConfigurationForGesture:helper.currentGesture];
    %orig;
    [helper endSuppressingSystemActionSnapshots];
    if (![helper hasStoredConfigurationForGesture:helper.currentGesture]) {
        [helper snapshotNativeConfigurationForGesture:helper.currentGesture];
    }
    [self ag_installSelectors];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self ag_installSelectors];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [[ActionGestureHelper sharedHelper] snapshotNativeConfigurationForGesture:[ActionGestureHelper sharedHelper].currentGesture];
}

%end

%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"]) return;
        ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
        [helper loadEditorState];
        if (!helper.settingsBundle.loaded) [helper.settingsBundle loadAndReturnError:nil];
        if (!NSClassFromString(@"ActionButtonSettings")) return;
        %init(ActionGestureOfficialSettings);
    }
}
