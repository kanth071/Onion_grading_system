// This file is only ever compiled in for web builds (see web_utils.dart's
// conditional export), so the web-only dart:html import is intentional.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Browsers can't write to an arbitrary local path or shell out to open a
/// file (no dart:io, no OpenFilex) - the PDF just gets opened directly, the
/// same way the existing web frontend already handles report downloads.
void openUrlInNewTab(String url) {
  html.window.open(url, '_blank');
}
