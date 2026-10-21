import 'dart:ui';

/// `allGridOptions` from the original script (texts kept verbatim).
class GridOption {
  final String value;
  final String text;
  final int count;
  const GridOption(this.value, this.text, this.count);
}

const allGridOptions = <GridOption>[
  GridOption('auto', 'Auto Adjust (No Gap)', 0),
  GridOption('1x1', '1 Col x 1 Row (1 pic)', 1),
  GridOption('1x2', '1 Col x 2 Row (2 pics)', 2),
  GridOption('2x1', '2 Col x 1 Row (2 pics)', 2),
  GridOption('1+2', '3 pics (1 Row 1 + 1 Row 2)', 3),
  GridOption('2+1', '3 pics (1 Row 2 + 1 Row 1)', 3),
  GridOption('1x3', '1 Col x 3 Row (3 pics)', 3),
  GridOption('3x1', '3 Col x 1 Row (3 pics)', 3),
  GridOption('2x2', '2 Col x 2 Row (4 pics)', 4),
  GridOption('1x4', '1 Col x 4 Row (4 pics)', 4),
  GridOption('4x1', '4 Col x 1 Row (4 pics)', 4),
  GridOption('1+3', '4 pics (1+3 Row)', 4),
  GridOption('3+1', '4 pics (3+1 Row)', 4),
  GridOption('3+2', '5 pics (3+2 Row)', 5),
  GridOption('2+3', '5 pics (2+3 Row)', 5),
  GridOption('1+4', '5 pics (1+4 Row)', 5),
  GridOption('4+1', '5 pics (4+1 Row)', 5),
  GridOption('2x3', '2 Col x 3 Row (6 pics)', 6),
  GridOption('3x2', '3 Col x 2 Row (6 pics)', 6),
  GridOption('1x6', '1 Col x 6 Row (6 pics)', 6),
  GridOption('6x1', '6 Col x 1 Row (6 pics)', 6),
  GridOption('4+3', '7 pics (4+3 Row)', 7),
  GridOption('3+4', '7 pics (3+4 Row)', 7),
  GridOption('2+3+2', '7 pics (2+3+2 Row)', 7),
  GridOption('2x4', '2 Col x 4 Row (8 pics)', 8),
  GridOption('4x2', '4 Col x 2 Row (8 pics)', 8),
  GridOption('3+3+2', '8 pics (3+3+2 Row)', 8),
  GridOption('3x3', '3 Col x 3 Row (9 pics)', 9),
  GridOption('4+5', '9 pics (4+5 Row)', 9),
  GridOption('5+4', '9 pics (5+4 Row)', 9),
  GridOption('2x5', '2 Col x 5 Row (10 pics)', 10),
  GridOption('5x2', '5 Col x 2 Row (10 pics)', 10),
  GridOption('3+4+3', '10 pics (3+4+3 Row)', 10),
  GridOption('4+4+3', '11 pics (4+4+3 Row)', 11),
  GridOption('3+5+3', '11 pics (3+5+3 Row)', 11),
  GridOption('3x4', '3 Col x 4 Row (12 pics)', 12),
  GridOption('4x3', '4 Col x 3 Row (12 pics)', 12),
  GridOption('2x6', '2 Col x 6 Row (12 pics)', 12),
  GridOption('6x2', '6 Col x 2 Row (12 pics)', 12),
  GridOption('4+5+4', '13 pics (4+5+4 Row)', 13),
  GridOption('3+4+3+3', '13 pics (3+4+3+3 Row)', 13),
  GridOption('2x7', '2 Col x 7 Row (14 pics)', 14),
  GridOption('7x2', '7 Col x 2 Row (14 pics)', 14),
  GridOption('4+3+4+3', '14 pics (4+3+4+3 Row)', 14),
  GridOption('3x5', '3 Col x 5 Row (15 pics)', 15),
  GridOption('5x3', '5 Col x 5 Row (15 pics)', 15),
  GridOption('4x4', '4 Col x 4 Row (16 pics)', 16),
  GridOption('2x8', '2 Col x 8 Row (16 pics)', 16),
  GridOption('8x2', '8 Col x 2 Row (16 pics)', 16),
  GridOption('4+4+5+4', '17 pics (4+4+5+4 Row)', 17),
  GridOption('5+4+5+3', '17 pics (5+4+5+3 Row)', 17),
  GridOption('3x6', '3 Col x 6 Row (18 pics)', 18),
  GridOption('6x3', '6 Col x 3 Row (18 pics)', 18),
  GridOption('2x9', '2 Col x 9 Row (18 pics)', 18),
  GridOption('5+5+5+4', '19 pics (5+5+5+4 Row)', 19),
  GridOption('4+5+6+4', '19 pics (4+5+6+4 Row)', 19),
  GridOption('4x5', '4 Col x 5 Row (20 pics)', 20),
  GridOption('5x4', '5 Col x 4 Row (20 pics)', 20),
  GridOption('2x10', '2 Col x 10 Row (20 pics)', 20),
  GridOption('3x7', '3 Col x 7 Row (21 pics)', 21),
  GridOption('7x3', '7 Col x 3 Row (21 pics)', 21),
  GridOption('5+6+6+5', '22 pics (5+6+6+5 Row)', 22),
  GridOption('2x11', '2 Col x 11 Row (22 pics)', 22),
  GridOption('6+6+6+5', '23 pics (6+6+6+5 Row)', 23),
  GridOption('4x6', '4 Col x 6 Row (24 pics)', 24),
  GridOption('6x4', '6 Col x 4 Row (24 pics)', 24),
  GridOption('3x8', '3 Col x 8 Row (24 pics)', 24),
  GridOption('5x5', '5 Col x 5 Row (25 pics)', 25),
  GridOption('5+6+5+5+5', '26 pics (5+6+5+5+5 Row)', 26),
  GridOption('3x9', '3 Col x 9 Row (27 pics)', 27),
  GridOption('9x3', '9 Col x 3 Row (27 pics)', 27),
  GridOption('4x7', '4 Col x 7 Row (28 pics)', 28),
  GridOption('7x4', '7 Col x 4 Row (28 pics)', 28),
  GridOption('6+6+6+6+5', '29 pics (6+6+6+6+5 Row)', 29),
  GridOption('5x6', '5 Col x 6 Row (30 pics)', 30),
  GridOption('6x5', '6 Col x 5 Row (30 pics)', 30),
  GridOption('3x10', '3 Col x 10 Row (30 pics)', 30),
];

/// Quality presets: (id, label, jpegQuality, resolutionScale).
class QualityPreset {
  final String id, label;
  final double q, res;
  const QualityPreset(this.id, this.label, this.q, this.res);
}

const qualityPresets = <QualityPreset>[
  QualityPreset('q-1', 'Low', 0.4, 0.6),
  QualityPreset('q-2', 'Medium', 0.7, 0.8),
  QualityPreset('q-3', 'High', 0.92, 1.0),
  QualityPreset('q-super', 'Super HD', 0.96, 1.2),
  QualityPreset('q-4', 'Ultra', 1.0, 1.5),
];

/// Palette entry (computedColorsList from baseSolidColors).
class PaletteColor {
  final Color value; // colour stored in the shape
  final Color display; // swatch colour
  final Color border;
  final bool isPureWhite;
  final String? key;
  const PaletteColor(this.value, this.display, this.border, {this.isPureWhite = false, this.key});
}

Color _rgba(int r, int g, int b, [double a = 1]) => Color.fromARGB((a * 255).round(), r, g, b);
Color _hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

class _Base {
  final String hex;
  final Color rgba, rgba30;
  final bool isWhite;
  final String? key;
  const _Base(this.hex, this.rgba, this.rgba30, {this.isWhite = false, this.key});
}

final _baseSolidColors = <_Base>[
  _Base('#fff200', _rgba(253, 255, 19), _rgba(255, 242, 0), key: 'yellow'),
  _Base('#00ff22', _rgba(0, 255, 34), _rgba(136, 255, 38), key: 'green'),
  _Base('#71FF8B', _rgba(113, 255, 139), _rgba(255, 23, 139)),
  _Base('#00e5ff', _rgba(0, 229, 255), _rgba(23, 255, 192), key: 'skyblue'),
  _Base('#ff9100', _rgba(255, 145, 0), _rgba(255, 191, 113)),
  _Base('#b700ff', _rgba(183, 0, 255), _rgba(238, 68, 255)),
  _Base('#9FE5FF', _rgba(160, 215, 254), _rgba(218, 112, 214)),
  _Base('#FF9517', _rgba(169, 229, 255), _rgba(255, 183, 178)),
  _Base('#ff7b7b', _rgba(255, 123, 123), _rgba(255, 38, 255)),
  _Base('#323232', _rgba(50, 50, 50, 0.85), _rgba(50, 0, 0)),
  _Base('#ffffff', _rgba(255, 255, 255), _rgba(255, 255, 255, 0.8), isWhite: true, key: 'white'),
];

final List<PaletteColor> computedColorsList = () {
  final list = <PaletteColor>[];
  for (final c in _baseSolidColors) {
    list.add(PaletteColor(c.rgba, _hex(c.hex), c.hex == '#ffffff' ? const Color(0xFF555555) : const Color(0xFFFFFFFF),
        isPureWhite: c.isWhite, key: c.key));
    if (!c.isWhite) list.add(PaletteColor(c.rgba30, c.rgba30, const Color(0xFFAAAAAA)));
  }
  return list;
}();

bool isWhiteColor(int argb) {
  final c = Color(argb);
  return (c.r * 255).round() == 255 && (c.g * 255).round() == 255 && (c.b * 255).round() == 255;
}

const shapeTypes = <(String, String)>[
  ('rect', 'Rectangle'),
  ('oval', 'Oval / Circle'),
  ('free', 'Free Hand'),
  ('free_straight', 'Free Hand (Straight Line)'),
  ('text', '✍️ Add Text'),
  ('select', 'Select & Transform'),
];

const blendModes = <(String, String)>[
  ('multiply', 'Multiply (Highlight)'),
  ('source-over', 'Normal (White / Opaque)'),
];
