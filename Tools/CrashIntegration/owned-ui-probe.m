#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
static unsigned visited=0;
static NSMutableArray *rows;
static NSString *match;
static AXUIElementRef found=NULL;
static id value(AXUIElementRef e,NSString *key){CFTypeRef raw=NULL;if(AXUIElementCopyAttributeValue(e,(__bridge CFStringRef)key,&raw)!=kAXErrorSuccess)return nil;return CFBridgingRelease(raw);}
static void walk(AXUIElementRef e,unsigned depth){
 if(depth>16||++visited>3000)return;
 NSMutableDictionary *row=[NSMutableDictionary dictionary];row[@"depth"]=@(depth);
 for(NSString *key in @[@"AXRole",@"AXSubrole",@"AXTitle",@"AXIdentifier",@"AXEnabled",@"AXValue"]){id v=value(e,key);if([v isKindOfClass:[NSString class]]||[v isKindOfClass:[NSNumber class]])row[key]=v;}
 [rows addObject:row];
 if(match && ([row[@"AXIdentifier"] isEqual:match]||[row[@"AXTitle"] isEqual:match]||[row[@"AXSubrole"] isEqual:match]) && [row[@"AXRole"] isEqual:@"AXButton"] && !found)found=(AXUIElementRef)CFRetain(e);
 NSArray *children=value(e,@"AXChildren");if([children isKindOfClass:[NSArray class]])for(id child in children)walk((__bridge AXUIElementRef)child,depth+1);
}
int main(int argc,char **argv){@autoreleasepool {
 if(argc<3)return 64;pid_t pid=atoi(argv[2]);NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
 char *resolved=realpath(app.bundleURL.path.fileSystemRepresentation,NULL);NSString *path=resolved?[NSString stringWithUTF8String:resolved]:nil;free(resolved);
 if(![path hasPrefix:@"/private/tmp/OKVideoMac-CrashIntegration/"])return 65;
 NSString *command=[NSString stringWithUTF8String:argv[1]];
 if([command isEqual:@"keys"]){if(argc!=4||!CGPreflightPostEventAccess())return 66;
   [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];usleep(100000);
   CGKeyCode code=atoi(argv[3]);CGEventRef down=CGEventCreateKeyboardEvent(NULL,code,true),up=CGEventCreateKeyboardEvent(NULL,code,false);
   CGEventSetFlags(down,kCGEventFlagMaskCommand);CGEventSetFlags(up,kCGEventFlagMaskCommand);
   for(int retry=0;retry<10&&NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid;retry+=1){[app activateWithOptions:0];usleep(50000);}
   if(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid){CFRelease(down);CFRelease(up);return 67;}
   CGEventRef modifierDown=CGEventCreateKeyboardEvent(NULL,55,true),modifierUp=CGEventCreateKeyboardEvent(NULL,55,false);
   CGEventSetFlags(modifierDown,kCGEventFlagMaskCommand);CGEventSetFlags(modifierUp,0);
   CGEventPost(kCGHIDEventTap,modifierDown);usleep(50000);
   CGEventPost(kCGHIDEventTap,down);usleep(50000);CGEventPost(kCGHIDEventTap,up);usleep(50000);
   CGEventPost(kCGHIDEventTap,modifierUp);CFRelease(modifierDown);CFRelease(modifierUp);CFRelease(down);CFRelease(up);return 0;
 }
 if([command isEqual:@"capture"]){if(argc<4||argc>5)return 64;
   NSString *output=[NSString stringWithUTF8String:argv[3]];if(![output hasPrefix:@"/private/tmp/OKVideoMac-CrashIntegration/"])return 65;
   NSArray *windows=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID));
   CGWindowID target=0;CGFloat area=0;
   for(NSDictionary *w in windows){if([w[(id)kCGWindowOwnerPID] intValue]!=pid||[w[(id)kCGWindowLayer] intValue]!=0)continue;if(argc==5&&strcmp(argv[4],"front")!=0&&![w[(id)kCGWindowName] isEqual:[NSString stringWithUTF8String:argv[4]]])continue;CGRect r;if(CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds],&r)&&r.size.width*r.size.height>area){area=r.size.width*r.size.height;target=[w[(id)kCGWindowNumber] unsignedIntValue];if(argc==5&&strcmp(argv[4],"front")==0)break;}}
   if(!target)return 2;CGImageRef image=CGWindowListCreateImage(CGRectNull,kCGWindowListOptionIncludingWindow,target,kCGWindowImageBoundsIgnoreFraming|kCGWindowImageBestResolution);if(!image)return 3;
   NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc]initWithCGImage:image];CFRelease(image);NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];return [png writeToFile:output atomically:YES]?0:4;
 }
 if(!AXIsProcessTrusted())return 66;
 rows=[NSMutableArray array];if([command isEqual:@"press"]){if(argc!=4)return 64;match=[NSString stringWithUTF8String:argv[3]];}
 AXUIElementRef root=AXUIElementCreateApplication(pid);
 if([command isEqual:@"menu"] || [command isEqual:@"menu-press"]){
   NSArray *children=value(root,@"AXChildren");AXUIElementRef bar=NULL;
   for(id child in children){if([value((__bridge AXUIElementRef)child,@"AXRole") isEqual:@"AXMenuBar"]){bar=(__bridge AXUIElementRef)child;break;}}
   NSMutableArray *items=[NSMutableArray array];
   for(id top in value(bar,@"AXChildren")){
     if(![value((__bridge AXUIElementRef)top,@"AXTitle") isEqual:app.localizedName])continue;
     for(id menu in value((__bridge AXUIElementRef)top,@"AXChildren"))for(id item in value((__bridge AXUIElementRef)menu,@"AXChildren")){
       AXUIElementRef e=(__bridge AXUIElementRef)item;NSMutableDictionary *row=[NSMutableDictionary dictionary];
       for(NSString *key in @[@"AXTitle",@"AXEnabled",@"AXMenuItemCmdChar"]){id v=value(e,key);if([v isKindOfClass:[NSString class]]||[v isKindOfClass:[NSNumber class]])row[key]=v;}
       [items addObject:row];
       if([command isEqual:@"menu-press"]&&argc==4&&[row[@"AXMenuItemCmdChar"] isEqual:[NSString stringWithUTF8String:argv[3]]]){
         AXError error=AXUIElementPerformAction(e,kAXPressAction);CFRelease(root);return error==kAXErrorSuccess?0:3;
       }
     }
   }
   CFRelease(root);NSData *data=[NSJSONSerialization dataWithJSONObject:items options:0 error:nil];fwrite(data.bytes,1,data.length,stdout);return [command isEqual:@"menu"]?0:2;
 }
 NSArray *windows=value(root,@"AXWindows");
 if([windows isKindOfClass:[NSArray class]])for(id window in windows)walk((__bridge AXUIElementRef)window,0);CFRelease(root);
 if([command isEqual:@"press"]){if(!found)return 2;AXError error=AXUIElementPerformAction(found,kAXPressAction);CFRelease(found);return error==kAXErrorSuccess?0:3;}
 NSData *data=[NSJSONSerialization dataWithJSONObject:rows options:0 error:nil];fwrite(data.bytes,1,data.length,stdout);return 0;
}}
