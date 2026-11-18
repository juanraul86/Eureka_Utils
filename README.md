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

## Generar los ejecutables

```powershell
powershell -ExecutionPolicy Bypass -File Build\Build-Exe.ps1 [-CertificateThumbprint <huella>]
```

Requisitos: Windows 11 (o Windows 10 22H2), Windows PowerShell 5.1 y .NET Framework 4.8, incluidos en Windows. No necesita instalar nada más.
