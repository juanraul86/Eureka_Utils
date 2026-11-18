# Firma de código gratuita con SignPath Foundation

Guía para que los ejecutables de Eureka_Utils se publiquen **firmados digitalmente sin coste**, de forma que Windows (Smart App Control y SmartScreen) confíe en ellos.

SignPath Foundation firma gratis proyectos de **código abierto**. El certificado está a nombre de *SignPath Foundation* e indica el proyecto. La firma no se hace en tu PC: se hace en GitHub Actions, para garantizar que el ejecutable sale exactamente del código público.

## Lo que ya está preparado en el repositorio

| Requisito de SignPath | Dónde está |
|---|---|
| Repositorio público con licencia de código abierto (OSI) | `LICENSE` (MIT) |
| Compilación automática y reproducible en CI | `.github/workflows/release.yml` |
| Política de firma de código, funciones del equipo y privacidad publicadas | `README.md` (secciones *Política de firma de código* y *Privacidad*) |
| Configuración de qué se firma | `.signpath/artifact-configuration.xml` |
| Publicación sin firmar mientras no haya aprobación | El flujo solo firma si existe la variable `SIGNPATH_ORGANIZATION_ID` |

## Pasos que tienes que hacer tú

1. **Activa la autenticación multifactor en GitHub** (Settings > Password and authentication), si aún no la tienes. SignPath la exige al equipo del proyecto.
2. **Comprueba que el repositorio es público** y que hay releases publicadas (ya existen la v2.1.0, la v2.2.0 y la v2.2.1). SignPath revisa que el proyecto esté publicado y en uso.
3. **Solicita la firma gratuita** en <https://signpath.org/apply>. Datos útiles para el formulario:
   - Proyecto: **Eureka_Utils**. Repositorio: `https://github.com/juanraul86/Eureka_Utils`.
   - Descripción: *Utilidad portable de código abierto para configurar, auditar y diagnosticar equipos Windows 11 (software, actualizaciones, bloatware, diagnóstico, antivirus, dominio/Intune y USB de instalación).*
   - Licencia: MIT. Lenguaje: PowerShell y C# (lanzador). CI: GitHub Actions.
   - Artefactos a firmar: `Eureka_Utils.exe` y `Eureka_Utils_Portable.exe` (Authenticode).
4. **Espera la aprobación.** SignPath revisa el proyecto a mano (suele tardar unos días o semanas) y crea para ti una organización en SignPath.io.
5. **Configura el proyecto en SignPath.io**, siguiendo sus indicaciones:
   - Crea el proyecto con *slug* `Eureka_Utils` y conecta el repositorio de GitHub (*Trusted Build System* de GitHub).
   - En *Artifact configurations*, crea una con el contenido de `.signpath/artifact-configuration.xml` (por ejemplo, con *slug* `initial`).
   - Usa la política de firma `release-signing` que te asignen (o la que indiquen) y añade tu usuario como aprobador.
   - Crea un **API token** para un usuario de CI con permiso de enviar solicitudes en ese proyecto.
6. **Añade los datos en GitHub** (repositorio > Settings > Secrets and variables > Actions):
   - *Secret* `SIGNPATH_API_TOKEN` = el token de SignPath.
   - *Variables*:
     - `SIGNPATH_ORGANIZATION_ID` = el id de tu organización en SignPath (un GUID).
     - `SIGNPATH_PROJECT_SLUG` = `Eureka_Utils`
     - `SIGNPATH_SIGNING_POLICY_SLUG` = `release-signing` (o el que te asignen)
     - `SIGNPATH_ARTIFACT_CONFIGURATION_SLUG` = `initial` (o el que hayas creado)
7. **Publica una versión firmada**: crea y sube una etiqueta nueva (por ejemplo `v2.3.0`). Las etiquetas publicadas no se pueden mover ni sobrescribir (regla del repositorio), así que cada intento de firma necesita un número nuevo:

   ```powershell
   git tag -a v2.3.0 -m "Eureka_Utils 2.3.0"
   git push origin v2.3.0
   ```

   GitHub Actions compila, envía la solicitud a SignPath, espera a que la apruebes en SignPath.io (recibirás un aviso) y publica en la release los ejecutables **firmados**.

## Comprobar la firma

```powershell
Get-AuthenticodeSignature .\Eureka_Utils_Portable.exe | Format-List Status, SignerCertificate
```

`Status` debe ser `Valid` y el firmante, *SignPath Foundation*. SmartScreen puede seguir mostrando un aviso con las primeras descargas hasta que el certificado gane reputación; Smart App Control deja de bloquear los ejecutables firmados por una entidad reconocida.

## Mientras no haya firma

Las releases se publican sin firmar y el flujo lo indica en su registro. En equipos con Smart App Control, usa `Eureka_Utils.cmd` del código fuente.
