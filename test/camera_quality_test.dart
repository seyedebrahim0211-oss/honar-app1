import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jan_fada/portrait_camera.dart';

void main() {
  test('flat/overexposed frame is rejected by quality heuristics', () {
    final frame = img.Image(width: 160, height: 200);
    img.fill(frame, color: img.ColorRgb8(245, 245, 245));
    final score = FrameQuality.fromRgb(frame);
    expect(score.brightness, greaterThan(214));
    expect(score.edgeEnergy, lessThan(1));
  });

  test('detailed picture yields greater sharpness score than a blank picture', () {
    final flat = img.Image(width: 160, height: 200);
    final patterned = img.Image(width: 160, height: 200);
    img.fill(flat, color: img.ColorRgb8(120, 120, 120));
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 160; x++) {
        final luma = ((x ~/ 9 + y ~/ 9) % 2) == 0 ? 30 : 215;
        patterned.setPixelRgb(x, y, luma, luma, luma);
      }
    }
    expect(FrameQuality.fromRgb(patterned).edgeEnergy,
      greaterThan(FrameQuality.fromRgb(flat).edgeEnergy));
  });
}
