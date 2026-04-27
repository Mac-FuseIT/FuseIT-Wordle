import 'package:flutter/material.dart';
import '../models/app_theme.dart';

void showHelpDialog(BuildContext context, AppTheme theme, String title, List<HelpSection> sections) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: theme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.absent)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Text(title, style: TextStyle(color: theme.textColor, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.close, color: theme.textColor), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(color: Color(0xFF3A3A3C)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sections.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (s.heading != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(s.heading!, style: TextStyle(color: theme.correct, fontSize: 14, fontWeight: FontWeight.bold)),
                          ),
                        Text(s.body, style: TextStyle(color: theme.textColor.withValues(alpha: 0.8), fontSize: 13, height: 1.4)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class HelpSection {
  final String? heading;
  final String body;
  const HelpSection({this.heading, required this.body});
}
