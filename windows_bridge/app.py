"""Interfaz Windows: Firebase de la app → ensayo local, sin dinero real."""
import os
import queue
import threading
import uuid
from pathlib import Path
from engine import Ledger
from firebase_client import FirebaseClient, SportsDbResults
from worker import Worker

PROJECT = 'login-d2344'
API_KEY = 'AIzaSyDeCVnwUNW-wiBHM_n5lp3D8b6qZuRlKT4'  # Configuración pública, igual que firebase_options.dart.


def main():
    import tkinter as tk
    from tkinter import ttk
    root = tk.Tk()
    root.title('Apuesta a jornada · PC · SOLO SIMULACIÓN')
    root.geometry('660x420')
    root.minsize(530, 360)
    frame = ttk.Frame(root, padding=20)
    frame.pack(fill='both', expand=True)
    ttk.Label(frame, text='Conecta con tu cuenta de la APP', font=('', 15, 'bold')).pack(anchor='w')
    ttk.Label(frame, text='Usa el mismo correo y contraseña que en el móvil.\nNo introduzcas aquí las credenciales de Betfair.\nNo se realizan apuestas reales.', wraplength=600).pack(anchor='w', pady=10)
    email, password = tk.StringVar(), tk.StringVar()
    ttk.Label(frame, text='Correo de la app').pack(anchor='w')
    email_field = ttk.Entry(frame, textvariable=email)
    email_field.pack(fill='x')
    ttk.Label(frame, text='Contraseña de la app').pack(anchor='w', pady=(8, 0))
    password_field = ttk.Entry(frame, textvariable=password, show='•')
    password_field.pack(fill='x')
    status = tk.StringVar(value='Inicia sesión y autoriza una jornada desde el móvil.')
    ttk.Label(frame, textvariable=status, wraplength=600).pack(anchor='w', pady=15)
    stop, events = threading.Event(), queue.Queue()
    thread = None
    closing = False

    def run(mail, secret):
        ledger = lock_file = None
        try:
            client = FirebaseClient(PROJECT, API_KEY)
            client.sign_in(mail, secret)
            secret = None
            folder = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'ApuestaJornada' / client.uid
            folder.mkdir(parents=True, exist_ok=True)
            # Una única instancia por cuenta en este PC; el lease protege otros PCs.
            lock_file = (folder / 'bridge.lock').open('a+b')
            if os.name == 'nt':
                import msvcrt
                lock_file.seek(0)
                lock_file.write(b'0')
                lock_file.flush()
                lock_file.seek(0)
                try: msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
                except OSError: raise ValueError('Ya hay otra ventana de este programa usando esta cuenta.') from None
            agent_file = folder / 'agent.txt'
            agent = agent_file.read_text().strip() if agent_file.exists() else uuid.uuid4().hex
            agent_file.write_text(agent)
            ledger = Ledger(folder / 'ensayo.sqlite3')
            worker = Worker(client, ledger, SportsDbResults(), agent, should_stop=stop.is_set)
            events.put('Sesión iniciada. Esperando la autorización del móvil…')
            while not stop.is_set():
                try:
                    state = worker.tick()
                    events.put(state['message'])
                except Exception as error:
                    events.put(f'En espera, sin registrar nuevas apuestas: {error}')
                stop.wait(15)
        except Exception as error:
            events.put(f'No se pudo conectar: {error}')
        finally:
            if ledger: ledger.close()
            if lock_file: lock_file.close()
            events.put(None)

    def start():
        nonlocal thread
        if thread and thread.is_alive(): return
        mail, secret = email.get().strip(), password.get()
        if not mail or not secret:
            status.set('Introduce el correo y la contraseña de la app.')
            return
        stop.clear()
        password.set('')
        connect.configure(state='disabled')
        email_field.configure(state='disabled')
        password_field.configure(state='disabled')
        status.set('Conectando…')
        thread = threading.Thread(target=run, args=(mail, secret), daemon=True)
        thread.start()

    def halt():
        stop.set()
        status.set('Deteniendo el ensayo local. El último acceso de red puede tardar unos segundos.\nPara revocar el OK guardado, pulsa «Detener jornada» en el móvil.')

    def close():
        nonlocal closing
        closing = True
        halt()
        root.title('Deteniendo…')
        if not thread or not thread.is_alive(): root.destroy()

    connect = ttk.Button(frame, text='Conectar PC', command=start)
    connect.pack(side='left', anchor='s')
    ttk.Button(frame, text='Detener PC', command=halt).pack(side='right', anchor='s')

    def poll():
        while not events.empty():
            message = events.get_nowait()
            if message is None:
                connect.configure(state='normal')
                email_field.configure(state='normal')
                password_field.configure(state='normal')
            else: status.set(message)
        if closing and (not thread or not thread.is_alive()):
            root.destroy()
            return
        root.after(200, poll)
    root.protocol('WM_DELETE_WINDOW', close)
    root.after(200, poll)
    root.mainloop()


if __name__ == '__main__':
    main()
