ethernet terminal lokalnie

Otwórz terminal i wpisz 
`nm-connection-editor` 
zainstaluj

jeśli brak: 
`sudo apt install network-manager-gnome`
Pojawi się okno z listą połączeń – kliknij “+” aby dodać nowe lub edytuj istniejące połączenie Ethernet (np. “Wired connection 1”).

W zakładce “IPv4 Settings”:
  Metoda: wybierz “Shared to other computers” (Udostępnione innym komputerom).
  Zapisz zmiany (Ctrl+S lub przycisk).
To automatycznie uruchomi dnsmasq dla DHCP, iptables/nftables dla NAT i włączy forwarding 