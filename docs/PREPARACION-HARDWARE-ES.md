# Qué preparar ahora

Inventario confirmado por el equipo el 16 de octubre de 2026. Todavía no hemos
inspeccionado ni probado físicamente estas piezas.

1. **Mesa para probar una sola columna.** Una ESP32-WROOM será la principal y la
   segunda quedará de repuesto. Deja juntos el cable USB-C de datos, multímetro,
   fuente de 5 V/4 A y adaptador de barril a terminal.
2. **Identificar los servos antes de darles corriente.** Hace falta confirmar si
   ya están los siete más un repuesto, fotografiar la etiqueta y conservar la
   ficha del proveedor. La ficha actual del FS0307 y el handoff no coinciden en
   recorrido y alimentación. La fuente disponible no está aprobada todavía para
   la variante real. El firmware compila con la salida PWM desactivada.
3. **Medir y probar a mano.** Consigue acceso a un calibre y una impresora. Empieza
   por el cupón de agujeros y la columna con manivela. Las dimensiones de cuerpo,
   eje y horn del servo deben medirse antes de imprimir el conjunto definitivo.
4. **Tornillería y acabado.** Prioriza los M3 × 8 y M3 × 12 con tuercas. Confirma
   también espuma, lija y Velcro/elástico. La longitud final de cada tornillo se
   revisa en la pieza; no fuerces un tornillo contra el fondo del plástico.
5. **Distribución eléctrica.** Las breadboards sirven para señales y conexiones
   provisionales de poca corriente. Prepara una distribución firme en placa
   perforada/terminales para la alimentación de los motores, dimensionada con el
   consumo medido. No pases la corriente de siete servos por la ESP32 ni por sus
   GPIO. Comprueba continuidad, polaridad y masa común con todo desconectado.

Si el pack contiene un electrolítico de 1000 µF/25 V, resérvalo para la entrada
de alimentación de los servos y verifica su polaridad antes de montarlo. No
sustituye a una fuente y un cableado adecuados. El pegamento CA debe quedar lejos
de guías, ejes y pines móviles; no cierres un conjunto que aún necesita ajustes.

El cable USB-A → barril de 5,5 × 2,1 mm puede esperar a la prueba portátil. No
aumenta la corriente que puede entregar el puerto o batería; hay que comprobar
también polaridad y caída de tensión bajo carga. La primera prueba se hace en
mesa con un solo servo, sin leva ni carga, tras confirmar sus límites.

**Orden de integración:** columna manual → retorno de los pines y 100 ciclos →
servo descargado y calibrado → una columna motorizada → siete columnas → BLE e
iPhone. Los criterios y pasos detallados están en [HARDWARE-BRINGUP.md](HARDWARE-BRINGUP.md)
y [la guía CAD](../cad/README.md). Ninguna prueba de software valida todavía este
montaje físico.
