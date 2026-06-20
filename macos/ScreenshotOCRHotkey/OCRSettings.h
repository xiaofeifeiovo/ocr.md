#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// User configuration, persisted as JSON under Application Support. The JSON
// shape mirrors the Windows app's config.json so the two stay easy to compare.
@interface OCRSettings : NSObject

@property(nonatomic, copy) NSString *model;
@property(nonatomic, copy) NSString *format;
@property(nonatomic, copy) NSString *customPrompt;
@property(nonatomic, copy) NSString *dashScopeKey;
@property(nonatomic, copy) NSString *mimoKey;
@property(nonatomic, copy) NSString *openRouterKey;
@property(nonatomic, assign) BOOL launchAtLogin;
@property(nonatomic, assign) BOOL silentLaunch;
@property(nonatomic, assign) BOOL hotkeyEnabled;

+ (instancetype)loadSettings;
- (void)save;

// Resolves the API key for the model's provider from the saved keys, falling
// back to matching environment variables. Returns @"" when none is set.
- (NSString *)apiKeyForModel:(NSString *)modelId;
- (BOOL)hasKeyForModel:(NSString *)modelId;

+ (NSURL *)configFileURL;

@end

NS_ASSUME_NONNULL_END
