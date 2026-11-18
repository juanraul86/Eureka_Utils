# Eureka_Utils

Utilidad **portable** para configurar, auditar y diagnosticar equipos Windows 11, de uso personal y profesional. Interfaz en **español, English, Français, Português, Euskara, Català, Valencià y Galego**, en modo claro u oscuro.

- **Hardware**: CPU, RAM, discos y **tarjeta gráfica (NVIDIA / AMD / Intel)** con su controlador; compatibilidad con Windows 11 y recomendaciones.
- **Software**: catálogo estilo *Centro de software* de SCCM (ofimática, gaming, streaming, IT: administración, soporte y ciberseguridad, desarrollo, creatividad...) con **dependencias** e **impacto en recursos**.
- **Actualizaciones**: `winget upgrade` comprobado al abrir y listo para lanzarse con un botón. Se **verifica el resultado** y, si una app no se actualiza, se avisa y se ofrece su **enlace de descarga manual**.
- **Bloatware**: detecta, quita y reinstala apps preinstaladas, indicando el riesgo de cada una.
- **Ajustes** de Windows (energía, gaming, privacidad, seguridad, administración).
- **Cuentas**: cuenta profesional de Microsoft 365 / Entra ID con **verificación en dos pasos** (MFA) y cuentas locales.
- **Dominio e Intune**: AD, Entra ID e híbrida, sincronización con Intune, Autopilot y diagnóstico MDM.
- **Diagnóstico**: estado del sistema, SFC, DISM, CHKDSK, memoria, eventos; **antivirus y malware** (Defender, análisis sin conexión, Microsoft Safety Scanner portátil para el USB) y acceso a las **consolas MMC**.
- **Perfiles**: Personal, Oficina, Oficina IT, Gaming, Gaming + Streaming, Creativo, Desarrollo, Estudiante y Equipo básico.
- **USB de instalación**: formatea e instala Windows 11+ y, en el primer inicio, Eureka_Utils aplica el perfil elegido.

## Inicio rápido

Descarga la última versión en **Releases** (`Eureka_Utils_Portable.exe`, un solo archivo) o clona el repositorio y ejecuta `Eureka_Utils.cmd`. Acepta el aviso de administrador.

```powershell
.\Eureka_Utils.cmd                                         # interfaz gráfica
.\Eureka_Utils.cmd -Perfil "Oficina (Microsoft 365)" -Desatendido
.\Eureka_Utils.cmd -ActualizarTodo                          # actualiza y verifica
.\Eureka_Utils.cmd -ListarCatalogo
```

> Los ejecutables no están firmados: con **Smart App Control** activado Windows los bloquea. Usa `Eureka_Utils.cmd` o fírmalos con `Build\Build-Exe.ps1 -CertificateThumbprint <huella>`.

## Estructura

| Carpeta | Contenido |
|---|---|
| `Modules\` | Lógica (hardware, software, actualizaciones, bloatware, ajustes, cuentas, dominio, diagnóstico, seguridad, USB, perfiles, informes) |
| `UI\` | Interfaz WPF (`MainWindow.xaml`, `Gui.ps1`) e idiomas (`I18n.ps1`) |
| `Lang\` | Traducciones (`.tsv`, una columna por idioma) |
| `Catalog\` | Catálogos editables: software, bloatware y perfiles |
| `Packages\` | Instaladores locales (Office ODT) y escáneres de rescate |
| `Build\` | Generación de `Eureka_Utils.exe` y `Eureka_Utils_Portable.exe` |
| `Docs\` | Documentación (instalación, manual, USB, técnica) con capturas |

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

## Generar los ejecutables

```powershell
powershell -ExecutionPolicy Bypass -File Build\Build-Exe.ps1 [-CertificateThumbprint <huella>]
```

Requisitos: Windows 11 (o Windows 10 22H2), Windows PowerShell 5.1 y .NET Framework 4.8, incluidos en Windows. No necesita instalar nada más.
