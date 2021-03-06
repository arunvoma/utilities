#Author Arun
#company Hortonworks
#Description: This script will prepare the ambariserver host and all ambari agent hosts.Builds cluster using blueprints


#Pre-req:- Once you have all hosts ready and FQDN are set then execute this script
#Password-less SSH needs to setup in advance from ambari server to all other hosts.
#Please verify before you run the script hostnames and IP are correctly set.
#This script has been tested for blueprint with 2 mgmt nodes,2 masters,3 slaves and 1 edge nodes.

#!/bin/bash#

#

LOGFILE=~/scripts/allnodesprep.log
rm -rf $LOGFILE 
touch $LOGFILE
hostsfile=~/scripts/all.hosts
dbcmdsfile=~/scripts/sql/pre-database-req.sql
dbcmds1file=~/scripts/sql/pre-database-req-1.sql
dropdbcmdsfile=~/scripts/sql/drop-db-cmds.sql
ambariserverip=`hostname -i`
ambariserverhost=`hostname -f`
curr_date=`date +"%Y%m%d"`

#ambarisetup
databasehost=XXXX
javahome="/usr/java/jdk1.8.0_151/"
databasename=XXX
postgresschema=XXX
databaseusername=XXX
databasepassword=XXX
jdbcdriver="/usr/share/java/postgresql-jdbc.jar"
jdbcdb=postgres

#Blueprint

blueprintfile=~/scripts/blueprint/training_hadoop.json
hdprepofile=~/scripts/blueprint/hdprepo.json
hdputilfile=~/scripts/blueprint/hdputil.json
hostmappingfile=~/scripts/blueprint/hostmapping-training.json
clustername=training
payloadfile=~/scripts/payload.txt
tfile=~/scripts/tmpfile.txt
touch tfile

printHeading()
{
echo -e "\n${1}\n________________________________\n" >> $LOGFILE 2>&1
}

function getrepos {

printHeading "getrepos"

for host in `cat $hostsfile` ; 
do

printHeading "Verifying on Host--$i";
ssh -o StrictHostKeyChecking=no $host 'yum repolist'
ssh -o StrictHostKeyChecking=no $host 'yum-config-manager --enable rhui-REGION-rhel-server-optional'
ssh -o StrictHostKeyChecking=no $host 'yum install -y libtirpc-devel'
ssh -o StrictHostKeyChecking=no $host 'yum install -y wget '
ssh -o StrictHostKeyChecking=no $host 'wget https://s3.amazonaws.com/XXXXX/hadoop/repo/ambari.repo -O /etc/yum.repos.d/ambari.repo'
ssh -o StrictHostKeyChecking=no $host 'wget https://s3.amazonaws.com/XXXXX/hadoop/repo/HDP-2.6.1.49-2.repo -O /etc/yum.repos.d/HDP-2.6.1.49-2.repo'
ssh -o StrictHostKeyChecking=no $host 'wget https://s3.amazonaws.com/XXXXX/hadoop/repo/HDP-UTILS.repo -O /etc/yum.repos.d/HDP-UTILS.repo'
ssh -o StrictHostKeyChecking=no $host 'wget https://s3.amazonaws.com/XXXXX/hadoop/repo/HDP.repo -O /etc/yum.repos.d/HDP.repo'
ssh -o StrictHostKeyChecking=no $host 'yum clean all'
ssh -o StrictHostKeyChecking=no $host 'yum repolist'
ssh -o StrictHostKeyChecking=no $host 'ls -l /etc/yum.repos.d/'
done

}

function allnodesprep {

printHeading "All Nodes Prep"

export WCOLL=$hostsfile
echo "Verifying on Host--$i";
pdsh 'hostname -f;hostname -i'
echo "Disabling THP"
pdsh 'echo " " >> /etc/rc.local'
pdsh 'echo "if test -f /sys/kernel/mm/redhat_transparent_hugepage/enabled; then " >> /etc/rc.local'
pdsh 'echo "  echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local'
pdsh 'echo "fi"  >> /etc/rc.local'
pdsh 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
pdsh 'echo never > /sys/kernel/mm/transparent_hugepage/defrag '
echo "SELINUX"
pdsh 'setenforce 0 && sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config '
pdsh 'sysctl vm.swappiness=1'
pdsh 'echo "*                soft    nofile          65536" >> /etc/security/limits.conf '
pdsh 'echo "*                hard    nofile          65536" >> /etc/security/limits.conf '
echo "Download JAVA Package and set JAVA_HOME"
pdsh 'cd /tmp;wget http://XXXX/AllNodes/jdk-8u151-linux-x64.rpm'
pdsh 'rpm -ivh /tmp/jdk-8u151-linux-x64.rpm'
pdsh 'alternatives --install /usr/bin/java java /usr/java/jdk1.8.0_151/bin/java 2'
pdsh 'alternatives --set java /usr/java/jdk1.8.0_151/bin/java'
echo "Verifying hostname FQDN and Java Version"
pdsh 'hostname -f;java -version'

}



function verify {

export WCOLL=$hostsfile
echo 'Verifying Hostname FQDN and IP'
pdsh 'hostname -f;hostname -i'
#pdsh 'yum clean all'
pdsh 'yum repolist'
echo 'Verifying repo files in all hosts'
pdsh 'ls -l /etc/yum.repos.d/'
echo "status of server"
ambari-server status
echo "verifying ambari-agents heartbeat to server"
pdsh 'grep -i hostname /etc/ambari-agent/conf/ambari-agent.ini'
pdsh 'hostname -f;ambari-agent status'
echo 'Verifying JDBC Properties on Ambari Server host'
grep -i jdbc /etc/ambari-server/conf/ambari.properties

}

function ambariserversetup {

export PGPASSWORD=XXXXX
psql -h ${databasehost} -U XXXXX -d postgres -f $dbcmdsfile
export PGPASSWORD=XXXX
psql -h ${databasehost} -U ambari -d ambari -f $dbcmds1file
psql -h ${databasehost} -U ambari -d ambari -f /var/lib/ambari-server/resources/Ambari-DDL-Postgres-CREATE.sql



ambari-server setup --database=postgres --databasehost=${databasehost}  --databaseport=5432 --java-home=${javahome} --databasename=${databasename} --postgresschema=${postgresschema} --databaseusername=${databaseusername} --databasepassword=${databasepassword} --verbose --silent
ambari-server setup --jdbc-db=${jdbcdb} --jdbc-driver=${jdbcdriver}
ambari-server start
}

function ambariagentsetup {

export WCOLL=$hostsfile
pdsh 'yum clean all;yum repolist'
pdsh 'yum install -y ambari-agent'
echo "set ambari-server"

lineNo=16
filename=/etc/ambari-agent/conf/ambari-agent.ini
ambariserverhost=`hostname -f`
var="hostname=${ambariserverhost}"
echo "$var"
`sed -i ${lineNo}s/.*/$var/ ${filename}`

if [ $? -ne 1 ]
then
	for host in `cat $hostsfile` ; 
	do
	scp /etc/ambari-agent/conf/ambari-agent.ini $host:/etc/ambari-agent/conf/ambari-agent.ini
	done
else
	echo "Ambari server is not receiving heartbeat from agents"
	exit 1
fi
echo "set smartsense"
pdsh 'sed -i s/verify=platform_default/verify=disable/g /etc/python/cert-verification.cfg'
pdsh 'ambari-agent restart'

}

function mgmtnodeprep {

printHeading "ambari-install"
yum install -y ambari-server;
yum install -y pdsh;

printHeading "database-pre-req"
yum install -y postgresql-jdbc*;
ls -l /usr/share/java/postgresql-jdbc.jar;
chmod 644 /usr/share/java/postgresql-jdbc.jar;


}

function clusterbuild {



curl -H "X-Requested-By: ambari" -X POST -u admin:XXXX http://${ambariserverip}:8080/api/v1/blueprints/${clustername} -d @${blueprintfile}
curl -H "X-Requested-By: ambari" -X PUT -u admin:XXXX http://${ambariserverip}:8080/api/v1/stacks/HDP/versions/2.6/operating_systems/redhat7/repositories/HDP-2.6 -d @${hdprepofile}
curl -H "X-Requested-By: ambari" -X PUT -u admin:XXXX http://${ambariserverip}:8080/api/v1/stacks/HDP/versions/2.6/operating_systems/redhat7/repositories/HDP-UTILS-1.1.0.21 -d @${hdputilfile}
curl -H "X-Requested-By: ambari" -X POST -u admin:XXXX http://${ambariserverip}:8080/api/v1/clusters/${clustername} -d @${hostmappingfile}

}

function cleanup {


ambari-server stop
export PGPASSWORD=XXXXX
psql -h ${databasehost} -U XXXXX -d postgres -f $dropdbcmdsfile
 

export WCOLL=./all.hosts
pdsh "yum -y remove ranger\*"
pdsh "yum -y remove hive\*"
pdsh "yum -y remove tez\*"
pdsh "yum -y remove pig\*"
pdsh "yum -y remove storm\*"
pdsh "yum -y remove zookeeper\*"
pdsh "yum -y remove falcon\*"
pdsh "yum -y remove oozie\*"
pdsh "yum -y remove flume\*"
pdsh "yum -y remove sqoop\*"
pdsh "yum -y remove slider\*"
pdsh "yum -y remove spark\*"
pdsh "yum -y remove hadoop\*"
pdsh "yum -y remove bigtop\*"
pdsh "yum -y remove smartsense\*"
pdsh "yum -y remove hdp-select\*"
pdsh "rm -rf /usr/hdp"
pdsh "rm -rf /var/log/hadoop/*"
pdsh "ambari-agent restart"

}

function all_servicechecks {

sed -i s/clustername/${clustername}/g ${payloadfile}

#echo "curl -ivk -H "X-Requested-By: ambari" -u admin:XXX -X POST -d @${payloadfile} http://${ambariserverip}:8080/api/v1/clusters/${clustername}/request_schedules"
rm -rf $tfile
curl  -H "X-Requested-By: ambari" -u admin:XX -X POST -d @${payloadfile} http://${ambariserverip}:8080/api/v1/clusters/${clustername}/request_schedules >> $tfile 2>&1
reqid=`grep -i -w "id" ${tfile} | cut -d ':' -f2 | tr -d ' '`
sleep 1
rm -rf $tfile
curl  -H "X-Requested-By: ambari" -u admin:XXX -X GET  http://${ambariserverip}:8080/api/v1/clusters/${clustername}/request_schedules/${reqid} >> $tfile 2>&1
status=`grep -i -w "status" ${tfile} | cut -d ':' -f2|tr -d ' "'`


x=0
while [ $x -eq 0 ]
do

rm -rf $tfile
curl  -H "X-Requested-By: ambari" -u admin:XXX -X GET  http://${ambariserverip}:8080/api/v1/clusters/${clustername}/request_schedules/${reqid} >> $tfile 2>&1
status=`grep -i -w "status" ${tfile} | cut -d ':' -f2|tr -d ' "'`

if [[ "${status}" = "SCHEDULED" ]]
then
	echo  "\nService checks are Scheduled ) \n"
	x=0
	sleep 1
elif [[ "${status}" = "COMPLETED" ]]
then
	echo  "\nService checks are Completed Successfully ) \n"
	x=1
elif [[ "${status}" = "FAILED" ]]
then
		echo  "\nService checks FAILED  ) \n"
		x=1
else
	
	echo   "Service Checks Failed to execute"
	x=1
fi
done

}

#calling functions

#cleanup
#getrepos
#mgmtnodeprep
#allnodesprep
#ambariserversetup
#ambariagentsetup
#verify
#clusterbuild
all_servicechecks 

