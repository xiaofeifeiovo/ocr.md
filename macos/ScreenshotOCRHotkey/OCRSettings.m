#import "OCRSettings.h"
#import "OCRConfig.h"

static NSString *TrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [(NSString *)value stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@implementation OCRSettings

+ (NSURL *)supportDirectoryURL {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *base = [fm URLForDirectory:NSApplicationSupportDirectory
                            inDomain:NSUserDomainMask
                   appropriateForURL:nil
                              create:YES
                               error:NULL];
    NSURL *dir = [base URLByAppendingPathComponent:@"ScreenshotOCR" isDirectory:YES];
    [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

+ (NSURL *)configFileURL {
    return [[self supportDirectoryURL] URLByAppendingPathComponent:@"config.json"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _model = [OCRDefaultModel copy];
        _format = [OCRDefaultFormat copy];
        _customPrompt = @"";
        _dashScopeKey = @"";
        _mimoKey = @"";
        _openRouterKey = @"";
        _launchAtLogin = NO;
        _silentLaunch = NO;
        _hotkeyEnabled = YES;
    }
    return self;
}

+ (instancetype)loadSettings {
    OCRSettings *settings = [[OCRSettings alloc] init];
    NSData *data = [NSData dataWithContentsOfURL:[self configFileURL]];
    if (data == nil) {
        return settings;
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return settings;
    }

    NSString *model = TrimmedString(json[@"model"]);
    if (model.length && OCRModelInfo(model) != nil) {
        settings.model = model;
    }
    NSString *format = TrimmedString(json[@"format"]);
    if (format.length && OCRSystemPrompt(format) != nil) {
        settings.format = format;
    }
    if ([json[@"custom_prompt"] isKindOfClass:[NSString class]]) {
        settings.customPrompt = json[@"custom_prompt"];
    }

    NSDictionary *keys = json[@"api_keys"];
    if ([keys isKindOfClass:[NSDictionary class]]) {
        settings.dashScopeKey = TrimmedString(keys[@"DASHSCOPE_API_KEY"]);
        settings.mimoKey = TrimmedString(keys[@"MIMO_API_KEY"]);
        settings.openRouterKey = TrimmedString(keys[@"OPENROUTER_API_KEY"]);
    }

    if ([json[@"launch_at_login"] isKindOfClass:[NSNumber class]]) {
        settings.launchAtLogin = [json[@"launch_at_login"] boolValue];
    }
    if ([json[@"silent_launch_at_login"] isKindOfClass:[NSNumber class]]) {
        settings.silentLaunch = [json[@"silent_launch_at_login"] boolValue];
    }
    if ([json[@"hotkey_enabled"] isKindOfClass:[NSNumber class]]) {
        settings.hotkeyEnabled = [json[@"hotkey_enabled"] boolValue];
    }
    return settings;
}

- (void)save {
    NSDictionary *json = @{
        @"model": self.model ?: OCRDefaultModel,
        @"format": self.format ?: OCRDefaultFormat,
        @"custom_prompt": self.customPrompt ?: @"",
        @"api_keys": @{
            @"DASHSCOPE_API_KEY": self.dashScopeKey ?: @"",
            @"MIMO_API_KEY": self.mimoKey ?: @"",
            @"OPENROUTER_API_KEY": self.openRouterKey ?: @"",
        },
        @"launch_at_login": @(self.launchAtLogin),
        @"silent_launch_at_login": @(self.silentLaunch),
        @"hotkey_enabled": @(self.hotkeyEnabled),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:json
                                                  options:NSJSONWritingPrettyPrinted
                                                    error:NULL];
    [data writeToURL:[OCRSettings configFileURL] atomically:YES];
}

- (NSString *)savedKeyForName:(NSString *)keyName {
    if ([keyName isEqualToString:@"DASHSCOPE_API_KEY"]) {
        return self.dashScopeKey ?: @"";
    }
    if ([keyName isEqualToString:@"MIMO_API_KEY"]) {
        return self.mimoKey ?: @"";
    }
    if ([keyName isEqualToString:@"OPENROUTER_API_KEY"]) {
        return self.openRouterKey ?: @"";
    }
    return @"";
}

- (NSString *)apiKeyForModel:(NSString *)modelId {
    NSDictionary *info = OCRModelInfo(modelId);
    if (info == nil) {
        return @"";
    }

    NSString *saved = TrimmedString([self savedKeyForName:info[@"key_name"]]);
    if (saved.length) {
        return saved;
    }

    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    for (NSString *envName in (NSArray<NSString *> *)info[@"key_envs"]) {
        NSString *value = TrimmedString(env[envName]);
        if (value.length) {
            return value;
        }
    }
    return @"";
}

- (BOOL)hasKeyForModel:(NSString *)modelId {
    return [self apiKeyForModel:modelId].length > 0;
}

@end
