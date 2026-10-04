import 'package:flutter/material.dart';

/// AI ishlatadigan funksiyalarni ajratib turuvchi kichik "AI" belgisi.
class AiBadge extends StatelessWidget {
  final double fontSize;

  const AiBadge({super.key, this.fontSize = 9});

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.55,
        vertical: fontSize * 0.2,
      ),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(fontSize),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: fontSize + 1, color: Colors.white),
          SizedBox(width: fontSize * 0.2),
          Text(
            'AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sarlavha + AI belgisi (AI funksiyalari ekranlarining AppBar'i uchun).
class AiTitle extends StatelessWidget {
  final String title;

  const AiTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        const AiBadge(fontSize: 10),
      ],
    );
  }
}
