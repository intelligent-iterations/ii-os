import 'package:web/web.dart' as web;

void notifyIiOsFirstFrame() {
  web.window.dispatchEvent(web.CustomEvent('ii-os-first-frame'));
}

void notifyIiOsStartupFailure() {
  web.window.dispatchEvent(web.CustomEvent('ii-os-startup-failed'));
}
