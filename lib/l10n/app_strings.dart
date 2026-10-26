import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// English is the canonical message catalogue and the default locale.
/// Placeholders are substituted after translation, so user text is never translated.
class AppStrings {
  final String language;
  const AppStrings(this.language);
  static const supportedLocales = [Locale('en'), Locale('es')];
  static const delegate = _AppStringsDelegate();
  String text(String source, [List<Object> arguments = const []]) {
    final template = language == 'es'
        ? spanishMessages[source] ?? source
        : source;
    return template.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < arguments.length ? arguments[index].toString() : match[0]!;
    });
  }

  /// Translate known application failures without modifying arbitrary user data.
  String error(Object error) {
    var message = error.toString();
    for (final prefix in ['Bad state: ', 'FormatException: ']) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length);
      }
    }
    if (spanishMessages.containsKey(message)) return text(message);
    for (final source in spanishMessages.keys.where(
      (key) => key.contains('{0}'),
    )) {
      final escaped = RegExp.escape(
        source,
      ).replaceAllMapped(RegExp(r'\\\{\d+\\\}'), (_) => '(.*?)');
      final pattern = RegExp('^$escaped\$', dotAll: true);
      final match = pattern.firstMatch(message);
      if (match != null) {
        return text(source, [
          for (var i = 1; i <= match.groupCount; i++) match[i]!,
        ]);
      }
    }
    return message;
  }
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();
  @override
  bool isSupported(Locale locale) => ['en', 'es'].contains(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale.languageCode));
  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings =>
      Localizations.of<AppStrings>(this, AppStrings) ?? const AppStrings('en');
}

/// English keys and Spanish resources. Add a complete catalogue before enabling another locale.
const spanishMessages = <String, String>{
  'Limit scheduling hours': 'Limitar horario de planificación',
  'Not before': 'No antes de',
  'Finish by': 'Terminar antes de',
  'The full duration must fit within this window and daily availability.':
      'La duración completa debe caber en esta franja y en la disponibilidad del día.',
  'Scheduling window: {0}–{1}': 'Franja de planificación: {0}–{1}',
  'Invalid activity time window.': 'Franja horaria de la actividad no válida.',
  'Outside the activity time window. Move or unlock the block.':
      'Fuera de la franja horaria de la actividad. Mueve o desbloquea el bloque.',
  'No continuous slot fits within the activity time window.':
      'No hay un hueco continuo suficiente dentro de la franja horaria de la actividad.',
  'The block must fit within the activity time window.':
      'El bloque debe caber dentro de la franja horaria de la actividad.',
  'This data requires backup version 4.':
      'Estos datos requieren una copia de seguridad de versión 4.',

  '\nThere is a conflict. Open the details.':
      '\nHay un conflicto. Abre el detalle.',
  ' (retired)': ' (retirada)',
  ' · Skipped': ' · Omitida',
  ' · retired': ' · retirada',
  '+{0} more': '+{0} más',
  'A tag with this name already exists.':
      'Ya existe una etiqueta con ese nombre.',
  'All local data will be replaced. You can export a backup from this screen before continuing.':
      'Se reemplazarán todos los datos locales. Antes de continuar, puedes exportar una copia desde esta pantalla.',
  'All statuses': 'Todos los estados',
  'All tags': 'Todas las etiquetas',
  'All types': 'Todos los tipos',
  'Appearance': 'Apariencia',
  'Apply': 'Aplicar',
  'Apply changes to': 'Aplicar cambios a',
  'Archive': 'Eliminar',
  'Archive activity': 'Eliminar actividad',
  'Archive activity?': '¿Eliminar actividad?',
  'Archive definition': 'Eliminar definición',
  'Remove activity': 'Eliminar actividad',
  'Remove activity?': '¿Eliminar actividad?',
  'Remove this activity from today, including today? It will disappear from the calendar and cannot be reactivated. Earlier dates are kept. Saved execution data is preserved in backups, but removed dates cannot be edited.':
      '¿Eliminar esta actividad desde hoy, incluido hoy? Desaparecerá del calendario y no podrá reactivarse. Se conservan las fechas anteriores. Los datos guardados se mantienen en las copias, pero las fechas eliminadas no pueden editarse.',
  'This activity has been removed and cannot be restored.':
      'Esta actividad se ha eliminado y no puede restaurarse.',
  'This data requires backup version 3.':
      'Estos datos requieren la versión 3 de las copias de seguridad.',
  'Schedule scope': 'Alcance de la planificación',
  'Start time': 'Hora de inicio',
  'End time': 'Hora de fin',
  'Choose start time': 'Elegir hora de inicio',
  'Choose end time': 'Elegir hora de fin',
  'Use 24:00 for the end of the day.': 'Usa 24:00 para el final del día.',
  'Enter a valid time in HH:mm format.':
      'Introduce una hora válida en formato HH:mm.',
  'The end time must be later than the start time.':
      'La hora de fin debe ser posterior a la hora de inicio.',
  'Every week': 'Todas las semanas',
  'This week only': 'Solo esta semana',
  'Ends on {0}, in the week of the start date.':
      'Termina el {0}, en la semana de la fecha de inicio.',
  'The activity no longer exists.': 'La actividad ya no existe.',
  'Stop this activity from today? Future pending occurrences, including fixed and locked ones, will be cancelled. Past, completed and already-started occurrences are kept. Cancelled occurrences with saved data remain under skipped activities, preserving assignments and subtask progress.':
      '¿Dejar de realizar esta actividad desde hoy? Se cancelarán las ejecuciones pendientes futuras, incluidas las estrictas y bloqueadas. Se conservan las pasadas, completadas y ya iniciadas. Las canceladas con datos guardados quedan entre las actividades omitidas, conservando horarios y progreso de subtareas.',
  'Assign / move time': 'Asignar / mover horario',
  'Automatic flexible': 'Flexible automática',
  'Available slots': 'Huecos disponibles',
  'Backup restored successfully.': 'Copia restaurada correctamente.',
  'Backup saved to {0}': 'Copia guardada en {0}',
  'Backups': 'Copias de seguridad',
  'Between 1 and 1440.': 'Entre 1 y 1440.',
  'Built-in': 'Predefinida',
  'Built-in tags cannot be retired.':
      'Las etiquetas predefinidas no se pueden eliminar.',
  'Calendar backup': 'Copia de Simple Calendar',
  'Cancel': 'Cancelar',
  'Change time': 'Cambiar horario',
  'Changing scope loads its saved data and discards unsaved changes. The definition uses its current values.':
      'Al cambiar el alcance se cargan sus datos guardados y se descartan los cambios sin guardar. La definición usa sus valores vigentes.',
  'Choose': 'Elegir',
  'Clear tag filter': 'Limpiar filtro de etiquetas',
  'Close details': 'Cerrar detalle',
  'Color': 'Color',
  'Color {0}': 'Color {0}',
  'Completed': 'Completada',
  'Completed today': 'Completada hoy',
  'Conflict with {0}.': 'Conflicto con {0}.',
  'Could not complete: {0}': 'No se pudo completar: {0}',
  'Create': 'Crear',
  'Create tag': 'Crear etiqueta',
  'Daily': 'Diariamente',
  'Dark': 'Oscuro',
  'Description (optional)': 'Descripción (opcional)',
  'Details': 'Detalle',
  'Duplicate occurrences or occurrences without a task.':
      'Ejecuciones duplicadas o sin tarea.',
  'Duplicate or incomplete tag catalogue.':
      'Catálogo de etiquetas duplicado o incompleto.',
  'Duplicate tasks.': 'Tareas duplicadas.',
  'Duration (minutes)': 'Duración (minutos)',
  'Edit activity': 'Editar actividad',
  'Edit tag': 'Editar etiqueta',
  'Edit the fixed activity\'s time.':
      'Edita el horario de la actividad estricta.',
  'Edit {0}': 'Editar {0}',
  'English': 'English',
  'Enter a name.': 'Escribe un nombre.',
  'Español': 'Español',
  'Everything is scheduled.': 'Todo está organizado.',
  'Export backup': 'Exportar copia',
  'Fixed': 'Estricta',
  'Fri': 'Vie',
  'Go to date': 'Ir a fecha',
  'Health': 'Salud',
  'High': 'Alta',
  'Home': 'Hogar',
  'Import backup': 'Importar copia',
  'Invalid availability.': 'Disponibilidad no válida.',
  'Invalid date.': 'Fecha no válida.',
  'Invalid occurrence.': 'Ejecución no válida.',
  'Invalid revision.': 'Revisión no válida.',
  'Invalid tag references.': 'Referencias de etiquetas no válidas.',
  'Invalid tag: use a name of 1 to 40 characters and an opaque color.':
      'Etiqueta no válida: nombre de 1 a 40 caracteres y color opaco.',
  'It will no longer be offered for new activities. Its name will remain reserved.':
      'Dejará de ofrecerse para nuevas actividades. Su nombre quedará reservado.',
  'Keep with warning': 'Conservar con aviso',
  'Language': 'Idioma',
  'Leisure': 'Ocio',
  'Light': 'Claro',
  'Lock schedule': 'Bloquear horario',
  'Low': 'Baja',
  'Manual flexible': 'Flexible manual',
  'Missing revisions.': 'Faltan revisiones.',
  'Mon': 'Lun',
  'Month': 'Mes',
  'Name': 'Nombre',
  'New activity': 'Nueva actividad',
  'New tag': 'Nueva etiqueta',
  'Next': 'Siguiente',
  'No activities yet. Use Create to add your first one.':
      'No hay actividades. Crea la primera con el botón Crear.',
  'Normal': 'Normal',
  'Once': 'Una vez',
  'Only this occurrence': 'Solo esta ejecución',
  'Organize activities without changing their schedule.':
      'Organiza tus actividades sin cambiar su planificación.',
  'Other': 'Otros',
  'Outside availability. Move or unlock the block.':
      'Fuera de la disponibilidad. Reubica o libera el bloque.',
  'Pending today': 'Pendiente hoy',
  'Personal': 'Personal',
  'Previous': 'Anterior',
  'Priority': 'Prioridad',
  'Refresh schedule': 'Actualizar planificación',
  'Remove time': 'Quitar horario',
  'Repeat': 'Repetición',
  'Replace data': 'Reemplazar datos',
  'Restore validated backup': 'Restaurar copia validada',
  'Retire': 'Retirar',
  'Retire {0}': 'Retirar {0}',
  'Retire “{0}”?': '¿Retirar «{0}»?',
  'Retry': 'Reintentar',
  'Routines': 'Rutinas',
  'Sat': 'Sáb',
  'Save': 'Guardar',
  'Save tag': 'Guardar etiqueta',
  'Saving…': 'Guardando…',
  'Scheduling': 'Planificación',
  'Scheduling conflicts': 'Hay horarios en conflicto',
  'Scheduling issues': 'Incidencias',
  'Search activities': 'Buscar actividades',
  'Search tags': 'Buscar etiquetas',
  'Selected weekdays': 'Días concretos',
  'Settings': 'Configuración',
  'Short blocks': 'Bloques breves',
  'Shortcuts: Ctrl+N creates an activity · Ctrl+T opens today.\nDrag a flexible block onto the timeline to lock it in 15-minute steps. You can also choose an exact time from its details.\n\nSimple Calendar · No accounts or Internet connection.':
      'Atajos: Ctrl+N crea una actividad · Ctrl+T abre hoy.\nArrastra un bloque flexible a la línea temporal para fijarlo en intervalos de 15 minutos. También puedes elegir una hora exacta desde el detalle.\n\nSimple Calendar · Sin cuentas ni conexión a Internet.',
  'Simple Calendar': 'Simple Calendar',
  'Skip this occurrence': 'Omitir esta ejecución',
  'Skipped today': 'Omitida hoy',
  'Start date: {0}': 'Fecha inicial: {0}',
  'Study': 'Estudio',
  'Subtasks (one per line)': 'Subtareas (una por línea)',
  'Subtasks · {0}/{1}': 'Subtareas · {0}/{1}',
  'Suggested': 'Sugerida',
  'Sun': 'Dom',
  'System': 'Sistema',
  'Tag name': 'Nombre de etiqueta',
  'Tags': 'Etiquetas',
  'Tags (optional)': 'Etiquetas (opcional)',
  'Tags: {0}': 'Etiquetas: {0}',
  'Tasks': 'Tareas',
  'The activity contains unknown tags.':
      'La actividad contiene etiquetas desconocidas.',
  'The backup exceeds 50 MB.': 'La copia supera 50 MB.',
  'The block must fit within availability.':
      'El bloque debe quedar dentro de la disponibilidad.',
  'The database cannot be opened. Check that its folder exists and that you have permission to access it.':
      'No se puede abrir la base de datos. Comprueba que su carpeta existe y que tienes permiso para acceder.',
  'The database cannot be read. Keep the original file and consult the recovery guide before restoring a backup.':
      'No se puede leer la base de datos. Conserva el archivo original y consulta la guía de recuperación antes de restaurar una copia.',
  'The database could not be opened.\n{0}\n\nClose the app and check access to the data folder.':
      'No se pudo abrir la base de datos.\n{0}\n\nCierra la aplicación y comprueba el acceso a la carpeta de datos.',
  'The Windows application data folder could not be located.':
      'No se ha podido localizar la carpeta de datos de aplicaciones de Windows.',
  'The Simple Calendar data path is not a database file.':
      'La ruta de datos de Simple Calendar no es un archivo de base de datos.',
  'The previous database version is unsupported. Keep the original data folder and use a compatible application version.':
      'La versión de la base de datos anterior no es compatible. Conserva la carpeta original y utiliza una versión compatible de la aplicación.',
  'The previous database failed its integrity check. Keep the original data folder and restore a valid backup.':
      'La base de datos anterior no ha superado la comprobación de integridad. Conserva la carpeta original y restaura una copia válida.',
  'The migrated database failed its integrity check. The original data folder has been preserved.':
      'La base de datos migrada no ha superado la comprobación de integridad. Se ha conservado la carpeta original.',
  'The database is busy. Close other instances and try again.':
      'La base de datos está ocupada. Cierra otras instancias y vuelve a intentarlo.',
  'The database is read-only. Check the folder and file permissions.':
      'La base de datos está en modo de solo lectura. Comprueba los permisos de la carpeta y del archivo.',
  'The date must be between 2000 and 2100.':
      'La fecha debe estar entre 2000 y 2100.',
  'The definition and its unchanged pending occurrences will be removed. History, exceptions and protected blocks will be kept.':
      'Se retirará la definición y sus ejecuciones pendientes sin modificar. Se conservarán el historial, las excepciones y los bloques protegidos.',
  'The definition does not match its latest revision.':
      'La definición y su última revisión no coinciden.',
  'The definition is no longer available. Close and reopen the editor.':
      'La definición ya no está disponible. Cierra y vuelve a abrir el editor.',
  'The definition, from today': 'La definición, desde hoy',
  'The end must not be earlier than the start.':
      'El final debe ser posterior al inicio.',
  'The local data operation could not be completed. Try again; if it persists, keep a backup and consult the recovery guide.':
      'No se pudo completar la operación con los datos locales. Vuelve a intentarlo; si persiste, conserva una copia y consulta la guía de recuperación.',
  'The scheduler places flexible blocks within these hours. Fixed activities keep their time. Equal start and end times close that day.':
      'El planificador coloca bloques flexibles dentro de estos límites. Las actividades estrictas conservan su horario. Inicio y final iguales cierran ese día.',
  'The scheduler will keep this position.':
      'El planificador respetará esta posición.',
  'The task contains invalid values.': 'La tarea contiene valores no válidos.',
  'There is no continuous slot long enough.':
      'No hay un hueco continuo suficiente.',
  'There is not enough space to save changes. Free up space and try again.':
      'No hay espacio suficiente para guardar los cambios. Libera espacio y vuelve a intentarlo.',
  'This tag cannot be saved.': 'No se puede guardar esta etiqueta.',
  'This tag is used by activities or their history. All associations and data will be kept. It will no longer be offered for new activities.':
      'Está asociada a actividades o a su historial. Se conservarán esas asociaciones y todos sus datos. Dejará de ofrecerse para nuevas actividades.',
  'This time overlaps with {0}. Choose another slot.':
      'Ese horario coincide con {0}. Elige otro hueco.',
  'Thu': 'Jue',
  'Time': 'Hora',
  'Today': 'Hoy',
  'Training': 'Entrenamiento',
  'Tue': 'Mar',
  'Unlock and reschedule suggestion': 'Liberar y recalcular sugerencia',
  'Unscheduled / skipped': 'Sin asignar / omitidas',
  'Unscheduled / skipped / short': 'Sin hora / omitidas / breves',
  'Unsupported backup format or version.':
      'Formato o versión de copia no compatible.',
  'Unsupported migration: {0} → {1}': 'Migración no compatible: {0} → {1}',
  'Untagged': 'Sin etiquetas',
  'Wed': 'Mié',
  'Week': 'Semana',
  'Weekdays': 'Lunes a viernes',
  'Weekly': 'Semanalmente',
  'Weekly availability': 'Disponibilidad semanal',
  'Work': 'Trabajo',
  'You can go back and change the time. Keeping this time will show warnings without moving protected blocks.\n\n{0}':
      'Puedes volver y cambiar la hora. Si conservas el horario, se mostrarán incidencias sin mover los bloques protegidos.\n\n{0}',
  'Your data stays on this computer. Export a backup to keep it safe or move it to another Windows computer.':
      'Los datos se guardan en este equipo. Exporta una copia para conservarlos o trasladarlos a otro Windows.',
  'Your day': 'Tu día',
  'Your month': 'Tu mes',
  'Your time, your way': 'Tu tiempo, a tu manera',
  'Your week': 'Tu semana',
  'to': 'a',
  '{0} min · Priority {1}': '{0} min · Prioridad {1}',
  '{0} min · unscheduled': '{0} min · sin horario',
  '{0}, {1} minutes, {2}': '{0}, {1} minutos, {2}',
  '{0}/{1} subtasks': '{0}/{1} subtareas',
  '▣ Manual / locked': '▣ Manual / bloqueada',
  '◇ Suggested automatic': '◇ Automática sugerida',
  '◷ Fixed': '◷ Estricta',
};
