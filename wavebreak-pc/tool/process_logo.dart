// The source PNG already has real alpha (viewers just composite it onto
// white). This just auto-crops to content and splits the mark from the
// wordmark for the different asset sizes the app needs.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(
    File('assets/branding/wavebreak_logo_source.png').readAsBytesSync(),
  )!;
  stdout.writeln('Source: ${src.width}x${src.height}');

  var minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      if (src.getPixel(x, y).a > 10) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  stdout.writeln('Content bbox: ($minX,$minY) - ($maxX,$maxY)');

  const pad = 6;
  minX = (minX - pad).clamp(0, src.width - 1);
  minY = (minY - pad).clamp(0, src.height - 1);
  maxX = (maxX + pad).clamp(0, src.width - 1);
  maxY = (maxY + pad).clamp(0, src.height - 1);

  final full = img.copyCrop(
    src,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );
  File('assets/branding/wavebreak_logo_full.png').writeAsBytesSync(img.encodePng(full));
  stdout.writeln('Wrote full lockup: ${full.width}x${full.height}');

  // Find the vertical gap between the mark and the wordmark below it.
  final rowHasContent = List<bool>.filled(full.height, false);
  for (var y = 0; y < full.height; y++) {
    for (var x = 0; x < full.width; x++) {
      if (full.getPixel(x, y).a > 10) {
        rowHasContent[y] = true;
        break;
      }
    }
  }
  var gapStart = -1, gapEnd = -1, bestGapLen = 0, bestStart = -1;
  for (var y = 0; y < full.height; y++) {
    if (!rowHasContent[y]) {
      if (gapStart == -1) gapStart = y;
      gapEnd = y;
    } else if (gapStart != -1) {
      final len = gapEnd - gapStart;
      if (len > bestGapLen) {
        bestGapLen = len;
        bestStart = gapStart;
      }
      gapStart = -1;
    }
  }
  stdout.writeln('Largest empty row band starts at $bestStart, length $bestGapLen');

  if (bestStart > 0) {
    final markOnly = img.copyCrop(full, x: 0, y: 0, width: full.width, height: bestStart);
    var mMinX = markOnly.width, mMaxX = 0, mMinY = markOnly.height, mMaxY = 0;
    for (var y = 0; y < markOnly.height; y++) {
      for (var x = 0; x < markOnly.width; x++) {
        if (markOnly.getPixel(x, y).a > 10) {
          if (x < mMinX) mMinX = x;
          if (x > mMaxX) mMaxX = x;
          if (y < mMinY) mMinY = y;
          if (y > mMaxY) mMaxY = y;
        }
      }
    }
    final markCropped = img.copyCrop(
      markOnly,
      x: mMinX,
      y: mMinY,
      width: mMaxX - mMinX + 1,
      height: mMaxY - mMinY + 1,
    );
    File('assets/branding/wavebreak_mark.png').writeAsBytesSync(img.encodePng(markCropped));
    stdout.writeln('Wrote mark-only: ${markCropped.width}x${markCropped.height}');

    // Everything below the gap is the wordmark.
    final wordTop = bestStart + bestGapLen;
    final wordmarkOnly = img.copyCrop(
      full,
      x: 0,
      y: wordTop,
      width: full.width,
      height: full.height - wordTop,
    );
    var wMinX = wordmarkOnly.width, wMaxX = 0, wMinY = wordmarkOnly.height, wMaxY = 0;
    for (var y = 0; y < wordmarkOnly.height; y++) {
      for (var x = 0; x < wordmarkOnly.width; x++) {
        if (wordmarkOnly.getPixel(x, y).a > 10) {
          if (x < wMinX) wMinX = x;
          if (x > wMaxX) wMaxX = x;
          if (y < wMinY) wMinY = y;
          if (y > wMaxY) wMaxY = y;
        }
      }
    }
    final wordmarkCropped = img.copyCrop(
      wordmarkOnly,
      x: wMinX,
      y: wMinY,
      width: wMaxX - wMinX + 1,
      height: wMaxY - wMinY + 1,
    );
    File('assets/branding/wavebreak_wordmark.png')
        .writeAsBytesSync(img.encodePng(wordmarkCropped));
    stdout.writeln('Wrote wordmark-only: ${wordmarkCropped.width}x${wordmarkCropped.height}');

    // Square app icon: the mark centered on the brand midnight background.
    const iconSize = 1024;
    final icon = img.Image(width: iconSize, height: iconSize, numChannels: 4);
    img.fill(icon, color: img.ColorUint8.rgb(0x0B, 0x10, 0x20));
    final markAspect = markCropped.width / markCropped.height;
    final targetW = (iconSize * 0.72).round();
    final targetH = (targetW / markAspect).round();
    final resizedMark = img.copyResize(markCropped, width: targetW, height: targetH);
    img.compositeImage(
      icon,
      resizedMark,
      dstX: (iconSize - targetW) ~/ 2,
      dstY: (iconSize - targetH) ~/ 2,
    );
    File('assets/branding/wavebreak_icon_1024.png').writeAsBytesSync(img.encodePng(icon));
    stdout.writeln('Wrote app icon: ${icon.width}x${icon.height}');

    // Square, transparent-background version for compact UI spots (connect
    // button, drawer icon) where the wide mark needs to sit in a square box
    // without stretching or a visible background tile.
    const sq = 800;
    final square = img.Image(width: sq, height: sq, numChannels: 4);
    final sqTargetW = (sq * 0.86).round();
    final sqTargetH = (sqTargetW / markAspect).round();
    final sqMark = img.copyResize(markCropped, width: sqTargetW, height: sqTargetH);
    img.compositeImage(
      square,
      sqMark,
      dstX: (sq - sqTargetW) ~/ 2,
      dstY: (sq - sqTargetH) ~/ 2,
    );
    File('assets/branding/wavebreak_mark_square.png').writeAsBytesSync(img.encodePng(square));
    stdout.writeln('Wrote square mark: ${square.width}x${square.height}');
  }
}
