//! Canal de órdenes confirmadas. No bloquea el hilo UDP del ratón.
use crate::win::HWND;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::time::Duration;

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
    let vk = tecla_codigo(nombre).ok_or("Tecla no admitida")?;
    let extended = if (0x25..=0x28).contains(&vk) { 1 } else { 0 };
    inyectar(&[entrada(vk, 0, extended), entrada(vk, 0, extended | 2)])
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
        "clipboard_get" => Ok(json!({"text": leer_clip(hwnd)?})),
        "clipboard_set" => { escribir_clip(hwnd, v["text"].as_str().ok_or("Falta texto")?)?; Ok(json!({})) }
        "status" => Ok(json!({"version":"0.3.0"})),
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
    let token = clave()?;
    let listener = TcpListener::bind(("0.0.0.0", 8787))?;
    // Una orden por conexión, procesada antes de aceptar la siguiente.
    // El cliente espera confirmación y nunca reintenta acciones automáticamente.
    for stream in listener.incoming() {
        let Ok(mut stream) = stream else { continue };
        stream.set_nodelay(true)?;
        stream.set_read_timeout(Some(Duration::from_secs(3)))?;
        stream.set_write_timeout(Some(Duration::from_secs(3)))?;
        let mut line = Vec::new();
        let result = BufReader::new((&mut stream).take(MAX_TRAMA)).read_until(b'\n', &mut line);
        if result.is_err() || line.last() != Some(&b'\n') { continue; }
        let response = match serde_json::from_slice::<Value>(&line) {
            Ok(v) if v["token"].as_str() == Some(token.as_str()) => {
                match ejecutar(&v, hwnd) {
                    Ok(data) => json!({"ok":true,"data":data}),
                    Err(e) => json!({"ok":false,"error":e}),
                }
            }
            _ => json!({"ok":false,"error":"Clave de enlace incorrecta. Revísala en Ajustes."}),
        };
        let _ = writeln!(stream, "{response}");
    }
    Ok(())
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
}
