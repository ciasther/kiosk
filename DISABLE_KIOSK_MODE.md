# Jak wyłączyć tryb Kiosk i wrócić do normalnego Ubuntu

**Czas**: 1 minuta  
**Dla**: Sytuacje gdy potrzebujesz dostępu do normalnego pulpitu Ubuntu

---

## 🚨 SZYBKA METODA (Z TTY)

Jeśli aplikacja kiosk już działa i nie możesz nic zrobić:

### Krok 1: Przełącz się na TTY

```
Naciśnij: Ctrl + Alt + F2
```

Zobaczysz czarny ekran z loginem tekstowym.

---

### Krok 2: Zaloguj się

```
login: kiosk
Password: 12345
```

(lub inne hasło jeśli zmieniłeś)

---

### Krok 3: Wyłącz service kiosk

```bash
sudo systemctl stop gastro-kiosk.service
sudo systemctl disable gastro-kiosk.service
```

**Co to robi**:
- `stop` - zatrzymuje aplikację TERAZ
- `disable` - wyłącza autostart (nie uruchomi się po restarcie)

---

### Krok 4: Wróć do GUI

```
Naciśnij: Ctrl + Alt + F7
```

(lub F1, zależnie od systemu)

Zobaczysz normalny pulpit Ubuntu!

---

## 💻 METODA PRZEZ SSH (Zdalnie)

Jeśli masz dostęp SSH z innego komputera:

```bash
# Połącz się
ssh kiosk@<IP_URZĄDZENIA>

# Wyłącz kiosk
sudo systemctl stop gastro-kiosk.service
sudo systemctl disable gastro-kiosk.service

# Restart display manager (opcjonalnie)
sudo systemctl restart lightdm
# lub
sudo systemctl restart gdm3
```

---

## 🔄 JAK PONOWNIE WŁĄCZYĆ KIOSK

### Metoda 1: Przez terminal

```bash
sudo systemctl enable gastro-kiosk.service
sudo systemctl start gastro-kiosk.service
```

### Metoda 2: Przez reboot

```bash
sudo systemctl enable gastro-kiosk.service
sudo reboot
```

---

## 🛠️ PEŁNE WYŁĄCZENIE (Maintenance Mode)

Jeśli chcesz normalnie używać komputera przez dłuższy czas:

### Opcja A: Tylko wyłącz service (zalecane)

```bash
sudo systemctl disable gastro-kiosk.service
sudo reboot
```

Po restarcie zobaczysz ekran logowania i normalny pulpit.

---

### Opcja B: Usuń service całkowicie (trwałe)

```bash
# Wyłącz service
sudo systemctl stop gastro-kiosk.service
sudo systemctl disable gastro-kiosk.service

# Usuń pliki service
sudo rm /etc/systemd/system/gastro-kiosk.service
sudo rm /usr/local/bin/gastro-kiosk-start.sh

# Reload systemd
sudo systemctl daemon-reload

# Reboot
sudo reboot
```

Po tym aplikacja kiosk nie będzie działać. Będziesz miał czysty Ubuntu.

**Aby przywrócić**: Uruchom ponownie `kiosk-install-v2.sh`

---

## 🖥️ CO SIĘ STANIE PO WYŁĄCZENIU

### Zostanie:
- ✅ Ubuntu (normalny system)
- ✅ LightDM lub GDM3 (display manager)
- ✅ Openbox lub GNOME (desktop environment)
- ✅ Użytkownik `kiosk` z hasłem
- ✅ VPN Tailscale (nadal połączony)
- ✅ Chromium (zainstalowany, możesz używać)

### Nie będzie:
- ❌ Auto-start aplikacji kiosk
- ❌ Fullscreen chromium
- ❌ Auto-restart na crash

### Po restarcie:
- Zobaczysz ekran logowania (login screen)
- Zaloguj się jako `kiosk` / `gastro2024`
- Zobaczysz normalny pulpit Ubuntu

---

## 📱 PRZYDATNE SCENARIUSZE

### Scenariusz 1: "Muszę zainstalować coś przez apt"

```bash
# TTY: Ctrl+Alt+F2
sudo systemctl stop gastro-kiosk.service

# Zainstaluj co potrzebujesz
sudo apt install PACKAGE_NAME

# Włącz z powrotem
sudo systemctl start gastro-kiosk.service
```

---

### Scenariusz 2: "Muszę skonfigurować WiFi"

```bash
# TTY: Ctrl+Alt+F2
sudo systemctl stop gastro-kiosk.service

# Ctrl+Alt+F7 (wróć do GUI)
# Otwórz Settings → WiFi
# Skonfiguruj

# TTY: Ctrl+Alt+F2
sudo systemctl start gastro-kiosk.service
```

---

### Scenariusz 3: "Chcę zmienić aplikację na inny URL"

```bash
# TTY: Ctrl+Alt+F2
sudo systemctl stop gastro-kiosk.service

# Edytuj startup script
sudo nano /usr/local/bin/gastro-kiosk-start.sh

# Znajdź linię:
# URL="https://100.64.0.7:3001?deviceId=..."
# Zmień URL na nowy

# Zapisz: Ctrl+X, Y, Enter

# Uruchom z powrotem
sudo systemctl start gastro-kiosk.service
```

---

### Scenariusz 4: "Chcę testować aplikację w normalnym Chromium"

```bash
# TTY: Ctrl+Alt+F2
sudo systemctl stop gastro-kiosk.service

# Ctrl+Alt+F7 (wróć do GUI)
# Otwórz Chromium normalnie (z menu)
# Wejdź na: https://100.64.0.7:3001?deviceId=kiosk01

# Testuj
# Możesz otworzyć DevTools (F12)
# Możesz używać myszy/klawiatury normalnie
```

---

### Scenariusz 5: "Coś nie działa, chcę debugować"

```bash
# TTY: Ctrl+Alt+F2
sudo systemctl stop gastro-kiosk.service

# Uruchom aplikację ręcznie (zobacz błędy)
/usr/local/bin/gastro-kiosk-start.sh

# Obserwuj logi w terminalu
# Naciśnij Ctrl+C aby zatrzymać

# Sprawdź logi
cat /var/log/gastro-kiosk-startup.log
journalctl -u gastro-kiosk.service -n 50
```

---

## 🔐 BEZPIECZEŃSTWO - Zmiana hasła

Po wyłączeniu kiosk mode, zmień hasło:

```bash
passwd
# Wpisz stare hasło: gastro2024
# Wpisz nowe hasło (2x)
```

---

## 🎛️ ZAAWANSOWANE: Zmiana Desktop Environment

### Z Openbox na GNOME (pełny desktop)

```bash
# Zainstaluj GNOME
sudo apt install -y ubuntu-desktop

# Przy następnym logowaniu:
# Kliknij ikonę koła zębatego (obok przycisku "Sign In")
# Wybierz: "Ubuntu" lub "GNOME"
```

### Z GNOME na Openbox (lekki WM)

```bash
# Przy logowaniu wybierz: "Openbox"
```

---

## 📋 CHECKLISTA - Wyłączanie Kiosk Mode

- [ ] Ctrl+Alt+F2 (przejdź na TTY)
- [ ] Zaloguj: kiosk / gastro2024
- [ ] `sudo systemctl stop gastro-kiosk.service`
- [ ] `sudo systemctl disable gastro-kiosk.service`
- [ ] Ctrl+Alt+F7 (wróć do GUI)
- [ ] Zobaczysz normalny pulpit
- [ ] (Opcjonalnie) Zmień hasło: `passwd`
- [ ] Zrób co potrzebujesz
- [ ] Aby włączyć z powrotem: `sudo systemctl enable gastro-kiosk.service && sudo reboot`

---

## ⚡ SKRÓTY KLAWISZOWE

```
Ctrl + Alt + F1 do F6  → TTY (terminal tekstowy)
Ctrl + Alt + F7 lub F1 → GUI (pulpit graficzny)
Ctrl + C               → Zatrzymaj program w terminalu
Ctrl + D               → Wyloguj z terminalu
```

---

## 🆘 CO JEŚLI NIE DZIAŁA?

### Problem: "Nie mogę się zalogować w TTY"

```
Możliwe przyczyny:
1. Złe hasło - spróbuj: gastro2024
2. Caps Lock włączony
3. Nieprawidłowa klawiatura (US vs PL)

Rozwiązanie:
- Reboot i trzymaj Shift podczas bootu
- Wybierz: Recovery Mode
- Wybierz: Root shell
- Zresetuj hasło: passwd kiosk
```

---

### Problem: "Service nie chce się zatrzymać"

```bash
# Force stop
sudo systemctl kill gastro-kiosk.service

# Sprawdź czy zatrzymany
systemctl status gastro-kiosk.service
# Powinno pokazać: inactive (dead)
```

---

### Problem: "Po wyłączeniu nadal widzę kiosk"

```bash
# Sprawdź czy service naprawdę wyłączony
systemctl status gastro-kiosk.service

# Sprawdź czy chromium nie działa z innego źródła
ps aux | grep chromium

# Zabij wszystkie chromium
pkill -9 chromium

# Restart display manager
sudo systemctl restart lightdm
# lub
sudo systemctl restart gdm3
```

---

## 📖 PODSUMOWANIE

### Wyłączenie kiosk (tymczasowe):
```bash
sudo systemctl stop gastro-kiosk.service
```

### Wyłączenie kiosk (trwałe, nie uruchomi się po restarcie):
```bash
sudo systemctl disable gastro-kiosk.service
```

### Ponowne włączenie:
```bash
sudo systemctl enable gastro-kiosk.service
sudo systemctl start gastro-kiosk.service
```

### Pełne usunięcie (jeśli chcesz czysty Ubuntu):
```bash
sudo systemctl disable gastro-kiosk.service
sudo rm /etc/systemd/system/gastro-kiosk.service
sudo rm /usr/local/bin/gastro-kiosk-start.sh
sudo systemctl daemon-reload
sudo reboot
```

---

## 🎓 TIP: Przydatne aliasy

Dodaj do `~/.bashrc`:

```bash
alias kiosk-stop='sudo systemctl stop gastro-kiosk.service'
alias kiosk-start='sudo systemctl start gastro-kiosk.service'
alias kiosk-status='systemctl status gastro-kiosk.service'
alias kiosk-disable='sudo systemctl disable gastro-kiosk.service'
alias kiosk-enable='sudo systemctl enable gastro-kiosk.service'
```

Później możesz używać:
```bash
kiosk-stop    # Zamiast sudo systemctl stop...
kiosk-start   # Zamiast sudo systemctl start...
```

---

**KONIEC INSTRUKCJI**

**Masz pytania? Sprawdź: `TROUBLESHOOTING_GUIDE.md`**
