# MisRegistros

**Versión del documento:** 0.2  
**Estado:** Stack tecnológico base aprobado; alcance funcional y diseño detallado en definición

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

### 3.3. Movimientos financieros

- Registrar ingresos.
- Registrar gastos.
- Consultar movimientos.
- Editar movimientos.
- Eliminar movimientos.

### 3.4. Categorías

- Clasificación de ingresos y gastos.
- Asociación de categorías con movimientos.

> **Decisión funcional pendiente:** definir si en V1 las categorías serán predefinidas por el sistema o administrables por cada usuario (creación, edición y eliminación).

### 3.5. Resúmenes

- Balance mensual.
- Total de ingresos.
- Total de gastos.
- Historial de movimientos.

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