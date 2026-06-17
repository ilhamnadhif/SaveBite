import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B3 Peta — bag di-plot di map.
/// Pola: KONTEN TAB, tetapi mengembalikan Stack full-bleed (bukan Column).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// Penempatan & gaya pin untuk tiap bag terdekat (mengikuti posisi & warna lama).
class _PinSpot {
  final double topFactor;
  final double leftFactor;
  final Color background;
  final Color foreground;
  const _PinSpot({
    required this.topFactor,
    required this.leftFactor,
    required this.background,
    required this.foreground,
  });
}

class _MapScreenState extends State<MapScreen> {
  // Posisi pin reuse dari desain lama, ditambah dua titik agar muat 4–5 bag.
  static const _spots = [
    _PinSpot(
      topFactor: 0.36,
      leftFactor: 0.28,
      background: AppColors.green,
      foreground: AppColors.amber,
    ),
    _PinSpot(
      topFactor: 0.50,
      leftFactor: 0.58,
      background: AppColors.greenBright,
      foreground: AppColors.white,
    ),
    _PinSpot(
      topFactor: 0.28,
      leftFactor: 0.64,
      background: AppColors.terracotta,
      foreground: AppColors.white,
    ),
    _PinSpot(
      topFactor: 0.44,
      leftFactor: 0.40,
      background: AppColors.greenBright,
      foreground: AppColors.white,
    ),
  ];

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    appState.loadConsumerHome();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.dark(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          // Pins dari data live (cache); ambil maksimum 4 & batasi indeks pilih.
          final bags = appState.nearbyBags.take(4).toList(growable: false);
          final selectedIndex =
              bags.isEmpty ? 0 : _selectedIndex.clamp(0, bags.length - 1);

          return Stack(
            children: [
              // Latar peta + grid.
              Positioned.fill(
                child: CustomPaint(painter: _MapGridPainter()),
              ),
              // Jalan (road bars) yang dirotasi.
              Positioned(
                top: size.height * 0.30,
                left: size.width * 0.18,
                child: Transform.rotate(
                  angle: 20 * 3.1415926535 / 180,
                  child: Container(
                    width: 90,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.mapRoad,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: size.height * 0.55,
                left: size.width * 0.50,
                child: Transform.rotate(
                  angle: -12 * 3.1415926535 / 180,
                  child: Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.mapRoad,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
              ),

              // Search bar mengambang (respek inset status bar; desain pakai top:58).
              Positioned(
                top: topInset + 12,
                left: 20,
                right: 20,
                child: _searchBar(context),
              ),

              // Price pins per bag terdekat.
              for (int i = 0; i < bags.length; i++)
                Positioned(
                  top: size.height * _spots[i].topFactor,
                  left: size.width * _spots[i].leftFactor,
                  child: _PricePin(
                    label: _pinLabel(bags[i].salePrice),
                    background: _spots[i].background,
                    foreground: _spots[i].foreground,
                    selected: i == selectedIndex,
                    onTap: () => setState(() => _selectedIndex = i),
                  ),
                ),

              // Titik lokasi pengguna.
              Positioned(
                top: size.height * 0.70,
                left: size.width * 0.38,
                child: const _UserDot(),
              ),

              // Kartu bawah (hanya saat ada bag).
              if (bags.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 34,
                  child: _bottomCard(context, bags[selectedIndex]),
                ),
            ],
          );
        },
      ),
    );
  }

  String _pinLabel(int salePrice) => 'Rp${salePrice ~/ 1000}rb';

  Widget _searchBar(BuildContext context) {
    return GestureDetector(
      onTap: () => AppNav.toSearch(context),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Text('Cari di area ini…',
                style: AppText.ui(14.5, color: AppColors.mutedAlt)),
          ],
        ),
      ),
    );
  }

  Widget _bottomCard(BuildContext context, Bag bag) {
    return GestureDetector(
      onTap: () => AppNav.toDetail(context, bag),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 30,
              offset: Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: FoodImage(bag.image, width: 78, height: 78),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(bag.merchant.name,
                              style:
                                  AppText.ui(14, weight: 700, color: AppColors.ink)),
                        ),
                        const SizedBox(width: 6),
                        Text('★ ${bag.merchant.rating}',
                            style: AppText.ui(12,
                                weight: 600, color: AppColors.body)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 8),
                      child: _DistanceLine(
                          '${bag.merchant.distance} · ambil ${bag.pickupWindow}'),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(formatRupiah(bag.originalPrice),
                            style: AppText.ui(12,
                                color: AppColors.strikethrough,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: AppColors.strikethrough)),
                        const SizedBox(width: 8),
                        Text(formatRupiah(bag.salePrice),
                            style: AppText.display(17,
                                weight: 800, color: AppColors.greenBright)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DistanceLine extends StatelessWidget {
  final String text;
  const _DistanceLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.ui(12.5, color: AppColors.body));
  }
}

class _PricePin extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final bool selected;
  final VoidCallback onTap;

  const _PricePin({
    required this.label,
    required this.background,
    required this.foreground,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(color: AppColors.white, width: 2)
                  : null,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(label,
                style: AppText.ui(12, weight: 800, color: foreground)),
          ),
          CustomPaint(size: const Size(12, 8), painter: _TrianglePainter(background)),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: AppColors.userDot,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332D7BE5),
            blurRadius: 0,
            spreadRadius: 6,
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = AppColors.mapGridBg;
    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..color = AppColors.mapGrid
      ..strokeWidth = 1;
    const step = 46.0;
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
