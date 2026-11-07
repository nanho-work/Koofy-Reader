import 'package:flutter/material.dart';

class KoofyReaderWordmark extends StatelessWidget {
  const KoofyReaderWordmark({
    super.key,
    this.width = 132,
    this.semanticLabel = 'Koofy Reader',
  });

  final double width;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    header: true,
    image: true,
    child: SizedBox(
      width: width,
      height: 24,
      child: ClipRect(
        child: OverflowBox(
          maxHeight: 48,
          child: Image.asset(
            'assets/images/promotions/koofy_reader_wordmark.png',
            width: width,
            fit: BoxFit.fitWidth,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
