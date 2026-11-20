# AGENTS.md — MisRegistros

## 1. Identidad del proyecto

MisRegistros es una aplicación multiplataforma de gestión financiera personal, con soporte multiusuario desde su diseño inicial.

La aplicación estará disponible para:

- iOS.
- Android.
- Web.

Se utilizará Flutter como tecnología cliente, priorizando una única base de código compartida siempre que sea razonable.

El proyecto utiliza:

- Flutter y Dart para iOS, Android y Web.
- NestJS y TypeScript para el backend.
- Supabase Auth para autenticación.
- Supabase PostgreSQL para persistencia de datos.
- Git para control de versiones.

La documentación funcional y arquitectónica se encuentra en `docs/`.

Antes de realizar cambios, consulta la documentación relevante para la tarea.

## 2. Filosofía de desarrollo

Todas las modificaciones deben respetar los siguientes principios:

- Respetar la arquitectura y las decisiones técnicas existentes.
- Priorizar la reutilización antes que la creación de nuevas soluciones.
- Mantener consistencia con los patrones y convenciones del proyecto.
- Aplicar Clean Code y principios SOLID con criterio.
- Favorecer soluciones simples, legibles y mantenibles.
- Evitar sobreingeniería, abstracciones innecesarias y duplicación.
- Trabajar de manera incremental y controlada.
- Comprender el contexto antes de modificar cualquier elemento.

## 3. Reglas obligatorias para los agentes

### 3.1. Inspeccionar antes de implementar

Antes de modificar o crear código:

1. Comprender el objetivo de la tarea.
2. Revisar las instrucciones y documentación relevantes.
3. Inspeccionar los archivos relacionados.
4. Identificar componentes, servicios, funciones o soluciones existentes que puedan reutilizarse.
5. Comprender las convenciones y patrones utilizados en esa parte del proyecto.
6. Identificar posibles impactos sobre otras funcionalidades y plataformas.

Nunca asumir que una funcionalidad no existe sin haberlo comprobado.

No leer indiscriminadamente todo el repositorio cuando la tarea solo requiere una parte específica.

### 3.2. Reutilización y consistencia

- Reutilizar código y componentes existentes siempre que sea razonable.
- No duplicar funcionalidades.
- No crear servicios, utilidades, componentes o abstracciones redundantes.
- No introducir patrones alternativos cuando ya existe uno establecido.
- No modificar estructuras existentes sin una razón técnica válida.
- Priorizar las soluciones ya implementadas y aprobadas en el proyecto.

Antes de desarrollar una funcionalidad, evaluar si puede resolverse extendiendo o reutilizando componentes existentes.

### 3.3. Control de cambios

- Modificar únicamente lo necesario para cumplir la tarea.
- No realizar refactorizaciones ajenas al objetivo solicitado.
- No modificar archivos fuera del alcance sin justificación.
- No eliminar funcionalidades existentes sin autorización.
- No sobrescribir cambios realizados por el usuario.
- No realizar operaciones destructivas sin autorización explícita.
- No modificar configuraciones del entorno sin justificación y aprobación.
- Evitar cambios masivos cuando una solución puntual sea suficiente.

### 3.4. Tecnologías y dependencias

- No incorporar nuevas tecnologías, bibliotecas o dependencias por iniciativa propia.
- Antes de proponer una dependencia, evaluar si el proyecto ya dispone de una solución.
- Justificar técnicamente cualquier incorporación.
- Solicitar aprobación antes de agregar dependencias o cambiar herramientas existentes.
- No reemplazar tecnologías o herramientas aprobadas sin autorización.

### 3.5. Decisiones arquitectónicas

- Respetar las decisiones documentadas.
- No cambiar silenciosamente la arquitectura.
- No introducir nuevas capas, módulos o patrones sin necesidad demostrable.
- No crear abstracciones anticipándose a necesidades futuras no confirmadas.
- Si una decisión existente presenta problemas, explicar el inconveniente y proponer alternativas antes de modificarla.
- Diferenciar claramente las decisiones aprobadas de las propuestas pendientes.

### 3.6. Calidad del código

- Aplicar Clean Code y principios SOLID cuando aporten valor.
- Mantener nombres claros y coherentes.
- Evitar duplicación y complejidad innecesaria.
- Separar responsabilidades.
- Mantener funciones y clases enfocadas en su propósito.
- Considerar el impacto de los cambios en las funcionalidades existentes.
- Favorecer código fácil de comprender, probar y mantener.
- Evitar soluciones excesivamente complejas para problemas simples.

### 3.7. Seguridad

- No exponer credenciales, tokens, contraseñas ni secretos.
- No incorporar secretos al repositorio.
- No compartir información sensible innecesariamente.
- No debilitar mecanismos de autenticación o autorización.
- Respetar el aislamiento de datos entre usuarios.
- No utilizar credenciales privilegiadas para operaciones ordinarias de usuarios.
- Validar entradas y controlar errores en los límites del sistema.
- No modificar políticas de seguridad sin justificación y autorización.
- No ejecutar operaciones sobre entornos productivos sin autorización explícita.

### 3.8. Pruebas y validaciones

- Ejecutar las validaciones pertinentes después de modificar código.
- Mantener las pruebas existentes.
- Agregar o actualizar pruebas cuando corresponda.
- No eliminar pruebas para conseguir que una implementación pase.
- Informar claramente cualquier validación que no haya podido ejecutarse.
- No afirmar que una funcionalidad está probada si no se ejecutaron las pruebas correspondientes.

### 3.9. Compatibilidad multiplataforma

Toda implementación de Flutter deberá considerar las plataformas objetivo:

- iOS.
- Android.
- Web.

Reglas:

- Priorizar la reutilización de código y lógica compartida.
- No asumir que una interfaz móvil funciona correctamente en escritorio.
- Considerar diseño adaptable (Responsive Design) y diferentes tamaños de pantalla.
- Evaluar las particularidades de navegación, sesiones, almacenamiento y permisos de cada plataforma.
- No introducir implementaciones específicas de una plataforma sin justificación.
- Evitar duplicar lógica de negocio entre plataformas.
- Cuando un cambio afecte a varias plataformas, validar su comportamiento en las plataformas involucradas que estén disponibles en el entorno.
- Informar claramente las plataformas que no pudieron probarse.

La compatibilidad multiplataforma forma parte de los requisitos del producto, no es una consideración opcional.

## 4. Documentación

- Mantener actualizada la documentación cuando cambien decisiones, contratos o comportamientos relevantes.
- Evitar documentación duplicada o contradictoria.
- Consultar los documentos existentes antes de crear otros nuevos.
- No inventar decisiones técnicas como si ya estuvieran aprobadas.
- No modificar documentación ajena al objetivo sin justificación.
- Utilizar español en la documentación del proyecto; mantener los identificadores de código en inglés y agregar comentarios únicamente cuando aporten valor, preferentemente en español.
- Documentar las decisiones arquitectónicas importantes y sus motivos.

## 5. Forma de trabajo

Para cada tarea:

1. Analizar el requerimiento.
2. Inspeccionar el contexto existente.
3. Identificar las soluciones reutilizables.
4. Determinar el alcance de los cambios.
5. Presentar un plan breve cuando la tarea implique varios cambios o decisiones relevantes.
6. Implementar de forma incremental.
7. Ejecutar las validaciones correspondientes.
8. Revisar los cambios realizados.
9. Informar el resultado.

Para tareas pequeñas y concretas, evitar planes y explicaciones innecesariamente extensos.

No realizar implementaciones adicionales que el usuario no haya solicitado.

Si durante el desarrollo aparece una necesidad que implique cambiar la arquitectura, incorporar dependencias o ampliar significativamente el alcance, detenerse y solicitar aprobación.

## 6. Comunicación con el usuario

El usuario quiere comprender y aprender durante el desarrollo.

Por lo tanto:

- Explicar las decisiones técnicas relevantes.
- Justificar las alternativas elegidas.
- No limitarse a entregar código sin contexto.
- Utilizar español en la comunicación, explicaciones y documentación; mantener los identificadores de código en inglés y escribir comentarios únicamente cuando aporten valor, preferentemente en español.
- Diferenciar claramente entre decisiones aprobadas, propuestas y pendientes.
- No asumir autorización para decisiones importantes.
- Evitar explicaciones innecesariamente extensas cuando la tarea sea sencilla.
- Trabajar de forma incremental, permitiendo cambios atómicos en varios archivos cuando formen parte de una misma unidad funcional.

## 7. Uso de herramientas y agentes de IA

- Todos los agentes deben respetar estas instrucciones y la documentación vigente.
- No asumir que un modelo tiene conocimiento completo de conversaciones anteriores.
- Consultar únicamente el contexto y los archivos relevantes para cada tarea.
- No duplicar instrucciones que ya están centralizadas en este archivo.
- No delegar decisiones arquitectónicas importantes sin revisión del usuario.
- Revisar los cambios generados antes de considerarlos finalizados.
- No ejecutar comandos destructivos, despliegues o acciones sensibles sin autorización.
- No asumir que una operación fue exitosa sin verificar su resultado.

## 8. Control de versiones

- Utilizar Git para mantener el historial de cambios.
- No modificar ni eliminar commits existentes.
- No ejecutar `git reset --hard`, `git clean -fd` u otras operaciones destructivas sin autorización explícita.
- No realizar commits automáticamente, salvo que el usuario lo solicite.
- Revisar los cambios antes de proponer un commit.
- Mantener los cambios organizados y relacionados con el objetivo de cada tarea.

## 9. Prioridad de las instrucciones

Ante cualquier conflicto:

1. Requisitos explícitos del usuario para la tarea actual.
2. Decisiones arquitectónicas aprobadas y documentadas.
3. Estas instrucciones generales.
4. Convenciones existentes en el código.

Si existe una contradicción relevante, detenerse y solicitar aclaración en lugar de improvisar.

---

## Principio rector

**Comprender antes de modificar. Reutilizar antes de crear. Justificar antes de introducir cambios. Validar antes de dar por terminado.**

El objetivo no es producir la mayor cantidad de código posible, sino construir software consistente, seguro, mantenible y alineado con la filosofía de MisRegistros.