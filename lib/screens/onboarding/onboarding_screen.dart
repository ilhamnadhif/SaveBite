import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// A2 Onboarding. Pola: LAYAR PENUH (Scaffold sendiri) + PageView carousel.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_Slide> _slides = [
    _Slide(
      image: SampleData.img5,
      title: 'Makanan enak, harga miring.',
      body:
          'Tiap sore, toko favoritmu mengemas stok berlebih jadi Surprise Bag dengan diskon 50–70%. Tinggal pesan, ambil sendiri, hemat banyak.',
    ),
    _Slide(
      image: SampleData.img2,
      title: 'Ambil sendiri, tanpa ribet.',
      body:
          'Pesan & bayar di aplikasi, lalu ambil pesananmu di toko pada jam yang ditentukan. Tunjukkan QR, beres.',
    ),
    _Slide(
      image: SampleData.img7,
      title: 'Kurangi makanan terbuang.',
      body:
          'Setiap bag yang kamu selamatkan ikut mengurangi food waste — hemat untukmu, baik untuk bumi.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await appState.markOnboardingSeen();
    if (mounted) AppNav.toFork(context);
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Padding(
          padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 32),
          child: Column(
            children: [
              // Lewati
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _finish,
                  child: Text(
                    'Lewati',
                    style: AppText.ui(15, weight: 600, color: AppColors.muted),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: _slides.length,
                  itemBuilder: (context, i) => _slideView(_slides[i]),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(label: 'Lanjut', onTap: _next),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slideView(_Slide slide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Center(child: _imageBlock(slide.image))),
        _dots(),
        Text(
          slide.title,
          style: AppText.display(28, weight: 800, height: 1.12),
        ),
        const SizedBox(height: 10),
        Text(
          slide.body,
          style: AppText.ui(15, color: AppColors.body, height: 1.55),
        ),
      ],
    );
  }

  Widget _imageBlock(String image) {
    return SizedBox(
      width: double.infinity,
      height: 300,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.chipBorder,
                border: Border.all(color: AppColors.inputBorder),
              ),
            ),
            FoodImage(image),
            // Bayangan dalam di bagian bawah (inset 0 -60px 60px -30px green/0.45).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 90,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0x73173D2C), // green @ ~0.45
                      Color(0x00173D2C),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < _slides.length; i++) ...[
            _Dot(active: i == _page),
            if (i != _slides.length - 1) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: active ? 22 : 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? AppColors.green : AppColors.handle,
        borderRadius: BorderRadius.circular(active ? 4 : 50),
      ),
    );
  }
}

class _Slide {
  final String image;
  final String title;
  final String body;
  const _Slide({required this.image, required this.title, required this.body});
}
