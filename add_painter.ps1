
$filePath = "lib\pantalla_principal.dart"
$content = [System.IO.File]::ReadAllText((Join-Path (Get-Location) $filePath), [System.Text.Encoding]::UTF8)

# 1. Add _DashedBorderPainter class after last } in file
$dashedPainter = @'

// ── Dashed border painter for ghost transactions ──────────────────────────
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double borderRadius;
  final double dashWidth;
  final double dashSpace;
  final double strokeWidth;

  const _DashedBorderPainter({
    required this.color,
    required this.borderRadius,
    required this.dashWidth,
    required this.dashSpace,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
          size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(borderRadius),
    );

    final path = Path()..addRRect(rrect);
    final PathMetrics pathMetrics = path.computeMetrics();

    for (final PathMetric metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
'@

# Remove trailing empty line if present, then append
$content = $content.TrimEnd()
$content = $content + "`r`n" + $dashedPainter

[System.IO.File]::WriteAllText((Join-Path (Get-Location) $filePath), $content, [System.Text.Encoding]::UTF8)
Write-Host "DashedBorderPainter added!"
