---
trigger: model_decision
description: "Aplicar cuando se diseñe, evalúe o modifique la arquitectura, estructura de módulos, responsabilidades, integraciones, flujos de datos o contratos entre componentes de MisRegistros."
---

# Reglas de arquitectura — MisRegistros

Estas reglas complementan a `AGENTS.md` definiendo los límites entre componentes, el estado de las decisiones arquitectónicas y la evolución del sistema.

## 1. Estado de las decisiones arquitectónicas

- Consultar `docs/ARCHITECTURE.md` para conocer tanto las decisiones aprobadas como las que siguen en definición, y `docs/README.md` para el alcance funcional.
- **Stack tecnológico base aprobado:**
  - **Flutter (Dart):** aplicación cliente para iOS, Android y Web.
  - **NestJS (TypeScript):** backend REST, responsable de la lógica de negocio, validaciones y autorización del lado servidor.
  - **Supabase Auth:** proveedor de autenticación y gestión de identidad.
  - **Supabase PostgreSQL:** persistencia de datos y aislamiento entre usuarios mediante Row Level Security (RLS).
- **Modelo de datos aprobado:** el modelo entidad-relación, las migraciones, los roles, las políticas RLS y las funciones RPC están definidos en `docs/DATA_MODEL.md` (pendientes de implementación y pruebas).
- **Diseño arquitectónico detallado en definición:** la estructura modular de Flutter y NestJS, los contratos API y las estrategias de navegación, sesiones y despliegue aún están pendientes de aprobación (ver `docs/ARCHITECTURE.md`).
- No asumir como aprobada ninguna decisión pendiente ni alterar la distribución de responsabilidades del stack aprobado sin justificación técnica y aprobación previa.

## 2. Separación de responsabilidades y contratos

- Evitar que la interfaz Flutter asuma lógica de negocio del servidor o acceda directamente a las tablas de la aplicación.
- Evitar duplicar reglas de negocio entre cliente, backend y base de datos; mantener NestJS como punto de aplicación de reglas de negocio y autorización del servidor, y PostgreSQL/RLS como capa de persistencia y aislamiento de datos.
- Antes de modificar endpoints, DTO, modelos, estructuras de datos o flujos de autenticación, identificar consumidores y dependencias, evaluar el impacto en iOS, Android y Web, y mantener coherencia entre cliente, API y modelo de datos.

## 3. Evolución arquitectónica (V1 vs. futuro)

- Las funcionalidades futuras (cuentas compartidas, grupos familiares, gastos compartidos, reportes avanzados) no deben condicionar ni sobreingenierizar la implementación de V1.
- Diseñar pensando en la extensibilidad sin implementar anticipadamente funcionalidades no aprobadas.

## 4. Propuestas de cambio estructural

Cuando una tarea requiera definir una decisión pendiente o modificar la estructura actual:

1. Analizar la arquitectura vigente y las decisiones documentadas.
2. Evaluar alternativas y su impacto en Flutter, NestJS y Supabase.
3. Presentar la propuesta y solicitar aprobación antes de implementarla.
4. Una vez aprobada, actualizar `docs/ARCHITECTURE.md` marcando la decisión como aprobada y retirando cualquier instrucción obsoleta o contradictoria.