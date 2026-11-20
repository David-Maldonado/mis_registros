# MisRegistros

**Versión del documento:** 0.3  
**Estado:** Stack tecnológico base y alcance funcional de V1 aprobados; diseño detallado de Flutter y NestJS en definición

## 1. Descripción del proyecto

MisRegistros es una aplicación multiplataforma orientada a la gestión y el seguimiento de registros financieros personales.

Su objetivo es permitir que cada usuario pueda registrar sus ingresos y gastos, organizarlos por categorías y consultar su comportamiento financiero mediante resúmenes e historiales.

La aplicación estará disponible para:

- iOS.
- Android.
- Web.

Se desarrollará utilizando una arquitectura cliente-servidor, con una única solución Flutter para las tres plataformas y un backend centralizado desarrollado con NestJS.

El sistema contará con soporte multiusuario desde su primera versión, garantizando el aislamiento y la privacidad de los datos de cada usuario.

## 2. Objetivos

- Facilitar el registro de ingresos y gastos.
- Organizar los movimientos mediante categorías.
- Consultar el historial de movimientos.
- Visualizar balances financieros mensuales.
- Ofrecer una experiencia consistente en dispositivos móviles y navegadores web.
- Adaptar la interfaz a diferentes tamaños de pantalla.
- Garantizar la privacidad y el aislamiento de los datos de cada usuario.
- Construir una base técnica que permita incorporar nuevas funcionalidades en el futuro.

## 3. Alcance de la primera versión (V1)

### 3.1. Plataformas

- Aplicación para iOS.
- Aplicación para Android.
- Aplicación Web adaptable a diferentes resoluciones.

Las tres plataformas compartirán la misma base de código Flutter, reutilizando la lógica y los componentes siempre que sea razonable.

La interfaz podrá adaptar su navegación y presentación según la plataforma y el tamaño de pantalla.

### 3.2. Usuarios y autenticación

- Registro de usuarios.
- Inicio de sesión.
- Cierre de sesión.
- Gestión de sesiones autenticadas.

### 3.3. Cuentas

- Cuentas de efectivo, bancos, billeteras electrónicas y tarjetas de crédito.
- Monedas soportadas: PYG y USD (sin conversión automática).
- Las cuentas líquidas (efectivo, bancos, billeteras) no pueden quedar con saldo negativo.
- Las tarjetas de crédito permiten registrar gastos aunque el usuario no tenga saldo en otras cuentas; la deuda se refleja en la tarjeta.
- El límite de crédito es informativo: la app puede advertir cuando se supera, pero no impide registrar el gasto.

### 3.4. Movimientos financieros

- Registrar ingresos.
- Registrar gastos.
- Registrar transferencias entre cuentas propias, incluidos los pagos de tarjetas.
- Registrar devoluciones parciales de gastos.
- Registrar ajustes de saldo.
- Consultar movimientos.
- Editar movimientos: la operación original se anula y se crea la corregida en un único paso, conservando el historial.
- Eliminar movimientos: la operación se anula; no se borra físicamente.

Toda entrada o salida de dinero queda registrada en el historial y en el flujo de la cuenta correspondiente.

### 3.5. Categorías

- Clasificación de ingresos y gastos mediante categorías y subcategorías (máximo dos niveles).
- Las categorías son personalizables: cada usuario las crea, edita y desactiva.
- No se crean categorías predefinidas; la app guía al usuario para crear la primera antes de registrar un ingreso o gasto.

### 3.6. Resúmenes

- Total de ingresos.
- Total de gastos (brutos, devoluciones y netos).
- Balance mensual (ingresos − gastos netos).
- Transferencias y ajustes, informados por separado.
- Entradas y salidas por cuenta.
- Historial de movimientos.

Los resúmenes se calculan por moneda y según la zona horaria del usuario (por defecto, `America/Asuncion`). Las transferencias entre cuentas propias y los ajustes no se suman a ingresos ni gastos, para no duplicar ni inflar los totales.

El detalle de las reglas se encuentra en [DATA_MODEL.md](DATA_MODEL.md).

## 4. Características multiusuario

MisRegistros será multiusuario desde su diseño inicial.

Cada usuario tendrá sus propios datos y solamente podrá consultar y administrar los registros que le pertenezcan.

Los principios de seguridad serán:

- Cada registro financiero estará asociado a un usuario.
- La API validará la identidad del usuario mediante tokens de autenticación.
- La base de datos contará con políticas de seguridad para evitar el acceso no autorizado a información de otros usuarios.
- Las operaciones deberán respetar el contexto del usuario autenticado.

## 5. Tecnologías

Stack tecnológico base aprobado para el proyecto:

| Componente | Tecnología |
|---|---|
| Aplicación multiplataforma | Flutter |
| Lenguaje móvil y web | Dart |
| Backend | NestJS |
| Lenguaje backend | TypeScript |
| Autenticación | Supabase Auth |
| Base de datos | Supabase PostgreSQL |
| Control de versiones | Git |

## 6. Criterios de calidad

El desarrollo seguirá estos principios:

- Clean Code.
- Principios SOLID.
- Separación de responsabilidades.
- Código legible y mantenible.
- Validación de datos.
- Seguridad desde el diseño.
- Pruebas automatizadas cuando corresponda.
- Compatibilidad entre plataformas.
- Diseño adaptable (Responsive Design).
- Evitar duplicación de código y complejidad innecesaria.

La arquitectura deberá ser proporcional a las necesidades reales del producto, evitando la sobreingeniería.

## 7. Evolución futura

La arquitectura deberá permitir incorporar funcionalidades adicionales sin comprometer las funcionalidades existentes.

Entre las posibles evoluciones se encuentran:

- Cuentas financieras compartidas.
- Grupos familiares.
- Administración de gastos compartidos.
- Reportes financieros avanzados.
- Nuevas funcionalidades y plataformas de acceso.

Estas funcionalidades no forman parte del alcance inicial de V1.