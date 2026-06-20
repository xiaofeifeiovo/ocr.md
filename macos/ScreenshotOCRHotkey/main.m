#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        // NSApplication.delegate is a weak reference, so keep the delegate alive
        // for the whole process lifetime with a static strong reference.
        static AppDelegate *delegate;
        delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
