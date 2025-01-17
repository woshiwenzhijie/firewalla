#!/bin/bash

if [[ -e /.dockerenv ]]; then
    #Disable iptables in docker
    /home/pi/firewalla/scripts/flush_iptables.sh
    exit
fi

BLACK_HOLE_IP="198.51.100.99"
BLUE_HOLE_IP="198.51.100.100"

sudo which ipset &>/dev/null || sudo apt-get install -y ipset

sudo ipset create blocked_ip_set hash:ip family inet hashsize 128 maxelem 65536 &>/dev/null
sudo ipset create blocked_domain_set hash:ip family inet hashsize 128 maxelem 65536 &>/dev/null
sudo ipset create blocked_net_set hash:net family inet hashsize 128 maxelem 65536 &>/dev/null
sudo ipset create blocked_ip_port_set hash:ip,port family inet hashsize 128 maxelem 65536 &>/dev/null
sudo ipset create blocked_mac_set hash:mac &>/dev/null
sudo ipset create trusted_ip_set hash:net family inet hashsize 128 maxelem 65536 &> /dev/null
sudo ipset create monitored_ip_set hash:ip family inet hashsize 128 maxelem 65536 &> /dev/null
sudo ipset create devicedns_mac_set hash:mac &>/dev/null
sudo ipset create protected_ip_set hash:ip family inet hashsize 128 maxelem 65536 &> /dev/null
sudo ipset create whitelist_ip_set hash:ip family inet hashsize 128 maxelem 65536 &> /dev/null
sudo ipset create whitelist_domain_set hash:ip family inet hashsize 128 maxelem 65536 &> /dev/null
sudo ipset create whitelist_net_set hash:ip family inet hashsize 128 maxelem 65536 &> /dev/null
sudo ipset create whitelist_ip_port_set hash:ip,port family inet hashsize 128 maxelem 65535 &>/dev/null
sudo ipset create whitelist_mac_set hash:mac &>/dev/null
sudo ipset create no_dns_caching_mac_set hash:mac &>/dev/null

# This is to ensure all ipsets are empty when initializing
sudo ipset flush blocked_ip_set
sudo ipset flush blocked_domain_set
sudo ipset flush blocked_net_set
sudo ipset flush blocked_ip_port_set
sudo ipset flush blocked_mac_set
sudo ipset flush trusted_ip_set
sudo ipset flush monitored_ip_set
sudo ipset flush devicedns_mac_set
sudo ipset flush protected_ip_set
sudo ipset flush whitelist_ip_set
sudo ipset flush whitelist_domain_set
sudo ipset flush whitelist_net_set
sudo ipset flush whitelist_ip_port_set
sudo ipset flush whitelist_mac_set
sudo ipset flush no_dns_caching_mac_set

sudo ipset add -! blocked_ip_set $BLACK_HOLE_IP
sudo ipset add -! blocked_ip_set $BLUE_HOLE_IP

# This is to remove all customized ip sets, to have a clean start
for set in `sudo ipset list -name | egrep "^c_"`; do
  sudo ipset destroy -! $set
done

# This is to remove all vpn client ip sets  
for set in `sudo ipset list -name | egrep "^vpn_client_"`; do
  sudo ipset destroy -! $set
done

sudo ip rule flush
sudo ip rule add pref 0 from all lookup local
sudo ip rule add pref 32766 from all lookup main
sudo ip rule add pref 32767 from all lookup default

# multi protocol block chain
sudo iptables -w -N FW_DROP &>/dev/null
sudo iptables -w -F FW_DROP
sudo iptables -w -C FW_DROP -p tcp -j REJECT &>/dev/null || sudo iptables -w -A FW_DROP -p tcp -j REJECT
sudo iptables -w -C FW_DROP -p all -j DROP &>/dev/null || sudo iptables -w -A FW_DROP -p all -j DROP

#FIXME: ignore if failed or not
sudo iptables -w -N FW_BLOCK &>/dev/null
sudo iptables -w -F FW_BLOCK

# return everything
sudo iptables -w -C FW_BLOCK -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j RETURN &>/dev/null || sudo iptables -w -A FW_BLOCK -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j RETURN

sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_ip_set dst -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_ip_set dst -j FW_DROP
sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_ip_set src -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_ip_set src -j FW_DROP
sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_domain_set dst -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_domain_set dst -j FW_DROP
sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_domain_set src -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_domain_set src -j FW_DROP
sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_net_set dst -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_net_set dst -j FW_DROP
sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_net_set src -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_net_set src -j FW_DROP
sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_ip_port_set dst,dst -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_ip_port_set dst,dst -j FW_DROP
sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_mac_set dst -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_mac_set dst -j FW_DROP
sudo iptables -w -C FW_BLOCK -p all -m set --match-set blocked_mac_set src -j FW_DROP &>/dev/null || sudo iptables -w -I FW_BLOCK -p all -m set --match-set blocked_mac_set src -j FW_DROP

# forward to fw_block
sudo iptables -w -C FORWARD -p all -j FW_BLOCK &>/dev/null || sudo iptables -w -A FORWARD -p all -j FW_BLOCK

# clear whitelist mark on dns packet in mangle table
sudo iptables -w -t mangle -C PREROUTING -p tcp -m tcp --dport 53 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -p tcp -m tcp --dport 53 -j CONNMARK --set-xmark 0x0/0x1
sudo iptables -w -t mangle -C PREROUTING -p tcp -m tcp --sport 53 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -p tcp -m tcp --sport 53 -j CONNMARK --set-xmark 0x0/0x1
sudo iptables -w -t mangle -C PREROUTING -p udp -m udp --dport 53 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -p udp -m udp --dport 53 -j CONNMARK --set-xmark 0x0/0x1
sudo iptables -w -t mangle -C PREROUTING -p udp -m udp --sport 53 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -p udp -m udp --sport 53 -j CONNMARK --set-xmark 0x0/0x1
# clear whitelist mark on dhcp packet in mangle table
sudo iptables -w -t mangle -C PREROUTING -p tcp -m tcp --dport 67 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -p tcp -m tcp --dport 67 -j CONNMARK --set-xmark 0x0/0x1
sudo iptables -w -t mangle -C PREROUTING -p tcp -m tcp --sport 67 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -p tcp -m tcp --sport 67 -j CONNMARK --set-xmark 0x0/0x1
sudo iptables -w -t mangle -C PREROUTING -p udp -m udp --dport 67 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -p udp -m udp --dport 67 -j CONNMARK --set-xmark 0x0/0x1
sudo iptables -w -t mangle -C PREROUTING -p udp -m udp --sport 67 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -p udp -m udp --sport 67 -j CONNMARK --set-xmark 0x0/0x1
# clear whitelist mark on local subnet traffic in mangle table
sudo iptables -w -t mangle -C PREROUTING -m set --match-set trusted_ip_set src -m set --match-set trusted_ip_set dst -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -m set --match-set trusted_ip_set src -m set --match-set trusted_ip_set dst -j CONNMARK --set-xmark 0x0/0x1
# clear whitelist mark on established connections in mangle table
sudo iptables -w -t mangle -C PREROUTING -m conntrack --ctstate RELATED,ESTABLISHED -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo iptables -w -t mangle -A PREROUTING -m conntrack --ctstate RELATED,ESTABLISHED -j CONNMARK --set-xmark 0x0/0x1

sudo iptables -w -N FW_WHITELIST &> /dev/null
sudo iptables -w -F FW_WHITELIST

# return if src/dst is in whitelist
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_ip_set src -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_ip_set src -j RETURN
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_ip_set dst -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_ip_set dst -j RETURN
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_domain_set src -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_domain_set src -j RETURN
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_domain_set dst -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_domain_set dst -j RETURN
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_net_set src -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_net_set src -j RETURN
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_net_set dst -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_net_set dst -j RETURN
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_ip_port_set dst,dst -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_ip_port_set dst,dst -j RETURN
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_mac_set dst -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_mac_set dst -j RETURN
sudo iptables -w -C FW_WHITELIST -p all -m set --match-set whitelist_mac_set src -j RETURN &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all -m set --match-set whitelist_mac_set src -j RETURN

# reject tcp
sudo iptables -w -C FW_WHITELIST -p tcp --source 0.0.0.0/0 --destination 0.0.0.0/0 -j REJECT &>/dev/null || sudo iptables -w -A FW_WHITELIST -p tcp --source 0.0.0.0/0 --destination 0.0.0.0/0 -j REJECT
# drop everything
sudo iptables -w -C FW_WHITELIST -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j DROP &>/dev/null || sudo iptables -w -A FW_WHITELIST -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j DROP

# divert to whitelist chain if whitelist bit is marked
sudo iptables -w -C FORWARD -m connmark --mark 0x1/0x1 -j FW_WHITELIST &>/dev/null || sudo iptables -w -I FORWARD -m connmark --mark 0x1/0x1 -j FW_WHITELIST

sudo iptables -w -N FW_SHIELD &> /dev/null
sudo iptables -w -F FW_SHIELD

# drop everything
sudo iptables -w -C FW_SHIELD -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j DROP &>/dev/null || sudo iptables -w -A FW_SHIELD -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j DROP

# return established and related connections
sudo iptables -w -C FW_SHIELD -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN &>/dev/null || sudo iptables -w -I FW_SHIELD -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN

# return if source ip is in trusted_ip_set
sudo iptables -w -C FW_SHIELD -m set --match-set trusted_ip_set src -j RETURN &>/dev/null || sudo iptables -w -I FW_SHIELD -m set --match-set trusted_ip_set src -j RETURN &>/dev/null

# divert to shield chain if dst ip is in protected_ip_set
sudo iptables -w -C FORWARD -m set --match-set protected_ip_set dst -j FW_SHIELD &>/dev/null || sudo iptables -w -A FORWARD -m set --match-set protected_ip_set dst -j FW_SHIELD

# nat blackhole 8888
sudo iptables -w -t nat -N FW_NAT_HOLE &>/dev/null
sudo iptables -w -t nat -F FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_HOLE -p tcp -j REDIRECT --to-ports 8888 &>/dev/null || sudo iptables -w -t nat -A FW_NAT_HOLE -p tcp -j REDIRECT --to-ports 8888
sudo iptables -w -t nat -C FW_NAT_HOLE -p udp -j REDIRECT --to-ports 8888 &>/dev/null || sudo iptables -w -t nat -A FW_NAT_HOLE -p udp -j REDIRECT --to-ports 8888
sudo iptables -w -t nat -C FW_NAT_HOLE -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_HOLE -j RETURN

# Special block chain for NAT table
sudo iptables -w -t nat -N FW_NAT_BLOCK &>/dev/null
sudo iptables -w -t nat -F FW_NAT_BLOCK

# Redirect global blocking ip set to port 8888
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_ip_set dst -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_ip_set dst -j FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_ip_set src -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_ip_set src -j FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_domain_set dst -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_domain_set dst -j FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_domain_set src -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_domain_set src -j FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_net_set dst -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_net_set dst -j FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_net_set src -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_net_set src -j FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_mac_set dst -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_mac_set dst -j FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_mac_set src -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_mac_set src -j FW_NAT_HOLE
sudo iptables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_ip_port_set dst,dst -j FW_NAT_HOLE &>/dev/null || sudo iptables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_ip_port_set dst,dst -j FW_NAT_HOLE &>/dev/null


sudo iptables -w -t nat -C FW_NAT_BLOCK -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j RETURN &>/dev/null ||   sudo iptables -w -t nat -A FW_NAT_BLOCK -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j RETURN

sudo iptables -w -t nat -C PREROUTING -j FW_NAT_BLOCK &>/dev/null || sudo iptables -w -t nat -I PREROUTING -j FW_NAT_BLOCK

sudo iptables -w -t nat -N FW_NAT_WHITELIST &>/dev/null
sudo iptables -w -t nat -F FW_NAT_WHITELIST

# return if src/dst is in whitelist
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_set src -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_set src -j RETURN
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_set dst -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_set dst -j RETURN
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_domain_set src -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_domain_set src -j RETURN
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_domain_set dst -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_domain_set dst -j RETURN
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_net_set src -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_net_set src -j RETURN
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_net_set dst -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_net_set dst -j RETURN
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_port_set dst,dst -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_port_set dst,dst -j RETURN
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_mac_set dst -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_mac_set dst -j RETURN
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_mac_set src -j RETURN &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_mac_set src -j RETURN

# redirect tcp udp to port 8888 by default
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p tcp -j REDIRECT --to-ports 8888 &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p tcp -j REDIRECT --to-ports 8888
sudo iptables -w -t nat -C FW_NAT_WHITELIST -p udp -j REDIRECT --to-ports 8888 &>/dev/null || sudo iptables -w -t nat -A FW_NAT_WHITELIST -p udp -j REDIRECT --to-ports 8888

# divert to whitelist chain if whitelist bit is marked
sudo iptables -w -t nat -C PREROUTING -m connmark --mark 0x1/0x1 -j FW_NAT_WHITELIST &>/dev/null || sudo iptables -w -t nat -I PREROUTING -m connmark --mark 0x1/0x1 -j FW_NAT_WHITELIST

# create dns redirect chain in PREROUTING
sudo iptables -w -t nat -N PREROUTING_DNS_DEFAULT &> /dev/null
sudo iptables -w -t nat -F PREROUTING_DNS_DEFAULT
sudo iptables -w -t nat -C PREROUTING -j PREROUTING_DNS_DEFAULT || sudo iptables -w -t nat -I PREROUTING -j PREROUTING_DNS_DEFAULT
sudo iptables -w -t nat -N PREROUTING_DNS_VPN &> /dev/null
sudo iptables -w -t nat -F PREROUTING_DNS_VPN
sudo iptables -w -t nat -C PREROUTING -j PREROUTING_DNS_VPN || sudo iptables -w -t nat -I PREROUTING -j PREROUTING_DNS_VPN
sudo iptables -w -t nat -N PREROUTING_DNS_SAFE_SEARCH &> /dev/null
sudo iptables -w -t nat -F PREROUTING_DNS_SAFE_SEARCH
sudo iptables -w -t nat -C PREROUTING -j PREROUTING_DNS_SAFE_SEARCH || sudo iptables -w -t nat -I PREROUTING -j PREROUTING_DNS_SAFE_SEARCH
sudo iptables -w -t nat -N PREROUTING_DNS_VPN_CLIENT &> /dev/null
sudo iptables -w -t nat -F PREROUTING_DNS_VPN_CLIENT
sudo iptables -w -t nat -C PREROUTING -j PREROUTING_DNS_VPN_CLIENT || sudo iptables -w -t nat -I PREROUTING -j PREROUTING_DNS_VPN_CLIENT

if [[ -e /.dockerenv ]]; then
  sudo iptables -w -C OUTPUT -p all -j FW_BLOCK &>/dev/null || sudo iptables -w -A OUTPUT -p all -j FW_BLOCK
fi

if [[ -e /sbin/ip6tables ]]; then

  sudo ipset create blocked_ip_set6 hash:ip family inet6 hashsize 128 maxelem 65536 &>/dev/null
  sudo ipset create blocked_domain_set6 hash:ip family inet6 hashsize 128 maxelem 65536 &>/dev/null
  sudo ipset create blocked_net_set6 hash:net family inet6 hashsize 128 maxelem 65536 &>/dev/null
  sudo ipset create blocked_ip_port_set6 hash:ip,port family inet6 hashsize 128 maxelem 65536 &>/dev/null
  sudo ipset create trusted_ip_set6 hash:ip family inet6 hashsize 128 maxelem 65536 &>/dev/null
  sudo ipset create monitored_ip_set6 hash:ip family inet6 hashsize 128 maxelem 65536 &>/dev/null
  sudo ipset create protected_ip_set6 hash:ip family inet6 hashsize 128 maxelem 65536 &>/dev/null
  sudo ipset create whitelist_ip_set6 hash:ip family inet6 hashsize 128 maxelem 65536 &> /dev/null
  sudo ipset create whitelist_domain_set6 hash:ip family inet6 hashsize 128 maxelem 65536 &> /dev/null
  sudo ipset create whitelist_net_set6 hash:ip family inet6 hashsize 128 maxelem 65536 &> /dev/null
  sudo ipset create whitelist_ip_port_set6 hash:ip,port family inet6 hashsize 128 maxelem 65536 &>/dev/null


  sudo ipset flush blocked_ip_set6
  sudo ipset flush blocked_domain_set6
  sudo ipset flush blocked_net_set6
  sudo ipset flush blocked_ip_port_set6
  sudo ipset flush trusted_ip_set6
  sudo ipset flush monitored_ip_set6
  sudo ipset flush protected_ip_set6
  sudo ipset flush whitelist_ip_set6
  sudo ipset flush whitelist_domain_set6
  sudo ipset flush whitelist_net_set6
  sudo ipset flush whitelist_ip_port_set6

  # multi protocol block chain
  sudo ip6tables -w -N FW_DROP &>/dev/null
  sudo ip6tables -w -F FW_DROP
  sudo ip6tables -w -C FW_DROP -p tcp -j REJECT &>/dev/null || sudo ip6tables -w -A FW_DROP -p tcp -j REJECT
  sudo ip6tables -w -C FW_DROP -p all -j DROP &>/dev/null || sudo ip6tables -w -A FW_DROP -p all -j DROP


  sudo ip6tables -w -N FW_BLOCK &>/dev/null
  sudo ip6tables -w -F FW_BLOCK

  # return everything
  sudo ip6tables -w -C FW_BLOCK -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j RETURN &>/dev/null ||   sudo ip6tables -w -A FW_BLOCK -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j RETURN

  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_ip_set6 dst -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_ip_set6 dst -j FW_DROP
  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_ip_set6 src -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_ip_set6 src -j FW_DROP
  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_domain_set6 dst -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_domain_set6 dst -j FW_DROP
  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_domain_set6 src -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_domain_set6 src -j FW_DROP
  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_net_set6 dst -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_net_set6 dst -j FW_DROP
  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_net_set6 src -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_net_set6 src -j FW_DROP
  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_ip_port_set6 dst,dst -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_ip_port_set6 dst,dst -j FW_DROP
  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_mac_set dst -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_mac_set dst -j FW_DROP
  sudo ip6tables -w -C FW_BLOCK -p all -m set --match-set blocked_mac_set src -j FW_DROP &>/dev/null ||   sudo ip6tables -w -I FW_BLOCK -p all -m set --match-set blocked_mac_set src -j FW_DROP
  
  # forward to fw_block
  sudo ip6tables -w -C FORWARD -p all -j FW_BLOCK &>/dev/null ||   sudo ip6tables -w -A FORWARD -p all -j FW_BLOCK

  # clear whitelist mark on dns packet in mangle table
  sudo ip6tables -w -t mangle -C PREROUTING -p tcp -m tcp --dport 53 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -p tcp -m tcp --dport 53 -j CONNMARK --set-xmark 0x0/0x1
  sudo ip6tables -w -t mangle -C PREROUTING -p tcp -m tcp --sport 53 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -p tcp -m tcp --sport 53 -j CONNMARK --set-xmark 0x0/0x1
  sudo ip6tables -w -t mangle -C PREROUTING -p udp -m udp --dport 53 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -p udp -m udp --dport 53 -j CONNMARK --set-xmark 0x0/0x1
  sudo ip6tables -w -t mangle -C PREROUTING -p udp -m udp --sport 53 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -p udp -m udp --sport 53 -j CONNMARK --set-xmark 0x0/0x1
  # clear whitelist mark on dhcp packet in mangle table
  sudo ip6tables -w -t mangle -C PREROUTING -p tcp -m tcp --dport 67 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -p tcp -m tcp --dport 67 -j CONNMARK --set-xmark 0x0/0x1
  sudo ip6tables -w -t mangle -C PREROUTING -p tcp -m tcp --sport 67 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -p tcp -m tcp --sport 67 -j CONNMARK --set-xmark 0x0/0x1
  sudo ip6tables -w -t mangle -C PREROUTING -p udp -m udp --dport 67 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -p udp -m udp --dport 67 -j CONNMARK --set-xmark 0x0/0x1
  sudo ip6tables -w -t mangle -C PREROUTING -p udp -m udp --sport 67 -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -p udp -m udp --sport 67 -j CONNMARK --set-xmark 0x0/0x1
  # clear whitelist mark on local subnet packet in mangle table
  sudo ip6tables -w -t mangle -C PREROUTING -m set --match-set trusted_ip_set6 src -m set --match-set trusted_ip_set6 dst -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -m set --match-set trusted_ip_set6 src -m set --match-set trusted_ip_set6 dst -j CONNMARK --set-xmark 0x0/0x1
  # clear whitelist mark on established connections in mangle table
  sudo ip6tables -w -t mangle -C PREROUTING -m conntrack --ctstate RELATED,ESTABLISHED -j CONNMARK --set-xmark 0x0/0x1 &>/dev/null || sudo ip6tables -w -t mangle -A PREROUTING -m conntrack --ctstate RELATED,ESTABLISHED -j CONNMARK --set-xmark 0x0/0x1

  sudo ip6tables -w -N FW_WHITELIST &> /dev/null
  sudo ip6tables -w -F FW_WHITELIST

  # return if src/dst is in whitelist
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_ip_set6 src -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_ip_set6 src -j RETURN
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_ip_set6 dst -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_ip_set6 dst -j RETURN
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_domain_set6 src -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_domain_set6 src -j RETURN
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_domain_set6 dst -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_domain_set6 dst -j RETURN
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_net_set6 src -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_net_set6 src -j RETURN
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_net_set6 dst -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_net_set6 dst -j RETURN
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_ip_port_set6 dst,dst -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_ip_port_set6 dst,dst -j RETURN
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_mac_set dst -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_mac_set dst -j RETURN
  sudo ip6tables -w -C FW_WHITELIST -p all -m set --match-set whitelist_mac_set src -j RETURN &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all -m set --match-set whitelist_mac_set src -j RETURN

  # reject tcp
  sudo ip6tables -w -C FW_WHITELIST -p tcp --source 0.0.0.0/0 --destination 0.0.0.0/0 -j REJECT &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p tcp --source 0.0.0.0/0 --destination 0.0.0.0/0 -j REJECT
  # drop everything
  sudo ip6tables -w -C FW_WHITELIST -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j DROP &>/dev/null || sudo ip6tables -w -A FW_WHITELIST -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j DROP

  # divert to white list chain if whitelist bit is marked
  sudo ip6tables -w -C FORWARD -m connmark --mark 0x1/0x1 -j FW_WHITELIST &>/dev/null || sudo ip6tables -w -I FORWARD -m connmark --mark 0x1/0x1 -j FW_WHITELIST


  sudo ip6tables -w -N FW_SHIELD &> /dev/null
  sudo ip6tables -w -F FW_SHIELD

  # drop everything
  sudo ip6tables -w -C FW_SHIELD -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j DROP &>/dev/null || sudo ip6tables -w -A FW_SHIELD -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j DROP

  # return established and related connections
  sudo ip6tables -w -C FW_SHIELD -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN &>/dev/null || sudo ip6tables -w -I FW_SHIELD -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN

  # return if source mac is in trusted_ip_set6
  sudo ip6tables -w -C FW_SHIELD -m set -match-set trusted_ip_set6 src -j RETURN &>/dev/null || sudo ip6tables -w -I FW_SHIELD -m set --match-set trusted_ip_set6 src -j RETURN &>/dev/null

  # divert to shield chain if dst ip is in protected_ip_set6
  sudo ip6tables -w -C FORWARD -m set --match-set protected_ip_set6 dst -j FW_SHIELD &>/dev/null || sudo ip6tables -w -A FORWARD -m set --match-set protected_ip_set6 dst -j FW_SHIELD

  # nat blackhole 8888
  sudo ip6tables -w -t nat -N FW_NAT_HOLE &>/dev/null
  sudo ip6tables -w -t nat -F FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_HOLE -p tcp -j REDIRECT --to-ports 8888 &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_HOLE -p tcp -j REDIRECT --to-ports 8888
  sudo ip6tables -w -t nat -C FW_NAT_HOLE -p udp -j REDIRECT --to-ports 8888 &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_HOLE -p udp -j REDIRECT --to-ports 8888
  sudo ip6tables -w -t nat -C FW_NAT_HOLE -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_HOLE -j RETURN

  # Special block chain for NAT table
  sudo ip6tables -w -t nat -N FW_NAT_BLOCK &>/dev/null
  sudo ip6tables -w -t nat -F FW_NAT_BLOCK

  # Redirect global blocking ip set to port 8888
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_ip_set6 dst -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_ip_set6 dst -j FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_ip_set6 src -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_ip_set6 src -j FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_domain_set6 dst -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_domain_set6 dst -j FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_domain_set6 src -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_domain_set6 src -j FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_net_set6 dst -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_net_set6 dst -j FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_net_set6 src -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_net_set6 src -j FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_mac_set dst -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_mac_set dst -j FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_mac_set src -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_mac_set src -j FW_NAT_HOLE
  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -m set --match-set blocked_ip_port_set6 dst,dst -j FW_NAT_HOLE &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_BLOCK -m set --match-set blocked_ip_port_set6 dst,dst -j FW_NAT_HOLE &>/dev/null

  sudo ip6tables -w -t nat -C FW_NAT_BLOCK -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j RETURN &>/dev/null ||   sudo ip6tables -w -t nat -A FW_NAT_BLOCK -p all --source 0.0.0.0/0 --destination 0.0.0.0/0 -j RETURN

  sudo ip6tables -w -t nat -C PREROUTING -j FW_NAT_BLOCK &>/dev/null || sudo ip6tables -w -t nat -I PREROUTING -j FW_NAT_BLOCK

  sudo ip6tables -w -t nat -N FW_NAT_WHITELIST &>/dev/null
  sudo ip6tables -w -t nat -F FW_NAT_WHITELIST

  # return if src/dst is in whitelist
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_set6 src -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_set6 src -j RETURN
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_set6 dst -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_set6 dst -j RETURN
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_domain_set6 src -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_domain_set6 src -j RETURN
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_domain_set6 dst -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_domain_set6 dst -j RETURN
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_net_set6 src -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_net_set6 src -j RETURN
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_net_set6 dst -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_net_set6 dst -j RETURN
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_port_set6 dst,dst -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_ip_port_set6 dst,dst -j RETURN
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_mac_set dst -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_mac_set dst -j RETURN
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p all -m set --match-set whitelist_mac_set src -j RETURN &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p all -m set --match-set whitelist_mac_set src -j RETURN

  # redirect tcp udp to port 8888 by default
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p tcp -j REDIRECT --to-ports 8888 &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p tcp -j REDIRECT --to-ports 8888
  sudo ip6tables -w -t nat -C FW_NAT_WHITELIST -p udp -j REDIRECT --to-ports 8888 &>/dev/null || sudo ip6tables -w -t nat -A FW_NAT_WHITELIST -p udp -j REDIRECT --to-ports 8888

  # divert to whitelist chain if whitelist chain is marked
  sudo ip6tables -w -t nat -C PREROUTING -m connmark --mark 0x1/0x1 -j FW_NAT_WHITELIST &>/dev/null || sudo ip6tables -w -t nat -I PREROUTING -m connmark --mark 0x1/0x1 -j FW_NAT_WHITELIST

  # create dns redirect chain in PREROUTING
  sudo ip6tables -w -t nat -N PREROUTING_DNS_DEFAULT &> /dev/null
  sudo ip6tables -w -t nat -F PREROUTING_DNS_DEFAULT
  sudo ip6tables -w -t nat -C PREROUTING -j PREROUTING_DNS_DEFAULT || sudo ip6tables -w -t nat -I PREROUTING -j PREROUTING_DNS_DEFAULT
  sudo ip6tables -w -t nat -N PREROUTING_DNS_VPN &> /dev/null
  sudo ip6tables -w -t nat -F PREROUTING_DNS_VPN
  sudo ip6tables -w -t nat -C PREROUTING -j PREROUTING_DNS_VPN || sudo ip6tables -w -t nat -I PREROUTING -j PREROUTING_DNS_VPN
  sudo ip6tables -w -t nat -N PREROUTING_DNS_SAFE_SEARCH &> /dev/null
  sudo ip6tables -w -t nat -F PREROUTING_DNS_SAFE_SEARCH
  sudo ip6tables -w -t nat -C PREROUTING -j PREROUTING_DNS_SAFE_SEARCH || sudo ip6tables -w -t nat -I PREROUTING -j PREROUTING_DNS_SAFE_SEARCH
  sudo ip6tables -w -t nat -N PREROUTING_DNS_VPN_CLIENT &> /dev/null
  sudo ip6tables -w -t nat -F PREROUTING_DNS_VPN_CLIENT
  sudo ip6tables -w -t nat -C PREROUTING -j PREROUTING_DNS_VPN_CLIENT || sudo ip6tables -w -t nat -I PREROUTING -j PREROUTING_DNS_VPN_CLIENT
fi

# redirect blue hole ip 80/443 port to localhost
sudo iptables -t nat -A PREROUTING -p tcp --destination ${BLUE_HOLE_IP} --destination-port 80 -j REDIRECT --to-ports 8880
sudo iptables -t nat -A PREROUTING -p tcp --destination ${BLUE_HOLE_IP} --destination-port 443 -j REDIRECT --to-ports 8883

# redirect 80 to 8835 for diag interface
for eth_ip in `ip addr show dev eth0 | awk '/inet / {print $2}'|cut -f1 -d/`; do
  sudo iptables -t nat -C PREROUTING -p tcp --destination ${eth_ip} --destination-port 80 -j REDIRECT --to-ports 8835 || sudo iptables -t nat -A PREROUTING -p tcp --destination ${eth_ip} --destination-port 80 -j REDIRECT --to-ports 8835
done
