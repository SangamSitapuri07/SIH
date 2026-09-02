import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/models.dart';
import '../theme.dart';

/// Full-screen map view that shows every PFZ polygon, geofence, and
/// point from a [MapPayload]. Uses OpenStreetMap tiles, no API key.
class MapScreen extends StatelessWidget {
  final MapPayload map;
  const MapScreen({super.key, required this.map});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marine map')),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: map.center,
          initialZoom: map.zoom,
          minZoom: 3,
          maxZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'in.sih.orca',
            maxZoom: 19,
          ),
          // Polygons first (so points sit on top)
          PolygonLayer(
            polygons: map.polygons
                .map(
                  (p) => Polygon(
                    points: p.coordinates,
                    color: _parseColor(p.color).withValues(alpha: 0.25),
                    borderColor: _parseColor(p.color),
                    borderStrokeWidth: 2,
                    isFilled: p.fill,
                    label: p.name,
                  ),
                )
                .toList(),
          ),
          // Markers for points (user + zone centroids)
          MarkerLayer(
            markers: map.points
                .map(
                  (pt) => Marker(
                    point: pt.position,
                    width: 60,
                    height: 60,
                    child: _MapMarker(
                      color: _parseColor(pt.color ?? '#3B82F6'),
                      label: pt.label ?? '',
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }
}

class _MapMarker extends StatelessWidget {
  final Color color;
  final String label;
  const _MapMarker({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.location_on, color: Colors.white, size: 12),
        ),
        if (label.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// Small inline map (used inside the chat screen) — the same widgets,
/// capped at a fixed height so it doesn't take over the screen.
class InlineMap extends StatelessWidget {
  final MapPayload map;
  final double height;
  const InlineMap({super.key, required this.map, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: MapScreen(map: map),
      ),
    );
  }
}
