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
92a7f70bf36fd975cd1163d7ae73bbb8dd6bc4060de5d0e5
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
