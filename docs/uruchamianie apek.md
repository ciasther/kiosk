Uruchamianie aplikacji React + Node.js na Ubuntu

Oto kompleksowy przewodnik jak uruchomić Twoją aplikację w trybie produkcyjnym z automatycznym startem w pełnoekranowym Chromium.​



Przygotowanie buildu React

W folderze frontend zbuduj wersję produkcyjną:



bash

cd frontend

npm run build

To utworzy katalog build ze zoptymalizowanymi plikami statycznymi gotowymi do serwowania.​



Uruchamianie backendu Node.js

Dla backendu najlepiej użyć PM2, który zapewnia automatyczne restarty i zarządzanie procesem:​



bash

\# Instalacja PM2 globalnie

sudo npm install -g pm2



\# Uruchomienie backendu

cd backend

pm2 start server.js --name "bakery-backend"



\# Zapisanie konfiguracji PM2 do autostartu

pm2 save

pm2 startup

Serwowanie frontendu React

Zainstaluj serve do hostowania buildu React:



bash

sudo npm install -g serve

cd frontend

pm2 serve build 3000 --spa --name "bakery-frontend"

pm2 save

Uruchamianie Chromium w trybie kiosk

Chromium z flagą --kiosk uruchomi się w pełnym ekranie bez interfejsu przeglądarki:​



bash

chromium-browser --kiosk --noerrdialogs --disable-infobars --no-first-run --disable-restore-session-state --app=http://localhost:3000

Automatyzacja przez systemd

Stwórz serwis systemd w /etc/systemd/system/bakery-kiosk.service:​



text

\[Unit]

Description=Bakery Kiosk Application

After=graphical.target



\[Service]

Type=simple

User=twoja\_nazwa\_użytkownika

Environment=DISPLAY=:0

Environment=WAYLAND\_DISPLAY=wayland-0

ExecStart=/usr/bin/chromium-browser --kiosk --noerrdialogs --disable-infobars --no-first-run --app=http://localhost:3000

Restart=always

RestartSec=5



\[Install]

WantedBy=graphical.target

Aktywuj serwis:



bash

sudo systemctl daemon-reload

sudo systemctl enable bakery-kiosk.service

sudo systemctl start bakery-kiosk.service

Powrót do Gnome

Aby przełączyć się z kiosku na pulpit Gnome:



Naciśnij Ctrl + Alt + F3 (wejście do terminala tekstowego)



Zaloguj się swoim loginem



Wykonaj:



bash

sudo systemctl stop bakery-kiosk.service

Wróć do trybu graficznego: Ctrl + Alt + F1 lub Ctrl + Alt + F2



Zaloguj się na Gnome normalnie



Aby ponownie uruchomić kiosk:



bash

sudo systemctl start bakery-kiosk.service

Sprawdzanie statusu

bash

\# Status aplikacji

pm2 status

pm2 logs bakery-backend

pm2 logs bakery-frontend



\# Status serwisu kiosku

sudo systemctl status bakery-kiosk.service

Ta konfiguracja zapewnia automatyczne uruchamianie przy starcie systemu, restarty po awariach i łatwe zarządzanie aplikacją.​

