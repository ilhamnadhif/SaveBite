import 'package:flutter/material.dart';

/// Palet warna SaveBite — deep-green + aksen oranye hangat di atas cream.
/// Konsumen = hijau, Merchant = terakota/cokelat (color-coding peran).
class AppColors {
  AppColors._();

  // Backgrounds
  static const cream = Color(0xFFFBF7EF); // background layar utama
  static const galleryBg = Color(0xFFE7E1D4);
  static const tanPlaceholder = Color(0xFFE7DDC8);

  // Hijau (konsumen / brand)
  static const green = Color(0xFF0F3D2C); // deep green — primary
  static const greenDark = Color(0xFF16442F); // kartu di atas deep green
  static const greenBright = Color(0xFF27A36A); // aksen cerah
  static const greenAccent = Color(0xFF1E8456); // teks aksen hijau
  static const greenSoftBg = Color(0xFFE8F3EC); // bg lembut hijau
  static const greenSoftBorder = Color(0xFFC9E3D2);
  static const greenMuted = Color(0xFF9FC9B2); // teks pudar di atas hijau
  static const greenMutedDeep = Color(0xFF5C7E6C);

  // Merchant (terakota / cokelat)
  static const brown = Color(0xFF8A3A14); // header & teks merchant
  static const brownCard = Color(0xFF9C4720); // kartu stat di header merchant
  static const terracotta = Color(0xFFE2592B); // aksi merchant + "hemat"
  static const terracottaSoftBg = Color(0xFFFBEFDD);
  static const terracottaSoftBorder = Color(0xFFF0DDB9);
  static const terracottaText = Color(0xFF7A5536);
  static const merchantMuted = Color(0xFFF0C9A8);

  // Savings (oranye)
  static const saveBg = Color(0xFFFBE9DF);
  static const saveText = Color(0xFFC2410C);

  // Gold / amber
  static const amber = Color(0xFFEFA63C);
  static const amberAvatar = Color(0xFFF2A33C);
  static const goldOnDark = Color(0xFFEFC07A);

  // Teks
  static const ink = Color(0xFF16231C); // teks utama
  static const body = Color(0xFF5C685F); // body sekunder
  static const body2 = Color(0xFF4F6157);
  static const body3 = Color(0xFF4A574F);
  static const muted = Color(0xFF8A958C);
  static const mutedAlt = Color(0xFF9BA39B);
  static const navInactive = Color(0xFFA0A89F);
  static const strikethrough = Color(0xFFA39B89);
  static const captionWarm = Color(0xFF9B8E72);
  static const emptyIcon = Color(0xFFB7AE9B);

  // Border & garis
  static const border = Color(0xFFF0EADB);
  static const borderAlt = Color(0xFFECE4D3);
  static const divider = Color(0xFFF4EEE0);
  static const inputBorder = Color(0xFFE3D9C5);
  static const chipBorder = Color(0xFFE7DDC8);
  static const handle = Color(0xFFD7CFBE);
  static const rule = Color(0xFFD2CABA);
  static const chevron = Color(0xFFC8C0AE);

  // Chip / netral
  static const neutralChip = Color(0xFFF1ECE0);
  static const neutralChip2 = Color(0xFFEEF0EC);
  static const emptyCircle = Color(0xFFEEEAE0);

  // Error / danger
  static const danger = Color(0xFFC24420);
  static const dangerBg = Color(0xFFFBE4DB);
  static const dangerSoftBg = Color(0xFFFBE8E2);
  static const dangerTintBg = Color(0xFFFBEDE6);
  static const ratingBg = Color(0xFFFCEFE9);

  // Scanner (gelap)
  static const scanBg = Color(0xFF101512);
  static const scanCard = Color(0xFF1B221D);
  static const scanCardBorder = Color(0xFF2A332C);
  static const scanMuted = Color(0xFF9FB3A6);

  // Peta
  static const mapBg = Color(0xFFE6E9E0);
  static const mapGrid = Color(0xFFDCE2D6);
  static const mapGridBg = Color(0xFFE9ECE3);
  static const mapRoad = Color(0xFFCFD8C6);

  // Brand pembayaran / aksen
  static const userDot = Color(0xFF2D7BE5);
  static const bca = Color(0xFF005BAA);
  static const gopay = Color(0xFF00AA13);
  static const ovo = Color(0xFF4C2A86);

  // Putih
  static const white = Color(0xFFFFFFFF);
}
