import 'package:flutter/material.dart';

/// The app's single [ThemeData]: every colour any widget needs derives from
/// this scheme (no widget-local hardcoded colours).
ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B6CFF)),
    fontFamilyFallback: const [
      'Nirmala UI',
      'Nirmala Text',
      'Segoe UI',
      'Segoe UI Historic',
      'Segoe UI Symbol',
      'Arial Unicode MS',
      'Mangal',
      'Utsaah',
      'Aparajita',
      'Kokila',
      'Nirmala UI Semilight',
      'Vrinda',
      'Raavi',
      'Ebrima',
      'Gadugi',
      'Leelawadee UI',
      'Javanese Text',
      'Myanmar Text',
      'Mongolian Baiti',
      'Microsoft Himalaya',
      'Microsoft Yi Baiti',
      'Sylfaen',
      'Microsoft YaHei',
      'Microsoft JhengHei',
      'SimSun',
      'NSimSun',
      'Meiryo',
      'Malgun Gothic',
    ],
    useMaterial3: true,
  );
}
