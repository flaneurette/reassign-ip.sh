#!/bin/bash
# sudo chmod +x reassign-ip.sh
# Reassign a new master IP, revokes the old one.
# This is useful, in case your(dynamic) IP changes
# To find the chain name: sudo iptables -L -n -v --line-numbers
# To find IP: sudo iptables -L -n -v --line-numbers | grep 100.2.3.4
# Notice: this script removes UFW.
# Notice: line prevents script from running suddenly. You MUST manually remove/uncomment this line:
# exit 1

# Root check.
if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

# Edit these before running.

# To find the chain name: sudo iptables -L -n -v --line-numbers
CHAIN="INPUT" # important, must match!
# Old IP to revoke access
# OLD_IP="2.2.2.2"
# New IP
NEW_IP="4.4.4.4"
SERVER_IP="1.1.1.1"
TAIL_IP="100.64.0.2"
# Ports the NEW IP is allowed to connect to:
PORTS_TCP=(22 25 80 443 587 993 8080 8085 8443)
PORTS_TCPDROP=(22 110 143 465 587 993 995 8080 8085 8443)
PORTS_UDP=(8080 8085 8443)

# Flush chain
iptables -F $CHAIN

# Restore ipsets first - iptables rules may depend on these sets existing
if [ -f /etc/iptables/ipsets.conf ]; then
    ipset restore -exist < /etc/iptables/ipsets.conf 2>&1
fi

# Delete old rules
#for p in "${PORTS_TCP[@]}"; do
#  sudo iptables -D $CHAIN -s $OLD_IP -p tcp --dport $p -j ACCEPT 2>/dev/null
#done
#for p in "${PORTS_UDP[@]}"; do
#  sudo iptables -D $CHAIN -s $OLD_IP -p udp --dport $p -j ACCEPT 2>/dev/null
#done

# Add new IP rules to INPUT chain. (recommended)
for p in "${PORTS_TCP[@]}"; do
  sudo iptables -A $CHAIN -s $NEW_IP -p tcp --dport $p -j ACCEPT
done
for p in "${PORTS_UDP[@]}"; do
  sudo iptables -A $CHAIN -s $NEW_IP -p udp --dport $p -j ACCEPT
done

# Add new SERVER rules to INPUT chain. (recommended)
for p in "${PORTS_TCP[@]}"; do
  sudo iptables -A $CHAIN -s $SERVER_IP -p tcp --dport $p -j ACCEPT
done
for p in "${PORTS_UDP[@]}"; do
  sudo iptables -A $CHAIN  -s $SERVER_IP -p udp --dport $p -j ACCEPT
done

# Add new second IP  rules to INPUT chain. (recommended)
#for p in "${PORTS_TCP[@]}"; do
#  sudo iptables -A $CHAIN  -s $NEW_IP2 -p tcp --dport $p -j ACCEPT
#done
#for p in "${PORTS_UDP[@]}"; do
#  sudo iptables -A $CHAIN -s $NEW_IP2 -p udp --dport $p -j ACCEPT
#done

# drop for all others
for p in "${PORTS_TCPDROP[@]}"; do
  sudo iptables -A $CHAIN -p tcp --dport $p -j DROP
done
for p in "${PORTS_UDP[@]}"; do
  sudo iptables -A $CHAIN -p udp --dport $p -j DROP
done

# Tail homepc
sudo iptables -A $CHAIN -s $TAIL_IP -p tcp --dport 22 -j ACCEPT

sudo iptables -A $CHAIN -i tailscale0 -p tcp --dport 22 -j ACCEPT
# sudo iptables -A $CHAIN -i tailscale0 -p tcp --dport 25 -j ACCEPT

sudo iptables -A $CHAIN -p tcp --dport 25 -j ACCEPT
sudo iptables -A $CHAIN -p tcp --dport 80 -j ACCEPT
sudo iptables -A $CHAIN -p tcp --dport 443  -j ACCEPT

sudo iptables -I $CHAIN 2 -s 203.0.113.99 -m comment --comment "CANARY-ADMIN" -j DROP

#Change default policy to drop.
sudo iptables -P $CHAIN DROP
sudo iptables -P FORWARD DROP
sudo iptables -F FORWARD
sudo iptables -F OUTPUT
sudo iptables -A $CHAIN -m state --state ESTABLISHED,RELATED -j ACCEPT

# Tailscale
sudo iptables -A FORWARD -i tailscale0 -o ens6 -j ACCEPT
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# Loopback
sudo iptables -I INPUT -i lo -j ACCEPT

# MUST EXIST!
sudo iptables -I INPUT 1 -j ts-input
sudo iptables -I INPUT 2 -j ts-forward

# Optional TCP:
sudo iptables -I INPUT -i lo -p tcp --dport 53 -j ACCEPT
sudo iptables -I OUTPUT -p tcp --dport 53 -j ACCEPT

# Let tailscale rebuild chains
# sudo systemctl restart tailscaled

# DNS
# UDP first:
sudo iptables -I INPUT -i lo -p udp --dport 53 -j ACCEPT

# OUTPUT
sudo iptables -P OUTPUT DROP
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 41641 -j ACCEPT
sudo iptables -A OUTPUT -o tailscale0 -j ACCEPT
sudo iptables -A OUTPUT -p icmp -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 67 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 68 -j ACCEPT
# sudo iptables -A OUTPUT -j LOG --log-prefix "OUTPUT DROP: " --log-level 4
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 25 -j ACCEPT
sudo iptables -A OUTPUT -s $TAIL_IP -p tcp --dport 22 -j ACCEPT
# Whois
sudo iptables -A OUTPUT -p tcp --dport 43 -j ACCEPT

# Restart fail2ban, to make sure it uses its chains.
sudo systemctl restart fail2ban

sleep 5

iptables-save > /etc/iptables/rules.v4

echo "Firewall rules updated successfully."
echo "Now run: sudo systemctl restart tailscaled "
