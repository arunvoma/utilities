#!/bin/bash



#TODO: HDFS Rebalancer

export JAVA_HOME=XXX
dirpath="XXX/restore-scripts"
restore_file_list="$dirpath/conf/restoreDirs.dat"
confFile="conf-prods3.conf"
NN1="XXX.com"
s3bucket=s3a://XXXXXXX
fs_s3a_server_side_encryption_algorithm=XXXX
fs_s3a_secret_key=XXX
fs_s3a_access_key=XXX
LOGFILE=/root/restore-scripts/distc.tmp

#cleaning tmp file
rm -rf $LOGFILE

function log {
      
				echo "[$(date +%Y/%m/%d:%H:%M:%S)]: $*" >> $LOGFILE 2>&1
}

function pre_check {

if [ $# -ne 2 ]
then
	echo  "\nError: Exactly two arguments are allowed. Like FREQUENCY DATE (Ex:- Daily 20180206 ) \n"
	exit 1
elif [[ ! "$1" =~ ^(Daily|Monthly|Annually)$ ]]
then
	echo   "\nError: First argument needs to be Frequency Daily/Monthly/Annually . Full argument set like Daily 20180206 \n"
	exit 1
elif [[  "$2" = "" ]]
then
	curr_date=`date +"%Y%m%d"`
	echo   "\n As you didn't provided any date value(date(YYYYMMDD) we will use current date - $curr_date \n"
else
	frequency=$1
	curr_date=$2
	echo   "Frequency $frequency and Curr_date is $curr_date"

fi

}






function restorefroms3 {

        formattedDirName=${frequency}/${curr_date}/
        filepath=$1
		
		log  "......perform Distcp function  formattedDirName-${formattedDirName} \n filepath-${filepath}....."
        log  " Starting Distcp in an async mode to S3 bucket ... Source: ${s3bucket}/${formattedDirName}$filepath \n Destination hdfs://$NN:8020/$filepath  "

		
       
        sudo -u hdfs hadoop distcp -D fs.s3a.server-side-encryption-algorithm=${fs_s3a_server_side_encryption_algorithm} \
        -D fs.s3a.secret.key=${fs_s3a_secret_key} \
        -D fs.s3a.access.key=${fs_s3a_access_key} \
        -p -update ${s3bucket}/${formattedDirName}$filepath hdfs://$NN1:8020/$filepath >> $LOGFILE 2>&1

         if [ $? -ne 0 ]
           then
                  log  "ERROR: Error submitting distcp jobs "
           else
                  log  "Distcp Jobs Submitted Successfully "
         fi

        #sudo -u hdfs hdfs dfs -chown -R hive:hdfs /${formattedDirName}
}

function readfilelist {
        log  "Reading Files List to import from S3 Bucket"
        for k in  `cat $restore_file_list`;
        do
                log  "Now intiaiting restoring file $k from s3bucket"
                restorefroms3 $k
        done
		
		
		
}

function verifyStat { 

	log  "In verifyStat Function"
	log  ' function check stat ' -- $1 $2

	finished=0 
	retries=0 
	maxretries=30

	while [ $finished -ne 1 ] 
	do
	   
	   jobstat=`mapred job -list all |grep $1|cut -f 2` >> $LOGFILE  

	   log  "Retry $retries for  $1 status is  ${jobstat}" 

           statusCount=`echo "${jobstat}"|grep "SUCCEEDED\|FAILED"|wc -l` >> $LOGFILE 
		   
		     log  " DEBUG: jobstat $jobstat and statusCount $statusCount"

           if [ $statusCount -eq $2 ] 
           then 
              finished=1
           fi 
	    
	   sleep 6
	   
	   let retries=$retries+1 
	   if [[ $retries == $maxretries ]] 
	   then 
	       log  " Max retries $maxretries hit !!! Aborting job check. Please check the YARN UI to see of the jobs are waiting for the resources or stuck. "
	       exit 1 

	   fi 
	done 

        #### Check for total Success and failure jobs

        successstatusCount=`echo "${jobstat}"|grep "SUCCEEDED"|wc -l`  

        failurestatusCount=`echo "${jobstat}"|grep "FAILED"|wc -l`

        if [ $failurestatusCount -gt 0 ]
        then
	   log  "ALERT Jobs ... Please look at YARN Job logs for further information. Listing Below ... "

           #echo "Some of the Distcp jobs failed. Please review logs for more information" |mailx -s "HDFS Distcp to s3 jobs FAILED. Review Logs !!!" XX

	fi

        if [ $successstatusCount -eq $2 ]
        then
	   log  "All Distcp Jobs Completed Successfully. Listing Below ... "
 
           #echo "All Distcp Jobs Completed Successfully. Please review logs for more information" |mailx -s "HDFS Distcp to s3 jobs completed SUCCESSFULLY." XX
	fi

        mapred job -list all |grep $1
	if [ $? -ne 0 ]
	then
	   log  "ERROR: Unable to Check Jobs "
        fi
        
}

function verifyJobStatus {


	log  "In verifyJobStatus function"
	getJobID=`cat /tmp/restore-scripts/distc.tmp |grep "DistCp job-id:"`

        getJobCount=`cat  /tmp/restore-scripts/distc.tmp |grep "DistCp job-id:"|wc -l`

		log  "DEBUG:getJobCount --$getJobCount "
		
		
        while read -r line;
        do 
           log  ${line##*: } 
           
           srchJobID+="${line##*: }\|"

           log  ${srchJobID}
        done <<< "${getJobID}"
       
        verifyStat ${srchJobID%\\\|*} ${getJobCount}

}

function notify {

log  " Inside Notify Function"
echo "Distcp jobs completed." |mailx -s "HDFS Restore Distcp Job From s3 to DR Cluster is completed. Review Logs $LOGFILE !!!" XX

}

function hdfsRebalancer {


##########################################################################################################################################
## This script runs the HDFS Rebalancer on the Active name node.
##########################################################################################################################################

## Declarations
thold=20
## Code begins here

nn1status=`sudo -u hdfs hdfs haadmin  -getServiceState nn1`

nn2status=`sudo -u hdfs hdfs haadmin  -getServiceState nn2`

log  $nn1status
log  $nn2status

if [ "$nn1status" == "active" ]
then
     log  "<<NN Master1>> is the active node. Will Initiate Rebalancer "
   #  ssh -t <<NN Master1>> "sudo -u hdfs hdfs balancer -threshold ${thold}"
else
     if [ "$nn2status" == "active" ]
     then
        log  "<<NN Master2>> is the active node. Will Initiate Rebalancer "
   #     ssh -t <<NN Master2>> " sudo -u hdfs hdfs balancer -threshold ${thold}"
     else
        log  "Both the name nodes are NOT in active state... Check the logs and re-run the script ... Aborting Rebalancer !!! "
        ####unSuccessfulEmail
	#	log $? "ERROR : HDFS Rebalancer Failed. Check Log for more information" |mailx -r hdpadmin@xxxx.com -s "ALERT: HDFS Rebalancer FAILED" user.name@gmail.com
		exit 1
     fi
fi

}


pre_check $1 $2 
readfilelist
verifyJobStatus
#notify
#TODO--hdfsRebalancer