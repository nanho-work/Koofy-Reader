import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_layout_controller.dart';

void main() {
  test(
    'auto mode does not flip to double on narrow viewport height changes',
    () {
      final controller = ReaderLayoutController(
        settings: ReaderSettings.defaults(),
      );

      final narrowShrunkenViewport = const Size(368.8, 467.4);

      expect(controller.isDoublePageMode(narrowShrunkenViewport), isFalse);
    },
  );

  test('auto mode still uses double on wide viewport', () {
    final controller = ReaderLayoutController(
      settings: ReaderSettings.defaults(),
    );

    expect(controller.isDoublePageMode(const Size(707.0, 731.0)), isTrue);
  });

  test('auto mode still uses double when a fold feature is present', () {
    final controller = ReaderLayoutController(
      settings: ReaderSettings.defaults(),
    );
    final mediaQueryData = MediaQueryData(
      displayFeatures: const <DisplayFeature>[
        DisplayFeature(
          bounds: Rect.fromLTWH(400, 0, 16, 800),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    );

    expect(
      controller.isDoublePageMode(
        const Size(368.8, 712.0),
        mediaQueryData: mediaQueryData,
      ),
      isTrue,
    );
  });
}
