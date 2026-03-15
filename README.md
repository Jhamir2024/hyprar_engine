# HYPR AR Engine

Motor de cámara AR nativo para Flutter — captura fotos y graba videos H.264 con stickers faciales en tiempo real.

## Características

- Cámara frontal nativa con preview en tiempo real via `CameraX`
- Detección facial con ML Kit (ojos, nariz, boca, ángulo de cabeza)
- Renderizado de filtros AR a 60 FPS con `CustomPainter`
- 15 filtros de rostro (Neon Cyber, Anime, Vampire, Zombie, Pop Art...)
- 5 stickers SVG faciales (Corona, Halo, Cuernos, Orejas de Gato, Astronauta)
- 10 filtros de color de escena (VHS, Golden Hour, Noir, Ocean...)
- Captura de fotos con stickers incluidos (RepaintBoundary)
- Grabación de video H.264 con stickers usando `MediaCodec` + `MediaMuxer`
- Guardado directo en galería (álbum "HYPR AR") via `MediaStore`

## Instalación

```yaml
dependencies:
  hyprar_engine:
    git:
      url: https://github.com/Jhamir2024/hyprar_engine
```

## Uso básico

```dart
import 'package:hyprar_engine/hyprar_engine.dart';

final engine = HyprarEngine();

// Inicializar cámara → devuelve textureId para Texture widget
final textureId = await engine.initializeCamera();

// Stream de datos faciales en tiempo real
engine.faceStream.listen((faceData) {
  // faceData contiene: leftEyeX/Y, rightEyeX/Y, noseX/Y, angleZ, x, y, width, height
});

// Grabar video con stickers
await engine.encodeVideoFrames(
  tempDir: '/ruta/a/frames/',
  fps: 15,
  width: 720,
  height: 1280,
  timestamps: [0, 66666, 133332, ...], // microsegundos
);
```

## Permisos requeridos (Android)

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

## Plataformas soportadas

| Plataforma | Soporte |
|-----------|---------|
| Android   | ✅ API 21+ |
| iOS       | Próximamente |

## Autor

Desarrollado por [Jhamir2024](https://github.com/Jhamir2024)
