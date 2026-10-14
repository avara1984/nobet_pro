import 'package:flutter/material.dart';

import '../core/tema.dart';

/// Yayında olmayan ayın listesi önizlenmek istendiğinde (Süper Admin hariç)
/// gösterilen uyarı — listenin kendisi hiç açılmaz.
Future<void> yayinlanmadiUyarisiGoster(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.lock_outline, size: 44, color: R.gri),
      title: const Text(
        'Bu Ayın Nöbet Listesi Henüz Yayınlanmamıştır.',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
      content: const Text(
        'Liste Onaylandığında Buradan Görebilirsiniz.',
        textAlign: TextAlign.center,
        style: TextStyle(color: R.gri, fontSize: 13),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );
}
