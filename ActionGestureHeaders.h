#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AGHardwareButtonEvent <NSObject>
- (uint64_t)downTime;
@end

@class SBLinkSystemAction;
@class SBSystemActionControl;
@class WFConfiguredStaccatoAction;

@interface SBRingerHardwareButton : NSObject
- (void)performActionsForButtonDown:(id<AGHardwareButtonEvent>)buttonDown;
- (void)performActionsForButtonLongPress:(id<AGHardwareButtonEvent>)longPress;
- (void)performActionsForButtonUp:(id<AGHardwareButtonEvent>)buttonUp;
@end

@interface SBSystemActionAbstractDataSource : NSObject
- (void)setSelectedSystemAction:(nullable SBLinkSystemAction *)systemAction;
- (void)updateSelectedAction;
@end

@interface SBSystemActionControl : NSObject
@end

@interface WFConfiguredStaccatoAction : NSObject <NSSecureCoding>
@end

@interface SBLinkSystemAction : NSObject
- (instancetype)initWithConfiguredAction:
    (WFConfiguredStaccatoAction *)configuredAction;
@end

@interface ActionButtonSettings : UIViewController
@end

@interface ActionButtonSettings (ActionGestureUI)
- (void)ag_installSelectors;
- (UIButton *)ag_selectorButtonWithTitle:(NSString *)title
                                    menu:(UIMenu *)menu
                      accessibilityLabel:(NSString *)accessibilityLabel;
- (UIMenu *)ag_gestureMenu;
- (void)ag_switchToGesture:(NSString *)gesture;
- (void)ag_replaceController;
@end

NS_ASSUME_NONNULL_END
