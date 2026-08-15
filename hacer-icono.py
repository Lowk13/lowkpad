#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera el icono de LowkPad: la flecha clasica del cursor del raton.

Se dibuja a mano en vez de coger el fichero de Windows 11: el cursor de
Microsoft es material con derechos y no se puede meter en un repositorio
publico. La forma de la flecha es generica y se reproduce igual.

Salida: Resources/Assets.xcassets/AppIcon.appiconset/icono-1024.png
"""

import os
from PIL import Image, ImageDraw, ImageFilter

LADO = 1024
SUPER = 4                      # se dibuja a 4x y se reduce, para bordes suaves
S = LADO * SUPER

AQUI = os.path.dirname(os.path.abspath(__file__))
DESTINO = os.path.join(AQUI, "Resources", "Assets.xcassets", "AppIcon.appiconset")

FONDO_A = (24, 27, 34)         # gris muy oscuro, como la app
FONDO_B = (13, 15, 19)
BORDE = (10, 11, 14)
RELLENO = (255, 255, 255)

# Contorno de la flecha, en fraccion del lado (0-1). Es la punta clasica:
# vertical a la izquierda, muesca a la derecha y la "cola" hacia abajo.
FLECHA = [
    (0.000, 0.000),
    (0.000, 0.740),
    (0.185, 0.567),
    (0.300, 0.855),
    (0.437, 0.795),
    (0.323, 0.512),
    (0.560, 0.500),
]


def main():
    os.makedirs(DESTINO, exist_ok=True)

    img = Image.new("RGB", (S, S), FONDO_A)
    d = ImageDraw.Draw(img)

    # degradado diagonal suave de fondo
    for i in range(S):
        t = i / S
        c = tuple(int(FONDO_A[k] + (FONDO_B[k] - FONDO_A[k]) * t) for k in range(3))
        d.line([(0, i), (S, i)], fill=c)

    # la flecha, centrada y a escala
    escala = S * 0.52
    ancho_f = max(x for x, _ in FLECHA) * escala
    alto_f = max(y for _, y in FLECHA) * escala
    ox = (S - ancho_f) / 2
    oy = (S - alto_f) / 2
    puntos = [(ox + x * escala, oy + y * escala) for x, y in FLECHA]

    # sombra, para que despegue del fondo
    sombra = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sombra).polygon([(x + S * 0.012, y + S * 0.016) for x, y in puntos],
                                   fill=110)
    sombra = sombra.filter(ImageFilter.GaussianBlur(S * 0.018))
    img.paste(Image.new("RGB", (S, S), (0, 0, 0)), (0, 0), sombra)

    d = ImageDraw.Draw(img)
    d.polygon(puntos, fill=RELLENO, outline=BORDE, width=int(S * 0.011))

    # Los iconos de iOS NO llevan transparencia ni esquinas redondeadas: el
    # sistema recorta el la mascara el solo. Se guarda en RGB a proposito.
    final = img.resize((LADO, LADO), Image.LANCZOS)
    salida = os.path.join(DESTINO, "icono-1024.png")
    final.save(salida, "PNG")
    print(f"icono guardado: {salida} ({os.path.getsize(salida)//1024} KB)")

    with open(os.path.join(DESTINO, "Contents.json"), "w", encoding="utf-8") as f:
        f.write("""{
  "images" : [
    {
      "filename" : "icono-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""")
    print("Contents.json escrito")


if __name__ == "__main__":
    main()
