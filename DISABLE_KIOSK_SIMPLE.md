# Jak wyłączyć Kiosk - PROSTY SPOSÓB

**Metoda**: Zmiana użytkownika w auto-login  
**Czas**: 30 sekund  
**Rezultat**: Zamiast aplikacji kiosk - normalny pulpit Ubuntu

---

## 🚀 NAJSZYBSZA METODA

### LightDM (jeśli używasz LightDM)

```bash
# 1. TTY: Ctrl+Alt+F2
# 2. Zaloguj: kiosk / gastro2024

# 3. Wyłącz auto-login użytkownika 'kiosk'
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf
```

**Zmień**:
```ini
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
```

**Na** (zakomentuj linię):
```ini
[Seat:*]
#autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
```

**Zapisz**: Ctrl+X, Y, Enter

```bash
# 4. Reboot
sudo reboot
```

**Po restarcie**: Zobaczysz ekran logowania. Zaloguj się jako `kiosk` i masz normalny pulpit!

---

### GDM3 (jeśli używasz GDM3)

```bash
# 1. TTY: Ctrl+Alt+F2
# 2. Zaloguj: kiosk / gastro2024

# 3. Wyłącz auto-login
sudo nano /etc/gdm3/custom.conf
```

**Zmień**:
```ini
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = kiosk
```

**Na** (zakomentuj):
```ini
[daemon]
#AutomaticLoginEnable = true
#AutomaticLogin = kiosk
```

**LUB** zmień użytkownika na innego:
```ini
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = twoj_user  # Zmień na istniejącego użytkownika (nie 'kiosk')
```

**Zapisz**: Ctrl+X, Y, Enter

```bash
# 4. Reboot
sudo reboot
```

---

## 💡 ALTERNATYWA: Stwórz drugiego użytkownika

Jeśli chcesz mieć **dwa konta**:
- `kiosk` - tylko dla aplikacji kiosk
- `admin` - dla normalnej pracy

```bash
# 1. Stwórz nowego użytkownika
sudo adduser admin
sudo usermod -aG sudo admin

# 2. Zmień auto-login na 'admin'
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf
```

Zmień:
```ini
autologin-user=admin
```

```bash
# 3. Reboot
sudo reboot
```

**Po restarcie**: Zaloguje się jako `admin`, normalny pulpit Ubuntu.

**Aby wrócić do kiosk**: Zmień z powrotem `autologin-user=kiosk`

---

## 🎯 CO SIĘ DZIEJE

### Gdy auto-login = kiosk:
```
Boot → LightDM → Auto-login jako 'kiosk' 
  → Openbox
  → systemd service (gastro-kiosk.service)
  → Chromium fullscreen
  → Aplikacja kiosk
```

### Gdy auto-login wyłączony:
```
Boot → LightDM → Ekran logowania
  → Logujesz się ręcznie jako 'kiosk'
  → Openbox
  → systemd service (gastro-kiosk.service) NADAL DZIAŁA!
  → Chromium fullscreen
  → Aplikacja kiosk
```

**PROBLEM**: Service nadal uruchamia aplikację!

---

## 🛠️ PEŁNE ROZWIĄZANIE (Service + Auto-login)

Aby naprawdę wyłączyć kiosk i mieć normalny pulpit:

### Metoda A: Wyłącz service + wyłącz auto-login

```bash
# 1. Wyłącz service
sudo systemctl disable gastro-kiosk.service

# 2. Wyłącz auto-login (zakomentuj autologin-user)
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf
# Zakomentuj: #autologin-user=kiosk

# 3. Reboot
sudo reboot
```

**Po restarcie**: Ekran logowania, zaloguj się, normalny pulpit bez aplikacji kiosk.

---

### Metoda B: Stwórz drugiego użytkownika + ustaw jako auto-login

```bash
# 1. Stwórz użytkownika 'admin' (bez kiosk service)
sudo adduser admin
sudo usermod -aG sudo admin

# 2. Zmień auto-login na 'admin'
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf
# Zmień: autologin-user=admin

# 3. Reboot
sudo reboot
```

**Po restarcie**: Auto-login jako `admin`, normalny pulpit.

**Kiosk service** działa tylko dla użytkownika `kiosk`, więc `admin` go nie zobaczy!

---

### Metoda C: Tylko zmień session (najprostsze!)

Jeśli chcesz zachować użytkownika `kiosk` ale bez aplikacji:

```bash
# 1. Wyłącz tylko service
sudo systemctl disable gastro-kiosk.service

# 2. Reboot
sudo reboot
```

**Po restarcie**: Auto-login jako `kiosk`, ale BEZ aplikacji kiosk. Normalny pulpit Openbox.

Aby włączyć z powrotem:
```bash
sudo systemctl enable gastro-kiosk.service
sudo reboot
```

---

## 📊 PORÓWNANIE METOD

| Metoda | Czas | Zmiana auto-login | Wyłącz service | Użytkownicy | Łatwość powrotu |
|--------|------|-------------------|----------------|-------------|----------------|
| **A: Wyłącz auto-login** | 1 min | Zakomentuj | NIE | 1 (kiosk) | Łatwy |
| **B: Drugi użytkownik** | 2 min | Zmień na admin | Nie dotyczy | 2 (kiosk + admin) | Bardzo łatwy |
| **C: Tylko wyłącz service** | 30s | NIE | TAK | 1 (kiosk) | Bardzo łatwy |

**Rekomendacja**: **Metoda B** (drugi użytkownik)

---

## 🎓 ZALECANA KONFIGURACJA

### Dla produkcji:

**2 użytkowników**:
- `kiosk` - tylko dla aplikacji kiosk (auto-login gdy potrzebujesz kiosk)
- `admin` - dla zarządzania systemem (auto-login gdy potrzebujesz normalnego pulpitu)

**Setup**:
```bash
# Raz na zawsze:
sudo adduser admin
sudo usermod -aG sudo admin

# Przełączanie:
# Chcesz kiosk?
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf
# autologin-user=kiosk

# Chcesz normalny pulpit?
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf
# autologin-user=admin

# Po każdej zmianie:
sudo reboot
```

---

## ⚡ SUPER SZYBKI SPOSÓB (Alias)

Dodaj do `~/.bashrc`:

```bash
alias kiosk-mode='sudo sed -i "s/autologin-user=.*/autologin-user=kiosk/" /etc/lightdm/lightdm.conf.d/50-autologin.conf && echo "Kiosk mode enabled. Reboot to apply."'

alias normal-mode='sudo sed -i "s/autologin-user=.*/autologin-user=admin/" /etc/lightdm/lightdm.conf.d/50-autologin.conf && echo "Normal mode enabled. Reboot to apply."'
```

**Użycie**:
```bash
# Włącz kiosk mode
kiosk-mode
sudo reboot

# Włącz normal mode
normal-mode
sudo reboot
```

---

## 🔄 SKRYPT AUTO-PRZEŁĄCZANIA

Stwórz skrypt `/usr/local/bin/toggle-kiosk.sh`:

```bash
#!/bin/bash

if ! [ $(id -u) = 0 ]; then
   echo "Run as sudo!"
   exit 1
fi

CONF="/etc/lightdm/lightdm.conf.d/50-autologin.conf"
CURRENT=$(grep "autologin-user=" "$CONF" | grep -v "^#" | cut -d'=' -f2)

if [ "$CURRENT" = "kiosk" ]; then
    echo "Switching to NORMAL mode (user: admin)"
    sed -i "s/autologin-user=kiosk/autologin-user=admin/" "$CONF"
    echo "✓ Normal mode enabled"
else
    echo "Switching to KIOSK mode (user: kiosk)"
    sed -i "s/autologin-user=admin/autologin-user=kiosk/" "$CONF"
    echo "✓ Kiosk mode enabled"
fi

echo ""
read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
else
    echo "Changes will apply after next reboot"
fi
```

**Uprawnienia**:
```bash
sudo chmod +x /usr/local/bin/toggle-kiosk.sh
```

**Użycie**:
```bash
sudo toggle-kiosk.sh
# Automatycznie przełącza między kiosk a admin
```

---

## 📝 PODSUMOWANIE

### Najprostszy sposób na wyłączenie kiosk:

**Opcja 1** (jeśli masz już użytkownika `admin`):
```bash
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf
# Zmień: autologin-user=admin
sudo reboot
```

**Opcja 2** (jeśli nie masz użytkownika `admin`):
```bash
sudo systemctl disable gastro-kiosk.service
sudo reboot
```

**Opcja 3** (stwórz użytkownika `admin` - raz na zawsze):
```bash
sudo adduser admin
sudo usermod -aG sudo admin
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf
# Zmień: autologin-user=admin
sudo reboot
```

---

**Która metoda Ci najbardziej odpowiada?** 

A) Tylko wyłączenie service (systemctl disable)  
B) Drugi użytkownik (kiosk + admin)  
C) Skrypt toggle (przełączanie jedną komendą)  
D) Coś innego?
