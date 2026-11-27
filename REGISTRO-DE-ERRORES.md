# Registro de errores de Eureka_Utils

Cada error corregido se documenta con todo detalle:

- **Qué pasaba:** lo que veía el usuario, con el mensaje exacto.
- **Por qué:** la causa real, hasta la línea de código.
- **Versiones afectadas.**
- **Cómo se ha solucionado.**
- **Cómo se evita que vuelva a pasar:** pruebas y salvaguardas.
- **Qué hacer si te ha pasado.**

Las novedades de cada versión están en [CHANGELOG.md](CHANGELOG.md).

---

## E-001 · Todos los botones fallan: «El término 'Get-CfgDevices' no se reconoce…» (permisos perdidos)

| | |
|---|---|
| Gravedad | **Crítica**: la aplicación se abre, pero ningún botón funciona |
| Versiones afectadas | 2.3.0 y anteriores que incluyen la protección de la carpeta |
| Corregido en | 2.4.0 |
| Detectado | 27/11/2026, en el equipo del autor |

### Qué pasaba

- La ventana se abría con normalidad y mostraba los datos del equipo.
- Al pulsar **cualquier botón que lanza una tarea** (Listar todo el hardware, Analizar el sistema, Buscar actualizaciones…), la barra de estado mostraba:

  > El término 'Get-CfgDevices' no se reconoce como nombre de un cmdlet, función, archivo de script o programa ejecutable. […]

  El nombre de la función cambia según el botón (Get-CfgSystemHealth, Get-CfgSecurityStatus…).
- A partir de ese momento ya no se podía:
  - Volver a abrir Eureka_Utils.
  - Leer sus archivos, ni siquiera como administrador: «Acceso denegado».
  - Usar git en la carpeta, porque `.git` también quedaba bloqueado.

### Cómo se llegaba a ese estado

1. **Siempre había un aviso de seguridad al abrir Eureka_Utils** como administrador: «Por seguridad: la carpeta de Eureka_Utils la pueden modificar usuarios sin permisos de administrador… ¿Proteger la carpeta ahora?». Ese aviso era un falso positivo (ver [E-002](#e-002--aviso-de-carpeta-insegura-en-cada-arranque-falso-positivo)).
2. Al responder **Sí**, se ejecutaba `Protect-CfgFolder` (Modules/Core.psm1) y dejaba sin permisos todos los archivos de la carpeta.
3. La ventana principal seguía funcionando porque ya tenía los módulos cargados en memoria.
4. Pero **cada botón ejecuta su tarea en un proceso aparte (runspace)** que vuelve a cargar los módulos desde el disco, para que la ventana no se congele. Sin permiso de lectura, los módulos no se cargaban y la primera función de la tarea «no se reconocía».

Lo mismo pasaba sin preguntar en los equipos instalados con un USB creado por Eureka_Utils ([E-003](#e-003--el-usb-de-instalación-dejaba-ceureka_utils-sin-permisos-en-el-equipo-nuevo)).

### Por qué

La función ejecutaba un único `icacls` sobre toda la carpeta, con `/T` (recursivo):

```
icacls <carpeta> /inheritance:r /grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX /T /C /Q
```

Con `/T`, icacls aplica **las dos operaciones a cada archivo, una detrás de otra**:

1. `/inheritance:r` **quita los permisos heredados** del archivo. En un archivo normal son todos sus permisos.
2. `/grant:r … (OI)(CI)…` intenta dar los permisos nuevos con los indicadores de herencia `(OI)` (objetos) y `(CI)` (contenedores). **Esos indicadores solo son válidos en carpetas**: en un archivo la operación falla.
3. Con `/C` icacls sigue adelante a pesar del fallo, y el archivo queda **con la lista de permisos vacía**. Nadie puede leerlo: ni el usuario, ni los administradores, ni SYSTEM. Solo el propietario puede volver a cambiar sus permisos.

En las carpetas sí funcionaba. Por eso las carpetas parecían correctas: SYSTEM, Administradores y Usuarios tenían sus permisos, pero los archivos de dentro estaban vacíos.

### Cómo se ha solucionado

`Protect-CfgFolder` hace ahora el trabajo en dos pasos, y cada paso solo usa lo que es válido para su destino:

1. **Solo la carpeta raíz, sin `/T`.** Se le quita la herencia y se le dan los permisos con `(OI)(CI)`: Administradores y SYSTEM, control total; Usuarios, leer y ejecutar.
2. **Todo lo de dentro: `icacls <carpeta>\* /reset /T`.** Subcarpetas y archivos vuelven a heredar los permisos de la raíz y pierden cualquier permiso explícito que diera escritura a otros.

### Cómo se evita que vuelva a pasar

- **Copia y marcha atrás.** Antes de tocar nada se guardan los permisos actuales (`icacls /save`). Si al terminar algún archivo de código no se puede leer, se restauran (`icacls /restore`) y la función informa del fallo. Eureka_Utils nunca se deja sin poder leer su propio código.
- **Autorreparación al arrancar, en los tres lanzadores:**
  - `Eureka_Utils.ps1`, antes de cargar los módulos: si alguno no se puede leer, ejecuta `icacls <carpeta>\* /reset /T` y lo deja en el registro («Permisos reparados…»).
  - `Eureka_Utils.cmd`, antes de lanzar el script: si `Eureka_Utils.ps1` no se puede leer, hace lo mismo.
  - `Eureka_Utils.exe`, antes de comprobar la integridad: si el script o los módulos no se pueden leer, hace lo mismo.
- **Mensaje claro en lugar del error críptico.** Antes de lanzar cada tarea se comprueba que se pueden leer los módulos. Si no, se explica qué pasa y el comando exacto para repararlo.
- **Pruebas automáticas** en `Tests/Run-Tests.ps1`, que GitHub Actions ejecuta antes de cada publicación:
  - *Ningún icacls con /T usa (OI)(CI)*: revisa todo el código y falla si alguna llamada a icacls vuelve a mezclarlos.
  - *Proteger la carpeta deja todo el código legible y heredando de la carpeta*: protege una carpeta temporal real y comprueba los permisos de cada archivo.
  - *Autorreparación*: deja un archivo sin permisos, como hacía el fallo, y comprueba que el comando de reparación lo recupera.

### Qué hacer si te ha pasado

- **Con la 2.4.0 o posterior:** abre Eureka_Utils con `Eureka_Utils.cmd` (pide permisos de administrador) y se repara solo.
- **A mano:** abre PowerShell **como administrador** y ejecuta, con la ruta de tu carpeta:

  ```powershell
  icacls "C:\ruta\a\Eureka_Utils\*" /reset /T /C
  ```

  Si algún archivo sigue sin poder leerse porque lo creó otro usuario, toma posesión antes:

  ```powershell
  takeown /F "C:\ruta\a\Eureka_Utils" /R /D S    # en Windows en inglés: /D Y
  icacls "C:\ruta\a\Eureka_Utils\*" /reset /T /C
  ```

---

## E-002 · Aviso de «carpeta insegura» en cada arranque (falso positivo)

| | |
|---|---|
| Gravedad | Alta: llevaba a pulsar «Proteger la carpeta» y provocar [E-001](#e-001--todos-los-botones-fallan-el-término-get-cfgdevices-no-se-reconoce-permisos-perdidos) |
| Versiones afectadas | 2.3.0 y anteriores |
| Corregido en | 2.4.0 |

### Qué pasaba

- Al abrir Eureka_Utils como administrador, aparecía casi siempre: «Por seguridad: la carpeta de Eureka_Utils la pueden modificar usuarios sin permisos de administrador (BUILTIN\Usuarios)…». Pasaba incluso cuando los usuarios solo podían leer.
- Después de proteger la carpeta, el registro decía igualmente «No se pudieron ajustar los permisos», y el aviso volvía en el siguiente arranque.

### Por qué

`Test-CfgFolderSecurity` (Modules/Core.psm1) buscaba permisos de escritura con esta máscara de bits:

```
'Write, Modify, FullControl, CreateFiles, AppendData, WriteData, ChangePermissions, TakeOwnership, Delete'
```

`FullControl` y `Modify` son **combinaciones que incluyen también los bits de lectura y ejecución**. Al hacer `permisos -band máscara`, el permiso «Leer y ejecutar» de Usuarios coincidía con esos bits de lectura. Cualquier carpeta que los usuarios pudieran leer se marcaba como insegura, es decir, todas.

### Cómo se ha solucionado

La máscara contiene ahora **solo los bits que permiten escribir**:

- Escribir datos o crear archivos (0x2) y anexar datos (0x4).
- Escribir atributos extendidos (0x10) y escribir atributos (0x100).
- Eliminar subcarpetas y archivos (0x40) y eliminar (0x10000).
- Cambiar permisos (0x40000) y tomar posesión (0x80000).
- Los genéricos GENERIC_ALL (0x10000000) y GENERIC_WRITE (0x40000000), que aparecen en los permisos heredables.

Los permisos se comparan como enteros de 32 bits sin signo.

### Cómo se evita que vuelva a pasar

Prueba *Seguridad de carpeta: la lectura de Usuarios no cuenta como riesgo, la escritura sí*. Comprueba que una carpeta con Usuarios en lectura no da aviso y que, al darles «Modificar», sí lo da.

---

## E-003 · El USB de instalación dejaba C:\Eureka_Utils sin permisos en el equipo nuevo

| | |
|---|---|
| Gravedad | **Crítica** en equipos instalados con un USB creado por Eureka_Utils |
| Versiones afectadas | 2.3.0 y anteriores |
| Corregido en | 2.4.0 (hay que volver a crear el USB o el `autounattend.xml`) |

### Qué pasaba

En los equipos instalados con un USB de Eureka_Utils (pestaña Instalar Windows), la configuración posterior a la instalación no funcionaba: ningún botón de Eureka_Utils funcionaba en el equipo nuevo, con el mismo error que [E-001](#e-001--todos-los-botones-fallan-el-término-get-cfgdevices-no-se-reconoce-permisos-perdidos).

### Por qué

`New-CfgAutounattend` (Modules/Media.psm1) escribe en el `autounattend.xml` una orden que Windows ejecuta como SYSTEM durante la instalación para proteger `C:\Eureka_Utils`. Era el mismo `icacls … /inheritance:r /grant:r …(OI)(CI)… /T`, con el mismo efecto sobre cada archivo.

### Cómo se ha solucionado

La orden del `autounattend.xml` hace ahora los dos pasos correctos:

```
cmd /c if exist C:\Eureka_Utils (icacls C:\Eureka_Utils /inheritance:r /grant:r …(OI)(CI)… /C /Q & icacls C:\Eureka_Utils\* /reset /T /C /Q)
```

Además, el equipo nuevo abre Eureka_Utils con `-PostInstalacion` como administrador. Si encuentra archivos sin permisos de un USB antiguo, la autorreparación de E-001 los recupera.

### Cómo se evita que vuelva a pasar

La prueba *Ningún icacls con /T usa (OI)(CI)* revisa también esta orden: analiza por separado cada llamada a icacls de una misma línea.

---

## E-004 · «Volumen marcado para revisión» daba AVISO con el disco en perfecto estado

| | |
|---|---|
| Gravedad | Baja: falso aviso |
| Versiones afectadas | 2.3.0 y anteriores, en Windows en español actual |
| Corregido en | 2.4.0 |

### Qué pasaba

Diagnóstico › Estado del sistema operativo mostraba: «AVISO · Volumen marcado para revisión — El volumen - C: no contiene errores».

### Por qué

El resultado de `fsutil dirty query` se interpretaba buscando el texto `NOT Dirty|no est`. Las versiones antiguas de Windows en español decían «no está sucio», pero **Windows 11 actual dice «no contiene errores»**, que no coincidía. Cualquier texto que no coincidiera se trataba como disco marcado.

### Cómo se ha solucionado

La nueva función `Test-CfgVolumeDirtyText` (Modules/Diagnostics.psm1):

- Reconoce primero las formas de decir «limpio» en varios idiomas: «NOT Dirty», «no está», «no contiene», «n'est pas», «não está».
- Después, las de «marcado»: «is Dirty», «sucio», «contiene errores», «est sale».
- **Ante la duda no avisa.**

### Cómo se evita que vuelva a pasar

Prueba *fsutil: "no contiene errores" no es un aviso*, con los textos en español actual, español antiguo e inglés, limpios y marcados.

---

## E-005 · En inglés, «WARNING» se montaba sobre el texto de las comprobaciones

| | |
|---|---|
| Gravedad | Cosmética |
| Versiones afectadas | 2.3.0 y anteriores |
| Corregido en | 2.4.0 |

### Qué pasaba

En las listas de comprobaciones en inglés, «WARNING» invadía el nombre de la comprobación («WARNINGDevices with problems»).

### Por qué

La columna del resultado en la plantilla `CheckTemplate` (UI/MainWindow.xaml) medía 62 píxeles fijos, pensados para «AVISO», «FALLO» y «OK».

### Cómo se ha solucionado

La columna mide ahora 84 píxeles, suficiente para «WARNING», «CRITICAL» y las traducciones más largas. Se ha comprobado con capturas en español e inglés.

---

## E-006 · «Exportar lista (CSV)» podía provocar un error sin controlar

| | |
|---|---|
| Gravedad | Media: el botón fallaba sin explicación y podía cerrar la ventana |
| Versiones afectadas | 2.2.0 a 2.3.0 |
| Corregido en | 2.4.0 |
| Detectado | 27/11/2026, en la prueba que pulsa todos los botones de la interfaz |

### Qué pasaba

En Drivers y BIOS › **Exportar lista (CSV)**, si la carpeta `Exports` no se podía escribir, el botón lanzaba una excepción sin controlar: «Acceso denegado a la ruta de acceso '…\Exports\Hardware_….csv'». Pasaba, por ejemplo, con Eureka_Utils abierto sin elevar o con la carpeta dañada por [E-001](#e-001--todos-los-botones-fallan-el-término-get-cfgdevices-no-se-reconoce-permisos-perdidos). No quedaba nada en el registro y el usuario no sabía qué había pasado.

### Por qué

A diferencia de las tareas en segundo plano, que capturan sus errores, este botón escribe el archivo directamente en el manejador del clic con `Export-Csv`, sin `try/catch`. En WPF, una excepción sin controlar en un manejador puede cerrar la aplicación.

### Cómo se ha solucionado

- La exportación va dentro de `try/catch`. Si falla, se registra en ERROR con la ruta y el motivo, y se muestra un mensaje que explica qué hacer: revisar los permisos de `Exports` o abrir Eureka_Utils como administrador.
- **Red de seguridad general:** `Show-CfgGui` registra un manejador de `Dispatcher.UnhandledException`. Cualquier error inesperado en cualquier botón se registra en ERROR, se muestra en la barra de estado («Error inesperado: … Detalle en la pestaña Registro») y **no cierra Eureka_Utils**.

### Cómo se evita que vuelva a pasar

La prueba que pulsa los botones de la interfaz real registra como fallo cualquier excepción de un botón. Con este cambio, pasa.

---

## E-007 · «Informe de batería» daba ERROR en los equipos de sobremesa

| | |
|---|---|
| Gravedad | Baja: falso error |
| Versiones afectadas | 2.3.0 y anteriores |
| Corregido en | 2.4.0 |
| Detectado | 27/11/2026, en la prueba que pulsa todos los botones de la interfaz |

### Qué pasaba

En un PC sin batería, el botón **Informe de batería** (pestaña Equipo) terminaba con «[ERROR] No se pudo generar el informe de batería.» y «1 acción(es) con error».

### Por qué

`New-CfgBatteryReport` (Modules/Hardware.psm1) ejecutaba `powercfg /batteryreport` sin comprobar si el equipo tiene batería. En un sobremesa powercfg no genera el archivo y eso se trataba como un fallo.

### Cómo se ha solucionado

- Antes de nada se consulta `Win32_Battery`. Sin batería, se registra como información («Este equipo no tiene batería…») y la acción termina correctamente.
- La barra de estado muestra «Este equipo no tiene batería.».
- Solo se intenta abrir el informe si el archivo existe.

---

## E-008 · Al terminar cualquier tarea se reactivaban todos los botones, también los que debían seguir desactivados

| | |
|---|---|
| Gravedad | Media: permitía pulsar acciones que no proceden |
| Versiones afectadas | 2.3.0 y anteriores |
| Corregido en | 2.4.0 |
| Detectado | 27/11/2026, al probar las tareas en paralelo pulsando todos los botones |

### Qué pasaba

Algunos botones se desactivan a propósito cuando no tienen sentido:
- **Convertir el disco a GPT**, cuando el disco ya es GPT.
- **Garantía**, cuando el fabricante no tiene web de garantía (PC montado).
- **Descargar y verificar**, cuando la versión nueva no tiene ejecutable.

Al terminar **cualquier** tarea, por ejemplo «Comprobar BIOS y requisitos», esos botones volvían a quedar activos. Se podía pulsar «Convertir el disco a GPT» con el disco ya en GPT. MBR2GPT lo rechaza, así que no había daño, pero no debería ofrecerse.

### Por qué

Con una sola tarea a la vez, `Set-CfgBusy` desactivaba una lista fija de unos 60 botones (`$script:TaskButtons`) al empezar una tarea y, al terminar, los ponía **todos** con `IsEnabled = $true`. No recordaba qué estado tenía cada uno, así que deshacía las desactivaciones de la propia aplicación.

### Cómo se ha solucionado

Con el nuevo modelo de tareas en paralelo:
- Ya no se desactiva la lista completa, solo **el botón que lanzó la tarea**.
- Antes de desactivarlo se guarda su estado (`ButtonWasEnabled`) y, al terminar la tarea, **recupera exactamente ese estado**, siempre que no haya otra tarea del mismo botón en marcha.
- La lista `$script:TaskButtons` y `Set-CfgBusy` se han eliminado.

### Cómo se evita que vuelva a pasar

La prueba que pulsa todos los botones de la interfaz real detecta el estado de cada botón: con el disco en GPT, «Convertir el disco a GPT» aparece como desactivado después de comprobar la BIOS.
