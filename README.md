# LowkPad

Usar el iPhone como ratón del PC. App de iOS + un programa pequeño que corre en Windows.

La versión **0.5.0** incorpora posiciones y tamaños para probar qué resulta más cómodo en la
mesa, el sofá o la cama. El selector ofrece **Mesa, Mano derecha y Mano izquierda**, con alturas
**Compacta, Media y Amplia** y distribución adaptada a vertical y horizontal. Las decisiones y
sus fuentes están en [Ergonomía](docs/ERGONOMIA.md); los cambios de esta versión, en las
[notas de la actualización](docs/PATCH_NOTES_0.5.0.md).

## Por qué existe

LowkPad permite ajustar por separado el movimiento, los gestos y la disposición. Utiliza UDP
para el ratón y TCP para teclado y paneles, según las necesidades de cada tipo de entrada:

- **UDP con estado acumulado.** Cada paquete lleva el total recorrido, no el incremento. Si uno
  se pierde, el siguiente informa del recorrido acumulado. Esto permite recuperar movimiento
  sin retransmitir cada muestra; no garantiza una trayectoria visual idéntica ante pérdidas.
- **El tráfico solicita prioridad de voz interactiva.** La prioridad efectiva depende de iOS,
  la red y el router; la marca no garantiza una cola Wi-Fi concreta ni menor latencia.
- **Un latido periódico** permite supervisar el enlace y mantener tráfico durante las pausas.
  No garantiza que la radio del iPhone permanezca activa ni evita toda demora al reanudar.
- **Velocidad y aceleración independientes**: `salida = entrada × ganancia × f(velocidad)`, con
  `f = 1` cuando la aceleración está apagada. Apagarla no te cambia la sensibilidad base.
- **El PC mantiene su propia posición del cursor y la escribe en absoluto**, para saltarse la
  curva de «precisión mejorada del puntero» de Windows, que si no descuadra todos los ajustes.

## Cómo hacer clic

Se puede usar con una mano o apoyado en la mesa. Los controles visibles y la respuesta háptica
complementan los gestos; la vibración se puede desactivar.

| Método | Para qué agarre |
|---|---|
| **Clic y Derecho** | Botones visibles; permiten mantener pulsado mientras se mueve el cursor. |
| **Arrastrar / Soltar** | Bloquea el clic primario para levantar y recolocar el pulgar durante un arrastre. |
| **Golpecito en la trasera** (acelerómetro) | Opción experimental a una mano. Desactivada en instalaciones nuevas; se respeta la preferencia existente. |
| **Segundo dedo** | Dos manos. Toque = clic; dedo apoyado = botón pulsado, para arrastrar sin levantar nada. |
| **Tocar / tap y medio** | Cualquiera. El clásico. |
| **Presión por huella** | Experimento desactivado: el cambio de contacto puede desplazar el cursor al pulsar. |

**Precisión** reduce temporalmente el movimiento enviado a ×0,35. No desactiva la aceleración
del host: al reducir la entrada también disminuye su velocidad estimada. La franja lateral de
scroll mide entre 44 y 64 puntos según el espacio y cambia de lado con el perfil. Se conserva
el scroll con dos dedos, sin añadir inercia. Los valores iniciales deben probarse en el iPhone.

Cambiar de postura no intercambia los botones izquierdo y derecho. El arrastre se libera al
abandonar el contexto de control, y el host conserva su protección ante una conexión perdida.

## Instalar

1. En el PC: abrir `lowkpad-host.exe` (servidor Rust, ratón UDP 8788 y paneles TCP 8787).
2. Descargar `LowkPad.ipa` de la
   [última compilación](../../releases/tag/ultima) **desde el propio iPhone**.
3. Abrirlo con **LiveContainer**.
4. En la app, «ajustes» → poner la IP del PC y la clave de enlace para los paneles.

La app 0.5.0 es compatible con el host 0.4.0. Al actualizar se conserva la misma IP y clave.

## Compilar

Se compila en GitHub Actions (runner de macOS). Se lanza a mano desde la pestaña **Actions** →
*Compilar LowkPad* → *Run workflow*, o simplemente subiendo un cambio.

No se firma nada: LiveContainer no lo necesita.

## Qué falta

El emparejado por QR, el cifrado de extremo a extremo y los atajos o scripts personalizados.


## Revisión 0.2.0 (13/09/2026)

- Reconexión sin receptores antiguos; estado y RTT protegidos entre hilos.
- Primer ping inmediato y reenvío periódico de ajustes para recuperarse de pérdidas/reinicio del host.
- Cancelar un gesto no hace clic. Scroll y segundo dedo dejan de competir durante un arrastre.
- Franja de scroll a izquierda o derecha. Los sensores se detienen al entrar en ajustes o perder foco.
- El host libera los botones tras 2 segundos sin paquetes válidos. El diagnóstico usa una sonda UDP sin tocar el ratón.
- Clics Win32 como par de eventos, sin un hilo que pueda soltar un arrastre posterior.

El host de esta revisión está en `Host/`. Compilar con `cargo build --release` desde esa carpeta.
La prueba `Tests/probar_host.py` usa UDP y una ventana de Windows para comprobar entrada real:
requiere el host abierto, Python con Tkinter y dejar el ratón quieto durante unos segundos.

Las cifras del panel son RTT de red, no latencia dedo-pantalla. La compilación no sustituye
la prueba de gestos, volumen, háptica y permisos en LiveContainer en el iPhone.
El prototipo actual todavía NO implementa el emparejado/cifrado descrito en PLAN.md.

Referencias de implementación: [muestras táctiles de UIKit](https://developer.apple.com/documentation/uikit/uievent/coalescedtouches(for:))
y [orden de eventos SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput).


## 0.3.0 — barra inferior y paneles

La barra inferior se desliza horizontalmente y reserva el área del indicador de inicio.
Multimedia, Portapapeles y Teclado abren paneles nativos. Ajustes también está en la barra.
La distribución utiliza el área segura del dispositivo, sin coordenadas propias del iPhone 13.
Los paneles tienen scroll y se ajustan al teclado mediante `keyboardLayoutGuide`.

- **Multimedia:** anterior, siguiente, play/pausa, stop, volumen +/− y silencio. Se envían las
  teclas multimedia estándar de Windows; la aplicación reproductora decide cuáles admite.
- **Portapapeles:** copiar en el PC con Ctrl+C → Recuperar del PC → Copiar al iPhone.
  Para el sentido contrario, pegar o escribir en el cuadro → Enviar y pegar en el PC. También se puede enviar solo al portapapeles sin pegar.
  Solo texto, máximo 64 KB; nunca se sincroniza automáticamente.
- **Teclado:** seleccionar el destino en el PC, escribir en el cuadro con el teclado nativo del
  iPhone y pulsar Enviar texto. Incluye Intro, Borrar, Tab, Esc y flechas. Compatible con Unicode.
- **Botones físicos de volumen:** se ha retirado por completo su captura. Funcionan normalmente en iOS.

### Conexión de los paneles

El ratón conserva UDP 8788. Los paneles usan TCP 8787 con respuesta de éxito/error y envío
secuencial. No se reintentan órdenes automáticamente: si se pierde una confirmación, se avisa
porque la orden podría haberse aplicado. No se reproduce el texto automáticamente al reconectar.

El host crea `paneles.key` junto al ejecutable. Pegar su contenido en **Ajustes → Clave de enlace**
en cada iPhone. No incluirlo en el repositorio ni en la IPA. La clave se conserva al actualizar
el host y la app guarda la copia local en UserDefaults. Las órdenes no autenticadas se rechazan.
Este canal está diseñado para la LAN de confianza: TCP usa una clave de acceso pero todavía no TLS.

### Verificación

`cargo test` comprueba las estructuras de entrada y la lista cerrada de teclas.
`Tests/probar_paneles.py` usa una ventana real de Windows, Unicode y portapapeles, y observa las
teclas multimedia mediante un hook que impide cambiar la reproducción durante la prueba.
No muestra el contenido anterior del portapapeles ni la clave de enlace.
GitHub Actions compila la IPA y ejecuta pruebas de interfaz en simuladores iPhone 13 e iPhone Air,
incluyendo el teclado desplegado; guarda resultados y capturas como artefactos.

La interacción física en LiveContainer, la háptica y el Wi-Fi requieren probar la IPA en el iPhone.


## 0.4.0 — teclado en directo y atajos

Al abrir Teclado aparece automáticamente el teclado de iOS. Cada letra, borrar e Intro se
manda inmediatamente al PC; ya no hay cuadro de composición ni botón Enviar. El móvil no guarda
el texto tecleado. La autocorrección está desactivada para no reescribir texto alrededor de un
cursor que solo conoce el PC. Si falla la conexión, se pausa el teclado y se descartan las teclas
pendientes; tocar la zona del teclado permite reconectar tras comprobar el texto del PC.

TCP 8787 permanece abierto mientras se usa. Las órdenes se confirman en orden, con TCP_NODELAY,
sin abrir una conexión por letra ni retransmitir acciones desde la app. El host admite hasta ocho
conexiones y serializa la ejecución para que dos atajos no mezclen sus modificadores.

Atajos, accesible deslizando la barra inferior, incluye **Win + Mayús + izquierda/derecha**,
Ctrl+C/X/V/A/Z/Y/S/F, Alt+Tab, Win+D, Win+flechas y atajos de pestañas Ctrl+T/W/Mayús+T/R.
Los modificadores se pulsan y liberan juntos en un lote de entrada de Windows.

Referencias: [UIKeyInput de Apple](https://developer.apple.com/documentation/uikit/uikeyinput)
y [atajos de Windows de Microsoft](https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec).
