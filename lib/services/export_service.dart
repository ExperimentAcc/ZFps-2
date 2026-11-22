import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Hands files (CSV / PNG) to the Android share sheet through the native channel.
class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  static const MethodChannel _channel = MethodChannel('com.zsdev.fpsmonitor/channel');

  /// Returns false when the share sheet could not be opened.
  Future<bool> shareBytes(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    String title = 'FPS Monitor',
  }) async {
    try {
      return await _channel.invokeMethod<bool>('shareFile', {
            'bytes': bytes,
            'fileName': fileName,
            'mimeType': mimeType,
            'title': title,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
