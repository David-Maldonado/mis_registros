import 'package:flutter/foundation.dart';

/// Notificador liviano para sincronizar vistas (Resumen, Cuentas, Movimientos, Categorías)
/// automáticamente después de cualquier operación de escritura.
class LedgerRefreshNotifier extends ChangeNotifier {
  int _version = 0;

  int get version => _version;

  void notifyDataChanged() {
    _version++;
    notifyListeners();
  }
}
