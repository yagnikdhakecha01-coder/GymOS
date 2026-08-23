import 'dart:io';
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
      if (pixel.a > 10) { // non-transparent
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

  // Create a 1024x1024 master canvas with a sleek dark background (#070D18 / #0B1329)
  // Matching GymOS dark aesthetic
  const canvasSize = 1024;
  final masterCanvas = img.Image(width: canvasSize, height: canvasSize);

  // Fill canvas with a rich deep midnight background
  // Top: #0D1527, Bottom: #070D18
  for (int y = 0; y < canvasSize; y++) {
    final double t = y / canvasSize;
    final r = (13 * (1 - t) + 7 * t).round();
    final g = (21 * (1 - t) + 13 * t).round();
    final b = (39 * (1 - t) + 24 * t).round();
    for (int x = 0; x < canvasSize; x++) {
      masterCanvas.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Scale the cropped logo to ~68% of the canvas for iOS so it looks bold, centered, and balanced
  const targetLogoSize = 700;
  final scaledLogo = img.copyResize(
    croppedLogo,
    width: targetLogoSize,
    height: targetLogoSize,
    interpolation: img.Interpolation.cubic,
  );

  final destX = ((canvasSize - targetLogoSize) / 2).round();
  final destY = ((canvasSize - targetLogoSize) / 2).round();

  // Composite the scaled logo onto the master canvas
  img.compositeImage(masterCanvas, scaledLogo, dstX: destX, dstY: destY);

  // Save the master icon
  final masterFile = File('assets/images/app_icon_master.png');
  masterFile.writeAsBytesSync(img.encodePng(masterCanvas));
  print('Saved master icon to assets/images/app_icon_master.png');

  // Also create a centered foreground for Android Adaptive Icon (needs ~432x432 inside 1024x1024 safe zone)
  final adaptiveForeground = img.Image(width: canvasSize, height: canvasSize);
  const adaptiveTargetSize = 540;
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
}
