# Cómo colaborar con Eureka_Utils

¡Gracias por tu interés! Toda ayuda cuenta: avisar de un fallo, proponer una mejora, traducir o enviar código.

*English: bug reports, ideas and pull requests are welcome in English or Spanish. The steps below apply in either language.*

## Informar de un error

1. Comprueba en [Issues](https://github.com/juanraul86/Eureka_Utils/issues) que no esté ya publicado.
2. Abre uno nuevo con la plantilla **Informe de error** e incluye:
   - La versión de Eureka_Utils (título de la ventana) y de Windows.
   - Qué hiciste, qué esperabas y qué pasó.
   - Las líneas relevantes del registro (pestaña **Registro** o carpeta `Logs`).
3. **Antes de pegar el registro, revísalo:** puede contener el nombre del equipo, usuarios y software instalado. Borra o sustituye lo que no quieras publicar.

¿Es un problema de seguridad? No lo publiques: sigue [SECURITY.md](SECURITY.md).

## Proponer una mejora

Abre un issue con la plantilla **Propuesta de mejora**: cuenta qué problema resuelve y para quién (hogar, oficina, IT, gaming...).

## Añadir software al catálogo

Las aplicaciones están en `Catalog/software.json`. Cada una indica su identificador de winget, cómo detectarla, sus dependencias y su impacto (disco, RAM, CPU, servicios). Copia una entrada parecida, comprueba el identificador con `winget show --id <Id> --exact` y ejecuta las pruebas.

## Traducciones

Los textos están en `Lang/*.tsv`, separados por `|` con las columnas `es|en|fr|pt|eu|ca|ca-valencia|gl`. Si una columna queda vacía se muestra el español; el valenciano usa el catalán si no tiene texto propio. Conserva los marcadores `{0}`, `{1}`...

## Enviar código

1. Haz un *fork*, crea una rama y haz tus cambios.
2. Respeta el estilo del proyecto:
   - Windows PowerShell 5.1, sin dependencias externas.
   - Los `.ps1` y `.psm1` con tildes se guardan en **UTF-8 con BOM**; `Eureka_Utils.cmd` en ASCII con finales CRLF.
   - Programas de Windows siempre con su ruta completa de System32.
   - Toda acción que modifica el equipo pide confirmación.
   - Los textos nuevos de la interfaz, traducidos en `Lang/`.
3. Ejecuta las pruebas (no cambian nada del equipo):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run-Tests.ps1
   ```

4. Abre un *pull request* explicando qué cambia y cómo lo has probado. Las pruebas se ejecutan también en GitHub Actions.

## Licencia

Al colaborar aceptas que tu aportación se publique bajo la [licencia MIT](LICENSE) del proyecto.
