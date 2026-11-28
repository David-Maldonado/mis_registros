import 'package:flutter/material.dart';

/// Resuelve un ícono semántico de Material a partir del nombre de la categoría
/// y su tipo (`expense` o `income`), con un ícono por defecto coherente si no
/// hay coincidencia exacta.
class CategoryIconResolver {
  const CategoryIconResolver._();

  static IconData resolve(String name, {String? type}) {
    final normalized = _normalize(name);

    if (normalized.isNotEmpty) {
      for (final rule in _rules) {
        for (final keyword in rule.keywords) {
          if (normalized.contains(keyword)) {
            return rule.icon;
          }
        }
      }
    }

    if (type == 'income') {
      return Icons.monetization_on_rounded;
    }
    return Icons.sell_rounded;
  }

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }

  static const List<_IconRule> _rules = [
    // Alimentación y supermercado
    _IconRule(
      icon: Icons.shopping_cart_rounded,
      keywords: ['super', 'mercado', 'despensa', 'almacen', 'verdura', 'carne', 'comestible'],
    ),
    _IconRule(
      icon: Icons.local_cafe_rounded,
      keywords: ['cafe', 'desayuno', 'merienda', 'panaderia', 'helado', 'chipa'],
    ),
    _IconRule(
      icon: Icons.restaurant_rounded,
      keywords: [
        'comida',
        'almuerzo',
        'cena',
        'restaurante',
        'delivery',
        'pedidos',
        'pizza',
        'hamburguesa',
        'asado',
        'bebida',
        'bar',
      ],
    ),

    // Transporte y vehículo
    _IconRule(
      icon: Icons.local_gas_station_rounded,
      keywords: ['combustible', 'nafta', 'gasoil', 'diesel', 'estacion de servicio'],
    ),
    _IconRule(
      icon: Icons.directions_car_rounded,
      keywords: ['auto', 'vehiculo', 'moto', 'taller', 'mecanico', 'estacionamiento', 'peaje', 'lavadero'],
    ),
    _IconRule(
      icon: Icons.directions_bus_rounded,
      keywords: ['transporte', 'bus', 'colectivo', 'pasaje', 'bolt', 'uber', 'taxi'],
    ),

    // Vivienda y servicios
    _IconRule(
      icon: Icons.home_rounded,
      keywords: ['alquiler', 'casa', 'hogar', 'vivienda', 'expensa', 'mueble', 'departamento', 'inmobiliaria'],
    ),
    _IconRule(
      icon: Icons.bolt_rounded,
      keywords: ['luz', 'ande', 'electricidad', 'energia'],
    ),
    _IconRule(
      icon: Icons.water_drop_rounded,
      keywords: ['agua', 'essap', 'aguateria'],
    ),
    _IconRule(
      icon: Icons.wifi_rounded,
      keywords: ['internet', 'wifi', 'celular', 'telefono', 'tigo', 'personal', 'claro', 'vox'],
    ),
    _IconRule(
      icon: Icons.receipt_long_rounded,
      keywords: ['servicio', 'factura', 'impuesto', 'iva', 'patente', 'municipalidad'],
    ),

    // Salud y cuidado personal
    _IconRule(
      icon: Icons.local_pharmacy_rounded,
      keywords: ['farmacia', 'remedio', 'medicamento'],
    ),
    _IconRule(
      icon: Icons.medical_services_rounded,
      keywords: ['salud', 'medico', 'doctor', 'clinica', 'hospital', 'dentista', 'odontolog', 'seguro medico', 'ips'],
    ),
    _IconRule(
      icon: Icons.content_cut_rounded,
      keywords: ['peluqueria', 'barberia', 'belleza', 'estetica', 'cuidado personal'],
    ),

    // Educación y tecnología
    _IconRule(
      icon: Icons.school_rounded,
      keywords: ['educacion', 'facultad', 'universidad', 'colegio', 'escuela', 'curso', 'libro', 'estudio', 'cuota escolar'],
    ),
    _IconRule(
      icon: Icons.devices_rounded,
      keywords: ['tecnologia', 'electronica', 'computadora', 'notebook', 'software', 'app', 'suscripcion'],
    ),

    // Compras, ocio y estilo de vida
    _IconRule(
      icon: Icons.checkroom_rounded,
      keywords: ['ropa', 'calzado', 'zapatilla', 'zapato', 'vestimenta', 'indumentaria'],
    ),
    _IconRule(
      icon: Icons.shopping_bag_rounded,
      keywords: ['compra', 'shopping', 'tienda'],
    ),
    _IconRule(
      icon: Icons.fitness_center_rounded,
      keywords: ['gym', 'gimnasio', 'deporte', 'futbol', 'padel', 'entrenamiento'],
    ),
    _IconRule(
      icon: Icons.movie_rounded,
      keywords: ['cine', 'netflix', 'spotify', 'streaming', 'entretenimiento', 'ocio', 'salida', 'juego', 'diversion'],
    ),
    _IconRule(
      icon: Icons.flight_rounded,
      keywords: ['viaje', 'vacacion', 'hotel', 'vuelo', 'turismo'],
    ),
    _IconRule(
      icon: Icons.pets_rounded,
      keywords: ['mascota', 'veterinaria', 'perro', 'gato'],
    ),
    _IconRule(
      icon: Icons.card_giftcard_rounded,
      keywords: ['regalo', 'cumple', 'donacion', 'ayuda', 'familia'],
    ),

    // Finanzas, ahorros y deudas
    _IconRule(
      icon: Icons.savings_rounded,
      keywords: ['ahorro', 'fondo', 'reserva', 'plazo fijo'],
    ),
    _IconRule(
      icon: Icons.credit_card_rounded,
      keywords: ['deuda', 'prestamo', 'cuota', 'tarjeta', 'banco', 'comision'],
    ),

    // Ingresos
    _IconRule(
      icon: Icons.payments_rounded,
      keywords: ['salario', 'sueldo', 'aguinaldo', 'nomina', 'quincena', 'jornal'],
    ),
    _IconRule(
      icon: Icons.work_rounded,
      keywords: ['freelance', 'honorario', 'proyecto', 'consultoria', 'trabajo', 'servicio profesional'],
    ),
    _IconRule(
      icon: Icons.storefront_rounded,
      keywords: ['venta', 'negocio', 'comercio', 'cliente', 'emprendimiento'],
    ),
    _IconRule(
      icon: Icons.trending_up_rounded,
      keywords: ['inversion', 'dividendo', 'interes', 'rendimiento', 'ganancia'],
    ),
    _IconRule(
      icon: Icons.volunteer_activism_rounded,
      keywords: ['bono', 'premio', 'extra', 'reembolso', 'propina'],
    ),
  ];
}

class _IconRule {
  const _IconRule({required this.icon, required this.keywords});

  final IconData icon;
  final List<String> keywords;
}
