import 'package:flutter/material.dart';

import '../models/pakistan_destination.dart';

class DestinationImage extends StatelessWidget {
  const DestinationImage({
    super.key,
    required this.destination,
    required this.height,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
  });

  final PakistanDestination destination;
  final double height;
  final double width;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      destination.assetImagePath,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (_, _, _) => _DestinationImageFallback(
        height: height,
        width: width,
        label: destination.name,
      ),
    );
  }
}

class _DestinationImageFallback extends StatelessWidget {
  const _DestinationImageFallback({
    required this.height,
    required this.width,
    required this.label,
  });

  final double height;
  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDDEBFF), Color(0xFFF7FAFF)],
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }
}
