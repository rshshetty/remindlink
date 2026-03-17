import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class ShareHandler {
  static const _channel = MethodChannel('com.remindlink/share');
  
  static Future<Map<String, String>?> getSharedData() async {
    try {
      final result = await _channel.invokeMethod('getSharedData');
      if (result != null) {
        return Map<String, String>.from(result);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting shared data: $e');
      return null;
    }
  }
}