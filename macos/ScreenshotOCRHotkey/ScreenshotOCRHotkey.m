#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

#import "GeneratedConfig.h"

static const OSType HotKeySignature =
    ((OSType)'S' << 24) | ((OSType)'O' << 16) | ((OSType)'C' << 8) | (OSType)'R';
static const UInt32 HotKeyIDValue = 1;

static NSString *ShellQuote(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'"
                                                        withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

static NSString *AppleScriptQuote(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\"
                                                        withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\""
                                                 withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, assign) EventHotKeyRef hotKeyRef;
@property(nonatomic, assign) EventHandlerRef eventHandlerRef;
@property(nonatomic, strong) NSTask *runningTask;
- (void)runOCR;
@end

static OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID eventHotKeyID;
    OSStatus status = GetEventParameter(
        event,
        kEventParamDirectObject,
        typeEventHotKeyID,
        NULL,
        sizeof(eventHotKeyID),
        NULL,
        &eventHotKeyID
    );

    if (status == noErr &&
        eventHotKeyID.signature == HotKeySignature &&
        eventHotKeyID.id == HotKeyIDValue) {
        AppDelegate *delegate = (__bridge AppDelegate *)userData;
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate runOCR];
        });
    }

    return noErr;
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self setupStatusMenu];
    [self registerHotKey];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self unregisterHotKey];
}

- (void)setupStatusMenu {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"OCR";

    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItem:[self menuItemWithTitle:@"Run Screenshot OCR" action:@selector(runOCRFromMenu)]];
    [menu addItem:[self menuItemWithTitle:@"Re-register Command-Shift-6" action:@selector(registerHotKeyFromMenu)]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self menuItemWithTitle:@"Install Login Item" action:@selector(installLoginItemFromMenu)]];
    [menu addItem:[self menuItemWithTitle:@"Remove Login Item" action:@selector(removeLoginItemFromMenu)]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self menuItemWithTitle:@"Open Project Folder" action:@selector(openProjectFolder)]];
    [menu addItem:[self menuItemWithTitle:@"Open Log File" action:@selector(openLogFile)]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self menuItemWithTitle:@"Quit" action:@selector(quit)]];

    self.statusItem.menu = menu;
}

- (NSMenuItem *)menuItemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

- (NSString *)scriptPath {
    NSString *environmentPath = NSProcessInfo.processInfo.environment[@"OCR_SCREENSHOT_SCRIPT"];
    if (environmentPath.length > 0) {
        return environmentPath;
    }

    NSString *userDefaultPath = [NSUserDefaults.standardUserDefaults stringForKey:@"OCRScreenshotScript"];
    if (userDefaultPath.length > 0) {
        return userDefaultPath;
    }

    return DefaultScriptPath;
}

- (NSString *)logPath {
    NSURL *logsDirectory = [NSFileManager.defaultManager.homeDirectoryForCurrentUser
        URLByAppendingPathComponent:@"Library/Logs"];
    [NSFileManager.defaultManager createDirectoryAtURL:logsDirectory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    return [logsDirectory URLByAppendingPathComponent:@"ScreenshotOCRHotkey.log"].path;
}

- (void)registerHotKey {
    [self unregisterHotKey];

    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;

    OSStatus installStatus = InstallEventHandler(
        GetApplicationEventTarget(),
        HotKeyHandler,
        1,
        &eventType,
        (__bridge void *)self,
        &_eventHandlerRef
    );

    if (installStatus != noErr) {
        [self showAlertWithTitle:@"Could not install hotkey handler"
                          message:[NSString stringWithFormat:@"macOS returned status %d.", installStatus]];
        return;
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = HotKeySignature;
    hotKeyID.id = HotKeyIDValue;

    OSStatus registerStatus = RegisterEventHotKey(
        kVK_ANSI_6,
        cmdKey | shiftKey,
        hotKeyID,
        GetApplicationEventTarget(),
        0,
        &_hotKeyRef
    );

    if (registerStatus != noErr) {
        [self showAlertWithTitle:@"Command-Shift-6 is not available"
                          message:[NSString stringWithFormat:@"macOS returned status %d. Disable any conflicting screenshot shortcut, then choose Re-register Command-Shift-6 from the OCR menu.", registerStatus]];
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

- (void)registerHotKeyFromMenu {
    [self registerHotKey];
}

- (void)runOCRFromMenu {
    [self runOCR];
}

- (void)runOCR {
    if (self.runningTask != nil && self.runningTask.isRunning) {
        [self showAlertWithTitle:@"OCR is already running"
                          message:@"Wait for the current screenshot OCR task to finish."];
        return;
    }

    NSString *path = self.scriptPath;
    if (![NSFileManager.defaultManager isExecutableFileAtPath:path]) {
        [self showAlertWithTitle:@"OCR script was not found"
                          message:[NSString stringWithFormat:@"Expected executable script at:\n%@\n\nRebuild the app after moving the project.", path]];
        return;
    }

    [self appendLogLine:[NSString stringWithFormat:@"Launching OCR script: %@", path]];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[
        @"-lc",
        [NSString stringWithFormat:@"%@ >> %@ 2>&1", ShellQuote(path), ShellQuote(self.logPath)]
    ];

    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf appendLogLine:[NSString stringWithFormat:@"OCR script exited with status %d", finishedTask.terminationStatus]];
            weakSelf.runningTask = nil;
        });
    };

    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        self.runningTask = task;
    } else {
        [self appendLogLine:[NSString stringWithFormat:@"Failed to launch OCR script: %@", error.localizedDescription]];
        [self showAlertWithTitle:@"Could not launch OCR" message:error.localizedDescription];
    }
}

- (void)installLoginItemFromMenu {
    [self updateLoginItem:YES];
}

- (void)removeLoginItemFromMenu {
    [self updateLoginItem:NO];
}

- (void)updateLoginItem:(BOOL)install {
    NSString *quotedName = AppleScriptQuote(AppDisplayName);
    NSString *quotedPath = AppleScriptQuote(NSBundle.mainBundle.bundlePath);
    NSString *script;

    if (install) {
        script = [NSString stringWithFormat:
            @"tell application \"System Events\"\n"
             "    if not (exists login item %@) then\n"
             "        make login item at end with properties {name:%@, path:%@, hidden:false}\n"
             "    end if\n"
             "end tell",
             quotedName, quotedName, quotedPath];
    } else {
        script = [NSString stringWithFormat:
            @"tell application \"System Events\"\n"
             "    if exists login item %@ then\n"
             "        delete login item %@\n"
             "    end if\n"
             "end tell",
             quotedName, quotedName];
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    task.arguments = @[@"-e", script];

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self showAlertWithTitle:@"Could not update login item" message:error.localizedDescription];
        return;
    }

    [task waitUntilExit];
    if (task.terminationStatus == 0) {
        [self showAlertWithTitle:install ? @"Login item installed" : @"Login item removed"
                          message:install
             ? @"Screenshot OCR will launch after you sign in."
             : @"Screenshot OCR will no longer launch after sign-in."];
    } else {
        [self showAlertWithTitle:@"Could not update login item"
                          message:[NSString stringWithFormat:@"macOS returned status %d. You can add or remove the app manually in System Settings > General > Login Items.", task.terminationStatus]];
    }
}

- (void)openProjectFolder {
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:ProjectPath]];
}

- (void)openLogFile {
    NSString *path = self.logPath;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    }
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]];
}

- (void)quit {
    [NSApp terminate:nil];
}

- (void)appendLogLine:(NSString *)message {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:NSDate.date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = self.logPath;

    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;
    [alert runModal];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
