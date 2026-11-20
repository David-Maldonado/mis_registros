---
trigger: model_decision
description: "Aplicar cuando se trabaje con autenticación, autorización, sesiones, tokens, datos de usuarios, base de datos, permisos o información sensible en MisRegistros."
---

# Reglas de seguridad — MisRegistros

## 1. Principios generales
- La seguridad debe considerarse desde el diseño, no agregarse al final.
- Aplicar el principio de mínimo privilegio.
- No asumir que los datos enviados por el cliente son confiables.
- No exponer información sensible en respuestas, registros o mensajes de error.
- Priorizar mecanismos de seguridad nativos y probados antes que soluciones personalizadas.

## 2. Autenticación y sesiones
- Utilizar Supabase Auth como proveedor de autenticación.
- NestJS debe validar los tokens JWT antes de permitir el acceso a recursos protegidos.
- No confiar únicamente en que el usuario esté autenticado en Flutter.
- No implementar mecanismos propios de autenticación o almacenamiento de contraseñas sin una decisión arquitectónica aprobada.
- Considerar las particularidades de gestión de sesiones en iOS, Android y Web.

## 3. Autorización y aislamiento de usuarios
- Cada usuario solo debe poder acceder a los recursos que tiene autorización para consultar o modificar.
- No confiar en un `user_id` enviado por el cliente para determinar la identidad del usuario.
- Obtener la identidad del usuario desde el contexto autenticado y validado en el backend.
- Aplicar Row Level Security (RLS) en PostgreSQL como una capa adicional de protección.
- No desactivar, debilitar ni modificar políticas RLS sin justificación y aprobación.
- No asumir que ocultar información en la interfaz equivale a protegerla.

## 4. Secretos y credenciales
- Nunca incluir contraseñas, tokens privados, claves secretas o credenciales reales en el código fuente.
- No registrar tokens, contraseñas ni información sensible en logs.
- Mantener los archivos de entorno y secretos fuera del control de versiones.
- Utilizar archivos de ejemplo con valores ficticios cuando sea necesario documentar variables de entorno.
- Nunca exponer la clave `service_role` de Supabase en Flutter, aplicaciones Web ni otros clientes.
- No utilizar privilegios elevados para operaciones ordinarias que deban respetar RLS.

## 5. Base de datos y datos financieros
- Validar y normalizar los datos recibidos antes de procesarlos.
- Utilizar consultas parametrizadas y evitar construir consultas SQL mediante concatenación insegura.
- Aplicar controles de acceso tanto en el backend como en PostgreSQL.
- Evitar exponer datos de otros usuarios mediante consultas, relaciones, filtros o identificadores manipulables.
- No modificar estructuras, restricciones o permisos de seguridad de la base de datos sin evaluar su impacto.

## 6. Dependencias y cambios sensibles
- No incorporar bibliotecas o mecanismos de seguridad nuevos sin evaluar primero las alternativas existentes.
- No modificar autenticación, autorización, políticas RLS o gestión de secretos fuera del alcance solicitado.
- Identificar riesgos antes de implementar cambios relacionados con seguridad.
- Solicitar aprobación cuando una modificación implique reducir controles de seguridad o cambiar decisiones establecidas.

## 7. Validación de seguridad
- Verificar escenarios de acceso autorizado y no autorizado.
- Comprobar que un usuario no pueda consultar ni modificar registros pertenecientes a otro.
- Revisar que los errores no revelen información interna o sensible.
- Verificar que los secretos no se encuentren en el código, logs o repositorio.
- Informar qué controles fueron comprobados y cuáles requieren validación adicional.