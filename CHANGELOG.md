# Bitácora de cambios de Eureka_Utils

Novedades de cada versión. El detalle de cada error corregido (qué pasaba, por qué y cómo se ha solucionado) está en [REGISTRO-DE-ERRORES.md](REGISTRO-DE-ERRORES.md).

## 2.4.0 · noviembre de 2026

### Novedades

- **Icono ⓘ en las comprobaciones.** Al final de cada fila que no está en OK aparece un icono redondo: naranja en los avisos, rojo en los fallos y azul en la información. Al pulsarlo se abre una ventana con:
  - **Qué ocurre:** la comprobación y lo que se ha detectado.
  - **A qué se debe** y **cómo solucionarlo:** una explicación propia de cada comprobación, en los 8 idiomas.
  - **Datos técnicos** leídos en ese momento cuando ayudan, por ejemplo:
    - Dispositivos con su código de error.
    - Eventos críticos con el código del pantallazo azul.
    - Errores agrupados por origen.
    - Estado de los servicios, de la red y de Defender.
  - **Informe para la IA:** la comprobación, la explicación, los datos del equipo, los datos técnicos y las últimas 60 líneas del registro. Por defecto oculta el nombre del equipo, del usuario y la carpeta del perfil.
  - **Preguntar a:** Claude, Microsoft Copilot, ChatGPT, Google Gemini, Perplexity, Le Chat u «Otra IA (solo copiar)». El informe se copia al portapapeles y se abre la web elegida para pegarlo; Eureka_Utils no envía nada por su cuenta. La IA elegida se recuerda.
  - Botones para copiar el informe, guardarlo como archivo (.md o .txt) y abrir el registro completo.
- El icono está en todas las listas de comprobaciones:
  - Diagnóstico y seguridad.
  - Compatibilidad con Windows 11.
  - TPM, UEFI y arranque seguro.
  - Cuenta profesional y Active Directory.

- **Tareas en paralelo.** Ya no hay que esperar a que termine una tarea para lanzar otra. Por ejemplo, puedes listar el hardware, medir la memoria o analizar el sistema mientras se actualizan las aplicaciones.
  - Se ejecutan hasta 4 tareas a la vez.
  - Las que modifican Windows o las aplicaciones (instalar, desinstalar, actualizar, bloatware, ajustes, perfiles, dominio, controladores, BIOS) siguen yendo **de una en una**, porque dos instaladores a la vez fallan. También van de una en una las de Defender, las del USB y las de gestión (gpupdate, Intune).
  - Todo lo que solo consulta va en paralelo con cualquier cosa.
  - Lo que no puede empezar todavía **espera en cola** y arranca solo cuando queda libre. Pedir otra vez algo que ya está en espera no lo duplica.
  - Solo se desactiva el botón de la tarea en marcha; el resto de la aplicación sigue disponible.
  - La barra de estado muestra «N en curso · M en espera»; al pasar el ratón por encima se ven los nombres.
  - Cada línea del registro lleva el nombre de su tarea entre llaves, por ejemplo `{Listando hardware y controladores}`, y el archivo de registro se escribe con un mutex para que las tareas no se pisen.

### Correcciones


- **[E-001] Crítico:** proteger la carpeta dejaba todos los archivos sin permisos y **ningún botón funcionaba** («El término 'Get-CfgDevices' no se reconoce…»). Se ha corregido la protección y se han añadido:
  - Copia de los permisos con marcha atrás automática.
  - Autorreparación al arrancar en `Eureka_Utils.ps1`, `Eureka_Utils.cmd` y `Eureka_Utils.exe`.
  - Un mensaje claro si vuelve a pasar.
  - Pruebas automáticas.
- **[E-002]** El aviso de «carpeta insegura» salía en cada arranque aunque los usuarios solo pudieran leer.
- **[E-003] Crítico:** el USB de instalación dejaba `C:\Eureka_Utils` sin permisos en el equipo nuevo. **Vuelve a crear el USB o el `autounattend.xml`** con esta versión.
- **[E-004]** «Volumen marcado para revisión» avisaba con el disco en buen estado en Windows en español («no contiene errores»).
- **[E-005]** En inglés, «WARNING» se montaba sobre el texto de las comprobaciones.
- **[E-006]** «Exportar lista (CSV)» podía dar un error sin controlar si no se podía escribir en `Exports`. Además, ahora hay una red de seguridad general: un error inesperado en cualquier botón se registra y se explica sin cerrar Eureka_Utils.
- **[E-008]** Al terminar cualquier tarea se reactivaban todos los botones, también los que la aplicación desactiva a propósito; por ejemplo, «Convertir el disco a GPT» con el disco ya en GPT.
- **[E-007]** «Informe de batería» daba ERROR en los equipos de sobremesa; ahora indica que el equipo no tiene batería.

### Pruebas

- Hay 9 pruebas automáticas nuevas (31 en total):
  - Las explicaciones cubren todas las comprobaciones y están traducidas.
  - El informe para la IA oculta los datos personales.
  - Está el icono.
  - `fsutil` se interpreta bien.
  - Los permisos de la carpeta (llamadas peligrosas a icacls, protección real en una carpeta temporal, falso positivo de seguridad y autorreparación).
- Revisión de los 54 botones que lanzan tareas: todas las órdenes que usan existen en los módulos que carga la tarea.
- Pruebas de las tareas en paralelo: los cerrojos de cada tarea y un escenario real con 4 tareas a la vez y una en cola.
- Prueba de la interfaz real pulsando los botones de cada pestaña. Los que modifican el equipo se han ejercitado hasta su confirmación (respondida con «No») o comprobado sin ejecutarlos.

## 2.3.0 · noviembre de 2026

- Pruebas automáticas en GitHub Actions: no se publica ninguna versión si fallan.
- Arranque más rápido: la detección pasa de unos 18 s a menos de 5 s.
- Aviso de versión nueva, y descarga con verificación de la huella SHA-256 publicada en GitHub.

## 2.2.1 · noviembre de 2026

- Identificación del equipo en la pestaña Hardware con los datos de cada fabricante:
  - Lenovo: tipo y modelo (MT y MTM).
  - Dell: Service Tag y Express Service Code.
  - HP: número de producto.
  - Número de serie y enlace a la garantía.

## 2.2.0 · noviembre de 2026

- Uso real de la memoria por programa.
- Pestaña **Drivers y BIOS**: lista de hardware y controladores, actualizaciones de controladores desde Windows Update, copia de seguridad de controladores, comprobación de la BIOS y guía por fabricante.
- Requisitos de los juegos con antitrampas: TPM 2.0, UEFI, disco GPT y arranque seguro.
- Botón para borrar los registros e informes.
