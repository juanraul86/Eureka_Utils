# Eureka_Utils · Configurador de equipos

Herramienta portable para preparar equipos Windows 11 de uso personal y profesional. Detecta el hardware (incluida la tarjeta gráfica NVIDIA/AMD/Intel), quita bloatware, instala software explicando sus dependencias y su consumo de recursos, mantiene todo actualizado con winget, aplica ajustes, configura cuentas (con verificación en dos pasos), une el equipo a Active Directory o a Microsoft Entra ID, sincroniza con Intune y crea USB de instalación de Windows 11 que dejan el equipo configurado sin intervención.

**Versión 2.0 · noviembre de 2026**

## Características

- **Hardware**: detección de CPU, RAM, discos, red y GPU, con recomendaciones y comprobación de compatibilidad con Windows 11 (TPM 2.0, UEFI, arranque seguro).
- **Software**: catálogo estilo Centro de software con dependencias, requisitos e impacto en disco y RAM antes de instalar.
- **Actualizaciones**: `winget upgrade` al abrir, con opción de actualizar todo o solo lo seleccionado.
- **Bloatware**: retirada de apps preinstaladas con indicación del riesgo (bajo, medio, alto) y posibilidad de reinstalarlas.
- **Ajustes de Windows**: energía, gaming, explorador, privacidad, seguridad y administración.
- **Perfiles**: Personal, Oficina (Microsoft 365), Oficina IT, Gaming, Gaming + Streaming, Creativo, Desarrollo, Estudiante y Equipo básico.
- **Cuentas y dominio**: cuentas locales, unión a Active Directory o Entra ID (la contraseña y el MFA los gestiona Microsoft; el configurador no los guarda), sincronización con Intune, unión híbrida y exportación del hash de Autopilot.
- **USB de instalación**: formatea e instala Windows 11 y deja el equipo configurado con el perfil elegido.
- **Informe**: exportación del estado del equipo en HTML.

## Requisitos

- Windows 11 y permisos de administrador.
- Windows PowerShell 5.1 (incluido en Windows). Interfaz WPF, sin dependencias externas.
- `winget` para instalar y actualizar software.

## Inicio rápido

1. Copia la carpeta del configurador (o descomprime el .zip) en un USB, un recurso compartido o el propio equipo.
2. Haz doble clic en `Configurador.exe` o en `Configurador.cmd` y acepta el aviso de administrador. Si Smart App Control bloquea el .exe, usa el .cmd.
3. Espera a que termine la detección y revisa las pestañas Hardware, Actualizaciones y Bloatware.
4. En la pestaña Equipo elige un perfil y pulsa **Revisar selección antes de aplicar** o **Aplicar perfil**.

## Documentación

La carpeta `Docs/` incluye, en HTML y PDF:

- Guía de instalación
- Manual de usuario
- Guía del USB de instalación de Windows
- Documentación técnica

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

