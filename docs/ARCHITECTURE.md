# Arquitectura de MisRegistros

**Versión:** 0.3  
**Estado:** Stack tecnológico base y modelo de datos aprobados; diseño de Flutter y NestJS en definición

## 1. Visión general

MisRegistros utilizará una arquitectura cliente-servidor compuesta por una aplicación multiplataforma, una API REST y servicios administrados de Supabase.

La aplicación cliente estará desarrollada con Flutter y funcionará en iOS, Android y Web.

La solución separará las responsabilidades de presentación, lógica de negocio, autenticación y persistencia de datos.

## 2. Componentes principales

### 2.1. Aplicación cliente — Flutter

Flutter será la tecnología utilizada para desarrollar las tres plataformas:

- iOS.
- Android.
- Web.

Responsabilidades:

- Presentar la interfaz de usuario.
- Gestionar la navegación.
- Administrar el estado de la aplicación.
- Permitir el registro, inicio y cierre de sesión.
- Obtener, mantener y cerrar la sesión de Supabase Auth.
- Consumir los endpoints de la API REST.
- Enviar el token de acceso en las solicitudes protegidas.
- Adaptar la presentación según la plataforma y el tamaño de pantalla.

Las funcionalidades y reglas de negocio compartidas deberán reutilizarse entre plataformas.

Las particularidades de presentación, navegación y almacenamiento podrán implementarse mediante soluciones específicas cuando las diferencias entre plataformas lo justifiquen.

Flutter no será responsable de implementar las reglas de negocio del servidor ni de acceder directamente a las tablas de la aplicación.

### 2.2. Autenticación — Supabase Auth

Responsabilidades:

- Registrar usuarios.
- Autenticar usuarios y gestionar el cierre de sesión.
- Administrar sesiones.
- Emitir tokens JWT.
- Proporcionar la identidad del usuario autenticado.

La implementación deberá considerar las particularidades de persistencia y administración de sesiones en navegadores y dispositivos móviles.

### 2.3. Backend — NestJS

Responsabilidades:

- Exponer la API REST.
- Validar los tokens JWT recibidos.
- Identificar al usuario autenticado.
- Aplicar las reglas de negocio.
- Validar los datos de entrada.
- Coordinar las operaciones de persistencia.
- Controlar las respuestas y errores de la API.

El backend será la capa principal de acceso a las funcionalidades del sistema.

Su comportamiento será independiente de la plataforma cliente que origine las solicitudes.

### 2.4. Base de datos — Supabase PostgreSQL

Responsabilidades:

- Almacenar usuarios y datos financieros.
- Mantener las relaciones entre entidades.
- Garantizar la integridad de los datos.
- Aplicar políticas de seguridad mediante Row Level Security (RLS).

## 3. Comunicación entre componentes

El flujo general será:

1. El usuario inicia sesión desde Flutter.
2. Supabase Auth autentica al usuario y entrega un JWT.
3. Flutter envía el JWT a NestJS mediante el encabezado Authorization.
4. NestJS valida el token e identifica al usuario.
5. NestJS ejecuta las reglas de negocio correspondientes.
6. El backend accede a Supabase utilizando el contexto JWT del usuario.
7. PostgreSQL aplica las políticas RLS.
8. NestJS devuelve la respuesta a Flutter.

Este flujo será común para iOS, Android y Web.

## 4. Estrategia multiplataforma

### 4.1. Código compartido

Se priorizará una única base de código Flutter para las tres plataformas.

La lógica de presentación, validaciones de cliente, servicios y funcionalidades compartidas deberán reutilizarse siempre que sea razonable.

### 4.2. Diseño adaptable

La interfaz deberá adaptarse a diferentes tamaños de pantalla.

Se contemplarán, como mínimo, dos experiencias de navegación:

- Móviles: navegación y componentes optimizados para pantallas táctiles y espacios reducidos.
- Escritorio y pantallas grandes: navegación y distribución adaptadas a mayor espacio disponible.

No se asumirá que una interfaz diseñada para móviles resulta automáticamente adecuada para escritorio.

### 4.3. Particularidades por plataforma

Se evaluarán las diferencias entre plataformas en aspectos como:

- Navegación.
- Gestión de sesiones.
- Almacenamiento seguro.
- Manejo de rutas.
- Permisos.
- Comportamiento de componentes.
- Experiencia de usuario.

Las implementaciones específicas deberán justificarse y evitar duplicar innecesariamente la lógica compartida.

## 5. Estrategia de seguridad multiusuario

La seguridad se implementará en varias capas:

- Autenticación mediante Supabase Auth.
- Validación de JWT en NestJS.
- Autorización de las operaciones en el backend.
- Asociación de los registros con el usuario propietario.
- Políticas RLS en las tablas correspondientes.

Las operaciones de acceso a datos deberán conservar el contexto de autenticación del usuario.

No se utilizará la clave `service_role` para las operaciones ordinarias de los usuarios, ya que esta puede omitir las políticas RLS.

## 6. Principios arquitectónicos

La solución seguirá estos principios:

- Separación de responsabilidades.
- Bajo acoplamiento entre componentes.
- Alta cohesión.
- Dependencias orientadas a abstracciones cuando aporte valor.
- Validación en los límites del sistema.
- Seguridad por defecto.
- Reutilización de código.
- Consistencia entre plataformas.
- Diseño preparado para evolución funcional.

## 7. Decisiones definidas

Las siguientes decisiones están aprobadas:

- **Base de datos ([DATA_MODEL.md](DATA_MODEL.md)):** modelo entidad-relación de PostgreSQL, estrategia de migraciones con Supabase CLI en `supabase/migrations/`, políticas RLS, roles y privilegios por tabla, escrituras vía RPC, lecturas agregadas vía vistas/funciones con RLS y pruebas con pgTAP (`supabase test db`).
- **Backend (`backend/`):**
  - Organización modular en NestJS: `config/`, `supabase/` (cliente por solicitud con JWT del usuario, sin `service_role`), `auth/` (`SupabaseAuthGuard` + `@CurrentUser()`), `common/` (filtro global de excepciones y `ValidationPipe`), y módulos de dominio (`currencies`, `profiles`, `accounts`, `categories`, `transactions`, `reports`).
  - Convenciones de la API REST: `/currencies`, `/profile`, `/accounts`, `/accounts/balances`, `/categories`, `/transactions` (con paginación por cursor `(occurred_at DESC, id DESC)` y endpoints específicos por tipo de operación, reemplazo atómico `PUT /transactions/:id`, descripción y anulación) y `/reports/monthly-summary` / `/reports/monthly-account-flows`.

## 8. Decisiones pendientes de implementación

Los siguientes aspectos se definirán antes de su implementación:

- Estructura modular de Flutter.
- Estrategia de pruebas automatizadas de NestJS y Flutter.
- Estrategia de navegación y diseño adaptable.
- Gestión de sesiones y almacenamiento según plataforma.
- Configuración de despliegue de la aplicación Web.