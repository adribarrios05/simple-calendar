[English](../../../README.md) · Español

Fuente: [README en inglés](../../../README.md). Revisado: 27 de octubre de 2026.

# Simple Calendar

Aplicación de escritorio Windows, local y sin cuentas. Combina horarios estrictos, planificación flexible automática y asignación manual en un calendario. La instalación comienza vacía: los datos de ejemplo solo existen en las pruebas.

El código y la documentación originales utilizan la [licencia MIT](../../../LICENSE.md). Los componentes de terceros conservan sus condiciones; consulta los [avisos de terceros](../../../THIRD_PARTY_NOTICES.md). El empaquetado incluye ambos documentos y genera THIRD_PARTY_NOTICES.txt con los avisos legibles de Flutter correspondientes a esa compilación.

## Estado e idiomas

La aplicación usa **inglés por defecto**, también al cargar preferencias antiguas sin idioma. Cambia a español desde **Settings → Language → Español**. La selección se guarda y viaja en las copias JSON; cambiar tema o disponibilidad la conserva. Los textos introducidos por el usuario no se traducen. Los nombres predefinidos sin renombrar se muestran en el idioma seleccionado, conservando IDs y datos originales.

La **1.0.0-beta.1** (compilación 1) está disponible como beta pública para Windows x64. El repositorio contiene la aplicación, las instrucciones de compilación y la documentación pública para contribuir.

[Descargar ZIP para Windows x64](https://github.com/adribarrios05/simple-calendar/releases/download/v1.0.0-beta.1/SimpleCalendar-1.0.0-beta.1-windows-x64.zip) · [Checksum SHA256](https://github.com/adribarrios05/simple-calendar/releases/download/v1.0.0-beta.1/SimpleCalendar-1.0.0-beta.1-windows-x64.zip.sha256) · [Notas de la versión](https://github.com/adribarrios05/simple-calendar/releases/tag/v1.0.0-beta.1)

## Instalar y abrir

1. Descarga el [ZIP para Windows x64](https://github.com/adribarrios05/simple-calendar/releases/download/v1.0.0-beta.1/SimpleCalendar-1.0.0-beta.1-windows-x64.zip) y extrae **todo su contenido** en una carpeta permanente.
2. Abre `SimpleCalendar.exe`. Conserva juntos el ejecutable, sus DLL y la carpeta `data`.
3. Puedes crear un acceso directo al ejecutable. No requiere Flutter, Visual Studio ni permisos de administrador para utilizarla.

Destino: Windows 10/11 x64. La distribución incluye el runtime de Visual C++ junto a la aplicación. El ejecutable no está firmado; no se ha generado un instalador MSI/MSIX. La compilación y la prueba nativa se realizaron en Windows 11 con Visual Studio 2022. Comprueba las futuras versiones en Windows sin herramientas de desarrollo; compilar en el equipo de desarrollo no demuestra por sí solo esa compatibilidad.

## Uso

- **Crear / Ctrl+N:** nombre, tipo, duración, fecha inicial, repetición, prioridad, descripción y subtareas. Las estrictas incluyen hora; las manuales empiezan sin asignar.
- **Hoy / Ctrl+T:** línea temporal de 24 horas, bloques, tareas sin asignar y huecos libres. El desplazamiento inicial muestra las horas de actividad habituales. Los bloques de menos de 34 minutos conservan su altura temporal y también aparecen en «Bloques breves» para abrirlos fácilmente.
- **Semana:** siete columnas con una escala horaria vertical compartida de 00:00 a 24:00. La posición indica el inicio y la altura representa la duración; el desplazamiento vertical mueve todos los días juntos. Sin horario y omitidas se muestran en una franja separada. Pulsa un bloque para ver detalles o la cabecera para abrir el día.
- **Mes:** navegar, consultar actividades y abrir un día. Las vistas Tareas y Rutinas permiten buscar, filtrar y editar definiciones; sus filtros «hoy» siempre consultan el día actual, aunque antes hayas navegado a otra fecha.
- **Detalle:** completar u omitir una ejecución, marcar subtareas, editar y fijar o liberar horarios. Completar la tarea no exige completar sus subtareas.
- **Asignar / mover horario:** elegir una hora exacta. También puedes arrastrar un bloque flexible del mismo día a la línea temporal, con precisión de 15 minutos. Una colocación manual queda bloqueada.
- **Editar:** desde el detalle se elige esta ejecución o la definición desde hoy. El historial y las excepciones con progreso se conservan. Desde Tareas se modifica la definición.
- **Configuración:** tema claro/oscuro/sistema, disponibilidad de cada día y copias JSON. Igualar inicio y final cierra ese día para la planificación flexible.

### Etiquetas

En Crear o Editar, pulsa **Etiquetas → Elegir** para buscar y seleccionar varias etiquetas opcionales. Puedes crear una personalizada desde ese selector y quitar las seleccionadas con la cruz del chip. Se incluyen Trabajo, Estudio, Entrenamiento, Personal, Hogar, Salud, Ocio y Otros. No cambian la prioridad, el horario ni la planificación de las actividades.

En **Configuración → Etiquetas** puedes crear, renombrar y cambiar colores. Las predefinidas no se pueden eliminar. Retirar una personalizada requiere confirmación: deja de ofrecerse para nuevas asignaciones, pero conserva sus asociaciones e historial; su nombre queda reservado. Se puede quitar de una actividad existente. Renombrar o recolorear actualiza su presentación global, también en el historial.

Tareas y Rutinas permiten filtrar por una etiqueta o por **Sin etiquetas**, junto a la búsqueda, tipo y estado; la cruz limpia el filtro. El calendario muestra indicadores discretos y el detalle ofrece todos los nombres. Los bloques breves conservan su altura temporal y muestran las etiquetas en el tooltip o detalle.

Las asociaciones pertenecen a la definición y se copian a cada ejecución. **Solo esta ejecución** cambia únicamente esa fecha. **La definición, desde hoy** respeta revisiones, historial y ejecuciones con progreso, bloqueo, excepción o ya iniciadas. Una edición que solo cambie etiquetas conserva las asignaciones regenerables. Las copias JSON nuevas incluyen el catálogo y todas sus asociaciones; se admiten copias antiguas sin etiquetas.

Se admiten fechas desde el 1 de enero de 2000 hasta el 31 de diciembre de 2100. Los días fuera de ese intervalo que completan una cuadrícula semanal o mensual no se pueden abrir. Las actividades breves de la semana también están disponibles en la franja superior. Si varias subtareas tienen el mismo texto, al editarlas sus marcas se corresponden por orden de aparición; una copia nueva del mismo texto no hereda marcas adicionales.

Las sugerencias automáticas tienen un borde más fino y la etiqueta «Sugerida» en bloques amplios. Las estrictas, manuales y bloqueadas tienen iconos propios. Los bloques pequeños muestran el nombre; el detalle ofrece la información completa.

Las asignaciones automáticas comienzan en múltiplos de cinco minutos: un hueco que empieza a las 17:48 se aprovecha desde las 17:50, siempre que quepa la duración completa. Las tareas ya iniciadas y los horarios manuales o bloqueados conservan su posición.

Editar la definición conserva también la ejecución de hoy si ya empezó; utiliza «Solo esta ejecución» para cambiarla deliberadamente. Al cambiar el alcance del editor se cargan los datos guardados correspondientes y se descartan cambios sin guardar. **Eliminar actividad** pide confirmación y la retira del calendario desde hoy, incluido hoy. No queda como omitida ni puede reactivarse. Se conservan las fechas anteriores y los datos originales en las copias. Las eliminaciones anteriores se convierten automáticamente al actualizar. **Omitir esta ejecución** sigue siendo una acción distinta y reversible.

Los conflictos estrictos se advierten antes de guardar. Puedes cambiar el horario o conservar ambos con una incidencia explícita; nunca se desplaza un bloque protegido para resolverlo. Los solapamientos se muestran en columnas separadas. Una asignación manual nueva que choque con un bloque protegido se rechaza con un mensaje.

## Datos y copias

SQLite se guarda en `%APPDATA%\Simple Calendar\calendar.sqlite`. La carpeta es independiente del ejecutable, los metadatos nativos y el idioma. Los cambios se guardan automáticamente. Una segunda apertura enfoca la ventana existente.

En el primer arranque, si no existe la base nueva y hay una agenda en `%APPDATA%\local.calendario\calendario\calendario.sqlite`, se migra automáticamente mediante una copia coherente creada por SQLite, incluidos los datos confirmados en WAL. La copia se comprueba antes de activarse. El original se conserva y nunca sustituye una base nueva existente. Si falla la migración, se detiene el arranque en lugar de mostrar una agenda vacía. El archivo `.migration.lock` coordina los intentos de migración.

Exporta una copia antes de actualizar. Tras comprobar la agenda nueva y exportar otra copia JSON, puedes archivar manualmente la carpeta antigua. No sigas utilizando ejecutables anteriores: escriben en la ruta antigua y sus cambios posteriores no se fusionan con la nueva. La futura distribución en Microsoft Store requiere comprobar sus rutas por separado.

Exporta desde Configuración. Para restaurar, selecciona una copia JSON: se validan formato, versión, fechas, rangos, relaciones, duplicados y revisiones antes de solicitar confirmación y reemplazar los datos en una transacción. Límite: 50 MB. Exporta antes una copia de los datos que quieras conservar. El JSON es legible y no está cifrado.

### Actualizar y comprobar los datos

1. Exporta una copia JSON y guárdala fuera de la carpeta de la aplicación.
2. Cierra la aplicación antes de sustituir los binarios. Extrae el nuevo ZIP completo en otra carpeta y conserva la versión anterior hasta comprobar la nueva.
3. Abre la nueva versión y comprueba una ejecución completada, sus subtareas, una asignación bloqueada y la disponibilidad. Los datos están fuera de la carpeta del ejecutable; mover el ZIP o su carpeta no los traslada.
4. Las migraciones se ejecutan al abrir la base. El esquema actual es **v5**, con actualización transaccional desde v1/v2/v3/v4. La estructura de tablas no cambia respecto a v3; se protegen el límite semanal, las eliminaciones y las franjas automáticas frente a binarios anteriores. Las copias nuevas son **v4**; se importan las v1/v2/v3. No abras esta base con un binario antiguo ni rebajes la versión de las copias. Conserva una copia previa a actualizar.

Las actividades flexibles automáticas permiten activar **Limitar horario de planificación**, con **No antes de** y **Terminar antes de** (por ejemplo, 09:00–14:00 del mismo día). Toda la duración debe caber en esa franja y en la disponibilidad diaria. Si no cabe, queda sin asignar y con un aviso. Las actividades existentes siguen sin límite propio hasta activarlo. Los bloques bloqueados o iniciados conservan su posición y muestran avisos si quedan fuera de la franja.

Estas instrucciones describen el procedimiento de actualización portable. Las pruebas automatizadas con bases temporales cubren esquema, edición, cierre y reapertura; repite también las comprobaciones de instalación y actualización entre distribuciones para cada futura versión.

### Si aparece un error de almacenamiento

- **Sin espacio:** libera espacio y reintenta. La prueba con el límite de páginas SQLite verifica que la escritura rechazada no sustituye los datos anteriores; no simula un corte eléctrico ni todas las averías de disco.
- **Solo lectura o sin acceso:** comprueba permisos, protección del archivo y acceso a la carpeta. No es necesario ejecutar la aplicación habitualmente como administrador.
- **Base ocupada:** cierra otras instancias y reintenta. No borres archivos de la base para desbloquearla.
- **Versión incompatible:** utiliza una versión de la aplicación que entienda ese esquema. No cambies manualmente `user_version` ni recrees la base para forzar la apertura.
- **Base ilegible o dañada:** cierra la aplicación y conserva una copia de toda su carpeta de datos antes de intentar recuperar nada. La aplicación no borra ni recrea automáticamente una base que no puede leer.

### Restaurar conservando el original

Si la aplicación abre, exporta antes el estado actual y utiliza Configuración → Importar copia. Un archivo incompatible se rechaza antes de reemplazar datos; si la escritura de la restauración falla, la transacción conserva el estado anterior.

Si no abre y ya dispones de una copia JSON válida, cierra todas las instancias y copia **toda** la carpeta de soporte a un lugar seguro, incluidos los archivos auxiliares SQLite que pueda haber. Una vez resguardado el original, aparta la carpeta dañada de su ubicación habitual sin borrarla; al abrir se creará una base vacía en la ubicación habitual. Importa entonces tu copia JSON desde Configuración y comprueba su contenido. Recuperarás el estado de esa copia, no los cambios posteriores a ella. Si la causa es un problema de permisos o versión, resuélvelo primero: crear otra carpeta no repara esos problemas.

Si no tienes una copia JSON utilizable, conserva los archivos originales y trabaja únicamente sobre duplicados para investigar la recuperación. No edites ni reemplaces tu única base, ni importes archivos de origen desconocido para intentar repararla. No se garantiza recuperar información de un archivo físicamente dañado.

## Desarrollar y compilar

Entorno comprobado: Flutter **3.41.4**, Dart **3.11.1**, Visual Studio Community **2022** con Desarrollo para escritorio con C++ y Windows SDK. Se fijan Drift/drift_dev **2.33.0** por compatibilidad con el analizador del SDK. Se utiliza Riverpod **2.6.1** y SQLite nativo; `pubspec.lock` fija la resolución probada. No actualices paquetes aisladamente sin ejecutar las verificaciones.

En PowerShell, desde el repositorio:

```powershell
flutter pub get
dart run build_runner build
flutter run -d windows
```

Verificación:

```powershell
flutter analyze
flutter test
flutter test integration_test/windows_test.dart -d windows
flutter build windows --release
```

Ejecutable: `build/windows/x64/runner/Release/SimpleCalendar.exe`. Para producir el ZIP con las DLL del runtime de Visual C++:

```powershell
.\scripts\package_windows.ps1
```

El script necesita Visual Studio instalado. `-SkipBuild` empaqueta la compilación existente. La aplicación funciona sin Internet; preparar el entorno de desarrollo y descargar paquetes requiere conexión la primera vez. No utiliza servicios externos durante su ejecución.

Consulta [ARCHITECTURE.md](../../../ARCHITECTURE.md) para las reglas del motor y [CONTRIBUTING.md](CONTRIBUTING.md) para contribuir. Referencias de dependencias: [Drift](https://pub.dev/packages/drift/versions/2.33.0), [Riverpod](https://pub.dev/packages/flutter_riverpod/versions/2.6.1).

La documentación principal y los comentarios de código están en inglés. Las traducciones humanas se mantienen en `docs/i18n/<idioma>/`. [Cómo contribuir](CONTRIBUTING.md).

## Capturas de la beta

Capturas de la interfaz real generadas con una base temporal y tareas ficticias. Las instalaciones nuevas no incluyen datos de ejemplo.

![Vista diaria en inglés](../../screenshots/day-en.png)

![Vista semanal en inglés](../../screenshots/week-en.png)

## Alcance y soporte

La beta incluye calendario local, tareas fijas/flexibles/manuales, recurrencias, etiquetas, subtareas, inglés/español y copias JSON. No incluye notificaciones, fechas límite, replanificación entre días, división en sesiones, varias franjas de disponibilidad ni sincronización. Estas funciones opcionales no bloquean la beta.

El ZIP no está firmado: Windows puede advertir de un editor desconocido. No hay instalador ni actualizador automático y los datos no están cifrados. Exporta una copia antes de actualizar. Las funciones opcionales quedan fuera del alcance de esta beta.

Utiliza [Issues](https://github.com/adribarrios05/simple-calendar/issues) para incidencias y propuestas. Incluye versión/compilación, Windows, pasos y resultados esperado/real. No adjuntes agendas, bases o copias personales; usa ejemplos ficticios y oculta información privada en capturas. El soporte es voluntario, sin plazo de respuesta garantizado.

## Versión y checksum

El script lee `pubspec.yaml` y genera el ZIP anterior junto a `SimpleCalendar-1.0.0-beta.1-windows-x64.zip.sha256`. Compara el primer campo del archivo SHA256 con:

```powershell
Get-FileHash .\SimpleCalendar-1.0.0-beta.1-windows-x64.zip -Algorithm SHA256
```

`-SkipBuild` comprueba que la versión del ejecutable coincida con `pubspec.yaml`; esto no demuestra que proceda del código actual. Recompila para publicar. No se garantiza reproducibilidad byte a byte. La [primera beta pública](https://github.com/adribarrios05/simple-calendar/releases/tag/v1.0.0-beta.1) incluye ambos archivos. En futuras versiones, publica el ZIP y su checksum bajo la etiqueta correspondiente tras completar las comprobaciones. El checksum no es una firma digital. Aumenta el número de beta y compilación en nuevas distribuciones; no reemplaces archivos ya publicados bajo la misma versión.

## Nombre del proyecto

El logotipo morado está en `assets/branding/app_icon.png` y aparece en la navegación. Windows utiliza `windows/runner/resources/app_icon.ico` para el ejecutable y la ventana. Para regenerar sus tamaños de 16 a 256 píxeles desde el PNG, ejecuta `powershell -NoProfile -File .\scripts\update_windows_icon.ps1` y vuelve a compilar. No requiere paquetes adicionales. El Explorador de Windows puede conservar en caché el icono de un ejecutable o acceso directo antiguo.

La marca es **Simple Calendar** en ambos idiomas. El paquete Dart se llama `simple_calendar` y el ejecutable de Windows, `SimpleCalendar.exe`. Las rutas antiguas, el identificador JSON `calendario-local` y el mutex de instancia conservan sus valores anteriores por compatibilidad con datos, copias y ejecutables previos. No son nombres visibles del producto.

## Rutinas semanales

Las actividades nuevas del formulario empiezan con repetición semanal. Elige **Todas las semanas** para mantener la rutina o **Solo esta semana** para terminar el domingo de la semana de la fecha de inicio. Repetición determina los días: diariamente, lunes a viernes, semanalmente o días elegidos. **Una vez** sigue disponible para una única fecha. Cambiar la fecha de inicio actualiza el límite de la semana.

## Horario de las actividades estrictas

El formulario utiliza **Hora de inicio** y **Hora de fin**, con entrada HH:mm o selector de reloj. La duración se calcula automáticamente. La hora de fin debe ser posterior a la de inicio dentro del mismo día; se admite 24:00 como final del día. Las actividades flexibles conservan el campo de duración estimada. Los datos existentes mantienen su formato y horario.
