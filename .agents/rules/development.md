---
trigger: model_decision
description: "Aplicar cuando se implemente, modifique, refactorice o revise código en cualquier componente de MisRegistros. Complementa AGENTS.md con criterios de calidad y reutilización."
---

# Reglas de desarrollo — MisRegistros

Estas reglas complementan a `AGENTS.md` con criterios prácticos de implementación y refactorización.

## 1. Implementación y reutilización

- Antes de escribir código nuevo, revisar módulos equivalentes en el componente afectado para seguir la misma forma de resolver el problema.
- Extender componentes y servicios existentes antes de duplicarlos; evitar utilidades para operaciones ya resueltas.
- No introducir abstracciones que no respondan a una necesidad concreta del requerimiento actual.

## 2. Calidad y diseño de código

- Favorecer funciones pequeñas, cohesivas y con bajo acoplamiento entre módulos.
- Evitar complejidad accidental y soluciones mágicas; no sacrificar legibilidad por reducir líneas de código.
- Mantener los identificadores de código en inglés y agregar comentarios únicamente cuando aporten valor (explicando el porqué), preferentemente en español.

## 3. Alcance, dependencias y refactorizaciones

- Separar las refactorizaciones necesarias para la tarea de las mejoras opcionales; no mezclarlas ni reestructurar módulos completos fuera del alcance.
- No actualizar versiones de paquetes o herramientas fuera del alcance solicitado.
- Informar qué validaciones o pruebas se ejecutaron y cuáles quedaron pendientes.