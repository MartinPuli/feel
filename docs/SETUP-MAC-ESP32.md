# FEEL: preparar la ESP32 desde tu Mac

Esta guía es para vuestra **ESP32-WROOM clásica con USB-C**. No necesitas una
Raspberry Pi para este montaje. El objetivo de hoy es que el Mac reconozca la
placa, instalar el firmware y leer su estado. **Deja el servo y la fuente externa
desconectados durante estos pasos.** El firmware inicial tiene los movimientos
físicos desactivados.

## 1. Abrir Terminal y comprobar las herramientas

Pulsa **⌘ + espacio**, escribe **Terminal** y pulsa Enter. Copia una línea cada vez:

```sh
git --version
python3 --version
```

Si macOS pide instalar las herramientas de desarrollo, acepta la instalación y
vuelve a abrir Terminal al terminar. Si `python3` no existe, instala Python 3 desde
[python.org para macOS](https://www.python.org/downloads/macos/) y repite la
comprobación. No necesitas instalar Xcode completo para este primer paso del ESP32.

## 2. Clonar la rama que contiene el código

Copia este bloque en Terminal:

```sh
mkdir -p ~/Projects
cd ~/Projects
git clone --branch feel/v1-foundation https://github.com/MartinPuli/hackharvard.git feel
cd feel
```

El repositorio es privado: usa tu acceso de GitHub si te lo pide. No pegues claves
o tokens en el chat. Si aparece `Repository not found`, comprueba que estás
identificado con una cuenta con acceso. No significa necesariamente que falte el
repositorio.

Si ya tienes una carpeta `~/Projects/feel`, no vuelvas a clonar encima. Entra en
ella y comprueba primero si tienes cambios propios:

```sh
cd ~/Projects/feel
git status
git fetch origin
git switch feel/v1-foundation
git pull --ff-only
```

Si Git avisa de cambios locales o conflictos, conserva esos archivos y comparte
el mensaje; no uses `reset --hard`. En esta rama, el código de la placa está en
`firmware/` y esta guía en `docs/SETUP-MAC-ESP32.md`.

## 3. Instalar PlatformIO en una carpeta aislada

Desde `~/Projects/feel`:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install platformio==6.1.18
pio --version
```

Debería mostrar PlatformIO Core 6.1.18. En una Terminal nueva, vuelve a ejecutar
`cd ~/Projects/feel` y `source .venv/bin/activate` antes de usar `pio`.
La primera compilación descarga las dependencias y necesita internet.

## 4. Identificar el puerto de vuestra placa

Conecta **una sola ESP32** al Mac mediante el cable USB-C de datos. Ejecuta:

```sh
ls /dev/cu.*
pio device list
```

Para identificarla, compara la lista antes y después de desenchufar y volver a
conectar **solo el USB de esa placa**. El puerto que aparece pertenece a esa
conexión. Puede tener un nombre parecido a `/dev/cu.usbserial-0001` o
`/dev/cu.SLAB_USBtoUART`; no copies estos ejemplos como si fueran tu puerto real.

Si no aparece ningún puerto nuevo: prueba el cable de datos y otro puerto USB,
evita temporalmente un hub y comprueba el chip USB-serie de la placa. Algunas
variantes requieren su controlador CP210x o CH34x. Instala únicamente el del chip
identificado, desde su fabricante o la documentación de la placa; una luz de
encendido no demuestra que la comunicación USB funcione.

## 5. Compilar el firmware, todavía sin cargarlo

```sh
pio run -j 2 --project-dir firmware -e esp32
```

Busca `SUCCESS` al final. El entorno correcto para vuestras placas WROOM es
**`esp32`**. No selecciones `esp32s3` ni los entornos `compilecheck`: estos últimos
son pruebas de compilación y prohíben la instalación.

Si falla, copia el primer error y las últimas líneas. No cambies límites de pulsos
ni opciones de motores para solucionar un error de herramientas.

## 6. Cargar el programa en la ESP32

Esta operación reemplaza el programa que tenga actualmente la placa. Revisa que
sea vuestra placa de pruebas y que el servo/fuente externa sigan desconectados.
Cierra cualquier monitor serie abierto.

Primero guarda el puerto real identificado. Sustituye el texto entre comillas:

```sh
FEEL_PORT='/dev/cu.TU_PUERTO_REAL'
```

Después ejecuta:

```sh
pio run -j 2 --project-dir firmware -e esp32 --target upload --upload-port "$FEEL_PORT"
```

Espera a que finalice y muestre `SUCCESS`. Si queda intentando conectar, algunas
placas requieren mantener pulsado **BOOT** mientras empieza la conexión y
soltarlo cuando comience la escritura. Si no funciona, comparte el error exacto;
no hagas un borrado completo ni cambies eFuses.

## 7. Leer el estado de FEEL

```sh
pio device monitor --port "$FEEL_PORT" --baud 115200 --echo --eol LF
```

Si no ves el arranque, pulsa brevemente **EN/RESET**. El firmware debe mostrar
`FEEL V1 greenfield` y `SERVO OUTPUT DISABLED`. Escribe:

```text
STATUS
```

Pulsa Enter. La respuesta debe incluir `outputState=0`, que significa que la
salida física PWM está desactivada. `HELP` muestra los comandos disponibles.
**No uses ARM, B ni US para intentar mover el servo todavía.** Para salir del
monitor, pulsa **Ctrl+C**. Ciérralo antes de volver a cargar firmware.

Que el programa arranque y responda confirma esa parte de la conexión con la
placa; no demuestra que los motores, BLE con el iPhone o la mecánica funcionen.

## 8. Antes de conectar un servo

Falta confirmar si tenéis los servos y cuál es su variante exacta. Envía una foto
de su etiqueta, conector y cables. La ficha actual del FS0307 no coincide con el
recorrido de 175° supuesto por el diseño; también hay una discrepancia entre
fichas de alimentación. No conectes automáticamente vuestra fuente de 5 V a un
servo sin identificarlo.

El esquema funcional previsto para **una sola columna**, una vez verificados
voltaje y cables, es:

| Conexión | Destino previsto |
|---|---|
| Señal del servo | GPIO **32** de la ESP32, identificado por la etiqueta GPIO; no por número de posición física |
| Masa del servo | Negativo de la fuente externa y GND de la ESP32, unidos |
| Alimentación del servo | Positivo de una fuente compatible con ese modelo |
| USB de la ESP32 | Mac, para programación/serie |

Los colores del cable no son prueba de su función. Los servos no se alimentan
desde un GPIO ni desde 3V3. No conectes el positivo de la fuente de motores al
positivo USB/placa por intuición. Antes del montaje definitivo, sigue
[HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md) y [CALIBRATION.md](CALIBRATION.md).

Primero se comprueba la columna manual, luego un servo descargado con sus límites
reales, después una columna motorizada y finalmente las siete. Sigue pendiente
la validación física; el firmware no tiene sensores de posición, fuerza o atasco.

## Referencias oficiales

- [PlatformIO: instalación](https://docs.platformio.org/en/latest/core/installation/index.html)
- [PlatformIO: comando run](https://docs.platformio.org/en/latest/core/userguide/cmd_run.html)
- [PlatformIO: monitor serie](https://docs.platformio.org/en/latest/core/userguide/device/cmd_monitor.html)
- [Espressif: conexión serie de ESP32](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/get-started/establish-serial-connection.html)
- [FEETECH: FS0307](https://www.feetechrc.com/en/6v-06kg-analog-steering-gear-fs0307.html)
