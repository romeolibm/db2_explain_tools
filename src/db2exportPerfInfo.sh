#!/bin/bash
###################################################################
# Collects (headers and csv export with lobs)
# 
# MG_DB="select * from table(MON_GET_DATABASE(-2))"
# MG_CON="select * from table(MON_GET_CONNECTION(NULL,-2,1))"
# MG_LCK="select * from table(MON_GET_LOCKS(NULL,-2))"
# MG_LCKW="select * from table(MON_GET_APPL_LOCKWAIT(NULL,-2,1))"
# MG_LATCH="select * from table(MON_GET_LATCH(NULL,-2))"
#
# MG_PKGCHS="select * from table(MON_GET_PKG_CACHE_STMT(NULL,NULL,NULL,-2))"
# 
###################################################################
TS=`date +%Y_%m_%d_%H_%M_%S`
STS=$TS

DB="$1"
NUM_SNAPS=$2
COLLECT_INTERVAL_SEC=$3
GET_DB2PD_LATCHES=$4
ZERO="0"
YES="y"

if [ -z "$DB" ]
then
  DB="--help"
fi

if [ -n "$NUM_SNAPS" ]
then
  let "NUM_SNAPS=$NUM_SNAPS"
else
  let "NUM_SNAPS=1"
fi

if [ -n "$COLLECT_INTERVAL_SEC" ]
then
   let "COLLECT_INTERVAL_SEC=$COLLECT_INTERVAL_SEC"
else
   let "COLLECT_INTERVAL_SEC=10"
fi

if [ -z "$GET_DB2PD_LATCHES" ]
then
  GET_DB2PD_LATCHES="y"
fi

if [ "$DB" == "--help" ]
then
	cat << EOF
------------------------------------------------------------------------------

 Export structured db2 SQL performance data.
 Syntax $0 database-alias 

------------------------------------------------------------------------------
EOF
  exit 100
fi

if ! db2 connect to $DB
then
  echo "Unable to connect to $DB"
  exit 2
fi

# create a work folder and cd to it
CFN="db2_perf_collect_$TS"
mkdir -p $CFN
if [ ! -d $CFN ]
then
  echo "Unable to create the collection folder !"
  exit 2
fi
cd $CFN
echo "Start db2 perf data collection at ts:$STS with db:$db num_snaps:$NUM_SNAPS collect_interval_sec:$COLLECT_INTERVAL_SEC" > export.log

# Queries
MG_DB="select * from table(MON_GET_DATABASE(-2))"
MG_CON="select * from table(MON_GET_CONNECTION(NULL,-2,1))"
MG_LCK="select * from table(MON_GET_LOCKS(NULL,-2))"
MG_LCKW="select * from table(MON_GET_APPL_LOCKWAIT(NULL,-2,1))"
MG_LATCH="select * from table(MON_GET_LATCH(NULL,-2))"
MG_FCM="select * from table(MON_GET_FCM(-2))"
MG_BP="select * from table(MON_GET_BUFFERPOOL(NULL,-2))"
MG_TS="select * from table(MON_GET_TABLESPACE(NULL,-2))"
MG_INDEX="select * from table(MON_GET_INDEX(NULL,NULL,-2))"
MG_TABLE="select * from table(MON_GET_TABLE(NULL,NULL,-2))"

MG_PKGCHS="select * from table(MON_GET_PKG_CACHE_STMT(NULL,NULL,NULL,-2))"

# dump the query headers first
 
db2 "$MG_DB fetch first 1 row only with ur" > mon_get_db_$TS.txt
db2 "$MG_CON fetch first 1 row only with ur" > mon_get_con_$TS.txt
db2 "$MG_LCK fetch first 1 row only with ur" > mon_get_lck_$TS.txt
db2 "$MG_LCKW fetch first 1 row only with ur" > mon_get_lckw_$TS.txt
db2 "$MG_LATCH fetch first 1 row only with ur" > mon_get_latch_$TS.txt
db2 "$MG_FCM fetch first 1 row only with ur" > mon_get_fcm_$TS.txt
db2 "$MG_BP fetch first 1 row only with ur" > mon_get_bp_$TS.txt
db2 "$MG_TS fetch first 1 row only with ur" > mon_get_ts_$TS.txt
db2 "$MG_INDEX fetch first 1 row only with ur" > mon_get_index_$TS.txt
db2 "$MG_TABLE fetch first 1 row only with ur" > mon_get_table_$TS.txt
db2 "$MG_PKGCHS fetch first 1 row only with ur" > mon_get_pkgcache_$TS.txt

let "nn=NUM_SNAPS"

while ((nn--))
do
	if [ $NUM_SNAPS -gt 1 ]
	then
	   TS=`date +%Y_%m_%d_%H_%M_%S_%N`
	fi
	
	# export data
	echo "Start Export " 
	echo "Export $MG_DB" 
	db2 "export to mon_get_db_$TS.csv of del $MG_DB" >> export.log 2>&1
	echo "Export $MG_CON"
	db2 "export to mon_get_con_$TS.csv of del $MG_CON"  >> export.log 2>&1
	echo "Export $MG_LCK"
	db2 "export to mon_get_lck_$TS.csv of del $MG_LCK"  >> export.log 2>&1
	echo "Export $MG_LCKW"
	db2 "export to mon_get_lckw_$TS.csv of del $MG_LCKW"  >> export.log 2>&1
	echo "Export $MG_LATCH"
	db2 "export to mon_get_latch_$TS.csv of del $MG_LATCH"  >> export.log 2>&1
	echo "Export $MG_FCM"
	db2 "export to mon_get_fcm_$TS.csv of del $MG_FCM"  >> export.log 2>&1
	echo "Export $MG_BP"
	db2 "export to mon_get_bp_$TS.csv of del $MG_BP"  >> export.log 2>&1
	echo "Export $MG_TS"
	db2 "export to mon_get_ts_$TS.csv of del $MG_TS"  >> export.log 2>&1
	echo "Export $MG_INDEX"
	db2 "export to mon_get_index_$TS.csv of del $MG_INDEX"  >> export.log 2>&1
	echo "Export $MG_TABLE"
	db2 "export to mon_get_table_$TS.csv of del $MG_TABLE"  >> export.log 2>&1
	
	echo "Export $MG_PKGCHS"
	mkdir -p mon_get_pkgchs_lob_$TS
	db2 "export to mon_get_pkgchs_$TS.csv of del lobs to mon_get_pkgchs_lob_$TS $MG_PKGCHS" >> export.log 2>&1
	
	if [ "$GET_DB2PD_LATCHES" == "$YES" ]
	then
	    echo "db2pd -latches" >> export.log
	    echo "db2pd -latches"
	    db2pd -latches > db2pd_latches_$TS.txt 2>&1
	fi
	if [ "$nn" -gt "$ZERO" ]
	then
	  echo "Sleeping for $COLLECT_INTERVAL_SEC sec until next collection..."
	  sleep $COLLECT_INTERVAL_SEC
	fi
done

ETS=`date +%Y_%m_%d_%H_%M_%S`
echo "Collection time:$STS,$ETS" >> export.log

cd ..
if ! tar -czf ${CFN}.tgz $CFN
then
  echo "Unable to create archive ${CFN}.tgz"
  exit 5
fi
echo "Created archive ${CFN}.tgz"
# cleanup
rm -rf $CFN
