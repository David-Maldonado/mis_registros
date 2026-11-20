---
trigger: model_decision
description: "Aplicar cuando se cree, modifique o revise documentación, o cuando un cambio de código afecte decisiones técnicas, arquitectura, contratos, modelo de datos, seguridad o comportamiento funcional documentado de MisRegistros."
---

# Reglas de documentación — MisRegistros

Estas reglas complementan a `AGENTS.md` definiendo las fuentes de verdad y cuándo actualizar la documentación del proyecto.

## 1. Fuentes de verdad

- `AGENTS.md`: instrucciones generales para los agentes.
- `docs/README.md`: propósito, alcance funcional y tecnologías del proyecto.
- `docs/ARCHITECTURE.md`: arquitectura, distribución de responsabilidades y decisiones técnicas (aprobadas y pendientes).
- No crear fuentes de verdad paralelas para información que ya tenga un documento responsable.
- Si se detectan contradicciones entre documentos, identificarlas y proponer su resolución antes de modificar información de forma arbitraria.

## 2. Criterios de contenido e idioma

- Redactar toda la documentación en español; mantener los identificadores de código en inglés y, en ejemplos de código, agregar comentarios únicamente cuando aporten valor, preferentemente en español.
- Documentar decisiones y comportamientos reales, diferenciando claramente lo aprobado de lo pendiente; no presentar implementaciones futuras o propuestas como si ya existieran o estuvieran aprobadas.
- Incluir ejemplos únicamente cuando ayuden a comprender o usar una funcionalidad, manteniéndolos alineados con la implementación vigente.
- Evitar duplicar reglas de agentes en la documentación funcional o arquitectónica y no convertir la documentación en un registro de cada cambio menor.

## 3. Cuándo actualizar la documentación

Evaluar la necesidad de actualizar `docs/` cuando un cambio afecte:

- La arquitectura o las responsabilidades de los componentes.
- Las tecnologías, dependencias o integraciones.
- Los contratos de API y los flujos de comunicación.
- El modelo de datos, las relaciones o las restricciones.
- La autenticación, autorización o seguridad.
- El alcance funcional o el comportamiento visible para los usuarios.
- Los procedimientos de instalación, configuración, ejecución o despliegue.

Informar qué documentación fue actualizada y qué aspectos quedaron pendientes de definición o actualización.