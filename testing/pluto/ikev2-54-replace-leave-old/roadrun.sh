ipsec auto --up road-east-ipv4-ikev2
ping -n -c 2 -I 192.0.1.254 192.0.2.254
ipsec whack --trafficstatus
# waiting 3 minutes in chunks of 15 seconds
sleep 40
ping -n -c 2 -I 192.0.1.254 192.0.2.254
ipsec whack --trafficstatus
echo done
