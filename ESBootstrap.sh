#!/usr/bin/env bash
# This will only work on Centos 7 (it has not been tested on other distros)

# Test if the VM can reach the internet to download packages
until ping -c 1 google.com | grep -q "bytes from"
do
    echo "offline, still waiting..."
    sleep 5
done
echo "online"

# Install Elasticsearch, Kibana, and Unzip
yum install -y unzip wget

# Get the GPG key
rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

# Add Elastic and Kibana and the Elastic Agents
# Download and install Ealsticsearch and Kibana change ver to whatever you want
# For me 8.0.0 is the latest we put it in /vagrant to not download it again
# The -q flag is need to not spam stdout on the host machine
# We also pull the SHA512 hashes for you to check

# var settings
VER=8.0.0
IP_ADDR=10.0.0.10
K_PORT=5601
ES_PORT=9200
F_PORT=8220
DNS=elastic-8-sec

echo "$IP_ADDR $DNS" >> /etc/hosts

wget -nc -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$VER-x86_64.rpm -P /vagrant
wget -nc -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$VER-x86_64.rpm.sha512 -P /vagrant

wget -nc -q https://artifacts.elastic.co/downloads/kibana/kibana-$VER-x86_64.rpm -P /vagrant
wget -nc -q https://artifacts.elastic.co/downloads/kibana/kibana-$VER-x86_64.rpm.sha512 -P /vagrant

wget -nc -q https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$VER-linux-x86_64.tar.gz -P /vagrant
wget -nc -q https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$VER-linux-x86_64.tar.gz.sha512 -P /vagrant

wget -nc -q https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$VER-windows-x86_64.zip -P /vagrant
wget -nc -q https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$VER-windows-x86_64.zip.sha512 -P /vagrant

# We output to a temp password file allowing auto config later on
tar -xvf /vagrant/elastic-agent-$VER-linux-x86_64.tar.gz -C /opt/
rpm --install /vagrant/elasticsearch-$VER-x86_64.rpm 2>&1 | tee /root/ESUpass.txt
rpm --install /vagrant/kibana-$VER-x86_64.rpm

# Make the cert dir to prevent pop-up later
mkdir /tmp/certs/

# Config the instances file for cert gen the ip is $IP_ADDR
cat > /tmp/certs/instance.yml << EOF
instances:
  - name: 'elasticsearch'
    dns: ['$DNS']
    ip: ['$IP_ADDR']
  - name: 'kibana'
    dns: ['$DNS']
  - name: 'fleet'
    dns: ['$DNS']
    ip: ['$IP_ADDR']
EOF

# Make the certs and move them where they are needed
/usr/share/elasticsearch/bin/elasticsearch-certutil ca --pem --pass secret --out /tmp/certs/elastic-stack-ca.zip
unzip /tmp/certs/elastic-stack-ca.zip -d /tmp/certs/
/usr/share/elasticsearch/bin/elasticsearch-certutil cert --ca-cert /tmp/certs/ca/ca.crt -ca-key /tmp/certs/ca/ca.key --ca-pass secret --pem --in /tmp/certs/instance.yml --out /tmp/certs/certs.zip
unzip /tmp/certs/certs.zip -d /tmp/certs/

mkdir /etc/kibana/certs
mkdir /etc/pki/fleet

cp /tmp/certs/ca/ca.crt /tmp/certs/elasticsearch/* /etc/elasticsearch/certs
cp /tmp/certs/ca/ca.crt /tmp/certs/kibana/* /etc/kibana/certs
cp /tmp/certs/ca/ca.crt /tmp/certs/fleet/* /etc/pki/fleet
cp -r /tmp/certs/* /root/

# This cp should be an unaliased cp to replace the ca.crt if it exists in the shared /vagrant dir
cp /tmp/certs/ca/ca.crt /vagrant

# Config and start Elasticsearch (we are also increasing the timeout for systemd to 500)
mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak

cat > /etc/elasticsearch/elasticsearch.yml << EOF
# ======================== Elasticsearch Configuration =========================
#
# ----------------------------------- Paths ------------------------------------
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
# ---------------------------------- Network -----------------------------------
network.host: $IP_ADDR
http.port: $ES_PORT
# --------------------------------- Discovery ----------------------------------
discovery.type: single-node
# ----------------------------------- X-Pack -----------------------------------
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.key: /etc/elasticsearch/certs/elasticsearch.key
xpack.security.transport.ssl.certificate: /etc/elasticsearch/certs/elasticsearch.crt
xpack.security.transport.ssl.certificate_authorities: [ "/etc/elasticsearch/certs/ca.crt" ]
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.key: /etc/elasticsearch/certs/elasticsearch.key
xpack.security.http.ssl.certificate: /etc/elasticsearch/certs/elasticsearch.crt
xpack.security.http.ssl.certificate_authorities: [ "/etc/elasticsearch/certs/ca.crt" ]
xpack.security.authc.api_key.enabled: true
EOF

sed -i 's/TimeoutStartSec=75/TimeoutStartSec=500/g' /lib/systemd/system/elasticsearch.service
systemctl daemon-reload
systemctl start elasticsearch
systemctl enable elasticsearch

# Gen the users and paste the output for later use
/usr/share/elasticsearch/bin/elasticsearch-reset-password -b -u kibana_system -a > /root/Kibpass.txt
# /usr/share/elasticsearch/bin/elasticsearch-reset-password -b -u elastic -a > /root/ESUpass.txt

# Add the Kibana password to the keystore
grep "New value:" /root/Kibpass.txt | awk '{print $3}' | sudo /usr/share/kibana/bin/kibana-keystore add --stdin elasticsearch.password

# Configure and start Kibana adding in the unique kibana_system keystore pass and generating the sec keys
cat > /etc/kibana/kibana.yml << EOF
# =========================== Kibana Configuration ============================
# -------------------------------- Network ------------------------------------
server.host: 0.0.0.0
server.port: $K_PORT
# ------------------------------ Elasticsearch --------------------------------
elasticsearch.hosts: ["https://$IP_ADDR:$ES_PORT"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "\${elasticsearch.password}"
# ---------------------------------- Various -----------------------------------
server.ssl.enabled: true
server.ssl.certificate: "/etc/kibana/certs/kibana.crt"
server.ssl.key: "/etc/kibana/certs/kibana.key"
elasticsearch.ssl.certificateAuthorities: [ "/etc/kibana/certs/ca.crt" ]
elasticsearch.ssl.verificationMode: "none"
# ---------------------------------- X-Pack ------------------------------------
xpack.security.encryptionKey: "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 ; echo '')"
xpack.encryptedSavedObjects.encryptionKey: "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 ; echo '')"
xpack.reporting.encryptionKey: "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 ; echo '')"
EOF

systemctl start kibana
systemctl enable kibana

# Var settings (has to happen after Elastic is installed)
E_PASS=$(sudo grep "generated password for the elastic" /root/ESUpass.txt | awk '{print $11}')

# Test if Kibana is running
echo "Testing if Kibana is online, could take some time, no more than 5 min"
until curl --silent --cacert /tmp/certs/ca/ca.crt -XGET "https://$DNS:$K_PORT/api/fleet/agent_policies" -H 'accept: application/json' -u elastic:$E_PASS | grep -vq '"items":\[\]'
do
    echo "Kibana starting, still waiting..."
    sleep 5
done
echo "Kibna online"

# Make the Fleet token
curl --silent -XPOST "https://$IP_ADDR:$ES_PORT/_security/service/elastic/fleet-server/credential/token/fleet-token-1" \
 --cacert /tmp/certs/ca/ca.crt \
 -u elastic:$E_PASS > /root/Ftoken.txt

# Get the policy key
until curl --silent --cacert /tmp/certs/ca/ca.crt -XGET "https://$DNS:$K_PORT/api/fleet/agent_policies" -H 'accept: application/json' -u elastic:$E_PASS | grep -q "Default policy"
do 
  echo "Kibana loading policies, still waiting..."
  sleep 5
done
sleep 5
echo "Kibana policies loaded"
curl --silent --cacert /tmp/certs/ca/ca.crt -XGET "https://$DNS:$K_PORT/api/fleet/agent_policies" -H 'accept: application/json' -u elastic:$E_PASS > /root/Pid.txt


# Add host IP and yaml settings to Fleet API
curl --silent --cacert /tmp/certs/ca/ca.crt -XPUT "https://$DNS:$K_PORT/api/fleet/outputs/fleet-default-output" \
 -u elastic:$E_PASS \
 -H "accept: application/json" \
 -H "kbn-xsrf: reporting" \
 -H "Content-Type: application/json" -d'{
"name": "default",
"type": "elasticsearch",
"is_default": true,
"is_default_monitoring": true,
"hosts": [
  "https://'$IP_ADDR:$ES_PORT'"
  ],
"ca_sha256": "",
"ca_trusted_fingerprint": "",
"config_yaml": "ssl.certificate_authorities: [\"/vagrant/ca.crt\"]"
}'

# Add fleet server IP to Fleet API
curl --silent --cacert /tmp/certs/ca/ca.crt -XPUT "https://$DNS:$K_PORT/api/fleet/settings" \
 -u elastic:$E_PASS \
 -H 'accept: application/json' \
 -H 'kbn-xsrf: reporting' \
 -H 'Content-Type: application/json' -d'{
    "fleet_server_hosts": [
      "https://'$IP_ADDR:$F_PORT'"
    ]
}'

# Install the fleet server
sudo /opt/elastic-agent-$VER-linux-x86_64/elastic-agent install -f --url=https://$DNS:$F_PORT \
 --fleet-server-es=https://$DNS:$ES_PORT \
 --fleet-server-service-token=$(cat /root/Ftoken.txt | sed "s/\,/'\n'/g" | grep -oP '[^"name"][a-zA-Z0-9]{50,}') \
 --fleet-server-policy=$(cat /root/Pid.txt | sed "s/\},{/'\n'/g" | grep "Default Fleet Server policy" | grep -oP '[0-9a-f]{8}-[0-9a-f]{4}-[0-5][0-9a-f]{3}-[089ab][0-9a-f]{3}-[0-9a-f]{12}') \
 --certificate-authorities=/vagrant/ca.crt \
 --fleet-server-es-ca=/etc/pki/fleet/ca.crt \
 --fleet-server-cert=/etc/pki/fleet/fleet.crt \
 --fleet-server-cert-key=/etc/pki/fleet/fleet.key

# Get the default policy id
cat /root/Pid.txt | sed "s/\},{/'\n'/g" | grep "Default policy" | grep -oP '[0-9a-f]{8}-[0-9a-f]{4}-[0-5][0-9a-f]{3}-[089ab][0-9a-f]{3}-[0-9a-f]{12}' > /root/Eid.txt
curl --silent --cacert /tmp/certs/ca/ca.crt -XGET "https://$DNS:$K_PORT/api/fleet/enrollment_api_keys" -H 'accept: application/json' -u elastic:$(sudo grep "generated password for the elastic" /root/ESUpass.txt | awk '{print $11}') | sed "s/\},{\|],/'\n'/g" | grep -E -m1 $(cat /root/Eid.txt) | grep -oP '[a-zA-Z0-9\=]{40,}' > /vagrant/AEtoken.txt

# Caldera
# yum
yum install -y wget git screen gcc openssl-devel bzip2-devel libffi-devel zlib-devel xz-devel

# python3
wget -nc -q https://www.python.org/ftp/python/3.9.0/Python-3.9.0.tgz -P /usr/local/src
tar -xvf /usr/local/src/Python-3.9.0.tgz -C /usr/local/src
/usr/local/src/Python-3.9.0/configure --enable-optimizations
make altinstall 

# golang
wget -nc -q https://go.dev/dl/go1.17.7.linux-amd64.tar.gz -P /usr/local/
tar -xvf /usr/local/go1.17.7.linux-amd64.tar.gz -C /usr/local/
echo "PATH=\$PATH:/usr/local/go/bin" >> /home/vagrant/.bash_profile

# rust 
su -c 'curl https://sh.rustup.rs -sSf | sh -s -- -y' vagrant

# caldera
git clone https://github.com/mitre/caldera.git --recursive /usr/local/caldera --branch 3.1.0
su -c '/usr/local/bin/python3.9 -m pip install -r /usr/local/caldera/requirements.txt' vagrant
chown -R vagrant /usr/local/caldera/