#ifndef slic3r_GUI_DeepLinkHandlerMac_hpp_
#define slic3r_GUI_DeepLinkHandlerMac_hpp_

#ifdef __APPLE__

namespace Slic3r { namespace GUI {

// Installs OrcaSlicer's own kAEGetURL Apple Event handler and adds an
// application:openURLs: method on the running NSApp delegate. Safe to call
// multiple times - the latest registration wins.
void register_mac_deep_link_handler();

// Drains a URL that arrived before GUI_App was ready to handle it, and marks
// subsequent URLs as ready-to-dispatch directly to MacOpenURL. Call once the
// plater has been constructed.
void flush_mac_deep_link_queue();

} } // namespace Slic3r::GUI

#endif // __APPLE__
#endif // slic3r_GUI_DeepLinkHandlerMac_hpp_
