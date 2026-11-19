# Política de seguridad / Security policy

## Versiones con soporte

Solo la última versión publicada en [Releases](https://github.com/juanraul86/Eureka_Utils/releases/latest) recibe correcciones de seguridad.

## Cómo informar de una vulnerabilidad

**No abras un issue público.** Usa el aviso privado de GitHub: pestaña **Security** del repositorio › **Report a vulnerability**.

Incluye la versión afectada, los pasos para reproducirlo y su posible impacto (por ejemplo, ejecución de código como administrador o filtración de datos del equipo). Recibirás respuesta lo antes posible, y la corrección se publicará en una versión nueva con una nota en sus novedades.

## Comprobar que un ejecutable es auténtico

Cada release incluye la huella SHA-256 de sus ejecutables. Compruébala en PowerShell:

```powershell
Get-FileHash .\Eureka_Utils_Portable.exe -Algorithm SHA256
```

Si no coincide con la publicada, no lo ejecutes.

---

*English: please do not open public issues for security problems. Use GitHub's private vulnerability reporting (Security › Report a vulnerability). Only the latest release is supported. Verify downloads against the SHA-256 published in each release.*
