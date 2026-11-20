class WorkspaceBanner {
  const WorkspaceBanner(this.path, {this.x = 0, this.y = 0});

  final String path;
  final double x;
  final double y;

  static WorkspaceBanner? fromJson(Object? value) {
    if (value is! Map || value['path'] is! String ||
        (value['path'] as String).isEmpty) return null;
    return WorkspaceBanner(value['path'] as String,
        x: offset(value['x']), y: offset(value['y']));
  }

  static double offset(Object? value) =>
      value is num && value.isFinite ? value.clamp(-1.0, 1.0).toDouble() : 0;

  Map<String, Object> toJson() => {'path': path, 'x': x, 'y': y};
}
