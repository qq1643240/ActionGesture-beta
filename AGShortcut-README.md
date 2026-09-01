# ActionGesture 独立快捷动作模块

这个目录只包含快捷动作，不包含也不修改：

- 单击、双击、长按识别；
- CoreMotion 方向识别；
- 原生系统动作 archive 解包、缓存和回放；
- `NSUserDefaults` 的系统动作监听；
- `viewDidLoad` / `viewWillDisappear` 生命周期。

请从原始仓库重新拉取：

```sh
git clone https://github.com/huami1314/ActionGesture.git
cd ActionGesture
```

然后把 `AGShortcutActions.h`、`AGShortcutActions.m` 复制到原始仓库，并按下面步骤接入。

## 1. 加入 Makefile

原始仓库的：

```make
ActionGesture_FILES = ActionGesture.xm ActionGestureSettings.xm ActionGestureHelper.m
```

改为：

```make
ActionGesture_FILES = ActionGesture.xm ActionGestureSettings.xm ActionGestureHelper.m AGShortcutActions.m
```

不要替换原始仓库的 `ActionGesture.xm` 或 `ActionGestureHelper.m`。

## 2. 快捷动作常量和 URL

模块固定使用以下值：

| 名称 | 值 | URL |
|---|---|---|
| 关闭 | `off` | 无 |
| 微信扫码 | `wechat.scan` | `weixin://scanqrcode` |
| 微信付款 | `wechat.pay` | `weixin://widget/pay` |
| 支付宝扫一扫 | `alipay.scan` | `alipay://platformapi/startapp?appId=10000007` |
| 支付宝付款码 | `alipay.pay` | `alipay://platformapi/startapp?appId=20000056` |

不要再次使用旧的 `weixin://dl/...`、`alipayqr://...` 或 `alipays://...` URL。

## 3. 接入原始 Helper 的执行入口

在原始 `ActionGestureHelper.m` 顶部加入：

```objc
#import "AGShortcutActions.h"
```

在原始 `executeGesture:onButton:event:` 中，先得到原仓库已经解析好的 configuration 和 resolvedDirection：

```objc
NSString *assignmentIdentifier =
    [self assignmentIdentifierForGesture:gesture
                                direction:resolvedDirection];
```

紧接着加入下面分支，然后再继续原仓库的 `selectConfiguration` / native replay 代码：

```objc
if ([AGShortcutActions
        isNoActionSectionIdentifier:configuration.sectionIdentifier]) {
    NSString *shortcut =
        [AGShortcutActions shortcutForAssignmentIdentifier:
                              assignmentIdentifier];
    if ([AGShortcutActions launchShortcut:shortcut]) {
        return YES;
    }
    // off 或 URL 不可用时返回 NO，让原始仓库继续执行自己的兜底逻辑。
    return NO;
}
```

关键点：必须使用当前 `executeGesture:` 已解析出的 `configuration.sectionIdentifier`，不能在快捷模块里重新读取 SpringBoard 全局状态。这样单击、双击、长按以及方向配置不会互相串值。

## 4. 接入设置页菜单

在原始 `ActionGestureSettings.xm` 顶部加入：

```objc
#import "AGShortcutActions.h"
```

原始设置页里新增一个快捷动作按钮，菜单直接这样生成：

```objc
NSString *assignmentIdentifier =
    [helper assignmentIdentifierForGesture:helper.currentGesture
                                  direction:[helper activeEditorDirection]];
BOOL noNativeAction =
    [AGShortcutActions
        isNoActionSectionIdentifier:currentConfiguration.sectionIdentifier];

UIButton *shortcutButton = [self ag_selectorButtonWithTitle:
    [AGShortcutActions titleForShortcut:
        [AGShortcutActions shortcutForAssignmentIdentifier:assignmentIdentifier]]
    menu:[AGShortcutActions menuForAssignmentIdentifier:assignmentIdentifier
                                               enabled:noNativeAction
                                     selectionHandler:^(__unused NSString *shortcut) {
                                         [self ag_replaceController];
                                     }]
    accessibilityLabel:@"快捷动作"];
```

`currentConfiguration` 必须使用原始 Helper 当前页面/当前方向已经读取的配置对象；不要让 `AGShortcutActions` 自己读取 SpringBoard 偏好。

如果你的原始仓库没有对外提供 `assignmentIdentifierForGesture:direction:`，就在 `ActionGestureHelper.h` 增加这个声明，或直接使用原始执行入口中已经生成的同一个 identifier。不要自行用当前手势名称覆盖方向 identifier。

## 5. 系统动作保存时关闭快捷动作

原始仓库的 `systemActionPreferenceDidChangeForKey:` 在完成 snapshot 后，为同一个 gesture/direction 调用：

```objc
[AGShortcutActions
    disableShortcutForAssignmentIdentifier:assignmentIdentifier];
```

只在新的 section identifier 是非空且不是 No Action 时调用。这样用户从“无操作”改成相机、手电筒、专注模式等系统动作后，该手势自己的快捷动作会自动变成“关闭”。

## 6. 不能复制的代码

不要把以下内容从旧版 ActionGesture2215 带回原始仓库：

- `AGPassThroughNative` 等旧的全局事件状态机；
- `openSensitiveURL:`；
- `UIApplication openURL` 兜底；
- 对 `SBSystemActionConfiguredActionArchive` 的全局强制清理；
- 用当前 SpringBoard 全局配置判断所有手势的快捷动作；
- 用替换整个导航控制器的方式刷新快捷动作按钮。

## 文件

- [AGShortcutActions.h](AGShortcutActions.h)
- [AGShortcutActions.m](AGShortcutActions.m)
- [接入代码示例](AGShortcutIntegrationSnippets.m)

该模块只适合在原始仓库中作为一个额外 `.m` 文件编译。不要把这个目录整体当作新的 ActionGesture 项目编译。
