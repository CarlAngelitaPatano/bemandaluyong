import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ===========================================================================
// Live Mandaluyong weather via Open-Meteo — free, no API key required.
// ===========================================================================
class Weather {
  final double tempC;
  final int code; // WMO weather code

  const Weather({required this.tempC, required this.code});

  /// Human label for the WMO weather code.
  String get label => switch (code) {
        0 => 'Clear sky',
        1 => 'Mostly clear',
        2 => 'Partly cloudy',
        3 => 'Cloudy',
        45 || 48 => 'Foggy',
        51 || 53 || 55 => 'Drizzle',
        61 || 63 || 65 => 'Rainy',
        66 || 67 => 'Freezing rain',
        71 || 73 || 75 || 77 => 'Snow',
        80 || 81 || 82 => 'Rain showers',
        95 => 'Thunderstorm',
        96 || 99 => 'Thunderstorm + hail',
        _ => 'Unsettled',
      };

  IconData get icon => switch (code) {
        0 || 1 => Icons.wb_sunny_outlined,
        2 => Icons.wb_cloudy_outlined,
        3 => Icons.cloud_outlined,
        45 || 48 => Icons.foggy,
        51 || 53 || 55 || 61 || 63 || 65 || 80 || 81 || 82 =>
          Icons.water_drop_outlined,
        95 || 96 || 99 => Icons.thunderstorm_outlined,
        _ => Icons.cloud_outlined,
      };
}

class WeatherService {
  WeatherService._();

  // Mandaluyong City center.
  static const _url =
      'https://api.open-meteo.com/v1/forecast?latitude=14.5794&longitude=121.0359'
      '&current=temperature_2m,weather_code&timezone=Asia%2FManila';

  /// Most recently fetched weather (used by notifications).
  static Weather? last;

  static Future<Weather> fetch() async {
    final res =
        await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw 'Weather unavailable';
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;
    final w = Weather(
      tempC: (current['temperature_2m'] as num).toDouble(),
      code: (current['weather_code'] as num).toInt(),
    );
    last = w;
    return w;
  }

  /// Fetches once if not already cached; quiet on failure.
  static Future<void> ensureLoaded() async {
    if (last != null) return;
    try {
      await fetch();
    } catch (_) {}
  }
}

/// Compact weather chip for the home banner. Quietly hides if offline.
class WeatherChip extends StatefulWidget {
  const WeatherChip({super.key});

  @override
  State<WeatherChip> createState() => _WeatherChipState();
}

class _WeatherChipState extends State<WeatherChip> {
  Weather? _weather;

  @override
  void initState() {
    super.initState();
    WeatherService.fetch().then((w) {
      if (mounted) setState(() => _weather = w);
    }).catchError((_) {}); // offline → just don't show
  }

  @override
  Widget build(BuildContext context) {
    final w = _weather;
    if (w == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
      ),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(w.icon, size: 16, color: colors.onPrimary),
          const SizedBox(width: 6),
          Text(
            '${w.tempC.round()}°C · ${w.label}',
            style: text.labelMedium?.copyWith(
              color: colors.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
