# Eureka_Utils · Configurador de equipos

Herramienta portable para preparar, auditar y diagnosticar equipos Windows 11 de uso personal y profesional. Detecta el hardware (incluida la tarjeta gráfica NVIDIA/AMD/Intel), quita bloatware, instala software explicando sus dependencias y su consumo de recursos, mantiene todo actualizado con winget, aplica ajustes, configura cuentas (con verificación en dos pasos), une el equipo a Active Directory o a Microsoft Entra ID, sincroniza con Intune, diagnostica el sistema y busca malware, y crea USB de instalación de Windows 11 que dejan el equipo configurado sin intervención.

**Versión 2.2 · noviembre de 2026**

## Características

- **Hardware**: detección de CPU, RAM, discos, red y GPU, con recomendaciones de controladores y comprobación de compatibilidad con Windows 11 (TPM 2.0, UEFI, arranque seguro).
- **Software**: catálogo estilo Centro de software con dependencias, requisitos e impacto en disco y RAM antes de instalar, calculado sobre el **consumo real de RAM** de lo que ya se está ejecutando en el equipo.
- **Drivers y BIOS**: listado de todo el hardware con su controlador (versión, fecha, firma y estado), controladores y firmware desde Windows Update, instalación desde carpeta, copia de seguridad de controladores y herramientas oficiales de Dell, HP, Lenovo e Intel. Versión y antigüedad de la BIOS con enlace al soporte del fabricante y preparación segura de la actualización (punto de restauración y BitLocker suspendido).
- **TPM 2.0, UEFI y arranque seguro (gaming)**: comprobación de los requisitos de los antitrampas (Valorant, Call of Duty, Battlefield 6), conversión MBR → GPT con MBR2GPT, reinicio directo en la BIOS e instrucciones según el fabricante (MSI, ASUS, Gigabyte, ASRock, Dell, HP, Lenovo, Acer).
- **Actualizaciones**: `winget upgrade` al abrir, con opción de actualizar todo o solo lo seleccionado. Después se **comprueba el resultado** y, si una aplicación no se ha actualizado, se avisa y se ofrece su **enlace de descarga manual**.
- **Bloatware**: retirada de apps preinstaladas con indicación del riesgo (bajo, medio, alto) y posibilidad de reinstalarlas.
- **Ajustes de Windows**: energía, gaming, explorador, privacidad, seguridad y administración.
- **Perfiles**: Personal, Oficina (Microsoft 365), Oficina IT (sistemas, soporte y ciberseguridad), Gaming, Gaming + Streaming, Creativo, Desarrollo, Estudiante y Equipo básico.
- **Cuentas y dominio**: cuentas locales, unión a Active Directory o Entra ID (la contraseña y el MFA los gestiona Microsoft; Eureka_Utils no los guarda), sincronización con Intune, unión híbrida y exportación del hash de Autopilot.
- **Diagnóstico**: estado del sistema operativo, SFC, DISM, CHKDSK, diagnóstico de memoria y errores recientes.
- **Antivirus y malware**: estado de Microsoft Defender, análisis rápido, completo, de una carpeta o USB y sin conexión, y Microsoft Safety Scanner portátil para llevar en el USB.
- **Consolas MMC**: acceso directo a las consolas de administración de Windows (y a las de RSAT si están instaladas).
- **USB de instalación**: formatea e instala Windows 11 y deja el equipo configurado con el perfil elegido.
- **Idiomas y tema**: interfaz en español, inglés, francés, portugués, euskera, catalán, valenciano y gallego, en modo claro u oscuro.
- **Informe**: exportación del estado del equipo en HTML.
- **Privacidad**: los registros e informes se guardan solo en el equipo; el botón **Borrar registros e informes** (pestaña Registro) los elimina.
- **Seguridad**: comprobación de integridad SHA-256 de los scripts en el lanzador, protección de la carpeta contra modificaciones sin permisos de administrador, instaladores locales verificados por hash o firma Authenticode y huellas SHA-256 de cada release.

## Requisitos

- Windows 11 y permisos de administrador.
- Windows PowerShell 5.1 (incluido en Windows). Interfaz WPF, sin dependencias externas.
- `winget` para instalar y actualizar software.

## Inicio rápido

1. Descarga `Eureka_Utils_Portable.exe` desde [Releases](https://github.com/juanraul86/Eureka_Utils/releases) (un solo archivo con todo dentro), o descarga el código con **Code > Download ZIP**.
2. Ejecuta `Eureka_Utils_Portable.exe`, o `Eureka_Utils.cmd` desde la carpeta del código, y acepta el aviso de administrador. Si Smart App Control bloquea el .exe (todavía no está firmado), usa `Eureka_Utils.cmd`.
3. Espera a que termine la detección y revisa las pestañas Hardware, Actualizaciones y Bloatware.
4. En la pestaña Equipo elige un perfil y pulsa **Revisar selección antes de aplicar** o **Aplicar perfil**.

También funciona sin interfaz, por ejemplo: `Eureka_Utils.cmd -Perfil "Oficina (Microsoft 365)" -Desatendido` o `Eureka_Utils.cmd -ActualizarTodo`.

## Documentación

La documentación completa (guía de instalación, manual de usuario, guía del USB de instalación de Windows y documentación técnica, en HTML y PDF con capturas) se distribuye en el paquete completo de Eureka_Utils. En este repositorio:

- [`FIRMA-DE-CODIGO.md`](FIRMA-DE-CODIGO.md): firma gratuita de los ejecutables con SignPath Foundation.
- [`Packages/LEEME.txt`](Packages/LEEME.txt): cómo añadir instaladores propios o sin conexión.
- `Build/Build-Exe.ps1`: genera `Eureka_Utils.exe` y `Eureka_Utils_Portable.exe`.

## Aviso

Esta herramienta modifica el equipo (software, ajustes, cuentas, dominio). Toda acción que lo cambia pide confirmación y se puede crear un punto de restauración antes de aplicar cambios. Revisa el perfil y la selección antes de ejecutarlo en equipos de producción.

## Autor

Juan Raúl Ruiz · [LinkedIn](https://www.linkedin.com/in/juanraulruizbartran)

## Política de firma de código (Code signing policy)

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).

Firma de código gratuita proporcionada por SignPath.io, certificado de SignPath Foundation.

- Los ejecutables publicados en *Releases* se compilan y firman automáticamente en **GitHub Actions** (`.github/workflows/release.yml`) a partir del código de este repositorio; nunca se firman binarios compilados fuera de ese proceso.
- **Equipo y funciones**
  - Autores (*committers*) y revisores (*reviewers*): [juanraul86](https://github.com/juanraul86)
  - Aprobadores de la firma (*approvers*): [juanraul86](https://github.com/juanraul86)
- Cada solicitud de firma la aprueba manualmente un aprobador. Las cuentas del equipo usan autenticación multifactor.
- Las versiones publicadas antes de activar la firma se indican como "sin firmar" en sus notas.

## Privacidad

Este programa no transfiere ninguna información a otros sistemas en red salvo que lo solicite expresamente el usuario o la persona que lo instala o lo utiliza. Las conexiones que realiza son las que el usuario lanza desde la interfaz: winget y Microsoft Store (instalar y actualizar software), los servicios de inicio de sesión de Microsoft (comprobar una cuenta profesional que el usuario escribe), la descarga de Microsoft Safety Scanner y las páginas web de descarga que el usuario abre. No incluye telemetría.

*This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.*

## Licencia

[MIT](LICENSE)

