# Método VEEX EXTERNAL

Receta completa para levantar un external sobre 3105. Todo lo que costó tiempo está aquí.

## Base

- 3105 (YangJiiii, GPLv3) es externo por diseño: usa el bundle falso `com.apple.mobile.MobileHouseArrest` y MHA-C2 para entrar a contenedores. No inyecta nada en la app objetivo, por eso el anti-cheat no ve un tweak.
- El motor NO se toca. Solo se reemplaza la vista raíz y el nombre visible.
- El bundle ID se queda `com.apple.mobile.MobileHouseArrest`. Cambiarlo rompe el acceso.
- Nombre visible: `Info.plist` (`CFBundleDisplayName`) y `INFOPLIST_KEY_CFBundleDisplayName` en `project.pbxproj`, en Debug y Release.

## Compilación

- Workflow en `.github/workflows/build.yml`, `macos-latest`, `xcodebuild` sobre el esquema real del proyecto (en esta versión `3105`), archive y export sin firmar.
- Los `.3105` se copian al bundle con patrón `*.3105`, a la raíz del bundle y entre comillas (hay nombres con espacio).
- Firma e instalación con GBox.
- El `.ipa` está dentro del zip del artifact.

## Licencia

- Gate con HMAC-SHA256 sobre payload de 7 bytes: días de vencimiento, flags y etiqueta de dispositivo.
- Comparación de firma en tiempo constante; los 5 primeros bytes.
- Clave secreta fija en el código.
- Persistencia en `UserDefaults`; al abrir se revalida sola.
- Maestras ilimitadas y multidispositivo, hardcodeadas. No se reparten.
- `silent` en la revalidación para no mostrar mensaje al arrancar.

## Regla crítica de parches

- `PatchProjectLibrary.overlappingTargetPath` rechaza dos parches con la misma ruta destino **aunque ninguno esté aplicado**.
- Por eso los grupos que comparten archivo son exclusivos: al apagar uno se restaura con `latestReceipt` → `inspectRestore` → `restore(allowChangedTargets: true)` y **después se borra de la biblioteca** con `PatchProjectLibrary.delete`.
- Solo entonces se importa el siguiente. Los grupos que no comparten ruta se quedan instalados y conviven.
- `targetOccupied` se resuelve liberando y reintentando. `privateOperationFailed` es paquete privado sin copia de autor: se arregla con `markAsAuthorCopy`.

## Import

- `importPackage(data:password:)` devuelve `Bool` y corre en tarea aparte.
- Esperar a que baje `isBusy` **antes** de importar, comparar IDs antes y después para identificar el proyecto nuevo, reintentar hasta 4 veces y cachear el UUID por fila en `UserDefaults`.
- `findItem`: primero el UUID cacheado, luego coincidencia exacta normalizada. El prefijo es solo respaldo y descarta los nombres reservados por otras filas (esto evita que `aim_drag` caiga en `aim_drag_antena`).

## Apply y restore

- `synchronizeWorkspace(item:)` si el esquema es 2 o más y `canInspectContents`; si no, el proyecto base.
- `DevicePatchService.apply(project:)`, `latestReceipt(projectID:)`, `inspectRestore`, `restore(allowChangedTargets:)`.
- Todo lo pesado en `Task.detached`.
- Con la app objetivo abierta el restore falla y el borrado no procede. Cerrarla siempre.

## Icono

- 1024x1024 exactos, PNG sin alpha, esquinas negras.
- `Assets.xcassets/AppIcon.appiconset/Contents.json` debe apuntar al archivo real.

## Anti-baneo

- Misma resolución y mismo formato que el original. Nunca cambiar tamaño ni compresión.
- Sustituir solo la textura, sin tocar la estructura del bundle ni agregar archivos.
- Probar en entrenamiento o custom, nunca ranked el mismo día.
- Restore Originals antes de cada actualización de la app objetivo.
- No mezclar con aimbot durante pruebas.
- El cubemap de cielo es lo más delicado: seis caras y orientación.

## Atribución

Si se distribuye, es GPLv3: publicar el código y acreditar a YangJiiii.
