#import <Foundation/Foundation.h>

@class OCRSettings;

NS_ASSUME_NONNULL_BEGIN

// Performs OCR by calling the OpenAI-compatible chat-completions endpoint for the
// configured model, mirroring ocr_core.ocr_image_bytes. The completion handler is
// always invoked on the main queue.
@interface OCREngine : NSObject

+ (void)recognizeImageData:(NSData *)pngData
                  settings:(OCRSettings *)settings
                completion:(void (^)(NSString *_Nullable text, NSError *_Nullable error))completion;

// Removes a single leading ```/```latex/```tex fence and trailing ``` fence,
// matching ocr_core.strip_markdown_fences.
+ (NSString *)stripMarkdownFences:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
