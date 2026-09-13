"""TCP persistente, escritura progresiva y movimiento real de una ventana propia."""
import ctypes as c
from ctypes import wintypes as w
import concurrent.futures, json, socket, statistics, time, tkinter as tk
from pathlib import Path

token=(Path.home()/'Scripts/lowkpad/paneles.key').read_text().strip()
u=c.windll.user32
u.SetProcessDpiAwarenessContext(c.c_void_p(-4))
u.GetAncestor.argtypes=[w.HWND,w.UINT];u.GetAncestor.restype=w.HWND
u.MonitorFromWindow.argtypes=[w.HWND,w.DWORD];u.MonitorFromWindow.restype=w.HANDLE
u.GetForegroundWindow.restype=w.HWND
root=tk.Tk();root.title('LowkPad: escritura y monitores');root.geometry('600x320+200+200')
editor=tk.Text(root);editor.pack(fill='both',expand=True)
root.update();root.focus_force();editor.focus_set()
hwnd=u.GetAncestor(editor.winfo_id(),2)
pool=concurrent.futures.ThreadPoolExecutor(max_workers=1)
s=socket.create_connection(('127.0.0.1',8787),timeout=4)
s.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
reader=s.makefile('rb')
results=[]
def check(name,condition,detail=''):
    assert condition,(name,detail)
    results.append(dict(test=name,result='PASS',detail=detail))
def pump(t=.03):
    until=time.monotonic()+t
    while time.monotonic()<until:root.update();time.sleep(.002)
def request(op,**args):
    s.sendall((json.dumps(dict(token=token,op=op,**args),ensure_ascii=False)+'\n').encode())
    return json.loads(reader.readline())
def send(op,**args):
    f=pool.submit(request,op,**args)
    while not f.done():pump(.005)
    value=f.result();assert value['ok'],value.get('error');pump()
    return value
try:
    pump(.3);root.focus_force();editor.focus_set();pump(.1)
    check('Ventana de prueba enfocada',u.GetForegroundWindow()==hwnd)
    send('status')
    written=''
    for letter in 'hola ñá':
        send('text',text=letter);written+=letter
        check('Letra reflejada inmediatamente '+str(len(written)),editor.get('1.0','end-1c')==written)
    send('key',key='backspace');written=written[:-1]
    check('Borrado remoto inmediato',editor.get('1.0','end-1c')==written)
    send('key',key='enter');written+='\n'
    check('Intro remoto inmediato',editor.get('1.0','end-1c')==written)
    send('text',text='😀');written+='😀'
    check('Emoji por el mismo canal',editor.get('1.0','end-1c')==written)
    def burst():
        times=[]
        for _ in range(100):
            start=time.perf_counter();response=request('text',text='a')
            assert response['ok'];times.append((time.perf_counter()-start)*1000)
        return times
    f=pool.submit(burst)
    while not f.done():pump(.005)
    times=f.result();pump()
    check('100 letras sin perder ni duplicar en una conexion',editor.get('1.0','end-1c')==written+'a'*100,
          f'RTT loopback mediana={statistics.median(times):.3f}ms; p95={sorted(times)[94]:.3f}ms')
    # Otra conexión responde mientras la primera permanece abierta.
    with socket.create_connection(('127.0.0.1',8787),timeout=2) as other:
        other.sendall((json.dumps(dict(token=token,op='status'))+'\n').encode())
        check('Una conexion persistente no bloquea otros paneles',json.loads(other.makefile('rb').readline())['ok'])
    send('shortcut',name='select_all')
    check('Ctrl+A selecciona texto en Windows',bool(editor.tag_ranges('sel')))
    send('text',text='reemplazado')
    check('Escribir sustituye la seleccion del PC',editor.get('1.0','end-1c')=='reemplazado')
    if u.GetSystemMetrics(80)>=2:
        original=u.MonitorFromWindow(hwnd,2)
        send('shortcut',name='monitor_right');pump(.5)
        siguiente=u.MonitorFromWindow(hwnd,2)
        check('Win Mayus derecha mueve la ventana a otro monitor',siguiente!=original)
        send('shortcut',name='monitor_left');pump(.5)
        check('Win Mayus izquierda devuelve la ventana',u.MonitorFromWindow(hwnd,2)==original)
    else: results.append(dict(test='Movimiento real entre monitores',result='SKIP: solo un monitor conectado'))
    check('No quedan Ctrl Mayus Alt ni Win pulsados',all(not (u.GetAsyncKeyState(k)&0x8000) for k in [0x10,0x11,0x12,0x5B]))
finally:
    reader.close();s.close();pool.shutdown();root.destroy()
print(json.dumps(results,ensure_ascii=False,indent=2))
