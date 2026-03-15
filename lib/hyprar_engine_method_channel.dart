import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'hyprar_engine_platform_interface.dart';

class MethodChannelHyprarEngine extends HyprarEnginePlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('hyprar_engine');
  
  // 🔥 NUEVO: Conectamos el EventChannel con el mismo nombre que pusimos en Kotlin
  final eventChannel = const EventChannel('hyprar_engine/faces');

  @override
  Future<int?> initializeCamera() async {
    return await methodChannel.invokeMethod<int>('initializeCamera');
  }

  @override
  Stream<Map<dynamic, dynamic>?> get faceStream {
    return eventChannel.receiveBroadcastStream().map((event) {
      if (event == null) return null;
      return Map<dynamic, dynamic>.from(event);
    });
  }

  @override
  Future<bool?> startRecording() async {
    return await methodChannel.invokeMethod<bool>('startRecording');
  }

  @override
  Future<String?> stopRecording() async {
    return await methodChannel.invokeMethod<String>('stopRecording');
  }

  @override
  @override
  Future<String?> encodeVideoFrames({
    required String tempDir,
    required int fps,
    required int width,
    required int height,
    required List<int> timestamps,
  }) async {
    return await methodChannel.invokeMethod<String>('encodeVideoFrames', {
      'tempDir': tempDir,
      'fps': fps,
      'width': width,
      'height': height,
      'timestamps': timestamps,
    });
  }
}