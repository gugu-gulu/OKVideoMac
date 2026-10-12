#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
static unsigned visited=0;
static AXUIElementRef dialog(AXUIElementRef element,unsigned depth) {
    if(depth>10 || ++visited>2000)return NULL;
    CFTypeRef raw=NULL;
    NSString *role=nil,*subrole=nil;
    if(AXUIElementCopyAttributeValue(element,kAXRoleAttribute,&raw)==kAXErrorSuccess)role=CFBridgingRelease(raw);
    if(AXUIElementCopyAttributeValue(element,kAXSubroleAttribute,&raw)==kAXErrorSuccess)subrole=CFBridgingRelease(raw);
    if([role isEqualToString:(__bridge NSString *)kAXSheetRole] || [subrole isEqualToString:(__bridge NSString *)kAXDialogSubrole])return (AXUIElementRef)CFRetain(element);
    for(NSString *key in @[@"AXWindows",@"AXChildren"]){
        if(AXUIElementCopyAttributeValue(element,(__bridge CFStringRef)key,&raw)!=kAXErrorSuccess)continue;
        NSArray *children=CFBridgingRelease(raw);
        if(![children isKindOfClass:[NSArray class]])continue;
        for(id child in children){AXUIElementRef result=dialog((__bridge AXUIElementRef)child,depth+1);if(result)return result;}
    }
    return NULL;
}
int main(int argc,char **argv){@autoreleasepool {
    if(argc!=2)return 64;
    NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:atoi(argv[1])];
    NSString *reportedPath=app.bundleURL.path;
    char *resolved=realpath(reportedPath.fileSystemRepresentation,NULL);
    NSString *path=resolved ? [NSString stringWithUTF8String:resolved] : nil;
    free(resolved);
    if(![path hasPrefix:@"/private/tmp/OKVideoMac-CrashIntegration/"])return 65;
    if(!AXIsProcessTrusted())return 66;
    AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier);
    AXUIElementRef sheet=dialog(root,0);CFRelease(root);
    if(!sheet){puts("no-error-dialog");return 2;}
    CFTypeRef button=NULL;
    AXError result=AXUIElementCopyAttributeValue(sheet,kAXDefaultButtonAttribute,&button);
    CFRelease(sheet);
    if(result!=kAXErrorSuccess || !button)return 3;
    result=AXUIElementPerformAction((AXUIElementRef)button,kAXPressAction);CFRelease(button);
    printf("default-error-button-press=%d\n",result);
    return result==kAXErrorSuccess ? 0 : 4;
}}
