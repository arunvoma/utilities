
#!/bin/bash 
###############################################################
## STEPS:--
## --------
## 1. Get the Hive dump file from Prod S3 bucket to DR Cluster
## 2. Modify the DB name in DUMP File to New DB
## 3. Restore the MYSQL DUMP 
## 4. Update Ambari HIVE Configs with new DB
## 5. Hive Service Check 
###############################################################
## USAGE restore-hive.sh <dump-file-date>
##Example restore-hive.sh 20180212

###############################################################
##NOTE:- Make sure the dump file exists in S3 bucket ######
##       and conf file restoreDirs exists before execution of this script                #######
###############################################################


#!/bin/bash

. conf/conf-prods3.conf
export JAVA_HOME=XX
NN="XX"
restoredir="/restore/prod/dbs/mysql"
db=mysql_hive_metadata
dumpfile="$restoredir/tmp/hive.dump"
host=XXX
port=3306
user=XX
db=hive
db_new="hive_new"
db_old="hive"
AMBARI_SERVER_HOST="XXX"
CLUSTER_NAME="XX"
LOGFILE=/root/restore-scripts/hive_distc.log




function log {
      
				echo "[$(date +%Y/%m/%d:%H:%M:%S)]: $*" >> $LOGFILE 2>&1
}
   
#clean log file
log "cleaning log file"
rm -rf $LOGFILE

function pre_check {


if [ $# -ne 2 ]
then
	echo  "\nError: Exactly two arguments are allowed. Like restore-hive.sh FREQUENCY DATE (Ex:- restore-hive.sh Daily 20180206 ) \n"
	exit 1
elif [[ ! "$1" =~ ^(Daily|Monthly|Annually)$ ]]
then
	echo   "\nError: First argument needs to be Frequency Daily/Monthly/Annually . Full argument set like restore-hive.sh Daily 20180206 \n"
	exit 1
elif [[  "$2" = "" ]]
then
	curr_date=`date +"%Y%m%d"`
	log   "\n As you didn't provided any date value(date(YYYYMMDD) we will use current date - $curr_date \n"
	filename="hive_${curr_date}*.zip"
	hivebkppath="/backups/prod/dbs/mysql/${filename}"
	echo  "\n Processing Just Started .....Tail the log file $LOGFILE to see progress"
	log   " Curr_date is $curr_date"
	
else
	frequency=$1
	curr_date=$2
	filename="hive_${curr_date}*.zip"
	hivebkppath="/backups/prod/dbs/mysql/${filename}"
	echo  "\n Processing Just Started .....Tail the log file $LOGFILE to see progress"
	log   "Frequency $frequency and Curr_date is $curr_date"

fi

}

function restoremetastorefroms3 {

		

		#Daily/20180106/backups/prod/dbs/mysql/
		formattedDirName=${frequency}/${curr_date}/
        filepath=$1
        log  "perform Distcp function  formattedDirName-${formattedDirName} \n filepath-${filepath}"
        log  " Starting Distcp in an async mode to S3 bucket ... Source: ${s3bucket}/${formattedDirName}$filepath \n Destination hdfs://$NN:8020/$filepath  "

		
        sudo -u hdfs hadoop distcp -D fs.s3a.server-side-encryption-algorithm=${fs_s3a_server_side_encryption_algorithm} \
        -D fs.s3a.secret.key=${fs_s3a_secret_key} \
        -D fs.s3a.access.key=${fs_s3a_access_key} \
        -p -update ${s3bucket}/${formattedDirName}$filepath hdfs://$NN:8020/$filepath >> $LOGFILE 2>&1

         if [ $? -ne 0 ]
           then
                  log   "ERROR: Error submitting distcp jobs..Exiting from the Process "
				  exit 1
           else
                  log   "Distcp Jobs Submitted Successfully "
         fi


}


function resynchivedb {

	filepath=$1
	log "cleaning Restoredir $restoredir/*"
	rm -rf $restoredir/*
	log "get hdfs file - $1"
  #get hdfs file
	hadoop fs -get hdfs://$NN:8020/$filepath $restoredir
  
   if [ $? -ne 0 ]
   then 
      log   "ERROR: Error downloading the database backup from HDFS "
   else
      log   "Downloaded successfully Hive Metastore DB  Successfully "
   fi
   log   "ls -l $restoredir"
   ls -l $restoredir >> $LOGFILE 2>&1
   log   "....Scrubbing mysql dump...."
   
   # log   "check zip file is OK"
   #unzip -j $restoredir/$filename	>> $LOGFILE 2>&1
   log   " check the list of files in zip file"
   log   "unzip -l $filename"
   unzip -l $restoredir/$filename	>> $LOGFILE 2>&1
   log   "unzip the file"
   log  "unzip  $restoredir/$filename -d $restoredir	>> $LOGFILE 2>&1"
   rm -rf $restoredir/tmp
   unzip  $restoredir/$filename -d $restoredir	>> $LOGFILE 2>&1
   
   log "Checking if dump file exists or not"
   if [ -f ${dumpfile} ]
   then
	log  "$dumpfile  found"
   else
     log "$dumpfile not found..Exiting the process"
	 exit 1
   fi
   
   log   "create new hive_new DB"
   mysql -u ${user} -p${mysqlpswd} --host ${host} --port ${port} --database ${db_old} -e"drop database IF EXISTS ${db_new};create database ${db_new}"	>> $LOGFILE 2>&1
   
   chmod 777 ${dumpfile}
   log "find and replace in file old DB with new DB in dump file"
   #to find and replace in file old DB with new DB
	sed  -i 's+USE `hive`;+USE `hive_new`;+1' /restore/prod/dbs/mysql/tmp/hive.dump
   
   log "restoring tables from dump"
   #restoring tables from dump
	mysql -u XX 'XX' --host XXX.com --port 3306 --database ${db_new} < ${dumpfile}
    log "set new db value"
   #set new db value
   python /var/lib/ambari-server/resources/scripts/configs.py -u XX -p XX -a set -l `hostname -f` -n XX  -c hive-site -k "ambari.hive.db.schema.name" -v "${db_new}" 	>> $LOGFILE 2>&1
  
	
   log   "Completed Step: Scrubbed mysql dump"
   log   "#Verify Table count in HiveDB before restore"
  # hiveGetTableCount ${db_new}	>> $LOGFILE 2>&1
   log "STOP HIVE Service"
   #STOP HIVE Service
   curl -u admin:$PASSWORD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop HIVE via REST"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' http://${AMBARI_SERVER_HOST}:8080/api/v1/clusters/${CLUSTER_NAME}/services/HIVE >> $LOGFILE 2>&1
   sleep 60
  
   log "START HIVE Service"
   #START HIVE Service
   curl -u admin:$PASSWORD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start HIVE via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://${AMBARI_SERVER_HOST}:8080/api/v1/clusters/${CLUSTER_NAME}/services/HIVE >> $LOGFILE 2>&1
    sleep 60
  
   
}

function validate_hive_dr() {

#Ambari- HIVE SERVICE CHECK
log "Ambari- HIVE SERVICE CHECK"
 curl -u admin:$PASSWORD -i -H 'X-Requested-By: ambari' -X POST -d '{"RequestInfo" :{"context":"HIVE Service Check","command":"HIVE_SERVICE_CHECK" }, "Requests/resource_filters":[{ "service_name":"HIVE"}]}' http://${AMBARI_SERVER_HOST}:8080/api/v1/clusters/${CLUSTER_NAME}/requests >> $LOGFILE 2>&1
sleep 30
 su -l hive -c "beeline -u 'jdbc:hive2://a:2181,b:2181,c:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2' -n 'hive' -p '' -e 'show databases;'" >> $LOGFILE 2>&1

}


function notify {

log   " Hive Restore Script execution(Restored File-${formattedDirName}$filepath) is completed..Mail will be sent with log attachment"
echo "Hive Restore Script execution(Restored File-${formattedDirName}$filepath) is completed."|mailx -a $LOGFILE -s "Restore of HIVE Dump from S3 is completed . Review Logs !!!" XX >> $LOGFILE 2>&1
 
rm -rf *.log *.json

}
pre_check $*
restoremetastorefroms3 $hivebkppath
resynchivedb $hivebkppath
validate_hive_dr
notify