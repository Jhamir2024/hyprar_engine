import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:permission_handler/permission_handler.dart';
import 'package:hyprar_engine/hyprar_engine.dart';
import 'package:gal/gal.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const HyprCameraApp());
}

class HyprCameraApp extends StatelessWidget {
  const HyprCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HyprCameraScreen(),
    );
  }
}

class HyprCameraScreen extends StatefulWidget {
  const HyprCameraScreen({super.key});

  @override
  State<HyprCameraScreen> createState() => _HyprCameraScreenState();
}

class _HyprCameraScreenState extends State<HyprCameraScreen> {
  final _hyprarEnginePlugin = HyprarEngine();
  int? _textureId;
  bool _isReady = false;

  int _activeFaceFilter = 0;
  int _activeWorldFilter = 0;

  final GlobalKey _camKey = GlobalKey();
  bool _isFlashing = false;

  // ── PNG overlays (worldId 11-15) ──────────────────────────────────
  final Map<int, ui.Image?> _overlayImages = {};

  // ── Video recording ───────────────────────────────────────────────
  bool _isRecording = false;
  bool _isEncodingVideo = false;
  double _recordProgress = 0.0;
  Timer? _recordTimer;

  // ── Captura de frames para video con stickers ─────────────────────
  String? _tempVideoDir;
  int _frameIndex = 0;
  bool _isCapturingFrame = false;
  int _videoWidth = 0;
  int _videoHeight = 0;
  final List<int> _frameTimestamps = []; // microsegundos desde inicio de grabación
  int _recordStartUs = 0;
  int _recordSeconds = 0;

  // ── Countdown timer ───────────────────────────────────────────────
  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    iniciarMotorAR();
    _cargarImagenes();
  }

  Future<void> iniciarMotorAR() async {
    var status = await Permission.camera.request();
    if (!status.isGranted) return;
    // Pedir micrófono al inicio para no bloquear durante grabación
    await Permission.microphone.request();

    try {
      final id = await _hyprarEnginePlugin.initializeCamera();
      if (mounted && id != null) {
        setState(() {
          _textureId = id;
          _isReady = true;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  // 🔥 MISIÓN B: LA FUNCIÓN DE CAPTURA
  Future<void> tomarFoto() async {
    _countdownTimer?.cancel();
    setState(() => _countdown = 0);
    // Vibración de obturador
    HapticFeedback.mediumImpact();
    // 1. Efecto de flash en la pantalla
    setState(() => _isFlashing = true);
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() => _isFlashing = false);

    try {
      // 2. Encuentra el marco de la cámara
      RenderRepaintBoundary boundary = _camKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // 3. Convierte el marco en una imagen HD (pixelRatio 3.0)
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        // 4. Lo guarda en el álbum HYPR AR de la Galería
        await Gal.putImageBytes(byteData.buffer.asUint8List(), album: "HYPR AR");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Captura guardada en la Galería! 📸', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error al guardar: $e");
    }
  }

  // ── CARGA DE SVGs → rasterizados como ui.Image ───────────────────────
  // SVG id → (path, ancho original, alto original)
  static const _assetMap = <int, (String, double, double)>{
    11: ('assets/corona.svg',      300, 300),
    12: ('assets/cuernos.svg',     400, 300),
    13: ('assets/halo.svg',        300, 120),
    14: ('assets/orejas_gato.svg', 400, 300),
    15: ('assets/astronauta.svg',  400, 500),
  };

  Future<void> _cargarImagenes() async {
    for (final entry in _assetMap.entries) {
      try {
        final (path, origW, origH) = entry.value;
        final svgString = await rootBundle.loadString(path);

        // Carga el SVG como Picture vectorial
        final info = await vg.loadPicture(SvgStringLoader(svgString), null);

        // Rasteriza a 512 px de ancho para alta calidad
        const targetW = 512.0;
        final targetH = targetW * origH / origW;

        final recorder = ui.PictureRecorder();
        final c = Canvas(recorder);
        c.scale(targetW / info.size.width, targetH / info.size.height);
        c.drawPicture(info.picture);
        final pic = recorder.endRecording();
        final img = await pic.toImage(targetW.toInt(), targetH.toInt());

        if (mounted) setState(() => _overlayImages[entry.key] = img);
      } catch (e) {
        debugPrint('SVG load error [${ entry.key}]: $e');
      }
    }
  }

  // ── GRABACIÓN DE VIDEO CON STICKERS (Long Press) ─────────────────────
  Future<void> _iniciarGrabacion() async {
    if (_isRecording || _isEncodingVideo) return;

    // Preparar directorio temporal para los frames
    final tmpBase = await getTemporaryDirectory();
    _tempVideoDir = '${tmpBase.path}/hypr_${DateTime.now().millisecondsSinceEpoch}';
    await Directory(_tempVideoDir!).create();
    _frameIndex = 0;
    _videoWidth = 0;
    _videoHeight = 0;
    _frameTimestamps.clear();
    _recordStartUs = 0;

    setState(() { _isRecording = true; _recordProgress = 0.0; _recordSeconds = 0; });

    // Timer: captura 1 frame cada 67 ms ≈ 15 fps objetivo, máx 60 segundos
    // Los timestamps reales aseguran velocidad de reproducción correcta
    _recordTimer = Timer.periodic(const Duration(milliseconds: 67), (t) async {
      setState(() {
        _recordProgress = t.tick / 900; // 15fps × 60s = 900
        _recordSeconds = (t.tick * 67) ~/ 1000;
      });
      if (_recordProgress >= 1.0) { _detenerGrabacion(); return; }

      if (_isCapturingFrame || !_isRecording) return;
      _isCapturingFrame = true;
      // Timestamp real del momento de captura
      final captureUs = DateTime.now().microsecondsSinceEpoch;
      try {
        final boundary = _camKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) { _isCapturingFrame = false; return; }
        if (_videoWidth == 0) {
          _videoWidth  = boundary.size.width.round();
          _videoHeight = boundary.size.height.round();
        }
        final img = await boundary.toImage(pixelRatio: 1.0);
        final bd  = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        if (bd != null && _isRecording && _tempVideoDir != null) {
          if (_recordStartUs == 0) _recordStartUs = captureUs;
          final name = _frameIndex.toString().padLeft(6, '0');
          await File('$_tempVideoDir/f$name.png')
              .writeAsBytes(bd.buffer.asUint8List());
          _frameTimestamps.add(captureUs - _recordStartUs);
          _frameIndex++;
        }
      } catch (e) {
        debugPrint('frame capture: $e');
      }
      _isCapturingFrame = false;
    });
  }

  Future<void> _detenerGrabacion() async {
    _recordTimer?.cancel();
    if (!_isRecording) return;
    setState(() { _isRecording = false; _recordProgress = 0.0; _recordSeconds = 0; });

    // Espera a que termine el último frame en curso
    while (_isCapturingFrame) {
      await Future.delayed(const Duration(milliseconds: 30));
    }

    final dir = _tempVideoDir;
    final timestamps = List<int>.from(_frameTimestamps);
    _tempVideoDir = null;
    _frameTimestamps.clear();
    if (dir == null || _frameIndex == 0) return;

    setState(() => _isEncodingVideo = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Procesando video con stickers...'),
          duration: Duration(seconds: 30),
          backgroundColor: Colors.black87,
        ),
      );
    }

    try {
      final uri = await _hyprarEnginePlugin.encodeVideoFrames(
        tempDir: dir,
        fps: 15,
        width: _videoWidth,
        height: _videoHeight,
        timestamps: timestamps,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uri != null ? '¡Video con stickers guardado en Galería! 🎬' : 'Grabación detenida',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('encodeVideoFrames error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar video: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isEncodingVideo = false);
  }

  // ── Cuenta regresiva (3-2-1 → tomarFoto) ─────────────────────────
  void _startCountdown() {
    if (_countdown > 0) {
      _countdownTimer?.cancel();
      setState(() => _countdown = 0);
      return;
    }
    setState(() => _countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
        tomarFoto();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _countdownTimer?.cancel();
    // Limpia carpeta temporal si quedó algo
    if (_tempVideoDir != null) {
      Directory(_tempVideoDir!).deleteSync(recursive: true);
    }
    super.dispose();
  }

  // MATRICES DE COLOR PARA LOS 10 FILTROS DE PAISAJE
  ColorFilter? _getWorldFilter(int id) {
    switch (id) {
      case 1: return const ColorFilter.mode(Color(0x44FF00FF), BlendMode.color); // Tokyo
      case 2: return const ColorFilter.matrix([1.2, 0, 0, 0, 0, 0, 1.1, 0, 0, 0, 0, 0, 0.9, 0, 0, 0, 0, 0, 1, 0]); // VHS
      case 3: return const ColorFilter.mode(Color(0x33FFB300), BlendMode.colorBurn); // Golden Hour
      case 4: return const ColorFilter.matrix([0, 0, 0, 0, 0, 0, 1.5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]); // Matrix Green
      case 5: return const ColorFilter.matrix([0.33, 0.59, 0.11, 0, 0, 0.33, 0.59, 0.11, 0, 0, 0.33, 0.59, 0.11, 0, 0, 0, 0, 0, 1, 0]); // Noir
      case 6: return const ColorFilter.mode(Color(0x4400E5FF), BlendMode.hue); // Cyber City
      case 7: return const ColorFilter.mode(Color(0x44FF99CC), BlendMode.softLight); // Pastel
      case 8: return const ColorFilter.matrix([0.39, 0.76, 0.18, 0, 0, 0.34, 0.68, 0.16, 0, 0, 0.27, 0.53, 0.13, 0, 0, 0, 0, 0, 1, 0]); // Sepia
      case 9: return const ColorFilter.mode(Color(0x55003399), BlendMode.overlay); // Ocean
      case 10: return const ColorFilter.mode(Color(0x44FF6600), BlendMode.color); // Autumn
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFD499FF))),
      );
    }

    final worldColorFilter = _getWorldFilter(_activeWorldFilter);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 🔥 RepaintBoundary captura: cámara + filtros AR + watermark + flash
          RepaintBoundary(
            key: _camKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Cámara + filtro de color
                worldColorFilter != null
                    ? ColorFiltered(colorFilter: worldColorFilter, child: Texture(textureId: _textureId!))
                    : Texture(textureId: _textureId!),

                // 2. IA de Rostros
                StreamBuilder<Map<dynamic, dynamic>?>(
                  stream: _hyprarEnginePlugin.faceStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
                    return CustomPaint(
                      painter: ARFilterPainter(
                        faceData: snapshot.data!,
                        faceId: _activeFaceFilter,
                        worldId: _activeWorldFilter,
                        overlayImages: _overlayImages,
                      ),
                    );
                  },
                ),

                // 3. Flash (dentro del boundary, sincronizado con la captura)
                if (_isFlashing) Container(color: Colors.white),
              ],
            ),
          ),

          // Overlay cuenta regresiva
          if (_countdown > 0)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: Tween<double>(begin: 1.8, end: 1.0).animate(
                      CurvedAnimation(parent: anim, curve: Curves.easeOut),
                    ),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Text(
                    '$_countdown',
                    key: ValueKey(_countdown),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 130,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Color(0xFFD499FF), blurRadius: 40),
                        Shadow(color: Colors.cyanAccent, blurRadius: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 5. Controles interactivos (FUERA del boundary → no aparecen en la foto)
          SafeArea(
            child: Stack(
              children: [
                const Positioned(
                  top: 20, left: 20,
                  child: Text("HYPR AR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),

                // Indicador de cámara (fuera del RepaintBoundary → no aparece en fotos/videos)
                Positioned(
                  top: 16, left: 90,
                  child: Row(
                    children: [
                      Icon(
                        Icons.videocam,
                        color: _isRecording ? Colors.red : const Color(0xFF00E676),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording ? Colors.red : const Color(0xFF00E676),
                          boxShadow: [
                            BoxShadow(
                              color: _isRecording ? Colors.red : const Color(0xFF00E676),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      if (_isRecording) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${(_recordSeconds ~/ 60).toString().padLeft(2, '0')}:${(_recordSeconds % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Botones top-right: perfil y temporizador
                Positioned(
                  top: 12, right: 12,
                  child: Row(
                    children: [
                      // Botón temporizador 3s
                      GestureDetector(
                        onTap: _startCountdown,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _countdown > 0
                                ? Colors.orangeAccent.withValues(alpha: 0.3)
                                : Colors.black45,
                            border: Border.all(
                              color: _countdown > 0 ? Colors.orangeAccent : Colors.white30,
                            ),
                          ),
                          child: Icon(
                            _countdown > 0 ? Icons.close : Icons.timer_outlined,
                            color: _countdown > 0 ? Colors.orangeAccent : Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Carruseles + botón de captura (parte inferior) ──────────────
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Filtros de rostro
                      SizedBox(
                        height: 70,
                        child: FilterCarouselHorizontal(
                          activeId: _activeFaceFilter,
                          onFilterChanged: (id) => setState(() => _activeFaceFilter = id),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 2. Filtros de mundo y accesorios
                      SizedBox(
                        height: 70,
                        child: FilterCarouselWorld(
                          activeId: _activeWorldFilter,
                          onFilterChanged: (id) => setState(() => _activeWorldFilter = id),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 3. Botón de captura / grabación (solo y centrado)
                      GestureDetector(
                        onTap: (_isRecording || _isEncodingVideo) ? null : tomarFoto,
                        onLongPressStart: _isEncodingVideo ? null : (_) => _iniciarGrabacion(),
                        onLongPressEnd: _isEncodingVideo ? null : (_) => _detenerGrabacion(),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_isRecording)
                              SizedBox(
                                width: 88, height: 88,
                                child: CircularProgressIndicator(
                                  value: _recordProgress,
                                  color: Colors.red,
                                  strokeWidth: 4,
                                ),
                              ),
                            Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isRecording ? Colors.red : Colors.white,
                                  width: 4,
                                ),
                                color: Colors.black.withValues(alpha: 0.3),
                              ),
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: _isRecording ? 28 : 60,
                                  height: _isRecording ? 28 : 60,
                                  decoration: BoxDecoration(
                                    color: _isRecording ? Colors.red : Colors.white,
                                    shape: BoxShape.rectangle,
                                    borderRadius: _isRecording ? BorderRadius.circular(6) : BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MOTOR AR - DIBUJANTE DE FILTROS
// ═══════════════════════════════════════════════════════
class ARFilterPainter extends CustomPainter {
  final Map<dynamic, dynamic> faceData;
  final int faceId;
  final int worldId;
  final Map<int, ui.Image?> overlayImages;

  ARFilterPainter({required this.faceData, required this.faceId, required this.worldId, required this.overlayImages});

  @override
  void paint(Canvas canvas, Size size) {
    if (faceData['leftEyeX'] == 0.0) return;

    final double scaleX = size.width  / (faceData['imgHeight'] as double);
    final double scaleY = size.height / (faceData['imgWidth']  as double);

    // ML Kit devuelve coordenadas en espacio portrait (post-rotación).
    // eyeX = posición horizontal en portrait → se usa para screen_x (con espejo de cámara frontal).
    // eyeY = posición vertical en portrait   → se usa para screen_y.
    // Espejo: screen_x = (imgHeight - eyeX) * scaleX
    final double imgH = faceData['imgHeight'] as double;
    final Offset L = Offset(
      (imgH - (faceData['leftEyeX']  as double)) * scaleX,
      (faceData['leftEyeY'] as double) * scaleY,
    );
    final Offset R = Offset(
      (imgH - (faceData['rightEyeX'] as double)) * scaleX,
      (faceData['rightEyeY'] as double) * scaleY,
    );
    final double ed = (L.dx - R.dx).abs();

    final Offset eyeMid   = Offset((L.dx + R.dx) / 2, (L.dy + R.dy) / 2);
    final Offset forehead = Offset(eyeMid.dx, eyeMid.dy - ed * 1.5);
    final Offset nose     = Offset(eyeMid.dx, eyeMid.dy + ed * 0.9);
    final Offset mouth    = Offset(eyeMid.dx, eyeMid.dy + ed * 1.8);

    final double fx = faceData['x'] as double;
    final double fy = faceData['y'] as double;
    final double fw = faceData['width']  as double;
    final double fh = faceData['height'] as double;
    final faceRect = Rect.fromLTRB(
      (imgH - fx - fw) * scaleX,   // espejo del borde izquierdo
      fy * scaleY,
      (imgH - fx) * scaleX,        // espejo del borde derecho
      (fy + fh) * scaleY,
    );

    // ── ACCESORIOS (columna izquierda 11‑15) ──────────────────────────
    // _pngBottom: ancla la parte INFERIOR de la imagen en `anchor`
    // _pngCenter: ancla el CENTRO de la imagen en `anchor`
    switch (worldId) {
      case 11: // Corona — gira con la cabeza y se apoya sobre la frente
        if (overlayImages[11] != null) {
          final anchor = eyeMid - Offset(0, ed * 1.2);
          final tilt = -(faceData['angleZ'] as double) * 3.14159265 / 180.0;
          canvas.save();
          canvas.translate(anchor.dx, anchor.dy);
          canvas.rotate(tilt);
          canvas.translate(-anchor.dx, -anchor.dy);
          _pngBottom(canvas, overlayImages[11]!, anchor, ed * 5.85);
          canvas.restore();
        } else {
          _emoji(canvas, "👑", forehead, ed * 3.0);
        }
        break;
      case 12: // Cuernos — ancla en frente, cuernos hacia arriba
        overlayImages[12] != null
          ? _pngBottom(canvas, overlayImages[12]!, eyeMid - Offset(0, ed * 1.0), ed * 7.0)
          : _emoji(canvas, "😈", forehead, ed * 3.0);
        break;
      case 13: // Halo — flota sobre la cabeza
        overlayImages[13] != null
          ? _pngCenter(canvas, overlayImages[13]!, eyeMid - Offset(0, ed * 2.5), ed * 2.56, 300, 120)
          : _emoji(canvas, "😇", forehead, ed * 3.0);
        break;
      case 14: // Orejas de gato — arriba de la cabeza
        overlayImages[14] != null
          ? _pngBottom(canvas, overlayImages[14]!, eyeMid - Offset(0, ed * 1.2), ed * 5.0)
          : _emoji(canvas, "🐱", forehead, ed * 3.0);
        break;
      case 15: // Astronauta — casco sobre el rostro, visor transparente para ver la cara
        if (overlayImages[15] != null) {
          final img = overlayImages[15]!;
          final h = faceRect.height * 2.2;
          final w = h * 400 / 500;
          final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
          final dst = Rect.fromCenter(center: faceRect.center, width: w, height: h);
          // saveLayer para poder borrar el visor con BlendMode.clear
          canvas.saveLayer(dst, Paint());
          canvas.drawImageRect(img, src, dst, Paint()..color = Colors.white.withValues(alpha: 0.95));
          // Oval transparente = visor donde se ve tu cara
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(faceRect.center.dx, faceRect.center.dy - faceRect.height * 0.03),
              width:  faceRect.width  * 0.82,
              height: faceRect.height * 0.72,
            ),
            Paint()..blendMode = BlendMode.clear,
          );
          canvas.restore();
        } else {
          _emoji(canvas, "🧑‍🚀", Offset(forehead.dx, L.dy), ed * 4.0);
        }
        break;
    }

    // ── FILTROS DE ROSTRO (carrusel inferior) ─────────────────────────
    switch (faceId) {
      case 1:  _beauty(canvas, faceRect, L, R, eyeMid, ed); break;
      case 2:  _neonCyber(canvas, faceRect, L, R, ed); break;
      case 3:  _animeEyes(canvas, L, R, ed); break;
      case 4:  _glitch(canvas, faceRect); break;
      case 5:  _joker(canvas, faceRect, L, R, mouth, ed); break;
      case 6:  _censor(canvas, L, R, ed); break;
      case 7:  _goldStar(canvas, faceRect, forehead, ed); break;
      case 8:  _thermal(canvas, faceRect); break;
      case 9:  _vampire(canvas, L, R, mouth, nose, ed); break;
      case 10: _tears(canvas, L, R, ed); break;
      case 11: _visorCyber(canvas, L, R, ed); break;
      case 12: _zombie(canvas, faceRect, L, R, ed); break;
      case 13: _sketch(canvas, faceRect, L, R, ed); break;
      case 14: _popArt(canvas, faceRect, L, R, ed); break;
      case 15: _holo(canvas, faceRect, ed); break;
    }
  }

  // ── HELPERS ──────────────────────────────────────────────────────────

  void _emoji(Canvas canvas, String e, Offset pos, double sz) {
    final tp = TextPainter(
      text: TextSpan(text: e, style: TextStyle(fontSize: sz)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  // Ancla la parte INFERIOR de la imagen en `anchor` y escala por ancho
  void _pngBottom(Canvas canvas, ui.Image img, Offset anchor, double width) {
    final aspect = img.height / img.width;
    final height = width * aspect;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromLTWH(anchor.dx - width / 2, anchor.dy - height, width, height);
    canvas.drawImageRect(img, src, dst, Paint());
  }

  // Ancla el CENTRO de la imagen en `anchor`, respetando la proporción original
  void _pngCenter(Canvas canvas, ui.Image img, Offset anchor, double height,
      double origW, double origH, {double opacity = 1.0}) {
    final width = height * origW / origH;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromCenter(center: anchor, width: width, height: height);
    canvas.drawImageRect(img, src, dst, Paint()..color = Colors.white.withValues(alpha: opacity));
  }

  Paint _glow(Color c, double blur, {double width = 6}) =>
      Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = width
             ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

  Paint _fill(Color c) => Paint()..color = c..style = PaintingStyle.fill;
  Paint _stroke(Color c, double w) => Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = w;

  // ── 1. BEAUTY GLOW ────────────────────────────────────────────────────
  void _beauty(Canvas canvas, Rect face, Offset L, Offset R, Offset mid, double ed) {
    // Aura suave sobre el rostro
    canvas.drawOval(face.inflate(10),
      Paint()..color = const Color(0x33FFB6C1)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    // Blush en mejillas
    final blushR = ed * 0.55;
    canvas.drawCircle(Offset(L.dx + ed * 0.8, L.dy + ed * 0.4), blushR,
      Paint()..color = const Color(0x55FF69B4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(Offset(R.dx - ed * 0.8, R.dy + ed * 0.4), blushR,
      Paint()..color = const Color(0x55FF69B4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    // Brillo en ojos
    canvas.drawCircle(L - Offset(ed * 0.08, ed * 0.08), ed * 0.12, _fill(Colors.white70));
    canvas.drawCircle(R - Offset(ed * 0.08, ed * 0.08), ed * 0.12, _fill(Colors.white70));
  }

  // ── 2. NEON CYBER ─────────────────────────────────────────────────────
  void _neonCyber(Canvas canvas, Rect face, Offset L, Offset R, double ed) {
    final rr = RRect.fromRectAndRadius(face, const Radius.circular(22));
    // Glow exterior morado
    canvas.drawRRect(rr, _glow(const Color(0xFFD499FF), 14, width: 8));
    // Borde fino interior
    canvas.drawRRect(rr, _stroke(const Color(0xFFD499FF), 2));
    // Brackets en esquinas
    final s = ed * 0.35;
    for (final c in [face.topLeft, face.topRight, face.bottomLeft, face.bottomRight]) {
      final sx = c == face.topLeft || c == face.bottomLeft ? s : -s;
      final sy = c == face.topLeft || c == face.topRight ? s : -s;
      canvas.drawLine(c, c + Offset(sx, 0), _stroke(Colors.cyanAccent, 3));
      canvas.drawLine(c, c + Offset(0, sy), _stroke(Colors.cyanAccent, 3));
    }
    // Línea de escaneo horizontal
    canvas.drawLine(Offset(face.left, L.dy), Offset(face.right, L.dy),
      Paint()..color = const Color(0x44D499FF)..strokeWidth = 1.5);
  }

  // ── 3. ANIME EYES ─────────────────────────────────────────────────────
  void _animeEyes(Canvas canvas, Offset L, Offset R, double ed) {
    for (final eye in [L, R]) {
      final r = ed * 0.72;
      // Esclerótica blanca
      canvas.drawCircle(eye, r, _fill(Colors.white));
      // Iris azul violeta con gradiente simulado
      canvas.drawCircle(eye, r * 0.65, _fill(const Color(0xFF5B4FE8)));
      canvas.drawCircle(eye, r * 0.45, _fill(const Color(0xFF7B6FFF)));
      // Pupila negra
      canvas.drawCircle(eye, r * 0.22, _fill(Colors.black));
      // Brillo principal
      canvas.drawCircle(eye - Offset(r * 0.22, r * 0.22), r * 0.15, _fill(Colors.white));
      // Brillo secundario pequeño
      canvas.drawCircle(eye + Offset(r * 0.2, -r * 0.1), r * 0.07, _fill(Colors.white70));
      // Línea de párpado superior
      canvas.drawArc(Rect.fromCircle(center: eye, radius: r), 3.8, 5.6, false,
        _stroke(Colors.black, 2.5));
    }
  }

  // ── 4. GLITCH ─────────────────────────────────────────────────────────
  void _glitch(Canvas canvas, Rect face) {
    // Capa roja desplazada a la izquierda
    canvas.drawRRect(RRect.fromRectAndRadius(face.translate(-6, 0), const Radius.circular(12)),
      Paint()..color = const Color(0x88FF0040)..style = PaintingStyle.stroke..strokeWidth = 3);
    // Capa cyan desplazada a la derecha
    canvas.drawRRect(RRect.fromRectAndRadius(face.translate(6, 0), const Radius.circular(12)),
      Paint()..color = const Color(0x8800FFFF)..style = PaintingStyle.stroke..strokeWidth = 3);
    // Líneas de glitch horizontales
    for (double y = face.top + 10; y < face.bottom; y += face.height / 8) {
      final w = face.width * (0.3 + (y % 3) * 0.2);
      canvas.drawLine(Offset(face.left + (face.width - w) / 2, y),
        Offset(face.left + (face.width + w) / 2, y),
        Paint()..color = const Color(0xAAFFFFFF)..strokeWidth = 1.5);
    }
  }

  // ── 5. JOKER ──────────────────────────────────────────────────────────
  void _joker(Canvas canvas, Rect face, Offset L, Offset R, Offset mouth, double ed) {
    // Óvalo blanco — clipeado al rostro para no generar blob flotante
    canvas.save();
    canvas.clipRect(face.inflate(12));
    canvas.drawOval(face, Paint()..color = const Color(0x66FFFFFF));
    canvas.restore();
    // Ojos negros sombreados
    canvas.drawCircle(L, ed * 0.45, Paint()..color = const Color(0x88000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(R, ed * 0.45, Paint()..color = const Color(0x88000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Sonrisa roja extendida
    final smileW = ed * 1.0;
    final path = Path()
      ..moveTo(mouth.dx - smileW, mouth.dy - ed * 0.1)
      ..quadraticBezierTo(mouth.dx, mouth.dy + ed * 0.5, mouth.dx + smileW, mouth.dy - ed * 0.1);
    canvas.drawPath(path, Paint()..color = Colors.red..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round);
    // Cicatrices de la sonrisa
    canvas.drawLine(mouth - Offset(smileW, ed * 0.1), mouth - Offset(smileW * 1.4, -ed * 0.3),
      _stroke(Colors.red, 2.5));
    canvas.drawLine(mouth + Offset(smileW, -ed * 0.1), mouth + Offset(smileW * 1.4, ed * 0.3),
      _stroke(Colors.red, 2.5));
  }

  // ── 6. CENSOR ─────────────────────────────────────────────────────────
  void _censor(Canvas canvas, Offset L, Offset R, double ed) {
    final mid = Offset((L.dx + R.dx) / 2, (L.dy + R.dy) / 2);
    final rect = Rect.fromCenter(center: mid, width: ed * 2.6, height: ed * 0.85);
    canvas.drawRect(rect, _fill(Colors.black));
    // Texto CENSORED
    final tp = TextPainter(
      text: const TextSpan(text: "▓▓▓▓▓▓▓▓", style: TextStyle(color: Color(0xFF333333), fontSize: 13, letterSpacing: 2)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    tp.paint(canvas, Offset(rect.left + (rect.width - tp.width) / 2, rect.top + (rect.height - tp.height) / 2));
  }

  // ── 7. GOLD STAR ──────────────────────────────────────────────────────
  void _goldStar(Canvas canvas, Rect face, Offset forehead, double ed) {
    // Marco dorado con glow
    canvas.drawRRect(RRect.fromRectAndRadius(face, const Radius.circular(16)),
      _glow(const Color(0xFFFFD700), 12, width: 5));
    canvas.drawRRect(RRect.fromRectAndRadius(face, const Radius.circular(16)),
      _stroke(const Color(0xFFFFD700), 2));
    // Estrellas brillantes alrededor
    final stars = [
      forehead, Offset(face.left - 12, face.center.dy),
      Offset(face.right + 12, face.center.dy), Offset(face.topLeft.dx, face.top - 10),
      Offset(face.topRight.dx, face.top - 10),
    ];
    for (final s in stars) {
      _dibujarEstrella(canvas, s, ed * 0.18, const Color(0xFFFFD700));
    }
  }

  void _dibujarEstrella(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = (i * 36 - 90) * 3.14159 / 180;
      final rad = i.isEven ? r : r * 0.45;
      final p = Offset(c.dx + rad * cos(angle), c.dy + rad * sin(angle));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, _fill(color)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawPath(path, _fill(color));
  }

  // ── 8. THERMAL ────────────────────────────────────────────────────────
  void _thermal(Canvas canvas, Rect face) {
    final colors = [Colors.blue, Colors.cyan, Colors.green, Colors.yellow, Colors.orange, Colors.red];
    final bandH = face.height / colors.length;
    for (int i = 0; i < colors.length; i++) {
      final band = Rect.fromLTWH(face.left, face.top + i * bandH, face.width, bandH + 1);
      canvas.drawRect(band, Paint()..color = colors[i].withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    // Borde blanco caliente
    canvas.drawRect(face, _stroke(Colors.white54, 1.5));
  }

  // ── 9. VAMPIRE ────────────────────────────────────────────────────────
  void _vampire(Canvas canvas, Offset L, Offset R, Offset mouth, Offset nose, double ed) {
    // Ojeras oscuras
    canvas.drawCircle(L, ed * 0.5, Paint()..color = const Color(0x66330000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawCircle(R, ed * 0.5, Paint()..color = const Color(0x66330000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    // Iris rojos brillantes
    canvas.drawCircle(L, ed * 0.28, _fill(const Color(0xFFCC0000)));
    canvas.drawCircle(R, ed * 0.28, _fill(const Color(0xFFCC0000)));
    canvas.drawCircle(L, ed * 0.28, _glow(Colors.red, 8, width: 4));
    canvas.drawCircle(R, ed * 0.28, _glow(Colors.red, 8, width: 4));
    // Pupila negra
    canvas.drawCircle(L, ed * 0.1, _fill(Colors.black));
    canvas.drawCircle(R, ed * 0.1, _fill(Colors.black));
    // Colmillos
    final fangBase = Offset(mouth.dx, mouth.dy - ed * 0.05);
    _fang(canvas, fangBase - Offset(ed * 0.18, 0));
    _fang(canvas, fangBase + Offset(ed * 0.18, 0));
  }

  void _fang(Canvas canvas, Offset base) {
    final path = Path()
      ..moveTo(base.dx - 7, base.dy)
      ..lineTo(base.dx + 7, base.dy)
      ..lineTo(base.dx, base.dy + 22)
      ..close();
    canvas.drawPath(path, _fill(Colors.white));
    canvas.drawPath(path, _stroke(Colors.red.withValues(alpha: 0.5), 1));
  }

  // ── 10. TEARS ─────────────────────────────────────────────────────────
  void _tears(Canvas canvas, Offset L, Offset R, double ed) {
    for (final eye in [L, R]) {
      // Línea principal brillante
      canvas.drawLine(eye, Offset(eye.dx, eye.dy + ed * 1.8),
        Paint()..color = const Color(0xBB00CFFF)..strokeWidth = 5
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      // Línea fina encima para brillo
      canvas.drawLine(eye, Offset(eye.dx, eye.dy + ed * 1.8),
        Paint()..color = Colors.white70..strokeWidth = 1.5);
      // Gota en la punta
      final dropCenter = Offset(eye.dx, eye.dy + ed * 1.9);
      canvas.drawCircle(dropCenter, 6, _fill(const Color(0xFF00CFFF)));
      canvas.drawCircle(dropCenter, 6, _glow(Colors.cyanAccent, 5, width: 2));
    }
  }

  // ── 11. VISOR CYBERPUNK ───────────────────────────────────────────────
  void _visorCyber(Canvas canvas, Offset L, Offset R, double ed) {
    final lw = ed * 0.85;
    final lh = lw * 0.55;
    // Puente entre lentes
    canvas.drawLine(L, R, _stroke(Colors.cyanAccent, 2.5));
    for (final eye in [L, R]) {
      final lens = Rect.fromCenter(center: eye, width: lw, height: lh);
      // Lente oscura con tinte cyan
      canvas.drawRRect(RRect.fromRectAndRadius(lens, const Radius.circular(8)),
        _fill(const Color(0xCC001A2E)));
      // Reflejo diagonal en lente
      canvas.drawLine(Offset(lens.left + lw * 0.15, lens.top + lh * 0.25),
        Offset(lens.left + lw * 0.4, lens.top + lh * 0.7),
        Paint()..color = Colors.cyanAccent.withValues(alpha: 0.5)..strokeWidth = 2);
      // Borde con glow
      canvas.drawRRect(RRect.fromRectAndRadius(lens, const Radius.circular(8)),
        _glow(Colors.cyanAccent, 6, width: 3));
      canvas.drawRRect(RRect.fromRectAndRadius(lens, const Radius.circular(8)),
        _stroke(Colors.cyanAccent, 1.5));
    }
  }

  // ── 12. ZOMBIE ────────────────────────────────────────────────────────
  void _zombie(Canvas canvas, Rect face, Offset L, Offset R, double ed) {
    // Tinte verde sobre el rostro
    canvas.drawOval(face, Paint()..color = const Color(0x4432CD32)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Ojos hundidos
    for (final eye in [L, R]) {
      canvas.drawCircle(eye, ed * 0.4, Paint()..color = const Color(0x88000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(eye, ed * 0.18, _fill(const Color(0xFFCCFF00)));
      canvas.drawCircle(eye, ed * 0.07, _fill(Colors.black));
    }
    // Grietas en la piel
    final crack = Path()
      ..moveTo(face.center.dx - ed * 0.3, face.top + face.height * 0.2)
      ..lineTo(face.center.dx - ed * 0.1, face.top + face.height * 0.4)
      ..lineTo(face.center.dx - ed * 0.25, face.top + face.height * 0.55);
    canvas.drawPath(crack, _stroke(const Color(0xFF005500), 2));
    final crack2 = Path()
      ..moveTo(face.center.dx + ed * 0.2, face.top + face.height * 0.3)
      ..lineTo(face.center.dx + ed * 0.05, face.top + face.height * 0.5);
    canvas.drawPath(crack2, _stroke(const Color(0xFF005500), 2));
  }

  // ── 13. SKETCH ────────────────────────────────────────────────────────
  void _sketch(Canvas canvas, Rect face, Offset L, Offset R, double ed) {
    final p = _stroke(Colors.black87, 1.8);
    // Contorno del rostro con líneas irregulares
    for (double offset = -2; offset <= 2; offset += 2) {
      canvas.drawOval(face.translate(offset, offset), _stroke(Colors.black54, 0.8));
    }
    // Ojos con trazos de lápiz
    for (final eye in [L, R]) {
      for (int i = -1; i <= 1; i++) {
        canvas.drawArc(
          Rect.fromCenter(center: eye + Offset(i.toDouble(), i.toDouble()), width: ed * 0.9, height: ed * 0.6),
          3.9, 5.5, false, _stroke(Colors.black87, 0.9));
      }
    }
    // Sombreado cruzado en mejillas
    for (double x = face.left + 10; x < L.dx - ed * 0.5; x += 7) {
      canvas.drawLine(Offset(x, L.dy - ed * 0.2), Offset(x + 12, L.dy + ed * 0.3), p);
    }
    for (double x = R.dx + ed * 0.5; x < face.right - 10; x += 7) {
      canvas.drawLine(Offset(x, R.dy - ed * 0.2), Offset(x + 12, R.dy + ed * 0.3), p);
    }
  }

  // ── 14. POP ART ───────────────────────────────────────────────────────
  void _popArt(Canvas canvas, Rect face, Offset L, Offset R, double ed) {
    // Contorno bold negro
    canvas.drawOval(face, _stroke(Colors.black, 4));
    // Puntos Ben-Day en fondo
    final dotPaint = Paint()..color = const Color(0x66FF1744);
    for (double x = face.left; x < face.right; x += 14) {
      for (double y = face.top; y < face.bottom; y += 14) {
        canvas.drawCircle(Offset(x, y), 4, dotPaint);
      }
    }
    // Ojos bold
    for (final eye in [L, R]) {
      canvas.drawCircle(eye, ed * 0.35, _fill(Colors.white));
      canvas.drawCircle(eye, ed * 0.35, _stroke(Colors.black, 3));
      canvas.drawCircle(eye, ed * 0.15, _fill(Colors.black));
      canvas.drawCircle(eye - Offset(ed * 0.1, ed * 0.1), ed * 0.07, _fill(Colors.white));
    }
    // Texto POP
    final tp = TextPainter(
      text: const TextSpan(text: "POW!", style: TextStyle(color: Color(0xFFFF1744), fontSize: 26, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(face.right - tp.width - 4, face.top - 30));
  }

  // ── 15. HOLO ──────────────────────────────────────────────────────────
  void _holo(Canvas canvas, Rect face, double ed) {
    final colors = [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple];
    // Líneas horizontales arcoíris sobre el rostro
    for (int i = 0; i < colors.length; i++) {
      final y = face.top + (face.height / colors.length) * i;
      canvas.drawLine(Offset(face.left, y), Offset(face.right, y),
        Paint()..color = colors[i].withValues(alpha: 0.4)..strokeWidth = face.height / colors.length - 1);
    }
    // Borde holográfico
    canvas.drawRRect(RRect.fromRectAndRadius(face, const Radius.circular(14)),
      _glow(Colors.white, 10, width: 5));
    canvas.drawRRect(RRect.fromRectAndRadius(face, const Radius.circular(14)),
      _stroke(Colors.white70, 2));
  }

  double cos(double angle) => angle == 0 ? 1 : (angle < 0 ? -cos(-angle) : _cos(angle));
  double sin(double angle) => _sin(angle);

  // Implementación simple sin importar dart:math
  double _cos(double x) {
    x = x % (2 * 3.14159265);
    double r = 1, t = 1;
    for (int i = 1; i <= 8; i++) { t *= -x * x / (2 * i * (2 * i - 1)); r += t; }
    return r;
  }
  double _sin(double x) {
    x = x % (2 * 3.14159265);
    double r = x, t = x;
    for (int i = 1; i <= 8; i++) { t *= -x * x / ((2 * i) * (2 * i + 1)); r += t; }
    return r;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ===============================================
// CLASES DE UI
// ===============================================
class FilterCarouselHorizontal extends StatelessWidget {
  final int activeId;
  final Function(int) onFilterChanged;

  FilterCarouselHorizontal({super.key, required this.activeId, required this.onFilterChanged});

  final List<Map<String, dynamic>> faceFilters = [
    {"id": 0,  "name": "Sin filtro",    "icon": Icons.block},
    {"id": 1,  "name": "Piel Suave",    "icon": Icons.face_retouching_natural},
    {"id": 2,  "name": "Neon Cyber",    "icon": Icons.center_focus_strong},
    {"id": 3,  "name": "Ojos Anime",    "icon": Icons.remove_red_eye},
    {"id": 5,  "name": "Joker",         "icon": Icons.sentiment_very_satisfied},
    {"id": 6,  "name": "Censura",       "icon": Icons.visibility_off},
    {"id": 7,  "name": "Estrellas",     "icon": Icons.masks},
    {"id": 8,  "name": "Calor",         "icon": Icons.thermostat},
    {"id": 9,  "name": "Vampiro",       "icon": Icons.coronavirus},
    {"id": 10, "name": "Lágrimas",      "icon": Icons.water_drop},
    {"id": 11, "name": "Visor",         "icon": Icons.smart_toy},
    {"id": 12, "name": "Zombie",        "icon": Icons.sick},
    {"id": 13, "name": "Boceto",        "icon": Icons.draw},
    {"id": 14, "name": "Pop Art",       "icon": Icons.color_lens},
    {"id": 15, "name": "Holográfico",   "icon": Icons.wifi_tethering},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      itemCount: faceFilters.length,
      itemBuilder: (context, index) {
        final filter = faceFilters[index];
        final isSelected = activeId == filter["id"];
        return GestureDetector(
          onTap: () => onFilterChanged(filter["id"]),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.3) : Colors.black45,
              border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white24, width: isSelected ? 2 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(filter["icon"], color: isSelected ? Colors.cyanAccent : Colors.white70, size: 24),
                const SizedBox(height: 2),
                Text(filter["name"],
                  style: TextStyle(color: isSelected ? Colors.cyanAccent : Colors.white70, fontSize: 8, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                  textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FilterCarouselWorld extends StatelessWidget {
  final int activeId;
  final Function(int) onFilterChanged;

  FilterCarouselWorld({super.key, required this.activeId, required this.onFilterChanged});

  final List<Map<String, dynamic>> worldFilters = [
    {"id": 0,  "name": "Sin filtro",     "icon": Icons.block},
    {"id": 1,  "name": "Luz Neón",       "icon": Icons.nightlight_round},
    {"id": 2,  "name": "Retro VHS",      "icon": Icons.videocam},
    {"id": 3,  "name": "Hora Dorada",    "icon": Icons.wb_sunny},
    {"id": 4,  "name": "Código",         "icon": Icons.memory},
    {"id": 5,  "name": "Blanco/Negro",   "icon": Icons.camera_roll},
    {"id": 6,  "name": "Ciudad Cyber",   "icon": Icons.location_city},
    {"id": 7,  "name": "Tonos Rosa",     "icon": Icons.favorite},
    {"id": 8,  "name": "Tono Sepia",     "icon": Icons.history},
    {"id": 9,  "name": "Mar Azul",       "icon": Icons.water},
    {"id": 10, "name": "Otoño",          "icon": Icons.eco},
    {"id": 11, "name": "Corona",         "icon": Icons.stars},
    {"id": 12, "name": "Cuernos",        "icon": Icons.warning},
    {"id": 13, "name": "Halo",           "icon": Icons.lens_blur},
    {"id": 14, "name": "Orejas Gato",    "icon": Icons.pets},
    {"id": 15, "name": "Astronauta",     "icon": Icons.rocket_launch},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      itemCount: worldFilters.length,
      itemBuilder: (context, index) {
        final filter = worldFilters[index];
        final isSelected = activeId == filter["id"];
        return GestureDetector(
          onTap: () => onFilterChanged(filter["id"]),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? const Color(0xFFD499FF).withValues(alpha: 0.3) : Colors.black45,
              border: Border.all(color: isSelected ? const Color(0xFFD499FF) : Colors.white24, width: isSelected ? 2 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(filter["icon"], color: isSelected ? const Color(0xFFD499FF) : Colors.white70, size: 20),
                const SizedBox(height: 2),
                Text(filter["name"],
                  style: TextStyle(color: isSelected ? const Color(0xFFD499FF) : Colors.white70, fontSize: 7, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                  textAlign: TextAlign.center, maxLines: 2),
              ],
            ),
          ),
        );
      },
    );
  }
}
