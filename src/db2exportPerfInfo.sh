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
DB="$1"

if [ -z "$DB" ]
then
  DB="--help"
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

# Queries
MG_DB="select * from table(MON_GET_DATABASE(-2))"
MG_CON="select * from table(MON_GET_CONNECTION(NULL,-2,1))"
MG_LCK="select * from table(MON_GET_LOCKS(NULL,-2))"
MG_LCKW="select * from table(MON_GET_APPL_LOCKWAIT(NULL,-2,1))"
MG_LATCH="select * from table(MON_GET_LATCH(NULL,-2))"

MG_PKGCHS="select * from table(MON_GET_PKG_CACHE_STMT(NULL,NULL,NULL,-2))"

# dump the query headers first
 
db2 "$MG_DB fetch first 1 row only with ur" > mon_get_db_$TS.txt
db2 "$MG_CON fetch first 1 row only with ur" > mon_get_con_$TS.txt
db2 "$MG_LCK fetch first 1 row only with ur" > mon_get_lck_$TS.txt
db2 "$MG_LCKW fetch first 1 row only with ur" > mon_get_lckw_$TS.txt
db2 "$MG_LATCH fetch first 1 row only with ur" > mon_get_latch_$TS.txt
db2 "$MG_PKGCHS fetch first 1 row only with ur" > mon_get_pkgcache_$TS.txt

# export data
echo "Export $MG_DB"
db2 "export to mon_get_db_$TS.csv of del $MG_DB" >> export.log 2>&1
echo "Export $MG_CON"
db2 "export to mon_get_con_$TS.csv of $MG_CON"  >> export.log 2>&1
echo "Export $MG_LCK"
db2 "export to mon_get_lck_$TS.csv of del $MG_LCK"  >> export.log 2>&1
echo "Export $MG_LCKW"
db2 "export to mon_get_lckw_$TS.csv of del $MG_LCKW"  >> export.log 2>&1
echo "Export $MG_LATCH"
db2 "export to mon_get_latch_$TS.csv of del $MG_LATCH"  >> export.log 2>&1

echo "Export $MG_PKGCHS"
mkdir -p mon_get_pkgchs_lob_$TS
db2 "export to mon_get_pkgchs_$TS.csv of del lobs to mon_get_pkgchs_lob_$TS $MG_PKGCHS" >> export.log 2>&1

cd ..
if ! tar -czf ${CFN}.tgz $CFN
then
  echo "Unable to create archive ${CFN}.tgz"
  exit 5
fi
echo "Created archive ${CFN}.tgz"
# cleanup
rm -rf $CFN
