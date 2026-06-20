#import "AppDelegate.h"
#import "OCRConfig.h"
#import "OCRSettings.h"
#import "OCREngine.h"
#import "SettingsWindowController.h"

#import <CoreGraphics/CoreGraphics.h>
#import <ServiceManagement/ServiceManagement.h>

static const OSType HotKeySignature =
    ((OSType)'S' << 24) | ((OSType)'O' << 16) | ((OSType)'C' << 8) | (OSType)'R';
static const UInt32 HotKeyIDValue = 1;

static NSRect OCRStandardizedRect(NSRect rect) {
    if (rect.size.width < 0) {
        rect.origin.x += rect.size.width;
        rect.size.width = -rect.size.width;
    }
    if (rect.size.height < 0) {
        rect.origin.y += rect.size.height;
        rect.size.height = -rect.size.height;
    }
    return rect;
}

typedef void (^OCRSelectionCompletion)(NSRect selectedRect, BOOL cancelled);

@interface OCRSelectionWindow : NSWindow
@end

@implementation OCRSelectionWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

@end

@interface OCRSelectionView : NSView
@property(nonatomic, copy) OCRSelectionCompletion completion;
@property(nonatomic, assign) NSPoint dragStart;
@property(nonatomic, assign) NSPoint dragCurrent;
@property(nonatomic, assign) BOOL dragging;
@end

@implementation OCRSelectionView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:NSCursor.crosshairCursor];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [[NSColor colorWithWhite:0.0 alpha:0.25] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);

    if (!self.dragging) {
        return;
    }

    NSRect selection = NSIntegralRect(OCRStandardizedRect(
        NSMakeRect(self.dragStart.x,
                   self.dragStart.y,
                   self.dragCurrent.x - self.dragStart.x,
                   self.dragCurrent.y - self.dragStart.y)));

    [[NSColor clearColor] setFill];
    NSRectFillUsingOperation(selection, NSCompositingOperationClear);

    NSBezierPath *border = [NSBezierPath bezierPathWithRect:selection];
    border.lineWidth = 2.0;
    [[NSColor colorWithCalibratedRed:0.2 green:0.55 blue:1.0 alpha:1.0] setStroke];
    [border stroke];
}

- (void)mouseDown:(NSEvent *)event {
    self.dragStart = [self convertPoint:event.locationInWindow fromView:nil];
    self.dragCurrent = self.dragStart;
    self.dragging = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragging) {
        return;
    }
    self.dragCurrent = [self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.dragging) {
        if (self.completion) {
            self.completion(NSZeroRect, YES);
        }
        return;
    }

    self.dragCurrent = [self convertPoint:event.locationInWindow fromView:nil];
    self.dragging = NO;

    NSRect selection = NSIntegralRect(OCRStandardizedRect(
        NSMakeRect(self.dragStart.x,
                   self.dragStart.y,
                   self.dragCurrent.x - self.dragStart.x,
                   self.dragCurrent.y - self.dragStart.y)));
    BOOL cancelled = selection.size.width < 4 || selection.size.height < 4;
    if (self.completion) {
        self.completion(selection, cancelled);
    }
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == kVK_Escape) {
        if (self.completion) {
            self.completion(NSZeroRect, YES);
        }
        return;
    }
    [super keyDown:event];
}

@end

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
@property(nonatomic, strong) NSWindow *selectionWindow;

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
    [self setupMainMenu];
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

    if ([NSProcessInfo.processInfo.arguments containsObject:@"--capture-now"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self runCapture];
        });
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self unregisterHotKey];
}

#pragma mark - Main menu (enables Cut/Copy/Paste in text fields)

// An LSUIElement app has no main menu, so the standard ⌘C/⌘V/⌘X/⌘A key
// equivalents have nowhere to be dispatched and text-field editing breaks.
// Installing a main menu with the standard Edit items routes those shortcuts to
// the field editor, even though the menu bar itself stays hidden.
- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"隐藏" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"退出 Screenshot OCR" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redoItem = [editMenu addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"z"];
    redoItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"拷贝" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;

    [NSApp setMainMenu:mainMenu];
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

    if (![self ensureScreenCaptureAccess]) {
        return;
    }

    self.busy = YES;
    [self beginNativeRegionSelection];
}

- (void)beginNativeRegionSelection {
    [self.hudTimer invalidate];
    self.hudTimer = nil;
    [self.hudWindow orderOut:nil];

    NSRect frame = NSZeroRect;
    for (NSScreen *screen in NSScreen.screens) {
        frame = NSIsEmptyRect(frame) ? screen.frame : NSUnionRect(frame, screen.frame);
    }
    if (NSIsEmptyRect(frame)) {
        self.busy = NO;
        [self showHUDText:@"无法读取屏幕信息" spinner:NO autoHide:YES];
        return;
    }

    OCRSelectionWindow *window = [[OCRSelectionWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.level = NSScreenSaverWindowLevel;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = NO;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorFullScreenAuxiliary |
                                NSWindowCollectionBehaviorStationary;

    OCRSelectionView *view = [[OCRSelectionView alloc] initWithFrame:NSMakeRect(0, 0,
                                                                                frame.size.width,
                                                                                frame.size.height)];
    __weak typeof(self) weakSelf = self;
    __weak NSWindow *weakWindow = window;
    view.completion = ^(NSRect selectedRect, BOOL cancelled) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        NSWindow *selectionWindow = weakWindow;
        NSRect globalRect = selectedRect;
        globalRect.origin.x += selectionWindow.frame.origin.x;
        globalRect.origin.y += selectionWindow.frame.origin.y;
        [strongSelf finishNativeRegionSelectionWithRect:globalRect cancelled:cancelled];
    };
    window.contentView = view;
    self.selectionWindow = window;

    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:view];
}

- (void)finishNativeRegionSelectionWithRect:(NSRect)selectedRect cancelled:(BOOL)cancelled {
    [self.selectionWindow orderOut:nil];
    self.selectionWindow = nil;

    if (cancelled) {
        self.busy = NO;
        [self showHUDText:@"已取消截图" spinner:NO autoHide:YES];
        return;
    }

    NSRect captureRect = NSIntegralRect(OCRStandardizedRect(selectedRect));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSError *captureError = nil;
        NSData *imageData = [self pngDataForScreenRect:captureRect error:&captureError];
        if (imageData.length == 0) {
            self.busy = NO;
            NSString *message = captureError.localizedDescription ?: @"截图失败";
            [self showHUDText:message spinner:NO autoHide:YES];
            if ([message containsString:@"权限"]) {
                [self showScreenCaptureAccessHelp];
            }
            return;
        }
        [self runOCRForImageData:imageData];
    });
}

- (BOOL)ensureScreenCaptureAccess {
    if (@available(macOS 10.15, *)) {
        if (CGPreflightScreenCaptureAccess()) {
            return YES;
        }

        BOOL granted = CGRequestScreenCaptureAccess();
        if (granted || CGPreflightScreenCaptureAccess()) {
            return YES;
        }

        [self showScreenCaptureAccessHelp];
        return NO;
    }
    return YES;
}

- (NSString *)screenCaptureTCCResetCommand {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"local.ocrclipboard.hotkey";
    return [NSString stringWithFormat:@"tccutil reset ScreenCapture %@", bundleID];
}

- (void)showScreenCaptureAccessHelp {
    [self showHUDText:@"需要允许截屏权限" spinner:NO autoHide:YES];

    NSString *message = [NSString stringWithFormat:
        @"请在 系统设置 > 隐私与安全性 > 屏幕录制 中允许 Screenshot OCR，然后退出并重新打开应用。\n\n"
         "如果列表里已经显示已允许但仍然弹权限提示，通常是旧构建的 TCC 记录和当前 app 签名不匹配。请退出 Screenshot OCR 后运行：\n\n%@",
        [self screenCaptureTCCResetCommand]];

    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Screenshot OCR 需要截屏权限";
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"打开系统设置"];
    [alert addButtonWithTitle:@"复制重置命令"];
    [alert addButtonWithTitle:@"稍后处理"];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSURL *url = [NSURL URLWithString:
            @"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
        [NSWorkspace.sharedWorkspace openURL:url];
    } else if (response == NSAlertSecondButtonReturn) {
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        [pasteboard clearContents];
        [pasteboard setString:[self screenCaptureTCCResetCommand] forType:NSPasteboardTypeString];
        [self showHUDText:@"重置命令已复制" spinner:NO autoHide:YES];
    }
}

- (CGRect)coreGraphicsRectForAppKitRect:(NSRect)rect {
    NSScreen *mainScreen = NSScreen.screens.firstObject ?: NSScreen.mainScreen;
    CGFloat mainHeight = mainScreen.frame.size.height;
    return CGRectMake(NSMinX(rect),
                      mainHeight - NSMaxY(rect),
                      rect.size.width,
                      rect.size.height);
}

- (NSData *)pngDataForScreenRect:(NSRect)rect error:(NSError **)error {
    if (@available(macOS 10.15, *)) {
        if (!CGPreflightScreenCaptureAccess()) {
            if (error) {
                *error = [NSError errorWithDomain:@"ScreenshotOCR"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"缺少截屏权限"}];
            }
            return nil;
        }
    }

    CGRect cgRect = [self coreGraphicsRectForAppKitRect:rect];
    CGImageRef image = CGWindowListCreateImage(cgRect,
                                               kCGWindowListOptionOnScreenOnly,
                                               kCGNullWindowID,
                                               kCGWindowImageBestResolution);
    if (image == NULL) {
        image = CGWindowListCreateImage(cgRect,
                                        kCGWindowListOptionOnScreenOnly,
                                        kCGNullWindowID,
                                        kCGWindowImageDefault);
    }
    if (image == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"ScreenshotOCR"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"截图失败"}];
        }
        return nil;
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CGImageRelease(image);
    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (data.length == 0 && error) {
        *error = [NSError errorWithDomain:@"ScreenshotOCR"
                                     code:3
                                 userInfo:@{NSLocalizedDescriptionKey: @"截图编码失败"}];
    }
    return data;
}

- (void)runOCRForImageData:(NSData *)imageData {
    [self showHUDText:@"正在识别截图…" spinner:YES autoHide:NO];

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
