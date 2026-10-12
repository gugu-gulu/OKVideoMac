#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
int main(int argc, char **argv) { @autoreleasepool {
  if(argc!=2)return 64;
  pid_t pid=(pid_t)atoi(argv[1]);
  NSArray *windows=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID));
  unsigned count=0;
  for(NSDictionary *w in windows) {
    if([w[(id)kCGWindowOwnerPID] intValue]!=pid || [w[(id)kCGWindowLayer] intValue]!=0)continue;
    CGRect r; if(CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&r) && r.size.width>200 && r.size.height>200)count++;
  }
  printf("%u\n",count); return 0;
}}
