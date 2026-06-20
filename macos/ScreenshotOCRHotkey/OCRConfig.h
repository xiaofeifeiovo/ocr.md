#import <Foundation/Foundation.h>

// Native port of the model/prompt configuration from ocr_core.py so the macOS
// app stays in sync with the web and Windows builds without bundling Python.

NS_ASSUME_NONNULL_BEGIN

extern NSString * const OCRDefaultModel;
extern NSString * const OCRDefaultFormat;

// Ordered list of model identifiers, matching the web UI order.
NSArray<NSString *> *OCRModelOrder(void);

// Per-model metadata dictionary with keys:
//   id, base_url, display, key_name, key_envs (NSArray<NSString *>),
//   thinking (NSNumber bool), stream (NSNumber bool), modalities (NSNumber bool)
// Returns nil for unknown models.
NSDictionary *_Nullable OCRModelInfo(NSString *modelId);

NSString *OCRModelDisplayName(NSString *modelId);

// Ordered output formats and their localized labels.
NSArray<NSString *> *OCRFormatOrder(void);
NSString *OCRFormatLabel(NSString *format);

// System prompt for a given output format, or nil for unknown formats.
NSString *_Nullable OCRSystemPrompt(NSString *format);

NS_ASSUME_NONNULL_END
