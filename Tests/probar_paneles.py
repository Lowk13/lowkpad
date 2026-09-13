"""Integración real TCP/Win32. No muestra ni persiste texto previo ni claves."""
import ctypes as c
from ctypes import wintypes as w
import json, socket, time, tkinter as tk
import concurrent.futures, threading
from pathlib import Path

token = (Path.home() / 'Scripts/lowkpad/paneles.key').read_text().strip()
def peticion(op, **args):
    with socket.create_connection(('127.0.0.1',8787), timeout=4) as s:
        s.sendall((json.dumps(dict(token=token,op=op,**args),ensure_ascii=False)+'\n').encode())
        return json.loads(s.makefile('rb').readline())

results=[]
def check(name, condition):
    assert condition, name
    results.append({'test':name,'result':'PASS'})

u=c.windll.user32
u.SetProcessDpiAwarenessContext(c.c_void_p(-4))
u.SetWindowsHookExW.argtypes=[c.c_int,c.c_void_p,w.HINSTANCE,w.DWORD]
u.SetWindowsHookExW.restype=c.c_void_p
u.CallNextHookEx.argtypes=[c.c_void_p,c.c_int,w.WPARAM,w.LPARAM]
u.CallNextHookEx.restype=w.LPARAM
u.UnhookWindowsHookEx.argtypes=[c.c_void_p]
class Key(c.Structure):
    _fields_=[('vk',w.DWORD),('scan',w.DWORD),('flags',w.DWORD),('time',w.DWORD),('extra',c.c_size_t)]
events=[]
CALLBACK=c.WINFUNCTYPE(w.LPARAM,c.c_int,w.WPARAM,w.LPARAM)
@CALLBACK
def hook(code,msg,data):
    if code>=0:
        k=c.cast(data,c.POINTER(Key)).contents
        if 0xAD<=k.vk<=0xB3:
            events.append((k.vk,msg))
            return 1 # Verificar entrada multimedia sin cambiar reproducción/volumen reales.
    return u.CallNextHookEx(None,code,msg,data)

root=tk.Tk();root.title('LowkPad: prueba de teclado');root.geometry('640x400+200+200')
root.attributes('-topmost',True)
editor=tk.Text(root);editor.pack(expand=True,fill='both')
root.update();root.focus_force();editor.focus_set()
h=u.SetWindowsHookExW(13,hook,None,0)
assert h, 'No se pudo instalar el observador de prueba'
def pump(t=.1):
    until=time.monotonic()+t
    while time.monotonic()<until: root.update();time.sleep(.002)

pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
def orden(op, **args):
    future = pool.submit(peticion, op, **args)
    while not future.done(): pump(.01)
    return future.result()

# No sobrescribir un portapapeles previo con formatos ajenos a texto.
previo=orden('clipboard_get')
puede_clip=previo['ok'] and (u.CountClipboardFormats()<=4)
try:
    check('Servidor 0.3.0 confirmado',orden('status')['data']['version']=='0.3.0')
    with socket.create_connection(('127.0.0.1',8787),timeout=4) as s:
        s.sendall(b'{"token":"incorrecta","op":"clipboard_get"}\n')
        check('Clave incorrecta no permite leer texto',not json.loads(s.makefile('rb').readline())['ok'])
    sample='LowkPad: ñ á € 😀\nSegunda línea "texto" \\ fin'
    if puede_clip:
        check('Escritura de portapapeles',orden('clipboard_set',text=sample)['ok'])
        check('Lectura bidireccional Unicode exacta',orden('clipboard_get')['data']['text']==sample)
    else:
        results.append({'test':'Portapapeles previo no textual/mixto','result':'SKIP para conservarlo'})
    check('Rechaza texto mayor de 64 KB',not orden('text',text='x'*65537)['ok'])
    check('Rechaza órdenes ajenas a la lista',not orden('shell',text='test')['ok'])
    pump(.3)
    root.focus_force();editor.focus_set();pump(.1)
    check('Inyección de texto confirmada',orden('text',text=sample)['ok']);pump()
    check('Editor Windows recibe Unicode y saltos de línea',editor.get('1.0','end-1c')==sample)
    check('Borrar confirmado',orden('key',key='backspace')['ok']);pump()
    check('Borrar actúa en el editor',editor.get('1.0','end-1c')==sample[:-1])
    if puede_clip:
        editor.delete('1.0', 'end');editor.focus_set()
        check('Enviar y pegar confirmado',orden('clipboard_paste',text=sample)['ok']);pump()
        check('Pegado real en la ventana del PC',editor.get('1.0','end-1c')==sample)
    for name,vk in [('previous',0xB1),('next',0xB0),('play_pause',0xB3),('stop',0xB2),('volume_up',0xAF),('volume_down',0xAE),('mute',0xAD)]:
        respuesta=orden('key',key=name)
        check('Multimedia '+name, respuesta['ok'] and (vk,0x100) in events and (vk,0x101) in events)

finally:
    if puede_clip: orden('clipboard_set',text=previo['data']['text'])
    u.UnhookWindowsHookEx(h);root.destroy();pool.shutdown()
print(json.dumps(results,ensure_ascii=False,indent=2))
