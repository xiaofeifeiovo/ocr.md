#import "SettingsWindowController.h"
#import "OCRConfig.h"
#import "OCRSettings.h"

@interface SettingsWindowController ()
@property(nonatomic, strong) OCRSettings *settings;
@property(nonatomic, strong) NSPopUpButton *modelPopUp;
@property(nonatomic, strong) NSPopUpButton *formatPopUp;
@property(nonatomic, strong) NSSecureTextField *dashScopeField;
@property(nonatomic, strong) NSSecureTextField *mimoField;
@property(nonatomic, strong) NSSecureTextField *openRouterField;
@property(nonatomic, strong) NSTextView *promptTextView;
@property(nonatomic, strong) NSButton *launchAtLoginCheckbox;
@property(nonatomic, strong) NSButton *silentLaunchCheckbox;
@property(nonatomic, strong) NSButton *hotkeyCheckbox;
@property(nonatomic, strong) NSArray<NSString *> *modelOrder;
@property(nonatomic, strong) NSArray<NSString *> *formatOrder;
@end

@implementation SettingsWindowController

- (instancetype)initWithSettings:(OCRSettings *)settings {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 540, 640)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Screenshot OCR 设置";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _settings = settings;
        _modelOrder = OCRModelOrder();
        _formatOrder = OCRFormatOrder();
        [self buildUI];
        [self loadValues];
    }
    return self;
}

#pragma mark - Layout helpers

- (NSTextField *)makeLabel:(NSString *)text bold:(BOOL)bold {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = bold ? [NSFont boldSystemFontOfSize:13] : [NSFont systemFontOfSize:13];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSStackView *)rowWithLabel:(NSString *)labelText control:(NSView *)control {
    NSTextField *label = [self makeLabel:labelText bold:NO];
    label.alignment = NSTextAlignmentRight;
    [label.widthAnchor constraintEqualToConstant:120].active = YES;
    [label setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];

    control.translatesAutoresizingMaskIntoConstraints = NO;
    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow
                        forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *row = [NSStackView stackViewWithViews:@[label, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
    ]];

    // Header.
    NSTextField *title = [self makeLabel:@"OCR 识别设置" bold:YES];
    title.font = [NSFont boldSystemFontOfSize:16];
    [stack addArrangedSubview:title];
    NSTextField *subtitle = [self makeLabel:@"按 ⌘⇧6 框选截图，AI OCR 结果会自动复制到剪贴板。" bold:NO];
    subtitle.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:subtitle];

    // Model + format.
    self.modelPopUp = [[NSPopUpButton alloc] init];
    for (NSString *modelId in self.modelOrder) {
        [self.modelPopUp addItemWithTitle:OCRModelDisplayName(modelId)];
    }
    NSStackView *modelRow = [self rowWithLabel:@"模型" control:self.modelPopUp];

    self.formatPopUp = [[NSPopUpButton alloc] init];
    for (NSString *format in self.formatOrder) {
        [self.formatPopUp addItemWithTitle:OCRFormatLabel(format)];
    }
    NSStackView *formatRow = [self rowWithLabel:@"输出格式" control:self.formatPopUp];

    [stack addArrangedSubview:modelRow];
    [stack addArrangedSubview:formatRow];

    // API keys.
    [stack addArrangedSubview:[self sectionSpacerWithTitle:@"API Key"]];
    self.dashScopeField = [[NSSecureTextField alloc] init];
    self.dashScopeField.placeholderString = @"DashScope / Qwen";
    self.mimoField = [[NSSecureTextField alloc] init];
    self.mimoField.placeholderString = @"MiMo";
    self.openRouterField = [[NSSecureTextField alloc] init];
    self.openRouterField.placeholderString = @"OpenRouter";
    [stack addArrangedSubview:[self rowWithLabel:@"DashScope / Qwen" control:self.dashScopeField]];
    [stack addArrangedSubview:[self rowWithLabel:@"MiMo" control:self.mimoField]];
    [stack addArrangedSubview:[self rowWithLabel:@"OpenRouter" control:self.openRouterField]];

    // Custom prompt.
    [stack addArrangedSubview:[self sectionSpacerWithTitle:@"自定义系统提示词（可选）"]];
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    self.promptTextView = [[NSTextView alloc] init];
    self.promptTextView.font = [NSFont systemFontOfSize:12];
    self.promptTextView.automaticQuoteSubstitutionEnabled = NO;
    self.promptTextView.automaticDashSubstitutionEnabled = NO;
    self.promptTextView.richText = NO;
    scroll.documentView = self.promptTextView;
    [scroll.heightAnchor constraintEqualToConstant:120].active = YES;
    [stack addArrangedSubview:scroll];

    // Launch + hotkey options.
    self.launchAtLoginCheckbox = [NSButton checkboxWithTitle:@"开机自动启动" target:nil action:nil];
    self.silentLaunchCheckbox = [NSButton checkboxWithTitle:@"开机自启时静默启动（仅驻留菜单栏）"
                                                    target:nil action:nil];
    self.hotkeyCheckbox = [NSButton checkboxWithTitle:@"启用全局快捷键 ⌘⇧6" target:nil action:nil];
    [stack addArrangedSubview:self.launchAtLoginCheckbox];
    [stack addArrangedSubview:self.silentLaunchCheckbox];
    [stack addArrangedSubview:self.hotkeyCheckbox];

    // Buttons.
    NSButton *saveButton = [NSButton buttonWithTitle:@"保存配置" target:self action:@selector(saveClicked:)];
    saveButton.keyEquivalent = @"\r";
    NSButton *captureButton = [NSButton buttonWithTitle:@"立即截图 OCR"
                                                 target:self
                                                 action:@selector(captureClicked:)];
    NSButton *closeButton = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closeClicked:)];
    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[saveButton, captureButton, closeButton]];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 10;
    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:buttonRow];

    // Config path hint.
    NSTextField *hint = [self makeLabel:[NSString stringWithFormat:@"配置文件：%@",
                                            OCRSettings.configFileURL.path]
                                   bold:NO];
    hint.textColor = [NSColor tertiaryLabelColor];
    hint.font = [NSFont systemFontOfSize:10];
    hint.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [stack addArrangedSubview:hint];

    // Make full-width rows span the stack width.
    for (NSView *view in @[modelRow, formatRow, scroll, hint]) {
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    for (NSView *view in stack.arrangedSubviews) {
        if ([view isKindOfClass:[NSStackView class]] &&
            ((NSStackView *)view).orientation == NSUserInterfaceLayoutOrientationHorizontal &&
            view != buttonRow) {
            [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        }
    }
}

- (NSView *)sectionSpacerWithTitle:(NSString *)titleText {
    NSTextField *label = [self makeLabel:titleText bold:YES];
    return label;
}

- (void)loadValues {
    NSUInteger modelIndex = [self.modelOrder indexOfObject:self.settings.model];
    if (modelIndex == NSNotFound) {
        modelIndex = [self.modelOrder indexOfObject:OCRDefaultModel];
    }
    if (modelIndex != NSNotFound) {
        [self.modelPopUp selectItemAtIndex:modelIndex];
    }

    NSUInteger formatIndex = [self.formatOrder indexOfObject:self.settings.format];
    if (formatIndex == NSNotFound) {
        formatIndex = [self.formatOrder indexOfObject:OCRDefaultFormat];
    }
    if (formatIndex != NSNotFound) {
        [self.formatPopUp selectItemAtIndex:formatIndex];
    }

    self.dashScopeField.stringValue = self.settings.dashScopeKey ?: @"";
    self.mimoField.stringValue = self.settings.mimoKey ?: @"";
    self.openRouterField.stringValue = self.settings.openRouterKey ?: @"";
    self.promptTextView.string = self.settings.customPrompt ?: @"";
    self.launchAtLoginCheckbox.state = self.settings.launchAtLogin ? NSControlStateValueOn : NSControlStateValueOff;
    self.silentLaunchCheckbox.state = self.settings.silentLaunch ? NSControlStateValueOn : NSControlStateValueOff;
    self.hotkeyCheckbox.state = self.settings.hotkeyEnabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyToSettings {
    NSInteger modelIndex = self.modelPopUp.indexOfSelectedItem;
    if (modelIndex >= 0 && modelIndex < (NSInteger)self.modelOrder.count) {
        self.settings.model = self.modelOrder[modelIndex];
    }
    NSInteger formatIndex = self.formatPopUp.indexOfSelectedItem;
    if (formatIndex >= 0 && formatIndex < (NSInteger)self.formatOrder.count) {
        self.settings.format = self.formatOrder[formatIndex];
    }
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    self.settings.dashScopeKey = [self.dashScopeField.stringValue stringByTrimmingCharactersInSet:ws];
    self.settings.mimoKey = [self.mimoField.stringValue stringByTrimmingCharactersInSet:ws];
    self.settings.openRouterKey = [self.openRouterField.stringValue stringByTrimmingCharactersInSet:ws];
    self.settings.customPrompt = [self.promptTextView.string stringByTrimmingCharactersInSet:ws];
    self.settings.launchAtLogin = self.launchAtLoginCheckbox.state == NSControlStateValueOn;
    self.settings.silentLaunch = self.silentLaunchCheckbox.state == NSControlStateValueOn;
    self.settings.hotkeyEnabled = self.hotkeyCheckbox.state == NSControlStateValueOn;
}

#pragma mark - Actions

- (void)persist {
    [self applyToSettings];
    [self.settings save];
    if (self.onSaved) {
        self.onSaved();
    }
}

- (void)saveClicked:(id)sender {
    [self persist];
}

- (void)captureClicked:(id)sender {
    [self persist];
    [self.window orderOut:nil];
    if (self.onCaptureNow) {
        self.onCaptureNow();
    }
}

- (void)closeClicked:(id)sender {
    [self.window orderOut:nil];
}

- (void)showPanel {
    [self loadValues];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

@end
