import 'hyprar_engine_platform_interface.dart';

class HyprarEngine {
  Future<int?> initializeCamera() {
    return HyprarEnginePlatform.instance.initializeCamera();
  }

  Stream<Map<dynamic, dynamic>?> get faceStream {
    return HyprarEnginePlatform.instance.faceStream;
  }

  Future<bool?> startRecording() {
    return HyprarEnginePlatform.instance.startRecording();
  }

  Future<String?> stopRecording() {
    return HyprarEnginePlatform.instance.stopRecording();
  }

  Future<String?> encodeVideoFrames({
    required String tempDir,
    required int fps,
    required int width,
    required int height,
    required List<int> timestamps,
  }) {
    return HyprarEnginePlatform.instance.encodeVideoFrames(
      tempDir: tempDir,
      fps: fps,
      width: width,
      height: height,
      timestamps: timestamps,
    );
  }
}