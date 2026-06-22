// Platform-specific file download helper
// Uses conditional imports to pick the right implementation per platform

export 'download_helper_io.dart'
    if (dart.library.html) 'download_helper_web.dart';
