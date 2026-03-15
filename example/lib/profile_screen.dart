import 'package:flutter/material.dart';
import 'dart:math' as math;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _selectedTab = 0;

  static const _purple = Color(0xFFD499FF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildStatsRow()),
          SliverToBoxAdapter(child: _buildAuthenticityCard()),
          SliverToBoxAdapter(child: _buildTabBar()),
          if (_selectedTab == 0) _buildPostsGrid() else _buildFavoritesGrid(),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 270,
      pinned: true,
      backgroundColor: Colors.black,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_horiz, color: Colors.white),
          onPressed: () {},
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A0A2E), Color(0xFF0A1A2E), Color(0xFF0A1A1A)],
                ),
              ),
            ),
            CustomPaint(painter: _StarfieldPainter()),
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 82, height: 82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_purple, Colors.cyanAccent],
                          ),
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(color: _purple.withValues(alpha: 0.4), blurRadius: 16),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.person, color: Colors.white, size: 42),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Flexible(
                                  child: Text(
                                    "@usuario_hypr",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _purple.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _purple, width: 1),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified, color: _purple, size: 11),
                                      SizedBox(width: 3),
                                      Text("HYPR", style: TextStyle(color: _purple, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              "Creador AR ✨  Explorando la realidad",
                              style: TextStyle(color: Colors.white60, fontSize: 12),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _actionButton("Editar Perfil", _purple, false),
                                const SizedBox(width: 8),
                                _actionButton("Compartir", Colors.white24, true),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, Color color, bool outline) {
    return Flexible(
      child: Container(
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: outline ? Colors.transparent : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: outline ? Colors.white38 : color, width: 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: outline ? Colors.white70 : color,
                fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _stat("248", "Publicaciones"),
          _statDivider(),
          _stat("12.4K", "Seguidores"),
          _statDivider(),
          _stat("891", "Siguiendo"),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 36, color: Colors.white12);

  Widget _buildAuthenticityCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0A2E), Color(0xFF0D1B2A)],
        ),
        border: Border.all(color: _purple.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: _purple.withValues(alpha: 0.08), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: _purple, size: 18),
              SizedBox(width: 8),
              Text("Score de Autenticidad",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 110, height: 68,
                child: CustomPaint(painter: _AuthScorePainter(score: 0.87)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    _scoreItem("Verificación ID", 0.95, const Color(0xFF00E5FF)),
                    const SizedBox(height: 9),
                    _scoreItem("Originalidad", 0.82, _purple),
                    const SizedBox(height: 9),
                    _scoreItem("Actividad", 0.78, const Color(0xFF69FF84)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _purple.withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.insights, color: _purple, size: 15),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    "Tu perfil es 87% auténtico en HYPR",
                    style: TextStyle(
                        color: _purple,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreItem(String label, double value, Color color) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 11))),
        const SizedBox(width: 8),
        SizedBox(
          width: 75,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text("${(value * 100).toInt()}%",
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12))),
      child: Row(
        children: [
          _tabItem(0, Icons.grid_on_rounded, "Mis Fotos"),
          _tabItem(1, Icons.favorite_border_rounded, "Favoritos"),
        ],
      ),
    );
  }

  Widget _tabItem(int index, IconData icon, String label) {
    final sel = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: sel ? _purple : Colors.transparent, width: 2),
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: sel ? _purple : Colors.white30, size: 22),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      color: sel ? _purple : Colors.white30,
                      fontSize: 11,
                      fontWeight:
                          sel ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostsGrid() {
    final mockPosts = [
      {'color': const Color(0xFF2D0A4E), 'icon': Icons.face_retouching_natural, 'label': 'Piel Suave'},
      {'color': const Color(0xFF001A2E), 'icon': Icons.smart_toy,              'label': 'Visor Cyber'},
      {'color': const Color(0xFF1A0000), 'icon': Icons.coronavirus,            'label': 'Vampiro'},
      {'color': const Color(0xFF0A1A0A), 'icon': Icons.sick,                   'label': 'Zombie'},
      {'color': const Color(0xFF2E1A00), 'icon': Icons.masks,                  'label': 'Estrellas'},
      {'color': const Color(0xFF1A001A), 'icon': Icons.stars,                  'label': 'Corona'},
      {'color': const Color(0xFF001A1A), 'icon': Icons.remove_red_eye,         'label': 'Ojos Anime'},
      {'color': const Color(0xFF2E0A0A), 'icon': Icons.sentiment_very_satisfied,'label': 'Joker'},
      {'color': const Color(0xFF0A002E), 'icon': Icons.wifi_tethering,         'label': 'Holográfico'},
      {'color': const Color(0xFF2E2A00), 'icon': Icons.thermostat,             'label': 'Calor'},
      {'color': const Color(0xFF00102E), 'icon': Icons.water_drop,             'label': 'Lágrimas'},
      {'color': const Color(0xFF002E10), 'icon': Icons.pets,                   'label': 'Orejas Gato'},
    ];
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final post = mockPosts[i % mockPosts.length];
          return Container(
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(color: post['color'] as Color),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(post['icon'] as IconData, color: Colors.white38, size: 30),
                const SizedBox(height: 4),
                Text(post['label'] as String,
                    style: const TextStyle(color: Colors.white24, fontSize: 8),
                    textAlign: TextAlign.center),
              ],
            ),
          );
        },
        childCount: 24,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
      ),
    );
  }

  Widget _buildFavoritesGrid() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_border,
                  color: Colors.white24, size: 52),
              const SizedBox(height: 16),
              const Text("Aún no tienes favoritos",
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 8),
              const Text("Guarda tus capturas favoritas aquí",
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Custom Painters ──────────────────────────────────────────────────────

class _AuthScorePainter extends CustomPainter {
  final double score;
  const _AuthScorePainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.92;
    final r = size.width * 0.44;
    const startAngle = math.pi;
    const sweepFull = math.pi;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle, sweepFull, false,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    // Filled arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle, sweepFull * score, false,
      Paint()
        ..color = const Color(0xFFD499FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    // Score text
    final tp = TextPainter(
      text: TextSpan(
        text: "${(score * 100).toInt()}%",
        style: const TextStyle(
          color: Color(0xFFD499FF),
          fontWeight: FontWeight.bold,
          fontSize: 17,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height - 5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StarfieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.25);
    final rand = math.Random(42);
    for (int i = 0; i < 60; i++) {
      final x = rand.nextDouble() * size.width;
      final y = rand.nextDouble() * size.height;
      final r = rand.nextDouble() * 1.5 + 0.3;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
