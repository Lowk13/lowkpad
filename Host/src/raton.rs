//! El motor del puntero: convierte movimiento de dedo en movimiento de cursor.

use crate::win::*;
use std::sync::Mutex;
use std::time::Instant;

#[derive(Clone, Copy)]
pub struct Cfg {
    pub ganancia: f64,
    pub aceleracion: bool,
    pub umbral_acel: f64,
    pub pendiente_acel: f64,
    pub tope_acel: f64,
    pub ganancia_scroll: f64,
    pub scroll_natural: bool,
    pub scroll_suave: bool,
}

impl Default for Cfg {
    fn default() -> Self {
        Cfg {
            ganancia: 1.8,
            aceleracion: true,
            umbral_acel: 450.0,
            pendiente_acel: 0.55,
            tope_acel: 3.5,
            ganancia_scroll: 1.0,
            scroll_natural: false,
            scroll_suave: true,
        }
    }
}

pub static CFG: Mutex<Cfg> = Mutex::new(Cfg {
    ganancia: 1.8,
    aceleracion: true,
    umbral_acel: 450.0,
    pendiente_acel: 0.55,
    tope_acel: 3.5,
    ganancia_scroll: 1.0,
    scroll_natural: false,
    scroll_suave: true,
});

fn enviar(flags: u32, dx: i32, dy: i32, datos: u32) {
    let entrada = INPUT {
        tipo: INPUT_MOUSE,
        mi: MOUSEINPUT { dx, dy, mouseData: datos, dwFlags: flags, time: 0, dwExtraInfo: 0 },
    };
    unsafe {
        SendInput(1, &entrada, std::mem::size_of::<INPUT>() as i32);
    }
}

fn escritorio_virtual() -> (i32, i32, i32, i32) {
    unsafe {
        (
            GetSystemMetrics(SM_XVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN),
            GetSystemMetrics(SM_CXVIRTUALSCREEN).max(1),
            GetSystemMetrics(SM_CYVIRTUALSCREEN).max(1),
        )
    }
}

fn cursor() -> (i32, i32) {
    let mut p = POINT::default();
    unsafe { GetCursorPos(&mut p) };
    (p.x, p.y)
}

/// Mantiene su PROPIA posicion del cursor y la escribe en absoluto.
///
/// El movimiento relativo de Windows pasa por la curva de "precision mejorada
/// del puntero" del sistema, que descuadraria los ajustes de aceleracion de la
/// app. Escribiendo en absoluto el control es total y reproducible.
pub struct Puntero {
    vx: i32,
    vy: i32,
    vw: i32,
    vh: i32,
    t_metricas: Instant,
    x: f64,
    y: f64,
    ultimo: (i32, i32),
    acc_v: f64,
    acc_h: f64,
    botones: u8,
}

impl Puntero {
    pub fn nuevo() -> Self {
        let (vx, vy, vw, vh) = escritorio_virtual();
        let (x, y) = cursor();
        Puntero {
            vx, vy, vw, vh,
            t_metricas: Instant::now(),
            x: x as f64,
            y: y as f64,
            ultimo: (x, y),
            acc_v: 0.0,
            acc_h: 0.0,
            botones: 0,
        }
    }

    /// El escritorio virtual cambia en caliente: la tele de segundo monitor se
    /// apaga, Windows la redetecta... Si nos quedamos con las medidas del
    /// arranque, el mapeo apunta a otro sitio y el cursor se vuelve loco.
    fn refrescar_metricas(&mut self) {
        if self.t_metricas.elapsed().as_secs_f64() < 1.0 {
            return;
        }
        self.t_metricas = Instant::now();
        let nuevo = escritorio_virtual();
        if nuevo != (self.vx, self.vy, self.vw, self.vh) {
            self.vx = nuevo.0;
            self.vy = nuevo.1;
            self.vw = nuevo.2;
            self.vh = nuevo.3;
            let (x, y) = cursor();
            self.x = x as f64;
            self.y = y as f64;
            self.ultimo = (x, y);
        }
    }

    /// Si el usuario ha tocado su raton fisico, no pelearse con el.
    fn resincronizar(&mut self) {
        let (x, y) = cursor();
        if (x - self.ultimo.0).abs() > 2 || (y - self.ultimo.1).abs() > 2 {
            self.x = x as f64;
            self.y = y as f64;
        }
    }

    pub fn mover(&mut self, dx: f64, dy: f64, dt: f64) {
        self.refrescar_metricas();
        self.resincronizar();

        let cfg = *CFG.lock().unwrap();
        let mut factor = cfg.ganancia;
        if cfg.aceleracion && dt > 0.0005 {
            let velocidad = (dx * dx + dy * dy).sqrt() / dt; // puntos por segundo
            let umbral = cfg.umbral_acel.max(1.0);
            if velocidad > umbral {
                let extra = 1.0 + cfg.pendiente_acel * (velocidad / umbral - 1.0);
                factor *= extra.min(cfg.tope_acel);
            }
        }

        self.x += dx * factor;
        self.y += dy * factor;
        self.x = self.x.clamp(self.vx as f64, (self.vx + self.vw - 1) as f64);
        self.y = self.y.clamp(self.vy as f64, (self.vy + self.vh - 1) as f64);

        let ix = self.x.round() as i32;
        let iy = self.y.round() as i32;
        if (ix, iy) == self.ultimo {
            return;
        }
        let ax = ((ix - self.vx) as f64 * 65535.0 / (self.vw - 1).max(1) as f64).round() as i32;
        let ay = ((iy - self.vy) as f64 * 65535.0 / (self.vh - 1).max(1) as f64).round() as i32;
        enviar(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK, ax, ay, 0);
        self.ultimo = (ix, iy);
    }

    pub fn boton(&mut self, cual: u8, abajo: bool) {
        let (bit, on, off) = match cual {
            b'l' => (1u8, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP),
            b'r' => (2u8, MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP),
            b'm' => (4u8, MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP),
            _ => return,
        };
        let pulsado = self.botones & bit != 0;
        if pulsado == abajo {
            return;
        }
        enviar(if abajo { on } else { off }, 0, 0, 0);
        if abajo { self.botones |= bit } else { self.botones &= !bit }
    }

    /// Par indivisible: ningún hilo tardío puede soltar un arrastre posterior.
    pub fn clic(&mut self, cual: u8) {
        let (bit, on, off) = match cual {
            b'l' => (1, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP),
            b'r' => (2, MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP),
            b'm' => (4, MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP),
            _ => return,
        };
        if self.botones & bit != 0 { return; }
        let entradas = [on, off].map(|flags| INPUT {
            tipo: INPUT_MOUSE,
            mi: MOUSEINPUT { dx: 0, dy: 0, mouseData: 0, dwFlags: flags, time: 0, dwExtraInfo: 0 },
        });
        unsafe { SendInput(2, entradas.as_ptr(), std::mem::size_of::<INPUT>() as i32); }
    }

    pub fn soltar_todo(&mut self) {
        for b in [b'l', b'r', b'm'] {
            self.boton(b, false);
        }
    }

    pub fn scroll(&mut self, dx: f64, dy: f64) {
        let cfg = *CFG.lock().unwrap();
        let signo = if cfg.scroll_natural { 1.0 } else { -1.0 };
        self.acc_v += dy * cfg.ganancia_scroll * 6.0 * signo;
        self.acc_h += dx * cfg.ganancia_scroll * 6.0;

        let paso = if cfg.scroll_suave { 10.0 } else { 120.0 };
        let n = (self.acc_v / paso) as i32;
        if n != 0 {
            self.acc_v -= n as f64 * paso;
            enviar(MOUSEEVENTF_WHEEL, 0, 0, (n as f64 * paso) as i32 as u32);
        }
        let n = (self.acc_h / paso) as i32;
        if n != 0 {
            self.acc_h -= n as f64 * paso;
            enviar(MOUSEEVENTF_HWHEEL, 0, 0, (n as f64 * paso) as i32 as u32);
        }
    }

    pub fn medidas(&self) -> (i32, i32, i32, i32) {
        (self.vx, self.vy, self.vw, self.vh)
    }
}

/// Que Windows no mienta con las coordenadas si hay escalado de pantalla.
pub fn preparar_dpi() {
    unsafe {
        // PER_MONITOR_AWARE_V2
        SetProcessDpiAwarenessContext(-4);
    }
}
