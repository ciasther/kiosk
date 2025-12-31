pobranie:

```
wget https://raw.githubusercontent.com/ciasther/kiosk/main/scripts/kiosk-install-debian13.sh
```
prawa:
```
chmod +x kiosk-install-debian13.sh
```
instalacja:
```
sudo bash kiosk-install-debian13.sh
```
```
c6e65fa87f61e97a0db35329f3462cda081d0e390924c914
```

zmiana TID terminala:
```bash
sudo nano /home/kiosk/payment-terminal-service/.env
```
i tam zamienic 00000000 na wlasciwy TID urządzenia ingenico!
```
01100460
```
ctrl+o > enter > ctrl+x

```bash
sudo reboot
```
