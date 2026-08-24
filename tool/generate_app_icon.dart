import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/images/logo.png');
  if (!file.existsSync()) {
    print('Error: assets/images/logo.png not found');
    return;
  }

  final bytes = file.readAsBytesSync();
  final logo = img.decodeImage(bytes);
  if (logo == null) {
    print('Error decoding logo image');
    return;
  }

  print('Loaded logo: ${logo.width}x${logo.height}, numChannels: ${logo.numChannels}');

  // Find bounding box of non-transparent content
  int minX = logo.width;
  int minY = logo.height;
  int maxX = 0;
  int maxY = 0;

  for (int y = 0; y < logo.height; y++) {
    for (int x = 0; x < logo.width; x++) {
      final pixel = logo.getPixel(x, y);
      if (pixel.a > 15) { // non-transparent
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  print('Bounding box: ($minX, $minY) to ($maxX, $maxY), width=${maxX - minX + 1}, height=${maxY - minY + 1}');

  // Crop logo to its tight bounding box
  final croppedWidth = (maxX - minX + 1).clamp(1, logo.width);
  final croppedHeight = (maxY - minY + 1).clamp(1, logo.height);
  final croppedLogo = img.copyCrop(logo, x: minX, y: minY, width: croppedWidth, height: croppedHeight);

  const canvasSize = 1024;
  const centerX = canvasSize / 2.0;
  const centerY = canvasSize / 2.0;
  const maxDist = 724.0; // sqrt(512^2 + 512^2)

  // 1. Create rich ambient radial background image for Android Adaptive Icons & iOS Master
  final bgImage = img.Image(width: canvasSize, height: canvasSize);
  for (int y = 0; y < canvasSize; y++) {
    for (int x = 0; x < canvasSize; x++) {
      final dx = x - centerX;
      final dy = y - centerY;
      final dist = sqrt(dx * dx + dy * dy);
      final double t = (dist / 512.0).clamp(0.0, 1.0);

      // Smooth radial gradient from rich deep navy #1B2B4A (center) to #060B14 (corners)
      final r = (27 * (1 - t * t) + 6 * (t * t)).round().clamp(0, 255);
      final g = (43 * (1 - t * t) + 11 * (t * t)).round().clamp(0, 255);
      final b = (74 * (1 - t * t) + 20 * (t * t)).round().clamp(0, 255);

      bgImage.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  final bgFile = File('assets/images/app_icon_background.png');
  bgFile.writeAsBytesSync(img.encodePng(bgImage));
  print('Saved background image to assets/images/app_icon_background.png');

  // 2. Create Android Adaptive Foreground (Sized to 630px ~61.5% safe zone to fill circle naturally without dark borders)
  final adaptiveForeground = img.Image(width: canvasSize, height: canvasSize);
  const adaptiveTargetSize = 630;
  final adaptiveScaledLogo = img.copyResize(
    croppedLogo,
    width: adaptiveTargetSize,
    height: adaptiveTargetSize,
    interpolation: img.Interpolation.cubic,
  );
  final adaptiveX = ((canvasSize - adaptiveTargetSize) / 2).round();
  final adaptiveY = ((canvasSize - adaptiveTargetSize) / 2).round();
  img.compositeImage(adaptiveForeground, adaptiveScaledLogo, dstX: adaptiveX, dstY: adaptiveY);

  final adaptiveFile = File('assets/images/app_icon_foreground.png');
  adaptiveFile.writeAsBytesSync(img.encodePng(adaptiveForeground));
  print('Saved adaptive foreground to assets/images/app_icon_foreground.png');

  // 3. Create iOS Master Canvas (740px ~72.2% size)
  final masterCanvas = img.Image.from(bgImage);
  const masterTargetSize = 740;
  final masterScaledLogo = img.copyResize(
    croppedLogo,
    width: masterTargetSize,
    height: masterTargetSize,
    interpolation: img.Interpolation.cubic,
  );
  final masterX = ((canvasSize - masterTargetSize) / 2).round();
  final masterY = ((canvasSize - masterTargetSize) / 2).round();
  img.compositeImage(masterCanvas, masterScaledLogo, dstX: masterX, dstY: masterY);

  final masterFile = File('assets/images/app_icon_master.png');
  masterFile.writeAsBytesSync(img.encodePng(masterCanvas));
  print('Saved master icon to assets/images/app_icon_master.png');
}
