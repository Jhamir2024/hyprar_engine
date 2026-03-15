import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'hyprar_engine_method_channel.dart';

abstract class HyprarEnginePlatform extends PlatformInterface {
  HyprarEnginePlatform() : super(token: _token);

  static final Object _token = Object();
  static HyprarEnginePlatform _instance = MethodChannelHyprarEngine();
  static HyprarEnginePlatform get instance => _instance;

  static set instance(HyprarEnginePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<int?> initializeCamera() {
    throw UnimplementedError('initializeCamera() no está implementado.');
  }

  // 🔥 NUEVO: El flujo de datos de los rostros
  Stream<Map<dynamic, dynamic>?> get faceStream {
    throw UnimplementedError('faceStream no está implementado.');
  }

  Future<bool?> startRecording() {
    throw UnimplementedError('startRecording() no está implementado.');
  }

  Future<String?> stopRecording() {
    throw UnimplementedError('stopRecording() no está implementado.');
  }

  Future<String?> encodeVideoFrames({
    required String tempDir,
    required int fps,
    required int width,
    required int height,
    required List<int> timestamps,
  }) {
    throw UnimplementedError('encodeVideoFrames() no está implementado.');
  }
}