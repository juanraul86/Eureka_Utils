**Eureka_Utils** es una utilidad portable para configurar, auditar y diagnosticar equipos Windows 11, de uso personal y profesional.

### Descargas
- **Eureka_Utils_Portable.exe**: un solo archivo con todo dentro. Llévalo a cualquier equipo y ejecútalo (pide permisos de administrador).
- **Eureka_Utils.exe**: lanzador para usar junto al código del repositorio (descarga el código con *Code > Download ZIP*).

### Novedades de la 2.2.1
- **Identificación del equipo** en la pestaña Hardware y en el informe: nombre comercial, número de serie, SKU y UUID; en Lenovo, Machine Type (MT) y modelo (MTM); en Dell, Service Tag y Express Service Code; en HP, número de producto. Botones para copiar los datos y abrir la garantía del fabricante.

### Novedades de la 2.2
- **Consumo real de RAM**: la pestaña Software calcula la memoria con lo que ya está en ejecución más lo que vas a instalar, y la pestaña Hardware muestra qué programas usan más memoria.
- Nueva pestaña **Drivers y BIOS**: todo el hardware con su controlador, controladores y firmware desde Windows Update, instalación desde carpeta, copia de seguridad de controladores y herramientas oficiales de Dell, HP, Lenovo e Intel.
- **BIOS**: versión y antigüedad, enlace al soporte del fabricante y preparación segura de la actualización.
- **TPM 2.0, UEFI y arranque seguro** para juegos con antitrampas: comprobación, MBR → GPT, reinicio en la BIOS e instrucciones por fabricante.
- **Seguridad**: integridad SHA-256 de los scripts, protección de la carpeta, verificación de instaladores locales, acciones de GitHub fijadas por commit y huellas SHA-256 en cada release. Botón para borrar registros e informes.

### Funciones principales
- Catálogo de software con **dependencias** e **impacto en recursos**, y perfiles: oficina, oficina IT (sistemas, soporte y ciberseguridad), gaming, gaming + streaming, creativo, desarrollo, estudiante y equipos básicos.
- **Actualizaciones winget verificadas**: si una app no se actualiza, se avisa y se ofrece su enlace de descarga manual.
- Detección de **hardware y tarjeta gráfica** (NVIDIA / AMD / Intel) con recomendaciones de controladores.
- Bloatware (quitar y reinstalar), ajustes de Windows, cuentas con **verificación en dos pasos**, dominio AD, Entra ID, Intune y Autopilot.
- **Diagnóstico** del sistema, **antivirus y malware** (Defender, análisis sin conexión, Microsoft Safety Scanner portátil) y acceso a las **consolas MMC**.
- **USB de instalación** de Windows 11+ que deja el equipo configurado automáticamente.
- Interfaz en **español, English, Français, Português, Euskara, Català, Valencià y Galego**, en modo claro u oscuro.

### Firma digital
Si los ejecutables de esta versión no están firmados, Windows puede bloquearlos (Smart App Control) o mostrar un aviso de SmartScreen. En ese caso usa `Eureka_Utils.cmd` del código fuente. Las versiones firmadas lo indican en la política de firma del README.
