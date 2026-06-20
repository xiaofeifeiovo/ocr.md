#import <Cocoa/Cocoa.h>

@class OCRSettings;

NS_ASSUME_NONNULL_BEGIN

// The configuration panel: model, output format, API keys, custom prompt, and
// launch options. Mirrors the Windows app's settings window.
@interface SettingsWindowController : NSWindowController

- (instancetype)initWithSettings:(OCRSettings *)settings;

// Called after the user saves; the settings object has been updated and
// persisted. The app re-applies the hotkey and login item here.
@property(nonatomic, copy, nullable) void (^onSaved)(void);

// Called when the user clicks "立即截图 OCR"; settings are already saved.
@property(nonatomic, copy, nullable) void (^onCaptureNow)(void);

- (void)showPanel;

@end

NS_ASSUME_NONNULL_END
