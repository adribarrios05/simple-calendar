# Contribuir a Simple Calendar

[English](../../../CONTRIBUTING.md) · Español

Fuente: [CONTRIBUTING.md](../../../CONTRIBUTING.md). Revisado: 27 de octubre de 2026. La versión inglesa es la referencia normativa.

Simple Calendar es un proyecto público con una [beta para Windows disponible](https://github.com/adribarrios05/simple-calendar/releases/tag/v1.0.0-beta.1). El código y la documentación originales utilizan la [licencia MIT](../../../LICENSE.md).

Al enviar una contribución original para incorporarla a Simple Calendar, aceptas ofrecerla bajo MIT. Envía únicamente trabajo propio o que tengas derecho a aportar. Identifica el código y los recursos de terceros y conserva sus avisos y condiciones; consulta los [componentes de terceros](../../../THIRD_PARTY_NOTICES.md). Cada contribuyente conserva sus derechos de autor; no se exige una cesión de copyright.

## Desarrollo

Usa Windows y el entorno de [README](README.md). Lee [AGENTS.md](../../../AGENTS.md) y [arquitectura](../../../ARCHITECTURE.md). Conserva IDs, historial, progreso, bloqueos, excepciones, lockfile e identidad de almacenamiento. Mantén dominio y planificador en Dart puro. No añadas cuentas, cloud ni integraciones externas.

Ejecuta `flutter analyze` y `flutter test`. Los cambios nativos requieren también la integración Windows y la compilación Release. Los cambios de esquema necesitan migración transaccional y pruebas; genera Drift, no edites su salida. Utiliza datos sintéticos y bases temporales: nunca adjuntes agendas reales, copias privadas ni secretos a incidencias.

Comunica qué comprobaciones ejecutaste y sus límites. Incluye versión de app/Windows, pasos, resultado esperado/real y evidencias anonimizadas. Los commits, pushes y publicaciones asistidos por agentes requieren solicitud explícita.

## Traducciones de la aplicación

Inglés es el idioma predeterminado. Los recursos ingleses/españoles están en `lib/l10n/app_strings.dart`, mediante un delegado de Flutter. Los selectores Material usan los delegados existentes de Flutter; no se añade una dependencia de ejecución.

Usa `context.strings.text('English template', [arguments])` y añade su traducción española con los mismos índices de parámetros. Inserta datos del usuario después de traducir; no traduzcas títulos, descripciones, subtareas o nombres personalizados. Los mensajes puros de dominio/persistencia se mantienen en inglés y se traducen al mostrarlos. IDs, JSON y rutas no dependen del idioma.

Las etiquetas predefinidas conservan su nombre almacenado e ID: solo se traduce la presentación si no se renombraron. Guardar sin cambiar su etiqueta visible conserva el nombre original.

Para otro idioma, añade un catálogo completo, valida la preferencia y prueba flujos, selectores, parámetros, errores, reapertura y copias. Si crecen los idiomas, plurales o formatos, evoluciona hacia ARB/gen-l10n de Flutter; no acumules reglas gramaticales improvisadas.

## Idiomas de documentación

La documentación principal y los comentarios son ingleses. Traduce primero README y CONTRIBUTING bajo `docs/i18n/<código>/<archivo>.md`, con enlace a la fuente y fecha de revisión. Actualiza versiones afectadas junto a la fuente o indica claramente que están desactualizadas.

Mantén un único AGENTS.md normativo en inglés: duplicarlo en subcarpetas introduce instrucciones con ámbito propio. ARCHITECTURE.md es el contrato técnico público en inglés. Los planes, auditorías y registros personales se conservan en private/, excluido de Git; el desarrollo público no depende de esos archivos. Conserva comandos, identificadores, límites y fechas; comprueba enlaces relativos.

## Incidencias y contribuciones

Utiliza [Issues](https://github.com/adribarrios05/simple-calendar/issues) para errores y propuestas. Busca incidencias existentes antes de crear una nueva. La plantilla pide versión/compilación de la app, Windows, pasos y resultado esperado/real. Usa datos ficticios y nunca adjuntes bases ni copias privadas. Para cambios mayores que una corrección pequeña, acuerda el alcance en una incidencia antes de preparar un pull request. El soporte es voluntario.
