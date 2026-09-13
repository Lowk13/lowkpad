// Sin consola: es una aplicacion de bandeja, no de terminal.
#![windows_subsystem = "windows"]

mod raton;
mod win;

use raton::{Cfg, Puntero, CFG};
use std::collections::HashMap;
use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use win::*;

const PUERTO: u16 = 8788;

static PAQUETES: AtomicU64 = AtomicU64::new(0);
static ESTADO: Mutex<String> = Mutex::new(String::new());

const ID_ESTADO: usize = 1;
const ID_SALIR: usize = 2;

// ---------------------------------------------------------------------------
// Lectura de los paquetes
// ---------------------------------------------------------------------------
//
// El protocolo es JSON plano, pero con una forma fija y conocida, asi que se
// lee a mano en vez de arrastrar una libreria entera. Siempre se busca la clave
// COMPLETA (`"s":`, no `s`), porque hay claves que son prefijo de otras: `s`
// contra `sx`, `sy` y `ses`.

fn buscar<'a>(texto: &'a str, clave: &str) -> Option<&'a str> {
    let patron = format!("\"{}\":", clave);
    let i = texto.find(&patron)? + patron.len();
    Some(&texto[i..])
}

fn numero(texto: &str, clave: &str) -> Option<f64> {
    let resto = buscar(texto, clave)?.trim_start();
    let fin = resto
        .find(|c: char| !(c.is_ascii_digit() || c == '-' || c == '+' || c == '.' || c == 'e'))
        .unwrap_or(resto.len());
    resto[..fin].parse::<f64>().ok().filter(|v| v.is_finite())
}

fn booleano(texto: &str, clave: &str) -> Option<bool> {
    let resto = buscar(texto, clave)?.trim_start();
    if resto.starts_with("true") { Some(true) }
    else if resto.starts_with("false") { Some(false) }
    else { None }
}

fn letra(texto: &str, clave: &str) -> Option<u8> {
    let resto = buscar(texto, clave)?.trim_start();
    resto.strip_prefix('"')?.bytes().next()
}

// ---------------------------------------------------------------------------
// Estado de cada movil conectado
// ---------------------------------------------------------------------------

struct Cliente {
    sesion: f64,
    seq: f64,
    x: f64,
    y: f64,
    tm: f64,
    sx: f64,
    sy: f64,
    ci: f64,
    botones: u8,
    visto: Instant,
}

fn bucle_udp() {
    let socket = match UdpSocket::bind(("0.0.0.0", PUERTO)) {
        Ok(s) => s,
        Err(e) => {
            aviso(&format!("No se pudo abrir el puerto {PUERTO}: {e}\n\n\
                            Puede que ya haya otra copia de LowkPad corriendo."));
            return;
        }
    };
    socket.set_read_timeout(Some(Duration::from_millis(100))).expect("timeout UDP");

    let mut puntero = Puntero::nuevo();
    let mut clientes: HashMap<SocketAddr, Cliente> = HashMap::new();
    let mut buffer = [0u8; 2048];
    let mut ultimo_estado = Instant::now();

    loop {
        // También se ejecuta cuando no llega ningún paquete (bloqueo del móvil).
        let expirado = clientes.values().any(|c| c.visto.elapsed() > Duration::from_secs(2));
        if expirado {
            puntero.soltar_todo();
            clientes.retain(|_, c| c.visto.elapsed() <= Duration::from_secs(2));
            for c in clientes.values_mut() { c.botones = 0; }
        }
        let (n, origen) = match socket.recv_from(&mut buffer) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let texto = match std::str::from_utf8(&buffer[..n]) {
            Ok(t) => t,
            Err(_) => continue,
        };
        PAQUETES.fetch_add(1, Ordering::Relaxed);

        // Una sonda no crea una sesión ni altera los botones del usuario.
        if buscar(texto, "t").map_or(false, |r| r.trim_start().starts_with("\"ping\"")) {
            if let Some(p) = numero(texto, "p") {
                let _ = socket.send_to(pong(p).as_bytes(), origen);
            }
            continue;
        }

        // --- ajustes que llegan del movil ---
        if buscar(texto, "t").map_or(false, |r| r.trim_start().starts_with("\"cfg\"")) {
            let mut c = CFG.lock().unwrap();
            let n = *c;
            *c = Cfg {
                ganancia: numero(texto, "gain").unwrap_or(n.ganancia),
                aceleracion: booleano(texto, "accel").unwrap_or(n.aceleracion),
                umbral_acel: numero(texto, "accel_thr").unwrap_or(n.umbral_acel),
                pendiente_acel: numero(texto, "accel_slope").unwrap_or(n.pendiente_acel),
                tope_acel: numero(texto, "accel_max").unwrap_or(n.tope_acel),
                ganancia_scroll: numero(texto, "scroll_gain").unwrap_or(n.ganancia_scroll),
                scroll_natural: booleano(texto, "scroll_natural").unwrap_or(n.scroll_natural),
                scroll_suave: booleano(texto, "scroll_smooth").unwrap_or(n.scroll_suave),
            };
            continue;
        }

        if !buscar(texto, "t").map_or(false, |r| r.trim_start().starts_with("\"m\"")) { continue; }
        let (ses, seq) = match (numero(texto, "ses"), numero(texto, "s")) {
            (Some(ses), Some(seq)) if ses > 0.0 && seq > 0.0 => (ses, seq),
            _ => continue,
        };
        let ahora = Instant::now();

        // Si la app se reinicia, su numeracion vuelve a empezar. Sin mirar el
        // identificador de sesion, tomariamos todos sus paquetes por atrasados
        // y la ignorariamos para siempre.
        let nuevo = match clientes.get(&origen) {
            None => true,
            Some(c) => c.sesion != ses || c.visto.elapsed().as_secs_f64() > 3.0,
        };

        if nuevo {
            puntero.soltar_todo();
            clientes.insert(origen, Cliente {
                sesion: ses,
                seq,
                x: numero(texto, "x").unwrap_or(0.0),
                y: numero(texto, "y").unwrap_or(0.0),
                tm: numero(texto, "tm").unwrap_or(0.0),
                sx: numero(texto, "sx").unwrap_or(0.0),
                sy: numero(texto, "sy").unwrap_or(0.0),
                ci: numero(texto, "ci").unwrap_or(0.0),
                botones: 0,
                visto: ahora,
            });
        } else {
            let c = clientes.get_mut(&origen).unwrap();

            // Paquete viejo o repetido: el estado ya esta mas adelante.
            if seq <= c.seq {
                if let Some(p) = numero(texto, "p") {
                    let _ = socket.send_to(pong(p).as_bytes(), origen);
                }
                continue;
            }
            c.visto = ahora;

            let x = numero(texto, "x").unwrap_or(c.x);
            let y = numero(texto, "y").unwrap_or(c.y);
            let tm = numero(texto, "tm").unwrap_or(c.tm);
            let dx = x - c.x;
            let dy = y - c.y;
            let dt = ((tm - c.tm) / 1000.0).max(0.001);
            if dx != 0.0 || dy != 0.0 {
                puntero.mover(dx, dy, dt);
            }

            let sx = numero(texto, "sx").unwrap_or(c.sx);
            let sy = numero(texto, "sy").unwrap_or(c.sy);
            if sx != c.sx || sy != c.sy {
                puntero.scroll(sx - c.sx, sy - c.sy);
            }

            // Botones mantenidos: se manda el ESTADO, no eventos, asi que una
            // perdida se corrige sola en el paquete siguiente.
            let bits = numero(texto, "b").unwrap_or(0.0) as u8;
            for (bit, nombre) in [(1u8, b'l'), (2, b'r'), (4, b'm')] {
                let quiero = bits & bit != 0;
                let tengo = c.botones & bit != 0;
                if quiero != tengo {
                    puntero.boton(nombre, quiero);
                }
            }
            c.botones = bits;

            // Clics sueltos: identificados, para no repetirlos ni perderlos.
            let ci = numero(texto, "ci").unwrap_or(0.0);
            if ci > c.ci {
                puntero.clic(letra(texto, "cb").unwrap_or(b'l'));
            }

            c.seq = seq;
            c.x = x;
            c.y = y;
            c.tm = tm;
            c.sx = sx;
            c.sy = sy;
            c.ci = ci;
        }

        if let Some(p) = numero(texto, "p") {
            let _ = socket.send_to(pong(p).as_bytes(), origen);
        }

        // El texto de estado se rehace UNA VEZ POR SEGUNDO, no en cada paquete:
        // formatearlo 120 veces por segundo significa 120 reservas de memoria
        // por segundo para algo que solo se mira al abrir el menú.
        if ultimo_estado.elapsed().as_secs_f64() >= 1.0 {
            ultimo_estado = Instant::now();
            let (_, _, vw, vh) = puntero.medidas();
            *ESTADO.lock().unwrap() = format!(
                "{} móvil(es) · {} paquetes · escritorio {}x{}",
                clientes.len(), PAQUETES.load(Ordering::Relaxed), vw, vh
            );
        }
    }
}

/// Compacto a proposito: sin espacios, menos bytes y formato predecible.
fn pong(marca: f64) -> String {
    format!("{{\"t\":\"pong\",\"p\":{}}}", marca as i64)
}

fn aviso(texto: &str) {
    unsafe {
        MessageBoxW(0, ancho(texto).as_ptr(), ancho("LowkPad").as_ptr(), 0x10);
    }
}

// ---------------------------------------------------------------------------
// Icono en la bandeja
// ---------------------------------------------------------------------------

unsafe extern "system" fn ventana_proc(h: HWND, msg: u32, w: usize, l: isize) -> isize {
    match msg {
        WM_BANDEJA => {
            let evento = l as u32;
            if evento == WM_RBUTTONUP || evento == WM_LBUTTONDBLCLK {
                let menu = CreatePopupMenu();
                AppendMenuW(menu, MF_STRING, ID_ESTADO, ancho("Estado…").as_ptr());
                AppendMenuW(menu, MF_SEPARATOR, 0, std::ptr::null());
                AppendMenuW(menu, MF_STRING, ID_SALIR, ancho("Salir").as_ptr());
                let mut p = POINT::default();
                GetCursorPos(&mut p);
                // Sin esto, el menu se queda abierto al pulsar fuera.
                SetForegroundWindow(h);
                TrackPopupMenu(menu, TPM_RIGHTBUTTON, p.x, p.y, 0, h, std::ptr::null());
                DestroyMenu(menu);
            }
            0
        }
        WM_COMMAND => {
            match w & 0xFFFF {
                ID_ESTADO => {
                    let e = ESTADO.lock().unwrap().clone();
                    let texto = if e.is_empty() {
                        format!("Escuchando en el puerto {PUERTO}.\n\nTodavía no se ha conectado ningún móvil.")
                    } else {
                        format!("Escuchando en el puerto {PUERTO}.\n\n{e}")
                    };
                    MessageBoxW(0, ancho(&texto).as_ptr(), ancho("LowkPad").as_ptr(), 0x40);
                }
                ID_SALIR => PostQuitMessage(0),
                _ => {}
            }
            0
        }
        WM_DESTROY => {
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(h, msg, w, l),
    }
}

fn main() {
    raton::preparar_dpi();
    std::thread::spawn(bucle_udp);

    unsafe {
        let instancia = GetModuleHandleW(std::ptr::null());
        let clase = ancho("LowkPadBandeja");

        let wc = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            style: 0,
            lpfnWndProc: Some(ventana_proc),
            cbClsExtra: 0,
            cbWndExtra: 0,
            hInstance: instancia,
            hIcon: 0,
            hCursor: 0,
            hbrBackground: 0,
            lpszMenuName: std::ptr::null(),
            lpszClassName: clase.as_ptr(),
            hIconSm: 0,
        };
        RegisterClassExW(&wc);

        // Ventana que nunca se muestra: solo existe para recibir los mensajes
        // del icono de la bandeja.
        let hwnd = CreateWindowExW(
            0, clase.as_ptr(), ancho("LowkPad").as_ptr(), 0,
            0, 0, 0, 0, 0, 0, instancia, std::ptr::null(),
        );

        // El icono se carga de un .ico junto al ejecutable; si no está, se usa
        // el genérico de Windows en vez de quedarse sin icono.
        let mut icono: HICON = 0;
        if let Ok(exe) = std::env::current_exe() {
            let ruta = exe.with_file_name("icono.ico");
            if ruta.exists() {
                icono = LoadImageW(0, ancho(&ruta.to_string_lossy()).as_ptr(),
                                   IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
            }
        }
        if icono == 0 {
            icono = LoadIconW(0, IDI_APPLICATION);
        }

        let mut datos: NOTIFYICONDATAW = std::mem::zeroed();
        datos.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        datos.hWnd = hwnd;
        datos.uID = 1;
        datos.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
        datos.uCallbackMessage = WM_BANDEJA;
        datos.hIcon = icono;
        for (i, c) in ancho("LowkPad — ratón desde el iPhone").iter().take(127).enumerate() {
            datos.szTip[i] = *c;
        }
        Shell_NotifyIconW(NIM_ADD, &datos);

        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, 0, 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        Shell_NotifyIconW(NIM_DELETE, &datos);
    }
}
