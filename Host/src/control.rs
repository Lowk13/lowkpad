//! Canal de órdenes confirmadas. No bloquea el hilo UDP del ratón.
use crate::win::HWND;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::time::Duration;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicUsize, Ordering};

const MAX_TEXTO: usize = 65536;
const MAX_TRAMA: u64 = 400000; // JSON puede escapar cada carácter como \uXXXX

#[repr(C)]
#[derive(Clone, Copy)]
struct Keyboard { vk: u16, scan: u16, flags: u32, time: u32, extra: usize }
#[repr(C)]
union Datos { key: Keyboard, padding: [u64; 4] }
#[repr(C)]
struct Entrada { tipo: u32, datos: Datos }

#[link(name = "user32")]
extern "system" {
    fn OpenClipboard(hwnd: HWND) -> i32;
    fn CloseClipboard() -> i32;
    fn EmptyClipboard() -> i32;
    fn GetClipboardData(format: u32) -> isize;
    fn SetClipboardData(format: u32, data: isize) -> isize;
    fn IsClipboardFormatAvailable(format: u32) -> i32;
}
#[link(name = "kernel32")]
extern "system" {
    fn GlobalAlloc(flags: u32, size: usize) -> isize;
    fn GlobalLock(h: isize) -> *mut u16;
    fn GlobalUnlock(h: isize) -> i32;
    fn GlobalFree(h: isize) -> isize;
    fn GlobalSize(h: isize) -> usize;
}
#[link(name = "bcrypt")]
extern "system" { fn BCryptGenRandom(h: isize, data: *mut u8, len: u32, flags: u32) -> i32; }

fn entrada(vk: u16, scan: u16, flags: u32) -> Entrada {
    Entrada { tipo: 1, datos: Datos { key: Keyboard { vk, scan, flags, time: 0, extra: 0 } } }
}
fn inyectar(v: &[Entrada]) -> Result<(), String> {
    let n = unsafe { crate::win::SendInput(v.len() as u32, v.as_ptr().cast(), std::mem::size_of::<Entrada>() as i32) };
    if n != v.len() as u32 { Err("Windows no aceptó toda la entrada. Comprueba la ventana activa y sus permisos.".into()) }
    else { Ok(()) }
}
fn tecla_codigo(nombre: &str) -> Option<u16> {
    Some(match nombre {
        "play_pause" => 0xB3, "stop" => 0xB2, "previous" => 0xB1, "next" => 0xB0,
        "volume_up" => 0xAF, "volume_down" => 0xAE, "mute" => 0xAD,
        "enter" => 0x0D, "backspace" => 0x08, "tab" => 0x09, "escape" => 0x1B,
        "left" => 0x25, "up" => 0x26, "right" => 0x27, "down" => 0x28,
        _ => return None,
    })
}
fn tecla(nombre: &str) -> Result<(), String> {
    if nombre == "paste" {
        return inyectar(&[entrada(0x11, 0, 0), entrada(0x56, 0, 0),
                          entrada(0x56, 0, 2), entrada(0x11, 0, 2)]);
    }
    let vk = tecla_codigo(nombre).ok_or("Tecla no admitida")?;
    let extended = if (0x25..=0x28).contains(&vk) { 1 } else { 0 };
    inyectar(&[entrada(vk, 0, extended), entrada(vk, 0, extended | 2)])
}
fn atajo_teclas(nombre: &str) -> Option<&'static [u16]> {
    Some(match nombre {
        "monitor_left" => &[0x5B, 0x10, 0x25],
        "monitor_right" => &[0x5B, 0x10, 0x27],
        "copy" => &[0x11, 0x43], "cut" => &[0x11, 0x58], "paste" => &[0x11, 0x56],
        "select_all" => &[0x11, 0x41], "undo" => &[0x11, 0x5A], "redo" => &[0x11, 0x59],
        "save" => &[0x11, 0x53], "find" => &[0x11, 0x46],
        "switch_window" => &[0x12, 0x09], "desktop" => &[0x5B, 0x44],
        "snap_left" => &[0x5B, 0x25], "snap_right" => &[0x5B, 0x27],
        "maximize" => &[0x5B, 0x26], "minimize" => &[0x5B, 0x28],
        "new_tab" => &[0x11, 0x54], "close_tab" => &[0x11, 0x57],
        "reopen_tab" => &[0x11, 0x10, 0x54], "refresh" => &[0x11, 0x52],
        _ => return None,
    })
}
fn atajo(nombre: &str) -> Result<(), String> {
    let keys = atajo_teclas(nombre).ok_or("Atajo no admitido")?;
    let flags = |vk: u16| if vk == 0x5B || (0x25..=0x28).contains(&vk) { 1 } else { 0 };
    let mut eventos: Vec<Entrada> = keys.iter().map(|&k| entrada(k, 0, flags(k))).collect();
    eventos.extend(keys.iter().rev().map(|&k| entrada(k, 0, flags(k) | 2)));
    let resultado = inyectar(&eventos);
    if resultado.is_err() {
        // Si Windows solo aceptó parte del lote, intentar liberar modificadores.
        let soltar: Vec<Entrada> = keys.iter().rev().map(|&k| entrada(k, 0, flags(k) | 2)).collect();
        let _ = inyectar(&soltar);
    }
    resultado
}
fn texto(s: &str) -> Result<(), String> {
    if s.len() > MAX_TEXTO || s.contains('\0') { return Err("Texto demasiado grande o no válido (máximo 64 KB).".into()); }
    // Unicode evita depender del idioma/distribución del teclado del PC.
    let mut v = Vec::new();
    for unidad in s.replace("\r\n", "\n").encode_utf16() {
        if unidad == 10 || unidad == 13 {
            v.extend([entrada(0x0D, 0, 0), entrada(0x0D, 0, 2)]);
        } else {
            v.extend([entrada(0, unidad, 4), entrada(0, unidad, 6)]);
        }
    }
    for fragmento in v.chunks(256) { inyectar(fragmento)?; }
    Ok(())
}
struct Clipboard;
impl Drop for Clipboard { fn drop(&mut self) { unsafe { CloseClipboard(); } } }
fn abrir(hwnd: HWND) -> Result<Clipboard, String> {
    for _ in 0..10 {
        if unsafe { OpenClipboard(hwnd) } != 0 { return Ok(Clipboard); }
        std::thread::sleep(Duration::from_millis(10));
    }
    Err("El portapapeles está ocupado. Vuelve a intentarlo.".into())
}
fn leer_clip(hwnd: HWND) -> Result<String, String> {
    let _guard = abrir(hwnd)?;
    unsafe {
        if IsClipboardFormatAvailable(13) == 0 { return Err("El portapapeles del PC no contiene texto.".into()); }
        let h = GetClipboardData(13);
        if h == 0 { return Err("No se pudo leer el portapapeles.".into()); }
        let size = GlobalSize(h);
        if size > MAX_TEXTO * 2 + 2 { return Err("Texto del PC demasiado grande (máximo 64 KB).".into()); }
        let p = GlobalLock(h);
        if p.is_null() { return Err("No se pudo acceder al texto.".into()); }
        let raw = std::slice::from_raw_parts(p, size / 2);
        let len = raw.iter().position(|x| *x == 0).unwrap_or(raw.len());
        let result = String::from_utf16(&raw[..len]).map_err(|_| "Texto Unicode no válido".to_string());
        GlobalUnlock(h);
        let result = result?;
        if result.len() > MAX_TEXTO { return Err("Texto demasiado grande (máximo 64 KB).".into()); }
        Ok(result)
    }
}
fn escribir_clip(hwnd: HWND, s: &str) -> Result<(), String> {
    if s.len() > MAX_TEXTO || s.contains('\0') { return Err("Texto demasiado grande o no válido (máximo 64 KB).".into()); }
    let data: Vec<u16> = s.encode_utf16().chain(Some(0)).collect();
    let _guard = abrir(hwnd)?;
    unsafe {
        let h = GlobalAlloc(2, data.len() * 2);
        if h == 0 { return Err("No hay memoria para el texto.".into()); }
        let p = GlobalLock(h);
        if p.is_null() { GlobalFree(h); return Err("No se pudo preparar el texto.".into()); }
        std::ptr::copy_nonoverlapping(data.as_ptr(), p, data.len());
        GlobalUnlock(h);
        if EmptyClipboard() == 0 || SetClipboardData(13, h) == 0 {
            GlobalFree(h); return Err("No se pudo escribir en el portapapeles.".into());
        }
    }
    Ok(())
}
fn ejecutar(v: &Value, hwnd: HWND) -> Result<Value, String> {
    match v["op"].as_str().unwrap_or("") {
        "key" => { tecla(v["key"].as_str().ok_or("Falta tecla")?)?; Ok(json!({})) }
        "text" => { texto(v["text"].as_str().ok_or("Falta texto")?)?; Ok(json!({})) }
        "shortcut" => { atajo(v["name"].as_str().ok_or("Falta atajo")?)?; Ok(json!({})) }
        "clipboard_get" => Ok(json!({"text": leer_clip(hwnd)?})),
        "clipboard_set" => { escribir_clip(hwnd, v["text"].as_str().ok_or("Falta texto")?)?; Ok(json!({})) }
        "clipboard_paste" => {
            escribir_clip(hwnd, v["text"].as_str().ok_or("Falta texto")?)?;
            tecla("paste")?;
            Ok(json!({}))
        }
        "status" => Ok(json!({"version":"0.4.0"})),
        _ => Err("Orden no admitida".into()),
    }
}
fn clave() -> std::io::Result<String> {
    let path = std::env::current_exe()?.with_file_name("paneles.key");
    if path.exists() {
        let value = std::fs::read_to_string(path)?.trim().to_owned();
        if value.len() == 32 && value.bytes().all(|c| c.is_ascii_hexdigit()) { return Ok(value); }
        return Err(std::io::Error::other("paneles.key no es válido"));
    }
    let mut bytes = [0u8;16];
    if unsafe { BCryptGenRandom(0, bytes.as_mut_ptr(), 16, 2) } != 0 {
        return Err(std::io::Error::other("No se pudo generar la clave"));
    }
    let value: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    std::fs::write(path, &value)?;
    Ok(value)
}
pub fn servir(hwnd: HWND) -> std::io::Result<()> {
    let token = Arc::new(clave()?);
    let listener = TcpListener::bind(("0.0.0.0", 8787))?;
    let ejecucion = Arc::new(Mutex::new(()));
    let activos = Arc::new(AtomicUsize::new(0));
    // Conexiones persistentes; varios clientes no pueden intercalar un atajo.
    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        if activos.fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| (n < 8).then_some(n + 1)).is_err() { continue; }
        let (token, ejecucion, activos) = (token.clone(), ejecucion.clone(), activos.clone());
        std::thread::spawn(move || {
            let _ = cliente(stream, hwnd, &token, &ejecucion);
            activos.fetch_sub(1, Ordering::SeqCst);
        });
    }
    Ok(())
}
fn cliente(stream: std::net::TcpStream, hwnd: HWND, token: &str, ejecucion: &Mutex<()>) -> std::io::Result<()> {
    stream.set_nodelay(true)?;
    stream.set_read_timeout(Some(Duration::from_secs(60)))?;
    stream.set_write_timeout(Some(Duration::from_secs(3)))?;
    let mut reader = BufReader::new(stream);
    loop {
        let mut line = Vec::new();
        (&mut reader).take(MAX_TRAMA).read_until(b'\n', &mut line)?;
        if line.last() != Some(&b'\n') { return Ok(()); }
        let valido;
        let response = match serde_json::from_slice::<Value>(&line) {
            Ok(v) if v["token"].as_str() == Some(token) => {
                valido = true;
                let _guard = ejecucion.lock().unwrap();
                match ejecutar(&v, hwnd) {
                    Ok(data) => json!({"ok":true,"data":data}),
                    Err(e) => json!({"ok":false,"error":e}),
                }
            }
            _ => { valido = false; json!({"ok":false,"error":"Clave de enlace incorrecta. Revísala en Ajustes."}) },
        };
        writeln!(reader.get_mut(), "{response}")?;
        if !valido { return Ok(()); }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn estructura_win64() { assert_eq!(std::mem::size_of::<Entrada>(), 40); }
    #[test] fn lista_cerrada_de_teclas() {
        assert_eq!(tecla_codigo("volume_up"), Some(0xAF));
        assert_eq!(tecla_codigo("play_pause"), Some(0xB3));
        assert_eq!(tecla_codigo("powershell"), None);
    }
    #[test] fn atajos_de_monitor_y_lista_cerrada() {
        assert_eq!(atajo_teclas("monitor_left"), Some(&[0x5B, 0x10, 0x25][..]));
        assert_eq!(atajo_teclas("monitor_right"), Some(&[0x5B, 0x10, 0x27][..]));
        assert_eq!(atajo_teclas("powershell"), None);
    }
}
