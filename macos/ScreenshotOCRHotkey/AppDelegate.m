#import "AppDelegate.h"
#import "OCRConfig.h"
#import "OCRSettings.h"
#import "OCREngine.h"
#import "SettingsWindowController.h"

#import <ServiceManagement/ServiceManagement.h>

static const OSType HotKeySignature =
    ((OSType)'S' << 24) | ((OSType)'O' << 16) | ((OSType)'C' << 8) | (OSType)'R';
static const UInt32 HotKeyIDValue = 1;

@interface AppDelegate ()
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) OCRSettings *settings;
@property(nonatomic, strong) SettingsWindowController *settingsController;
@property(nonatomic, assign) EventHotKeyRef hotKeyRef;
@property(nonatomic, assign) EventHandlerRef eventHandlerRef;
@property(nonatomic, assign) BOOL busy;

// HUD.
@property(nonatomic, strong) NSWindow *hudWindow;
@property(nonatomic, strong) NSTextField *hudLabel;
@property(nonatomic, strong) NSProgressIndicator *hudSpinner;
@property(nonatomic, strong) NSTimer *hudTimer;

// Menu items whose state is refreshed when the menu opens.
@property(nonatomic, strong) NSMenuItem *hotkeyMenuItem;
@property(nonatomic, strong) NSMenuItem *loginMenuItem;
@end

#pragma mark - Carbon hotkey callback

static OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotKeyID;
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                                        NULL, sizeof(hotKeyID), NULL, &hotKeyID);
    if (status == noErr &&
        hotKeyID.signature == HotKeySignature &&
        hotKeyID.id == HotKeyIDValue) {
        AppDelegate *delegate = (__bridge AppDelegate *)userData;
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate runCapture];
        });
    }
    return noErr;
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.settings = [OCRSettings loadSettings];
    [self setupStatusItem];

    if (self.settings.hotkeyEnabled) {
        [self registerHotKey];
    }

    // Show the panel on launch unless the user opted into silent launch, and
    // always show it when no usable API key is configured yet.
    BOOL hasKey = [self.settings hasKeyForModel:self.settings.model];
    if (!self.settings.silentLaunch || !hasKey) {
        [self showSettings:nil];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self unregisterHotKey];
}

#pragma mark - Status item + menu

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage *icon = nil;
    if (@available(macOS 11.0, *)) {
        icon = [NSImage imageWithSystemSymbolName:@"text.viewfinder" accessibilityDescription:@"OCR"];
    }
    if (icon) {
        icon.template = YES;
        self.statusItem.button.image = icon;
    } else {
        self.statusItem.button.title = @"OCR";
    }

    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;

    [menu addItem:[self menuItemWithTitle:@"立即截图 OCR（⌘⇧6）" action:@selector(runCaptureFromMenu)]];
    [menu addItem:[NSMenuItem separatorItem]];

    self.hotkeyMenuItem = [self menuItemWithTitle:@"启用快捷键 ⌘⇧6" action:@selector(toggleHotkey:)];
    [menu addItem:self.hotkeyMenuItem];
    [menu addItem:[self menuItemWithTitle:@"设置…" action:@selector(showSettings:)]];
    [menu addItem:[NSMenuItem separatorItem]];

    self.loginMenuItem = [self menuItemWithTitle:@"开机自动启动" action:@selector(toggleLoginItem:)];
    [menu addItem:self.loginMenuItem];
    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItem:[self menuItemWithTitle:@"退出" action:@selector(quit)]];

    self.statusItem.menu = menu;
}

- (NSMenuItem *)menuItemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    self.hotkeyMenuItem.state = self.settings.hotkeyEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginMenuItem.state = [self loginItemEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
}

#pragma mark - Hotkey

- (void)registerHotKey {
    [self unregisterHotKey];

    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;

    OSStatus installStatus = InstallEventHandler(GetApplicationEventTarget(), HotKeyHandler, 1,
                                                 &eventType, (__bridge void *)self,
                                                 &_eventHandlerRef);
    if (installStatus != noErr) {
        [self showAlert:@"无法安装快捷键处理器"
                message:[NSString stringWithFormat:@"macOS 返回状态 %d。", installStatus]];
        return;
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = HotKeySignature;
    hotKeyID.id = HotKeyIDValue;
    OSStatus registerStatus = RegisterEventHotKey(kVK_ANSI_6, cmdKey | shiftKey, hotKeyID,
                                                  GetApplicationEventTarget(), 0, &_hotKeyRef);
    if (registerStatus != noErr) {
        [self showAlert:@"⌘⇧6 无法注册"
                message:@"该快捷键可能已被占用。请在 系统设置 > 键盘 > 键盘快捷键 中关闭冲突项，再从菜单重新启用。"];
    }
}

- (void)unregisterHotKey {
    if (_hotKeyRef != NULL) {
        UnregisterEventHotKey(_hotKeyRef);
        _hotKeyRef = NULL;
    }
    if (_eventHandlerRef != NULL) {
        RemoveEventHandler(_eventHandlerRef);
        _eventHandlerRef = NULL;
    }
}

- (void)toggleHotkey:(id)sender {
    self.settings.hotkeyEnabled = !self.settings.hotkeyEnabled;
    [self.settings save];
    if (self.settings.hotkeyEnabled) {
        [self registerHotKey];
        [self showHUDText:@"已启用快捷键 ⌘⇧6" spinner:NO autoHide:YES];
    } else {
        [self unregisterHotKey];
        [self showHUDText:@"已停用快捷键 ⌘⇧6" spinner:NO autoHide:YES];
    }
}

#pragma mark - Capture + OCR

- (void)runCaptureFromMenu {
    [self runCapture];
}

- (void)runCapture {
    if (self.busy) {
        [self showHUDText:@"正在识别，请稍候…" spinner:YES autoHide:NO];
        return;
    }

    if (![self.settings hasKeyForModel:self.settings.model]) {
        [self showHUDText:@"请先在设置中填写 API Key" spinner:NO autoHide:YES];
        [self showSettings:nil];
        return;
    }

    self.busy = YES;

    NSString *tempPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"ocr_%@.png",
                                            [[NSUUID UUID] UUIDString]]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
        task.arguments = @[@"-i", @"-s", @"-x", @"-tpng", tempPath];

        NSError *launchError = nil;
        BOOL launched = [task launchAndReturnError:&launchError];
        if (launched) {
            [task waitUntilExit];
        }

        NSFileManager *fm = NSFileManager.defaultManager;
        NSNumber *size = nil;
        [[NSURL fileURLWithPath:tempPath] getResourceValue:&size
                                                    forKey:NSURLFileSizeKey
                                                     error:NULL];
        BOOL hasImage = launched && [fm fileExistsAtPath:tempPath] && size.longLongValue > 0;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!launched) {
                self.busy = NO;
                [self showHUDText:@"无法启动截图工具" spinner:NO autoHide:YES];
                return;
            }
            if (!hasImage) {
                // User pressed Esc / cancelled the selection.
                self.busy = NO;
                [self showHUDText:@"已取消截图" spinner:NO autoHide:YES];
                return;
            }
            [self runOCRForImageAtPath:tempPath];
        });
    });
}

- (void)runOCRForImageAtPath:(NSString *)path {
    [self showHUDText:@"正在识别截图…" spinner:YES autoHide:NO];

    NSData *imageData = [NSData dataWithContentsOfFile:path];
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];

    if (imageData.length == 0) {
        self.busy = NO;
        [self showHUDText:@"读取截图失败" spinner:NO autoHide:YES];
        return;
    }

    NSString *format = self.settings.format;
    [OCREngine recognizeImageData:imageData
                         settings:self.settings
                       completion:^(NSString *text, NSError *error) {
        self.busy = NO;
        if (error) {
            [self showHUDText:[NSString stringWithFormat:@"OCR 失败：%@", error.localizedDescription]
                      spinner:NO
                     autoHide:YES];
            return;
        }

        NSString *result = text ?: @"";
        if ([format isEqualToString:@"tex"] || [format isEqualToString:@"formula"]) {
            result = [OCREngine stripMarkdownFences:result];
        }
        NSString *trimmed = [result stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            [self showHUDText:@"OCR 结果为空" spinner:NO autoHide:YES];
            return;
        }

        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:result forType:NSPasteboardTypeString];
        [self showHUDText:@"OCR 完成，结果已复制到剪贴板" spinner:NO autoHide:YES];
    }];
}

#pragma mark - Settings panel

- (void)showSettings:(id)sender {
    if (self.settingsController == nil) {
        self.settingsController = [[SettingsWindowController alloc] initWithSettings:self.settings];
        __weak typeof(self) weakSelf = self;
        self.settingsController.onSaved = ^{
            [weakSelf settingsDidChange];
        };
        self.settingsController.onCaptureNow = ^{
            [weakSelf runCapture];
        };
    }
    [self.settingsController showPanel];
}

- (void)settingsDidChange {
    if (self.settings.hotkeyEnabled) {
        [self registerHotKey];
    } else {
        [self unregisterHotKey];
    }
    [self applyLoginItem:self.settings.launchAtLogin];
    [self showHUDText:@"配置已保存" spinner:NO autoHide:YES];
}

#pragma mark - Login item (SMAppService)

- (BOOL)loginItemEnabled {
    if (@available(macOS 13.0, *)) {
        return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
    }
    return NO;
}

- (void)applyLoginItem:(BOOL)enabled {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService mainAppService];
        NSError *error = nil;
        BOOL ok = enabled ? [service registerAndReturnError:&error]
                          : [service unregisterAndReturnError:&error];
        if (!ok && error) {
            [self showAlert:@"无法更新开机启动项"
                    message:[NSString stringWithFormat:@"%@\n\n你也可以在 系统设置 > 通用 > 登录项 中手动管理。",
                                error.localizedDescription]];
        }
        // Keep the saved flag in sync with the real state.
        BOOL actual = service.status == SMAppServiceStatusEnabled;
        if (self.settings.launchAtLogin != actual) {
            self.settings.launchAtLogin = actual;
            [self.settings save];
        }
    } else {
        [self showAlert:@"需要 macOS 13 或更高版本"
                message:@"开机自动启动功能需要 macOS Ventura 或更新系统。"];
    }
}

- (void)toggleLoginItem:(id)sender {
    BOOL newValue = ![self loginItemEnabled];
    self.settings.launchAtLogin = newValue;
    [self.settings save];
    [self applyLoginItem:newValue];
    [self showHUDText:newValue ? @"已开启开机自动启动" : @"已关闭开机自动启动"
              spinner:NO
             autoHide:YES];
}

#pragma mark - HUD

- (void)ensureHUD {
    if (self.hudWindow != nil) {
        return;
    }

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 64)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.level = NSStatusWindowLevel;
    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    window.ignoresMouseEvents = YES;
    window.hasShadow = YES;

    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:window.contentView.bounds];
    effect.material = NSVisualEffectMaterialHUDWindow;
    effect.state = NSVisualEffectStateActive;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = 14;
    effect.layer.masksToBounds = YES;
    effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = effect;

    self.hudSpinner = [[NSProgressIndicator alloc] init];
    self.hudSpinner.style = NSProgressIndicatorStyleSpinning;
    self.hudSpinner.controlSize = NSControlSizeSmall;
    self.hudSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hudSpinner setContentHuggingPriority:NSLayoutPriorityRequired
                                forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.hudLabel = [NSTextField labelWithString:@""];
    self.hudLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.hudLabel.textColor = [NSColor labelColor];
    self.hudLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.hudLabel.maximumNumberOfLines = 2;
    self.hudLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *row = [NSStackView stackViewWithViews:@[self.hudSpinner, self.hudLabel]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 10;
    row.alignment = NSLayoutAttributeCenterY;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [effect addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor constant:18],
        [row.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor constant:-18],
        [row.centerYAnchor constraintEqualToAnchor:effect.centerYAnchor],
    ]];

    self.hudWindow = window;
}

- (void)showHUDText:(NSString *)text spinner:(BOOL)spinner autoHide:(BOOL)autoHide {
    [self ensureHUD];

    self.hudLabel.stringValue = text ?: @"";
    self.hudSpinner.hidden = !spinner;
    if (spinner) {
        [self.hudSpinner startAnimation:nil];
    } else {
        [self.hudSpinner stopAnimation:nil];
    }

    // Size the window to fit the text, then position it bottom-center.
    [self.hudLabel sizeToFit];
    CGFloat width = MIN(440, MAX(220, self.hudLabel.intrinsicContentSize.width + (spinner ? 80 : 56)));
    NSScreen *screen = [NSScreen mainScreen];
    NSRect visible = screen.visibleFrame;
    NSRect frame = NSMakeRect(NSMidX(visible) - width / 2,
                              NSMinY(visible) + 120,
                              width, 64);
    [self.hudWindow setFrame:frame display:YES];

    [self.hudTimer invalidate];
    self.hudTimer = nil;
    self.hudWindow.alphaValue = 1.0;
    [self.hudWindow orderFrontRegardless];

    if (autoHide) {
        self.hudTimer = [NSTimer scheduledTimerWithTimeInterval:2.2
                                                         repeats:NO
                                                           block:^(NSTimer *timer) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.35;
                self.hudWindow.animator.alphaValue = 0.0;
            } completionHandler:^{
                [self.hudWindow orderOut:nil];
            }];
        }];
    }
}

#pragma mark - Misc

- (void)showAlert:(NSString *)title message:(NSString *)message {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;
    [alert runModal];
}

- (void)quit {
    [NSApp terminate:nil];
}

@end
