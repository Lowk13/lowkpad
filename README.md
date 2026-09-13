# LowkPad

Usar el iPhone como ratón del PC. App de iOS + un programa pequeño que corre en Windows.

Esta versión es un **banco de pruebas**: sirve para decidir, probándolo en el sofá y en la
cama, cuál de las formas de hacer clic es la buena. Casi todo se ajusta desde el propio móvil
a propósito, para no tener que recompilar por cada cambio de un número.

## Por qué existe

Las apps de este tipo que hay por ahí van por TCP, que retransmite los paquetes perdidos y
provoca tirones; no dejan configurar la aceleración por separado de la velocidad; y para hacer
clic te obligan a levantar el dedo o a darle a un botón en la pantalla. Aquí:

- **UDP con estado acumulado.** Cada paquete lleva el total recorrido, no el incremento. Si uno
  se pierde, el siguiente ya trae la cuenta correcta: el hueco se cierra solo, sin retransmitir
  y sin saltos. Probado tirando el 60 % de los paquetes a propósito: el cursor acaba exactamente
  en el mismo sitio.
- **El tráfico va marcado como voz interactiva**, así el Wi-Fi lo mete en su cola prioritaria.
- **Un latido constante** impide que la radio del iPhone entre en ahorro de energía, que es lo
  que hace que el primer movimiento tras una pausa llegue tarde.
- **Velocidad y aceleración independientes**: `salida = entrada × ganancia × f(velocidad)`, con
  `f = 1` cuando la aceleración está apagada. Apagarla no te cambia la sensibilidad base.
- **El PC mantiene su propia posición del cursor y la escribe en absoluto**, para saltarse la
  curva de «precisión mejorada del puntero» de Windows, que si no descuadra todos los ajustes.

## Cómo hacer clic

Pensado para usarlo **a una mano** (tumbado, en el sofá) y **sin mirar el móvil**, con la vista
puesta en el monitor. De ahí que todo lleve vibración: es la única forma de saber que has hecho
clic sin mirar.

| Método | Para qué agarre |
|---|---|
| **Golpecito en la trasera** (acelerómetro) | Una mano. El pulgar apunta y no se levanta; el índice golpea por detrás. |
| **Segundo dedo** | Dos manos. Toque = clic; dedo apoyado = botón pulsado, para arrastrar sin levantar nada. |
| **Tocar / tap y medio** | Cualquiera. El clásico. |
| **Barra inferior** | Dos manos. |
| **Presión por huella** | Experimento. En Safari este dato venía fijo; aquí se lee de otra fuente. |

## Instalar

1. En el PC: abrir `lowkpad-host.exe` (servidor Rust, UDP 8788).
2. Descargar `LowkPad.ipa` de la
   [última compilación](../../releases/tag/ultima) **desde el propio iPhone**.
3. Abrirlo con **LiveContainer**.
4. En la app, «ajustes» → poner la IP del PC.

## Compilar

Se compila solo en GitHub Actions (runner de macOS). Al ser un repositorio público, esos
runners son gratis y sin límite de minutos. Se lanza a mano desde la pestaña **Actions** →
*Compilar LowkPad* → *Run workflow*, o simplemente subiendo un cambio.

No se firma nada: LiveContainer no lo necesita.

## Qué falta

El emparejado por QR, el cifrado de extremo a extremo y los accesos directos/scripts.


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
