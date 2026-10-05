import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/logging/file_log.dart';

bool get _ru => Platform.localeName.toLowerCase().startsWith('ru');

/// Shown instead of a blank window when the start fails (an exception
/// before or while building the app, or no first frame in time): what
/// happened, where the log is, a button to open the logs folder. Plain
/// widgets only — no theme, fonts or providers that could fail again.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFF050305),
      debugShowCheckedModeBanner: false,
      builder: (context, _) => StartupErrorView(error: error),
    );
  }
}

/// The error screen itself — also used as ErrorWidget.builder, so a widget
/// that fails to build says so instead of leaving a grey box.
class StartupErrorView extends StatelessWidget {
  const StartupErrorView({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final logDir = FileLog.directory;
    final title = _ru ? 'WAVEBREAK не запустился' : 'WAVEBREAK could not start';
    final body = _ru
        ? 'Произошла ошибка при запуске. Отправьте в поддержку файл журнала из этой папки:'
        : 'Something went wrong while starting. Please send the log file from this folder to support:';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF050305),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Color(0xFFF5F2F0),
                          fontSize: 22,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Text(body,
                      style: const TextStyle(
                          color: Color(0xA6F5F2F0), fontSize: 14, height: 1.4)),
                  const SizedBox(height: 8),
                  SelectableText(logDir,
                      style: const TextStyle(
                          color: Color(0xFF7CEEE8), fontSize: 13)),
                  const SizedBox(height: 20),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _Button(
                      label: _ru ? 'Открыть папку логов' : 'Open logs folder',
                      onTap: () => Process.run('explorer.exe', [logDir]),
                    ),
                    _Button(
                      label: _ru ? 'Скопировать путь' : 'Copy path',
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: logDir)),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Text(error,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0x66F5F2F0), fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F2F0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF050305),
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}
