"""Integración con UDP y Win32 reales, clics dirigidos a una ventana de prueba."""
import ctypes, json, socket, statistics, time, tkinter as tk
from ctypes import wintypes

u = ctypes.windll.user32
u.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
original = wintypes.POINT()
u.GetCursorPos(ctypes.byref(original))
root = tk.Tk()
root.title('LowkPad: prueba de entrada')
root.geometry('640x400+200+200')
root.attributes('-topmost', True)
clicks = []
root.bind('<ButtonPress-1>', lambda e: clicks.append('down'))
root.bind('<ButtonRelease-1>', lambda e: clicks.append('up'))
root.update()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(1)
state = dict(t='m', ses=8765432, s=1, tm=0, x=0, y=0, sx=0, sy=0, b=0, ci=0, cb='l')
results = []

def pump(seconds=.03):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        root.update()
        time.sleep(.002)

def raw(obj):
    s.sendto(json.dumps(obj, separators=(',', ':')).encode(), ('127.0.0.1', 8788))

def send(**changes):
    state.update(s=state['s']+1, tm=state['tm']+10)
    state.update(changes)
    raw(state)
    pump()

def pos():
    p = wintypes.POINT(); u.GetCursorPos(ctypes.byref(p)); return p.x, p.y

def check(name, ok, detail=''):
    assert ok, (name, detail)
    results.append(dict(test=name, result='PASS', detail=detail))

try:
    raw(dict(t='cfg', cfg=dict(gain=1, accel=False)))
    u.SetCursorPos(450, 400); pump()
    send()
    base = pos()
    send(x=40)
    check('Movimiento absoluto sin aceleracion', pos() == (base[0]+40, base[1]), str((base, pos())))
    raw(dict(state, s=state['s']-1, x=999)); pump()
    check('Descarta paquetes atrasados', pos() == (base[0]+40, base[1]))
    send(x=100)  # las muestras intermedias se pierden
    check('Recupera movimiento acumulado con perdida', pos() == (base[0]+100, base[1]))
    for i in range(1, 11): send(x=100+i*.1)
    check('Conserva precision subpixel', pos() == (base[0]+101, base[1]), str((base, pos())))
    send(ci=1); raw(state); pump()
    check('Clic real y deduplicacion', clicks == ['down', 'up'], str(clicks))
    send(ci=2); send(b=1); pump(.08)
    check('Clic seguido de arrastre no se suelta', bool(u.GetAsyncKeyState(1) & 0x8000))
    raw(dict(t='ping', p=77)); pump()
    check('Diagnostico no interrumpe arrastre', bool(u.GetAsyncKeyState(1) & 0x8000))
    s.recvfrom(2048)
    pump(2.2)
    check('Desconexion libera boton sin mas paquetes', not (u.GetAsyncKeyState(1) & 0x8000))
    send(b=0, x=10000)
    check('Reconectar no reproduce movimiento antiguo', pos() == (base[0]+101, base[1]), str((base, pos())))
    times=[]
    for i in range(100):
        start=time.perf_counter(); raw(dict(t='ping',p=i))
        reply=json.loads(s.recvfrom(2048)[0]); assert reply['p']==i
        times.append((time.perf_counter()-start)*1000)
    check('100 ecos UDP validos', True, f'mediana={statistics.median(times):.3f} ms; p95={sorted(times)[94]:.3f} ms (loopback)')
finally:
    send(b=0)
    raw(dict(t='cfg',cfg=dict(gain=1.8,accel=True)))
    u.SetCursorPos(original.x, original.y)
    root.destroy(); s.close()
print(json.dumps(results, indent=2, ensure_ascii=False))


