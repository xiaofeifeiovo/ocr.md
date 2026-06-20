#import "OCRConfig.h"

NSString * const OCRDefaultModel = @"google/gemini-3.1-flash-lite";
NSString * const OCRDefaultFormat = @"tex";

static NSString * const DashScopeBaseURL = @"https://dashscope.aliyuncs.com/compatible-mode/v1";
static NSString * const MiMoBaseURL = @"https://token-plan-cn.xiaomimimo.com/v1";
static NSString * const OpenRouterBaseURL = @"https://openrouter.ai/api/v1";

static NSArray<NSString *> *DashScopeKeyEnvs(void) {
    return @[ @"DASHSCOPE_API_KEY", @"QWEN_API_KEY", @"ALIYUN_DASHSCOPE_API_KEY" ];
}

static NSArray<NSString *> *MiMoKeyEnvs(void) {
    return @[ @"MIMO_API_KEY", @"XIAOMI_MIMO_API_KEY" ];
}

static NSArray<NSString *> *OpenRouterKeyEnvs(void) {
    return @[ @"OPENROUTER_API_KEY" ];
}

static NSDictionary *MakeModel(NSString *modelId,
                               NSString *baseURL,
                               NSString *display,
                               NSString *keyName,
                               NSArray<NSString *> *keyEnvs,
                               BOOL thinking,
                               BOOL stream,
                               BOOL modalities) {
    return @{
        @"id": modelId,
        @"base_url": baseURL,
        @"display": display,
        @"key_name": keyName,
        @"key_envs": keyEnvs,
        @"thinking": @(thinking),
        @"stream": @(stream),
        @"modalities": @(modalities),
    };
}

static NSArray<NSDictionary *> *AllModels(void) {
    static NSArray<NSDictionary *> *models;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        models = @[
            MakeModel(@"qwen3-vl-plus", DashScopeBaseURL, @"高精度（Qwen3-VL）",
                      @"DASHSCOPE_API_KEY", DashScopeKeyEnvs(), YES, NO, NO),
            MakeModel(@"qwen3-vl-flash", DashScopeBaseURL, @"快速（Qwen3-VL）",
                      @"DASHSCOPE_API_KEY", DashScopeKeyEnvs(), YES, NO, NO),
            MakeModel(@"qwen3.5-plus", DashScopeBaseURL, @"最佳质量（Qwen3.5）",
                      @"DASHSCOPE_API_KEY", DashScopeKeyEnvs(), YES, NO, NO),
            MakeModel(@"qwen3.5-flash", DashScopeBaseURL, @"快速（Qwen3.5）",
                      @"DASHSCOPE_API_KEY", DashScopeKeyEnvs(), YES, NO, NO),
            MakeModel(@"qwen3.5-omni-flash", DashScopeBaseURL, @"多模态快速（Qwen3.5-Omni）",
                      @"DASHSCOPE_API_KEY", DashScopeKeyEnvs(), NO, YES, YES),
            MakeModel(@"qwen-vl-plus", DashScopeBaseURL, @"均衡（Qwen2.5-VL）",
                      @"DASHSCOPE_API_KEY", DashScopeKeyEnvs(), YES, NO, NO),
            MakeModel(@"qwen-vl-max", DashScopeBaseURL, @"高精度（Qwen2.5-VL）",
                      @"DASHSCOPE_API_KEY", DashScopeKeyEnvs(), YES, NO, NO),
            MakeModel(@"mimo-v2.5", MiMoBaseURL, @"MiMo v2.5",
                      @"MIMO_API_KEY", MiMoKeyEnvs(), NO, NO, NO),
            MakeModel(@"google/gemini-3.1-flash-lite", OpenRouterBaseURL, @"Gemini Flash Lite",
                      @"OPENROUTER_API_KEY", OpenRouterKeyEnvs(), NO, NO, NO),
        ];
    });
    return models;
}

static NSDictionary<NSString *, NSDictionary *> *ModelIndex(void) {
    static NSDictionary<NSString *, NSDictionary *> *index;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (NSDictionary *model in AllModels()) {
            map[model[@"id"]] = model;
        }
        index = [map copy];
    });
    return index;
}

NSArray<NSString *> *OCRModelOrder(void) {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (NSDictionary *model in AllModels()) {
        [ids addObject:model[@"id"]];
    }
    return [ids copy];
}

NSDictionary *OCRModelInfo(NSString *modelId) {
    if (modelId == nil) {
        return nil;
    }
    return ModelIndex()[modelId];
}

NSString *OCRModelDisplayName(NSString *modelId) {
    NSDictionary *info = OCRModelInfo(modelId);
    return info ? info[@"display"] : (modelId ?: @"");
}

NSArray<NSString *> *OCRFormatOrder(void) {
    return @[ @"plain", @"markdown", @"tex", @"formula" ];
}

NSString *OCRFormatLabel(NSString *format) {
    static NSDictionary<NSString *, NSString *> *labels;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        labels = @{
            @"plain": @"纯文本",
            @"markdown": @"Markdown",
            @"tex": @"LaTeX",
            @"formula": @"公式识别",
        };
    });
    return labels[format] ?: format;
}

NSString *OCRSystemPrompt(NSString *format) {
    static NSDictionary<NSString *, NSString *> *prompts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prompts = @{
            @"markdown":
                @"你是一个严谨的 OCR 转写工具，任务是将图片中的可见内容转换为忠实的 Markdown。\n"
                @"严格规则：\n"
                @"- 只输出 Markdown 正文，不要包含开场白、总结、解释或代码块包裹\n"
                @"- 按阅读顺序保留标题、段落、列表、表格、脚注标记、引用和数学公式\n"
                @"- 表格优先使用 Markdown 表格；结构过复杂时用清晰的纯文本排版\n"
                @"- 行内公式使用 $...$，独立成行或多行公式使用 $$...$$\n"
                @"- 对无法确定的字符保持克制，可用 [?] 标记，不要自行补写原文没有的内容\n"
                @"- 不要遗漏任何可见文字、数字、符号或注释",
            @"tex":
                @"你是一个严谨的 OCR 转写工具，任务是将图片中的内容转换为可直接插入 LaTeX 文档的正文片段。\n"
                @"严格规则：\n"
                @"- 只输出 LaTeX 正文片段，不要包含开场白、总结、解释或代码块包裹\n"
                @"- 输出内容默认已经位于 \\begin{document} 内部；不要输出 \\documentclass、导言区、\\begin{document} 或 \\end{document}\n"
                @"- 保留章节标题、段落、列表、表格、脚注、编号、引用标记和公式等原有结构\n"
                @"- 行内公式仅在原文确为行内数学时克制使用 $...$ 包裹\n"
                @"- 独立成行、居中展示或多行推导的公式使用 $$...$$ 包裹；不要使用 \\(...\\) 或 \\[...\\]\n"
                @"- 不要把普通正文整段放进数学环境；文字与公式混排时保持原本语义\n"
                @"- 表格优先使用 tabular、longtable、booktabs 等正文环境，不要额外引入宏包\n"
                @"- 对无法确定的字符保持克制，可用 \\text{[?]} 标记，不要自行补写原文没有的内容\n"
                @"- 不要遗漏任何可见文字、数字、符号或注释",
            @"formula":
                @"你是一个专业的数学 OCR 工具，任务是将图片中的手写或打印公式转换为 LaTeX 正文片段。\n"
                @"严格规则：\n"
                @"- 只输出 LaTeX，不要包含开场白、总结、解释或代码块包裹\n"
                @"- 输出内容默认已经位于 \\begin{document} 内部；不要输出导言区或 document 环境\n"
                @"- 单个独立公式或主要公式使用 $$...$$ 包裹；短小的行内公式只有在原图确为行内时使用 $...$\n"
                @"- 多行推导保持原有换行，可在 $$...$$ 内使用 aligned、alignedat、cases、matrix 等环境\n"
                @"- 准确识别积分、求和、分式、根号、上下标、希腊字母、矩阵、向量、集合符号和标点\n"
                @"- 手写笔迹不规整时根据数学上下文谨慎推断；无法确定的符号用 \\text{[?]} 标记\n"
                @"- 不要遗漏任何公式内容，也不要添加原图中没有的内容",
            @"plain":
                @"你是一个严谨的 OCR 转写工具，任务是将图片中的可见内容提取为纯文本。\n"
                @"严格规则：\n"
                @"- 只输出纯文本，不要包含开场白、总结、解释、Markdown 语法或代码块\n"
                @"- 按阅读顺序保留段落、换行、列表层级和表格的大致排版\n"
                @"- 数学、单位、标点和大小写尽量按原样转写，不要改写成解释性文字\n"
                @"- 对无法确定的字符保持克制，可用 [?] 标记\n"
                @"- 不要遗漏任何可见文字，也不要添加原文中没有的内容",
        };
    });
    return prompts[format];
}
