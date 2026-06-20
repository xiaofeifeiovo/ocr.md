#import "OCREngine.h"
#import "OCRConfig.h"
#import "OCRSettings.h"

static NSString * const OCRErrorDomain = @"ScreenshotOCR";

@implementation OCREngine

+ (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:OCRErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"OCR 失败"}];
}

+ (void)finishOnMain:(void (^)(NSString *_Nullable, NSError *_Nullable))completion
                text:(NSString *_Nullable)text
               error:(NSError *_Nullable)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(text, error);
    });
}

+ (void)recognizeImageData:(NSData *)pngData
                  settings:(OCRSettings *)settings
                completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion {
    NSString *modelId = settings.model.length ? settings.model : OCRDefaultModel;
    NSDictionary *info = OCRModelInfo(modelId);
    if (info == nil) {
        [self finishOnMain:completion text:nil
                     error:[self errorWithMessage:[NSString stringWithFormat:@"未知模型：%@", modelId]]];
        return;
    }

    NSString *apiKey = [settings apiKeyForModel:modelId];
    if (apiKey.length == 0) {
        [self finishOnMain:completion text:nil
                     error:[self errorWithMessage:@"缺少 API Key，请在设置中填写当前模型对应的密钥。"]];
        return;
    }

    NSString *format = settings.format.length ? settings.format : OCRDefaultFormat;
    NSString *customPrompt = [settings.customPrompt
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *systemPrompt = customPrompt.length ? customPrompt : OCRSystemPrompt(format);
    if (systemPrompt == nil) {
        systemPrompt = OCRSystemPrompt(OCRDefaultFormat);
    }

    BOOL stream = [info[@"stream"] boolValue];
    NSString *base64 = [pngData base64EncodedStringWithOptions:0];
    NSString *dataURL = [@"data:image/png;base64," stringByAppendingString:base64];

    NSDictionary *userContentImage = @{
        @"type": @"image_url",
        @"image_url": @{@"url": dataURL},
    };
    NSDictionary *userContentText = @{
        @"type": @"text",
        @"text": @"请处理这张图片。",
    };

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = modelId;
    body[@"messages"] = @[
        @{@"role": @"system", @"content": systemPrompt},
        @{@"role": @"user", @"content": @[userContentImage, userContentText]},
    ];
    body[@"stream"] = @(stream);
    body[@"temperature"] = [format isEqualToString:@"formula"] ? @(0.01) : @(0.1);
    if ([info[@"thinking"] boolValue]) {
        // The Python client passes this through extra_body, which lands at the
        // top level of the request payload.
        body[@"enable_thinking"] = @(NO);
    }
    if ([info[@"modalities"] boolValue]) {
        body[@"modalities"] = @[@"text"];
    }

    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (bodyData == nil) {
        [self finishOnMain:completion text:nil
                     error:[self errorWithMessage:@"无法构造请求内容。"]];
        return;
    }

    NSString *endpoint = [info[@"base_url"] stringByAppendingString:@"/chat/completions"];
    NSURL *url = [NSURL URLWithString:endpoint];
    if (url == nil) {
        [self finishOnMain:completion text:nil
                     error:[self errorWithMessage:[NSString stringWithFormat:@"无效的接口地址：%@", endpoint]]];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    request.timeoutInterval = 180.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:apiKey]
        forHTTPHeaderField:@"Authorization"];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:request
                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                [self finishOnMain:completion text:nil
                             error:[self errorWithMessage:
                                        [NSString stringWithFormat:@"网络请求失败：%@",
                                            error.localizedDescription]]];
                return;
            }

            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (http.statusCode < 200 || http.statusCode >= 300) {
                NSString *snippet = [self snippetFromData:data];
                [self finishOnMain:completion text:nil
                             error:[self errorWithMessage:
                                        [NSString stringWithFormat:@"接口返回 %ld：%@",
                                            (long)http.statusCode, snippet]]];
                return;
            }

            NSString *text = stream ? [self textFromStreamData:data]
                                    : [self textFromJSONData:data];
            if (text == nil) {
                [self finishOnMain:completion text:nil
                             error:[self errorWithMessage:@"无法解析接口返回内容。"]];
                return;
            }
            [self finishOnMain:completion text:text error:nil];
        }];
    [task resume];
}

+ (NSString *)snippetFromData:(NSData *)data {
    if (data.length == 0) {
        return @"无响应内容";
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length > 300) {
        text = [[text substringToIndex:300] stringByAppendingString:@"…"];
    }
    return text.length ? text : @"无响应内容";
}

+ (NSString *)textFromJSONData:(NSData *)data {
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSArray *choices = json[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) {
        return nil;
    }
    NSDictionary *message = choices[0][@"message"];
    if (![message isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id content = message[@"content"];
    return [content isKindOfClass:[NSString class]] ? content : @"";
}

+ (NSString *)textFromStreamData:(NSData *)data {
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (raw == nil) {
        return nil;
    }

    NSMutableString *result = [NSMutableString string];
    for (NSString *rawLine in [raw componentsSeparatedByString:@"\n"]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
        if (![line hasPrefix:@"data:"]) {
            continue;
        }
        NSString *payload = [[line substringFromIndex:5]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (payload.length == 0 || [payload isEqualToString:@"[DONE]"]) {
            continue;
        }

        NSData *chunkData = [payload dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *chunk = [NSJSONSerialization JSONObjectWithData:chunkData options:0 error:NULL];
        if (![chunk isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSArray *choices = chunk[@"choices"];
        if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) {
            continue;
        }
        NSDictionary *delta = choices[0][@"delta"];
        id content = [delta isKindOfClass:[NSDictionary class]] ? delta[@"content"] : nil;
        if ([content isKindOfClass:[NSString class]]) {
            [result appendString:content];
        }
    }
    return result;
}

+ (NSString *)stripMarkdownFences:(NSString *)text {
    NSString *cleaned = [text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSRegularExpression *leading =
        [NSRegularExpression regularExpressionWithPattern:@"^```(?:latex|tex)?\\s*"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:NULL];
    cleaned = [leading stringByReplacingMatchesInString:cleaned
                                                options:0
                                                  range:NSMakeRange(0, cleaned.length)
                                           withTemplate:@""];

    NSRegularExpression *trailing =
        [NSRegularExpression regularExpressionWithPattern:@"\\s*```$"
                                                  options:0
                                                    error:NULL];
    cleaned = [trailing stringByReplacingMatchesInString:cleaned
                                                 options:0
                                                   range:NSMakeRange(0, cleaned.length)
                                            withTemplate:@""];

    return [cleaned stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
