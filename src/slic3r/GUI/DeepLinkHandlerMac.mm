// macOS deep-link delivery shim for orcaslicer:// URLs.
//
// Background: after upgrading to wxWidgets 3.3.2 (OrcaSlicer commit 8248b063),
// cold-launching the app via an orcaslicer:// link on macOS Tahoe drops the URL
// before wxWidgets's kAEGetURL handler can dispatch it - see OrcaSlicer #13119.
// Registering our own NSAppleEventManager handler and an application:openURLs:
// method on the live NSApp delegate makes the delivery independent of
// wxNSAppController's timing.

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include "DeepLinkHandlerMac.h"
#include "GUI_App.hpp"

#include <atomic>

#include <wx/string.h>

@interface OrcaDeepLinkHandler : NSObject
@property (atomic, copy) NSString *pendingURL;
+ (instancetype)sharedHandler;
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
- (void)dispatchURLString:(NSString *)url;
@end

namespace Slic3r { namespace GUI {
// Set to true once GUI_App is initialized enough that MacOpenURL can do
// useful work; until then incoming URLs are queued on the shared handler.
static std::atomic<bool> g_app_ready{false};

static void dispatch_url_to_app(NSString *url)
{
    if (url.length == 0) return;
    wxString wx_url = wxString::FromUTF8([url UTF8String]);
    // MacOpenURL must run on the main/GUI thread.
    if ([NSThread isMainThread]) {
        wxGetApp().MacOpenURL(wx_url);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            wxGetApp().MacOpenURL(wx_url);
        });
    }
}
} } // namespace Slic3r::GUI

@implementation OrcaDeepLinkHandler

+ (instancetype)sharedHandler
{
    static OrcaDeepLinkHandler *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[OrcaDeepLinkHandler alloc] init]; });
    return instance;
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply
{
    (void)reply;
    NSString *url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    [self dispatchURLString:url];
}

- (void)dispatchURLString:(NSString *)url
{
    if (url.length == 0) return;
    if (Slic3r::GUI::g_app_ready.load()) {
        Slic3r::GUI::dispatch_url_to_app(url);
    } else {
        // Keep only the most recent URL - cold launches deliver at most one.
        self.pendingURL = url;
    }
}

@end

// Method implementation injected onto whatever class is acting as the
// NSApplication delegate. macOS 10.13+ prefers application:openURLs: over
// the legacy kAEGetURL Apple Event, so implementing it covers Tahoe's
// modern delivery path.
static void orca_application_openURLs(id self, SEL _cmd, NSApplication *app, NSArray<NSURL *> *urls)
{
    (void)self; (void)_cmd; (void)app;
    OrcaDeepLinkHandler *handler = [OrcaDeepLinkHandler sharedHandler];
    for (NSURL *url in urls) {
        [handler dispatchURLString:[url absoluteString]];
    }
}

namespace Slic3r { namespace GUI {

void register_mac_deep_link_handler()
{
    OrcaDeepLinkHandler *handler = [OrcaDeepLinkHandler sharedHandler];

    // Last writer wins for NSAppleEventManager handlers, so calling this
    // after wxWidgets has installed its own handleGetURLEvent: takes over
    // the kAEGetURL delivery.
    [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:handler
            andSelector:@selector(handleGetURLEvent:withReplyEvent:)
          forEventClass:kInternetEventClass
             andEventID:kAEGetURL];

    // Inject application:openURLs: onto the live delegate class (if any).
    // wxWidgets does not implement this selector, so class_addMethod will
    // succeed and the delegate will start receiving URLs through the
    // modern delivery path.
    id delegate = [[NSApplication sharedApplication] delegate];
    if (delegate) {
        Class cls = object_getClass(delegate);
        SEL sel = @selector(application:openURLs:);
        if (cls && !class_respondsToSelector(cls, sel)) {
            // v@:@@  --> void return, self, _cmd, NSApplication*, NSArray*
            class_addMethod(cls, sel, (IMP)orca_application_openURLs, "v@:@@");
        }
    }
}

void flush_mac_deep_link_queue()
{
    g_app_ready.store(true);
    OrcaDeepLinkHandler *handler = [OrcaDeepLinkHandler sharedHandler];
    NSString *url = handler.pendingURL;
    if (url) {
        handler.pendingURL = nil;
        dispatch_url_to_app(url);
    }
}

} } // namespace Slic3r::GUI
