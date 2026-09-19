# Ergonomía de LowkPad

Investigación y decisiones de diseño: **18 de septiembre de 2026**.

El objetivo es manejar Windows con precisión desde el iPhone y poder elegir una postura cómoda. La revisión combina documentación oficial de aplicaciones de ratón remoto, recomendaciones de Apple y estudios de interacción táctil. No identifica un diseño universalmente superior: el tamaño de la mano, el agarre y la tarea cambian lo que resulta cómodo.

## Evidencia consultada

| Fuente primaria | Hallazgo relevante | Aplicación a LowkPad |
| --- | --- | --- |
| [Apple: UI Design Dos and Don’ts](https://developer.apple.com/design/tips/) | Recomienda objetivos táctiles de al menos 44 × 44 puntos, separación, contraste y contenido adaptado a la pantalla. | Controles suficientemente grandes y distribución basada en el espacio disponible y las áreas seguras. |
| [Buschek, Hackenschmied y Alt, INTERACT 2017: Dynamic UI Adaptations for One-Handed Use of Large Mobile Touchscreen Devices](https://www.medien.ifi.lmu.de/pubdb/publications/pub/buschek2017interact/buschek2017interact.pdf) | En un estudio de laboratorio con 35 participantes y dos teléfonos, acercar controles a la mano mejoró el alcance y redujo movimientos del dispositivo. Las personas percibieron mayor comodidad. Cambiar de distribución también tiene un coste de activación. | Perfiles elegidos explícitamente, estables durante el uso y recordados entre sesiones. No mover los controles automáticamente mientras se apunta. |
| [Bergstrom-Lehtovirta y Oulasvirta, CHI 2014: Modeling the Functional Area of the Thumb on Mobile Touchscreen Surfaces](https://www.netlab.tkk.fi/~oulasvir/pubs/paper2117.pdf) | El alcance del pulgar depende de la superficie, la mano y el agarre. | Ofrecer varias posiciones y alturas, sin tratar una única geometría como adecuada para todos. |
| [Remote Mouse: guía oficial de gestos](https://blog.remotemouse.net/gestures/) | Documenta movimiento con un dedo, toque para clic, dos dedos para clic derecho o desplazamiento y gestos de arrastre. | Mantener gestos reconocibles y añadir alternativas visibles para las acciones que cuesten con una mano. |
| [Unified Remote: Basic Input](https://www.unifiedremote.com/remotes/basic-input) y [modo Single-Touch](https://www.unifiedremote.com/tutorials/how-to-change-to-singletouch-mouse) | Documenta ajustes independientes de puntero y desplazamiento, dirección del scroll y un modo orientado al uso con una mano. | La postura y las preferencias de movimiento deben poder ajustarse; los gestos de varios dedos no deben ser la única forma de realizar tareas frecuentes. |
| [Mobile Mouse: guía oficial de configuración](https://mobilemouse.com/setup/) | Ofrece botones explícitos, bloqueo de arrastre, opción de desactivar el clic al tocar y orientación horizontal. Describe UDP como una opción que puede reducir el retraso inicial en algunas redes. | Botones visibles y arrastre mantenido entre contactos; conservar una ruta de movimiento ligera, sin prometer una latencia idéntica en todas las redes. |

Las fichas de los productos demuestran funciones documentadas por sus autores. No constituyen una comparación independiente de velocidad o comodidad.

## Decisiones adoptadas

### Posición y tamaño

El selector ofrece **Mesa, Mano derecha y Mano izquierda**. Mesa aprovecha una superficie amplia; los modos de mano acercan la zona útil y sus controles al lado seleccionado. Cambiar de mano modifica la geometría, no el significado de clic izquierdo y derecho.

Las alturas **Compacta, Media y Amplia** permiten probar cuánto recorrido resulta cómodo sin cambiar continuamente el agarre. La distribución responde al espacio disponible, incluidos el modo horizontal y las áreas seguras del iPhone; no depende de unas coordenadas exclusivas del iPhone 13.

Estas tres alturas son alternativas prácticas, no categorías validadas por los estudios. El usuario puede comparar posiciones con el mismo recorrido del cursor antes de elegir.

### Clic y arrastre

Los controles explícitos **Clic** y **Derecho** complementan los gestos existentes y admiten mantener el botón pulsado. **Arrastrar** bloquea el botón primario hasta soltarlo, de modo que se puede levantar y recolocar el pulgar al mover una ventana o seleccionar texto a lo largo de varios monitores.

El estado de arrastre debe ser visible. Al abandonar el contexto de control —por ejemplo, abrir un panel, cambiar la distribución o pasar la app a segundo plano— se libera el botón para evitar un arrastre involuntario. La pérdida de conexión también debe terminar liberando los botones en el servidor.

### Precisión

**Precisión** reduce temporalmente el movimiento enviado a **×0,35** y muestra su estado. Esto permite alternar entre recorrer distancias grandes y ajustar la posición sin entrar en ajustes.

El factor 0,35 es una elección inicial para probar, no un valor óptimo obtenido de la investigación. Se escala la entrada localmente: también disminuye la velocidad que estima el servidor y, por tanto, puede cambiar cuánto interviene su aceleración. **No se desactiva la aceleración del servidor.**

### Desplazamiento

Se mantiene el scroll con dos dedos y se ofrece una franja lateral para usarlo con un pulgar. Su ancho se limita inicialmente a **44–64 puntos**: 44 puntos sigue la recomendación mínima de alcance táctil de Apple; el límite superior es una decisión propia para preservar espacio de movimiento. El perfil sitúa la franja en el lado correspondiente.

La dirección natural y la sensibilidad continúan siendo preferencias separadas de la postura. No se añade inercia: soltar el dedo debe detener el desplazamiento, una elección de previsibilidad que conviene contrastar con el uso real.

### Gestos experimentales

**Golpecito** empieza desactivado en instalaciones nuevas, para que recolocar el teléfono no sea por defecto una forma de hacer clic. Se respetan las preferencias ya guardadas y la función continúa disponible para quien la prefiera.

La estimación de presión a partir de la huella sigue siendo experimental. No se convierte en interacción principal: cambiar la superficie de contacto puede desplazar el punto de contacto mientras se intenta pulsar.

No se incorpora control giroscópico en esta revisión. Su calibración y la separación entre apuntar y recolocar el teléfono requieren pruebas físicas específicas. Que otras aplicaciones lo ofrezcan no demuestra que mejore la precisión o la comodidad de este uso.

## Alcance y validación

La evidencia general respalda controles alcanzables y opciones según la mano. No valida las dimensiones concretas de LowkPad, el factor de precisión ni su comportamiento en un iPhone Air. Los estudios citados utilizaron otros dispositivos y tareas de selección; tampoco midieron fatiga prolongada con esta app.

Las pruebas de software pueden comprobar tamaños, cambios de distribución, gestos, liberación de botones y transmisión de órdenes. La comodidad, el agarre y la latencia percibida necesitan una prueba con el iPhone físico y la red habitual. Un tiempo de respuesta medido en el propio PC no equivale a la latencia completa desde el dedo hasta el monitor.

Para comparar los perfiles, resulta útil repetir estas tareas: seleccionar un objetivo pequeño, abrir un menú contextual, recorrer una página y arrastrar una ventana entre monitores. Conviene observar errores, necesidad de recolocar la mano y esfuerzo, además de rapidez. Los valores iniciales quedan disponibles para ajustar a partir de esa experiencia.
