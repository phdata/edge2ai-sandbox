#! /bin/bash
echo "-- Configure and optimize the OS"
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.d/rc.local
echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.d/rc.local
# add tuned optimization https://www.cloudera.com/documentation/enterprise/6/6.2/topics/cdh_admin_performance.html
echo  "vm.swappiness = 1" >> /etc/sysctl.conf
sysctl vm.swappiness=1
timedatectl set-timezone UTC
# CDSW requires Centos 7.5, so we trick it to believe it is...
echo "CentOS Linux release 7.5.1810 (Core)" > /etc/redhat-release

echo "-- Install Java OpenJDK8 and other tools"
yum install -y java-1.8.0-openjdk-devel vim wget curl git bind-utils

# Check input parameters
case "$1" in
        aws)
            echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony.conf
            systemctl restart chronyd
            ;;
        azure)
            umount /mnt/resource
            mount /dev/sdb1 /opt
            ;;
        gcp)
            ;;
        *)
            echo $"Usage: $0 {aws|azure|gcp} template-file [docker-device]"
            echo $"example: ./setup.sh azure default_template.json"
            echo $"example: ./setup.sh aws cdsw_template.json /dev/xvdb"
            exit 1
esac

TEMPLATE=$2
# ugly, but for now the docker device has to be put by the user
DOCKERDEVICE=$3


echo "-- Configure networking"
PUBLIC_IP=`curl https://api.ipify.org/`
hostnamectl set-hostname `hostname -f`
echo "`hostname -I` `hostname`" >> /etc/hosts
sed -i "s/HOSTNAME=.*/HOSTNAME=`hostname`/" /etc/sysconfig/network
systemctl disable firewalld
systemctl stop firewalld
setenforce 0
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config


echo "-- Install CM and MariaDB repo"
wget https://archive.cloudera.com/cm6/6.3.0/redhat7/yum/cloudera-manager.repo -P /etc/yum.repos.d/

## MariaDB 10.1
cat - >/etc/yum.repos.d/MariaDB.repo <<EOF
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF

yum clean all
rm -rf /var/cache/yum/
yum repolist

yum install -y cloudera-manager-daemons cloudera-manager-agent cloudera-manager-server
yum install -y MariaDB-server MariaDB-client
cat conf/mariadb.config > /etc/my.cnf


echo "--Enable and start MariaDB"
systemctl enable mariadb
systemctl start mariadb

echo "-- Install JDBC connector"
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.46.tar.gz -P ~
tar zxf ~/mysql-connector-java-5.1.46.tar.gz -C ~
mkdir -p /usr/share/java/
cp ~/mysql-connector-java-5.1.46/mysql-connector-java-5.1.46-bin.jar /usr/share/java/mysql-connector-java.jar
rm -rf ~/mysql-connector-java-5.1.46*

echo "-- Create DBs required by CM"
mysql -u root < ~/edge2ai-sandbox/scripts/create_db.sql

echo "-- Secure MariaDB"
mysql -u root < ~/edge2ai-sandbox/scripts/secure_mariadb.sql

echo "-- Prepare CM database 'scm'"
/opt/cloudera/cm/schema/scm_prepare_database.sh mysql scm scm cloudera

echo "-- Install CSDs"
# install local CSDs
mv ~/*.jar /opt/cloudera/csd/

wget https://archive.cloudera.com/CFM/csd/1.0.0.0/NIFI-1.9.0.1.0.0.0-90.jar -P /opt/cloudera/csd/
wget https://archive.cloudera.com/CFM/csd/1.0.0.0/NIFICA-1.9.0.1.0.0.0-90.jar -P /opt/cloudera/csd/
wget https://archive.cloudera.com/CFM/csd/1.0.0.0/NIFIREGISTRY-0.3.0.1.0.0.0-90.jar -P /opt/cloudera/csd/
wget https://archive.cloudera.com/cdsw1/1.6.0/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDH6-1.6.0.jar -P /opt/cloudera/csd/
# CSD for C5
wget https://archive.cloudera.com/cdsw1/1.6.0/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDH5-1.6.0.jar -P /opt/cloudera/csd/
wget https://archive.cloudera.com/spark2/csd/SPARK2_ON_YARN-2.4.0.cloudera1.jar -P /opt/cloudera/csd/

chown cloudera-scm:cloudera-scm /opt/cloudera/csd/*
chmod 644 /opt/cloudera/csd/*

echo "-- Install local parcels"
mv ~/*.parcel ~/*.parcel.sha /opt/cloudera/parcel-repo/
chown cloudera-scm:cloudera-scm /opt/cloudera/parcel-repo/*

echo "-- Install CEM Tarballs"
mkdir -p /opt/cloudera/cem
wget https://archive.cloudera.com/CEM/centos7/1.x/updates/1.0.0.0/CEM-1.0.0.0-centos7-tars-tarball.tar.gz -P /opt/cloudera/cem
tar xzf /opt/cloudera/cem/CEM-1.0.0.0-centos7-tars-tarball.tar.gz -C /opt/cloudera/cem
tar xzf /opt/cloudera/cem/CEM/centos7/1.0.0.0-54/tars/efm/efm-1.0.0.1.0.0.0-54-bin.tar.gz -C /opt/cloudera/cem
tar xzf /opt/cloudera/cem/CEM/centos7/1.0.0.0-54/tars/minifi/minifi-0.6.0.1.0.0.0-54-bin.tar.gz -C /opt/cloudera/cem
tar xzf /opt/cloudera/cem/CEM/centos7/1.0.0.0-54/tars/minifi/minifi-toolkit-0.6.0.1.0.0.0-54-bin.tar.gz -C /opt/cloudera/cem
rm -f /opt/cloudera/cem/CEM-1.0.0.0-centos7-tars-tarball.tar.gz
ln -s /opt/cloudera/cem/efm-1.0.0.1.0.0.0-54 /opt/cloudera/cem/efm
ln -s /opt/cloudera/cem/minifi-0.6.0.1.0.0.0-54 /opt/cloudera/cem/minifi
ln -s /opt/cloudera/cem/efm/bin/efm.sh /etc/init.d/efm
chown -R root:root /opt/cloudera/cem/efm-1.0.0.1.0.0.0-54
chown -R root:root /opt/cloudera/cem/minifi-0.6.0.1.0.0.0-54
chown -R root:root /opt/cloudera/cem/minifi-toolkit-0.6.0.1.0.0.0-54
rm -f /opt/cloudera/cem/efm/conf/efm.properties
cp ~/edge2ai-sandbox/conf/efm.properties /opt/cloudera/cem/efm/conf
rm -f /opt/cloudera/cem/minifi/conf/bootstrap.conf
cp ~/edge2ai-sandbox/conf/bootstrap.conf /opt/cloudera/cem/minifi/conf
sed -i "s/YourHostname/`hostname -f`/g" /opt/cloudera/cem/efm/conf/efm.properties
sed -i "s/YourHostname/`hostname -f`/g" /opt/cloudera/cem/minifi/conf/bootstrap.conf
/opt/cloudera/cem/minifi/bin/minifi.sh install

echo "-- Configure MiNiFi to run MQTT NAR"
wget http://central.maven.org/maven2/org/apache/nifi/nifi-mqtt-nar/1.8.0/nifi-mqtt-nar-1.8.0.nar -P /opt/cloudera/cem/minifi/lib
chown root:root /opt/cloudera/cem/minifi/lib/nifi-mqtt-nar-1.8.0.nar
chmod 660 /opt/cloudera/cem/minifi/lib/nifi-mqtt-nar-1.8.0.nar

echo "-- Enable passwordless root login via rsa key"
ssh-keygen -f ~/myRSAkey -t rsa -N ""
mkdir ~/.ssh
cat ~/myRSAkey.pub >> ~/.ssh/authorized_keys
chmod 400 ~/.ssh/authorized_keys
ssh-keyscan -H `hostname` >> ~/.ssh/known_hosts
sed -i 's/.*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
systemctl restart sshd

echo "-- Start CM, it takes about 2 minutes to be ready"
systemctl start cloudera-scm-server

while [ `curl -s -X GET -u "admin:admin"  http://localhost:7180/api/version` -z ] ;
    do
    echo "waiting 10s for CM to come up..";
    sleep 10;
done

echo "-- Now CM is started and the next step is to automate using the CM API"

yum install -y epel-release
yum install -y python-pip
pip install --upgrade pip
pip install cm_client

sed -i "s/YourHostname/`hostname -f`/g" ~/edge2ai-sandbox/$TEMPLATE
sed -i "s/YourCDSWDomain/cdsw.$PUBLIC_IP.nip.io/g" ~/edge2ai-sandbox/$TEMPLATE
sed -i "s/YourPrivateIP/`hostname -I | tr -d '[:space:]'`/g" ~/edge2ai-sandbox/$TEMPLATE
sed -i "s#YourDockerDevice#$DOCKERDEVICE#g" ~/edge2ai-sandbox/$TEMPLATE

sed -i "s/YourHostname/`hostname -f`/g" ~/edge2ai-sandbox/scripts/create_cluster.py

python ~/edge2ai-sandbox/scripts/create_cluster.py $TEMPLATE

echo "-- Install Mosquitto and MQTT"
yum install -y mosquitto
pip install paho-mqtt
systemctl enable mosquitto
systemctl start mosquitto
git clone https://github.com/phdata/edge2ai-workshop ~/edge2ai-workshop
mv ~/edge2ai-workshop/mqtt.* ~
mv ~/edge2ai-workshop/spark.iot* ~

echo "-- Start EFM and Minifi"
service efm start
service minifi start

echo "-- At this point you can login into Cloudera Manager host on port 7180 and follow the deployment of the cluster"


#########################################################
# utility functions
#########################################################
dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

starting_dir=`pwd`

# logging function
log() {
    echo -e "[$(date)] [$BASH_SOURCE: $BASH_LINENO] : $*"
    echo -e "[$(date)] [$BASH_SOURCE: $BASH_LINENO] : $*" >> $starting_dir/setup-all.log
}

# Load util functions.
. $starting_dir/scripts/utils.sh

#####################################################
# first check if JQ is installed
#####################################################
log "Installing jq"

jq_v=`jq --version 2>&1`
if [[ $jq_v = *"command not found"* ]]; then
    if [[ $machine = "Mac" ]]; then
        sudo curl -L -s -o jq "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64"
    else
        sudo curl -L -s -o jq "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
    fi
    sudo chmod +x ./jq
    sudo cp jq /usr/bin
else
    log "jq already installed. Skipping"
fi

jq_v=`jq --version 2>&1`
if [[ $jq_v = *"command not found"* ]]; then
    log "error installing jq. Please see README and install manually"
    echo "Error installing jq. Please see README and install manually"
    exit 1
fi

#########################################################
# Install component "Supeset"
#########################################################
# Check CDSW again...  Runs long sometimes

log "check status of cdsw before starting superset install"

# Check CDSW again...  Runs long sometimes
echo
echo
echo "Full Output of CDSW status..."
echo
echo
cdsw status
echo
echo

# install superset
$starting_dir/scripts/superset_setup.sh

# return to starting dir
echo "ending dir at install of superset is --> "`pwd`
cd $dir
log "Completed install of Superset"

#########################################################
# load the nifi template via api
#########################################################
log "Load NiFi template"

#  get the host ip:
GETIP=`ip route get 1 | awk '{print $NF;exit}'`
echo "GETIP --> "$GETIP

#get the root process group id for the main canvas:
ROOT_PG_ID=`curl -k -s GET http://$GETIP:8080/nifi-api/process-groups/root | jq -r '.id'`
echo "root pg id -->"$ROOT_PG_ID

# Upload the template
echo "starting_dir --> "$starting_dir
curl -k -s -F template=@"$starting_dir/templates/cdsw_rest_api.xml" -X POST http://$GETIP:8080/nifi-api/process-groups/$ROOT_PG_ID/templates/upload

log "nifi template loaded"
