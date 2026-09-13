//! Lo justo de Win32, declarado a mano.
//!
//! Se evita la caja `windows` a proposito: son cientos de miles de lineas
//! generadas para exponer toda la API, y aqui hacen falta doce funciones.

#![allow(non_snake_case, non_camel_case_types)]

pub type HWND = isize;
pub type HICON = isize;
pub type HMENU = isize;
pub type HINSTANCE = isize;

// --- raton ---
pub const INPUT_MOUSE: u32 = 0;
pub const MOUSEEVENTF_MOVE: u32 = 0x0001;
pub const MOUSEEVENTF_LEFTDOWN: u32 = 0x0002;
pub const MOUSEEVENTF_LEFTUP: u32 = 0x0004;
pub const MOUSEEVENTF_RIGHTDOWN: u32 = 0x0008;
pub const MOUSEEVENTF_RIGHTUP: u32 = 0x0010;
pub const MOUSEEVENTF_MIDDLEDOWN: u32 = 0x0020;
pub const MOUSEEVENTF_MIDDLEUP: u32 = 0x0040;
pub const MOUSEEVENTF_WHEEL: u32 = 0x0800;
pub const MOUSEEVENTF_HWHEEL: u32 = 0x1000;
pub const MOUSEEVENTF_ABSOLUTE: u32 = 0x8000;
pub const MOUSEEVENTF_VIRTUALDESK: u32 = 0x4000;

pub const SM_XVIRTUALSCREEN: i32 = 76;
pub const SM_YVIRTUALSCREEN: i32 = 77;
pub const SM_CXVIRTUALSCREEN: i32 = 78;
pub const SM_CYVIRTUALSCREEN: i32 = 79;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MOUSEINPUT {
    pub dx: i32,
    pub dy: i32,
    pub mouseData: u32,
    pub dwFlags: u32,
    pub time: u32,
    pub dwExtraInfo: usize,
}

/// `INPUT` es una union; aqui solo se usa la parte de raton. El `repr(C)`
/// coloca `mi` en el desplazamiento 8 por alineacion, que es justo lo que
/// espera Windows (tamano total 40 bytes en 64 bits).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct INPUT {
    pub tipo: u32,
    pub mi: MOUSEINPUT,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct POINT {
    pub x: i32,
    pub y: i32,
}

// --- ventana y bandeja ---
pub const WM_DESTROY: u32 = 0x0002;
pub const WM_COMMAND: u32 = 0x0111;
pub const WM_USER: u32 = 0x0400;
pub const WM_BANDEJA: u32 = WM_USER + 1;
pub const WM_RBUTTONUP: u32 = 0x0205;
pub const WM_LBUTTONDBLCLK: u32 = 0x0203;

pub const NIM_ADD: u32 = 0;
pub const NIM_DELETE: u32 = 2;
pub const NIF_MESSAGE: u32 = 0x01;
pub const NIF_ICON: u32 = 0x02;
pub const NIF_TIP: u32 = 0x04;

pub const IMAGE_ICON: u32 = 1;
pub const LR_LOADFROMFILE: u32 = 0x0010;
pub const LR_DEFAULTSIZE: u32 = 0x0040;
pub const IDI_APPLICATION: usize = 32512;

pub const MF_STRING: u32 = 0x0000;
pub const MF_SEPARATOR: u32 = 0x0800;
pub const TPM_RIGHTBUTTON: u32 = 0x0002;

#[repr(C)]
pub struct NOTIFYICONDATAW {
    pub cbSize: u32,
    pub hWnd: HWND,
    pub uID: u32,
    pub uFlags: u32,
    pub uCallbackMessage: u32,
    pub hIcon: HICON,
    pub szTip: [u16; 128],
    pub dwState: u32,
    pub dwStateMask: u32,
    pub szInfo: [u16; 256],
    pub uVersion: u32,
    pub szInfoTitle: [u16; 64],
    pub dwInfoFlags: u32,
    pub guidItem: [u8; 16],
    pub hBalloonIcon: HICON,
}

#[repr(C)]
pub struct WNDCLASSEXW {
    pub cbSize: u32,
    pub style: u32,
    pub lpfnWndProc: Option<unsafe extern "system" fn(HWND, u32, usize, isize) -> isize>,
    pub cbClsExtra: i32,
    pub cbWndExtra: i32,
    pub hInstance: HINSTANCE,
    pub hIcon: HICON,
    pub hCursor: isize,
    pub hbrBackground: isize,
    pub lpszMenuName: *const u16,
    pub lpszClassName: *const u16,
    pub hIconSm: HICON,
}

#[repr(C)]
pub struct MSG {
    pub hwnd: HWND,
    pub message: u32,
    pub wParam: usize,
    pub lParam: isize,
    pub time: u32,
    pub pt: POINT,
}

#[link(name = "user32")]
extern "system" {
    pub fn SendInput(cInputs: u32, pInputs: *const INPUT, cbSize: i32) -> u32;
    pub fn GetSystemMetrics(nIndex: i32) -> i32;
    pub fn GetCursorPos(lpPoint: *mut POINT) -> i32;
    pub fn SetProcessDpiAwarenessContext(value: isize) -> i32;

    pub fn RegisterClassExW(c: *const WNDCLASSEXW) -> u16;
    pub fn CreateWindowExW(
        ex: u32, clase: *const u16, titulo: *const u16, estilo: u32,
        x: i32, y: i32, w: i32, h: i32,
        padre: HWND, menu: HMENU, inst: HINSTANCE, param: *const u8,
    ) -> HWND;
    pub fn DefWindowProcW(h: HWND, m: u32, w: usize, l: isize) -> isize;
    pub fn GetMessageW(msg: *mut MSG, h: HWND, min: u32, max: u32) -> i32;
    pub fn TranslateMessage(msg: *const MSG) -> i32;
    pub fn DispatchMessageW(msg: *const MSG) -> isize;
    pub fn PostQuitMessage(code: i32);
    pub fn LoadIconW(inst: HINSTANCE, nombre: usize) -> HICON;
    pub fn LoadImageW(inst: HINSTANCE, nombre: *const u16, tipo: u32,
                      cx: i32, cy: i32, carga: u32) -> isize;
    pub fn CreatePopupMenu() -> HMENU;
    pub fn AppendMenuW(menu: HMENU, flags: u32, id: usize, texto: *const u16) -> i32;
    pub fn DestroyMenu(menu: HMENU) -> i32;
    pub fn TrackPopupMenu(menu: HMENU, flags: u32, x: i32, y: i32,
                          reservado: i32, h: HWND, rect: *const u8) -> i32;
    pub fn SetForegroundWindow(h: HWND) -> i32;
    pub fn MessageBoxW(h: HWND, texto: *const u16, titulo: *const u16, tipo: u32) -> i32;
}

#[link(name = "shell32")]
extern "system" {
    pub fn Shell_NotifyIconW(mensaje: u32, datos: *const NOTIFYICONDATAW) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    pub fn GetModuleHandleW(nombre: *const u16) -> HINSTANCE;
}

/// Texto de Rust a cadena terminada en cero que entienda Windows.
pub fn ancho(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}
