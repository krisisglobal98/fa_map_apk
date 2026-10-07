import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../core/geo.dart';

class RefPolygon {
  RefPolygon(this.label, this.outer, this.properties);
  final String label;
  final List<LatLng> outer;
  final Map<String, dynamic> properties;

  late final double _w = outer.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
  late final double _e = outer.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
  late final double _s = outer.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
  late final double _n = outer.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);

  bool contains(LatLng p) {
    if (p.longitude < _w || p.longitude > _e || p.latitude < _s || p.latitude > _n) return false;
    return Geo.pointInPolygon(p, outer);
  }

  LatLng get center {
    var lat = 0.0, lon = 0.0;
    final pts = outer.length > 1 && outer.first == outer.last ? outer.sublist(0, outer.length - 1) : outer;
    for (final p in pts) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / pts.length, lon / pts.length);
  }
}

/// Lapisan referensi vektor (mis. batas blok) dari GeoJSON.
class ReferenceLayer {
  ReferenceLayer({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    this.labelField,
    this.visible = true,
    this.polygons = const [],
    this.lines = const [],
  });

  final String id;
  final String name;
  final String path;
  final String? labelField;
  bool visible;
  final DateTime createdAt;
  List<RefPolygon> polygons;
  List<List<LatLng>> lines;

  static const labelCandidates = ['blok', 'block', 'kode_blok', 'name', 'nama', 'label', 'id'];

  /// Membaca FeatureCollection: Polygon, MultiPolygon, LineString, MultiLineString.
  static ({List<RefPolygon> polygons, List<List<LatLng>> lines, String? labelField}) parseGeoJson(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    final feats = data['type'] == 'FeatureCollection'
        ? (data['features'] as List).cast<Map<String, dynamic>>()
        : [data];
    final polys = <RefPolygon>[];
    final lines = <List<LatLng>>[];
    String? labelField;

    List<LatLng> ring(List coords) =>
        coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();

    for (final f in feats) {
      final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? {};
      labelField ??= labelCandidates.firstWhere((k) => props.containsKey(k), orElse: () => '');
      if (labelField.isEmpty) labelField = null;
      final label = labelField == null ? '' : '${props[labelField] ?? ''}';
      final g = f['geometry'] as Map<String, dynamic>?;
      if (g == null) continue;
      final coords = g['coordinates'] as List;
      switch (g['type']) {
        case 'Polygon':
          polys.add(RefPolygon(label, ring(coords.first as List), props));
          break;
        case 'MultiPolygon':
          for (final p in coords) {
            polys.add(RefPolygon(label, ring((p as List).first as List), props));
          }
          break;
        case 'LineString':
          lines.add(ring(coords));
          break;
        case 'MultiLineString':
          for (final l in coords) {
            lines.add(ring(l as List));
          }
          break;
      }
    }
    return (polygons: polys, lines: lines, labelField: labelField);
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'path': path,
        'label_field': labelField,
        'visible': visible ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory ReferenceLayer.fromRow(Map<String, Object?> r) => ReferenceLayer(
        id: r['id'] as String,
        name: r['name'] as String,
        path: r['path'] as String,
        labelField: r['label_field'] as String?,
        visible: (r['visible'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}
