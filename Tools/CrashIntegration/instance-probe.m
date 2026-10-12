#import <AppKit/AppKit.h>
int main(int argc, char **argv) { @autoreleasepool {
    if (argc==2 && strcmp(argv[1],"serve")==0) {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        puts("ready"); fflush(stdout); [NSApp run]; return 0;
    }
    if (argc!=3) return 64;
    if (strcmp(argv[1],"list")==0) {
        NSMutableArray *pids=[NSMutableArray array];
        for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:[NSString stringWithUTF8String:argv[2]]]) {
            if(!app.terminated) [pids addObject:@(app.processIdentifier)];
        }
        NSData *data=[NSJSONSerialization dataWithJSONObject:pids options:0 error:nil];
        fwrite(data.bytes,1,data.length,stdout);return 0;
    }
    if (strcmp(argv[1],"quit")==0) {
        NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:atoi(argv[2])];
        return [app terminate] ? 0 : 2;
    }
    return 64;
}}
