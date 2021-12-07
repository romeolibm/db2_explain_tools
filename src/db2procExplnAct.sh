#!/bin/bash
##############################################################################
# Script used to generate bulk explain plans for a given routine call
# in a db2 database.
# 
# To use, first execute the setup phase against your database if this is the
# first use or you need to update the database objects
#
# Setup phase syntax:
# 
# db2procEplnAct.sh <db-name> _setup_
#
# to extract the execution plans (db2exfmt) for all statements of a routine
# after setup phase (only once needed) use the following syntax:
#
# Execution phase:
#  
#  db2procExplnAct.sh <db-alias> <mode:base|actuals> <sp-call-or-command-starting-with-'db2'>
#
# Example 1: Explain all statements executed by a routine or simple SQL (one line SQL)
#  
#  db2procEplnAct.sh SAMPLE base "call my_proc('param1','param2',?)"
#  
# Example 2: Explain all statements executed by shell script  
#
#  db2procExplnAct.sh sample actuals db2_my_sql_script.sh
#
# The output of the script will be a .tgz archive following the naming pattern
#
# db2exfmt_<db-name>_<timestamp>.tgz
#
# Collect the explains including section actuals 
#
# db2procEplnAct.sh SAMPLE actuals "call my_proc('param1','param2',?)"
#
##############################################################################

DB="$1"
MODE="$2"
SQL="$3"

RTN_SCHEMA="USER"
RTN_NAME="'NONE'"

if [ -z "$DB" ]
then
  DB="--help"
fi

if [ "$DB" == "--help" ]
then
	cat << EOF
------------------------------------------------------------------------------

A script used to execute explain from activity bulk explains for a given
routine call or script you provide as the last parameter of this script.
	
When used for the first time, or the version of the stored procedure 
defined and used by the script changes you need to execute the setup
phase.

  Setup phase:
  
  db2procExplnAct.sh <db-alias> _setup_

  Execution phase:
  
  db2procExplnAct.sh <db-alias> <mode:base|actuals> <sp-call-or-command-starting-with-'db2'>

  Example 1: Explain all statements executed by a routine or simple SQL (one line SQL)
  
  db2procExplnAct.sh sample actuals 'call my_sp()'
  
  Example 2: Explain all statements executed by shell script  

  db2procExplnAct.sh sample actuals db2_my_sql_script.sh
  
  The script when sucessful will generate a .tgz archive with the name pattern
  
  db2exfmt_<db-alias>_<current-timestamp>.tgz
  
  the file is usuely sent to the IBM SMEs for RCA (via ECUREP) 

------------------------------------------------------------------------------
EOF
  exit 100
fi

if [ -z "$MODE" ]
then
  echo "A collection mode (base|actuals) must be specified as second parameter of this script!"
  exit 1
else
	if [ "$MODE" == "base" ]
	then
		echo "Collecting mode = base"
	elif [ "$MODE" == "actuals" ]
	then
		echo "Collecting mode = actuals"	
	elif [ "$MODE" == "_setup_" ]
	then
		echo "Setup mode!"	
	else
		echo "Invalid collection mode:$MODE expecting 'base' or 'actuals'"
		exit 2
	fi
fi

if [ "$MODE" != "_setup_" ]
then
	if [ -z "$SQL" ]
	then
	  echo "A SQL call statement must be specified as second parameter of this script!"
	  exit 1
	fi
fi

if [ "$MODE" == "_setup_" ]
then
  	cat << EOF > db2exfmtsetup.sql
create tablespace monspace in IBMDEFAULTGROUP managed by automatic storage
@
CALL SYSPROC.SYSINSTALLOBJECTS('EXPLAIN', 'C', CAST (NULL AS VARCHAR(128)), USER)
@
CREATE EVENT MONITOR ACTEVMON
       FOR ACTIVITIES
       WRITE TO TABLE
       ACTIVITY (TABLE ACTIVITY_ACTEVMON
                 IN MONSPACE
                 PCTDEACTIVATE 100),
       ACTIVITYMETRICS (TABLE ACTIVITYMETRICS_ACTEVMON
                        IN MONSPACE
                        PCTDEACTIVATE 100),
       ACTIVITYSTMT (TABLE ACTIVITYSTMT_ACTEVMON
                     IN MONSPACE
                     PCTDEACTIVATE 100),
       ACTIVITYVALS (TABLE ACTIVITYVALS_ACTEVMON
                     IN MONSPACE
                     PCTDEACTIVATE 100),
       CONTROL (TABLE CONTROL_ACTEVMON
                IN MONSPACE
                PCTDEACTIVATE 100)
       MANUALSTART
@

CREATE EVENT MONITOR PKGEVMON
       FOR PACKAGE CACHE
       WRITE TO TABLE
       PKGCACHE (TABLE PKGCACHE_PKGEVMON
                 IN MONSPACE
                 PCTDEACTIVATE 100),
       PKGCACHE_METRICS (TABLE PKGCACHE_METRICS_PKGEVMON
                        IN MONSPACE
                        PCTDEACTIVATE 100),
       PKGCACHE_STMT_ARGS (TABLE PKGCACHE_STMT_ARGS_PKGEVMON
                        IN MONSPACE
                        PCTDEACTIVATE 100),
       CONTROL (TABLE CONTROL_PKGEVMON
                IN MONSPACE
                PCTDEACTIVATE 100)
       MANUALSTART
@

DROP TABLE DB2EXFMT_STMTS
@

CREATE GLOBAL TEMPORARY TABLE DB2EXFMT_STMTS (
  ins_ts timestamp default current_timestamp,
  stmt varchar(1024)
) ON COMMIT PRESERVE ROWS
@

CREATE OR REPLACE PROCEDURE 
explain_from_section
(
  in p_rtn_schema      varchar(128),
  in p_rtn_name        varchar(128),
  in p_max_stmts       int default 20,
  in p_expln_src       varchar(64) default 'activity',
  in p_evmon_in        varchar(128) default 'ACTEVMON',
  in explain_schema_in varchar(128) default USER
)
specific explain_from_section
begin
	DECLARE SQLCODE INTEGER DEFAULT 0;
	DECLARE SQLSTATE CHAR(5) DEFAULT '00000';
	DECLARE at_end SMALLINT DEFAULT 0;
	DECLARE retcode int default 0;
	DECLARE SQL_MESSAGE_TEXT VARCHAR(32672) DEFAULT '';
	DECLARE STMT1 VARCHAR(1024);
	DECLARE EXEC_ID VARCHAR(32) FOR BIT DATA default NULL;
	DECLARE tot_act_time bigint default 0;
	DECLARE APPL_ID_V varchar(64) default '';
	DECLARE UOW_ID_V integer default 0;
	DECLARE ACTIVITY_ID_V bigint default 0;
        DECLARE first_use_time_v timestamp;
	DECLARE I INTEGER default 0;
	DECLARE rcode INT;
	DECLARE errorLabel varchar(32672);
	
	DECLARE EXPLAIN_REQUESTOR 	VARCHAR(128) DEFAULT '';
	DECLARE EXPLAIN_SCHEMA 		VARCHAR(128) DEFAULT ''; 
	DECLARE EXPLAIN_TIME 		TIMESTAMP;
	DECLARE EXECUTION_TIME 		TIMESTAMP;
	DECLARE SOURCE_NAME			VARCHAR(128) DEFAULT '';
	DECLARE SOURCE_SCHEMA		VARCHAR(128) DEFAULT '';
	DECLARE SOURCE_VERSION		VARCHAR(64) DEFAULT '';
	DECLARE DBNAME				VARCHAR(18) DEFAULT '';
	DECLARE DB2EXFMT_RUN		VARCHAR(1024) DEFAULT '';
	
    DECLARE NUM_EXEC_WITH_METRICS 	BIGINT;
    DECLARE SECTION_TYPE  			CHAR(1);
    DECLARE SECTION_NUMBER 			BIGINT;
    DECLARE PACKAGE_SCHEMA 			VARCHAR(128);
    DECLARE PACKAGE_NAME            VARCHAR(128);
    DECLARE DB2VERSION              VARCHAR(64);
    DECLARE COLSET1                 VARCHAR(64) default 'stmtid,planid';
    DECLARE COLSET2                 VARCHAR(64) default 'stmtid,planid';
    
	DECLARE C1 CURSOR FOR S1;
	DECLARE C2 CURSOR FOR S2;
	-- in case of no data found  
	--  DECLARE EXIT HANDLER FOR NOT FOUND
	--    SIGNAL SQLSTATE value '38200' SET MESSAGE_TEXT= '100: NO DATA FOUND'; 
	DECLARE CONTINUE HANDLER FOR NOT FOUND
	SET at_end = 1;
	-- Capture full SQL message text for SQL errors and warnings
	DECLARE CONTINUE HANDLER FOR SQLEXCEPTION, SQLWARNING
	begin
	  get diagnostics exception 1 SQL_MESSAGE_TEXT = MESSAGE_TEXT;
	  SET rcode = SQLCODE;
	end;
	
	set DB2VERSION=(select distinct prod_release from sysibmadm.env_prod_info fetch first row only);
	if DB2VERSION='10.1' 
	then
	   set COLSET1='package_name,section_number,varchar(stmt_text,200)';
	   set COLSET2='package_name,section_number';
	end if;
		
	insert into db2EXFMT_STMTS values (current timestamp, '#!/bin/bash');
	--------------------------------------------------------------------------------
	-- Perform the explains from section fond in the package cache
	--------------------------------------------------------------------------------
	insert into db2EXFMT_STMTS values (current timestamp,
	   '#start:p_rtn_schema:'
	   ||coalesce(p_rtn_schema,'NULL')
	   ||' p_rtn_schema:'||coalesce(p_rtn_schema,'NULL')
	   ||' p_rtn_name:'||coalesce(p_rtn_name,'NULL')
	   ||' p_max_stmts:'||coalesce(p_max_stmts,'NULL')
	   ||' p_expln_src:'||coalesce(p_expln_src,'NULL')
	   ||' p_evmon_in:'||coalesce(p_evmon_in,'NULL')
	   ||' explain_schema_in:'||coalesce(explain_schema_in,'NULL')
	);
	set APPL_ID_V = (values sysproc.mon_get_application_id());
	
	insert into db2EXFMT_STMTS values (current timestamp,'#msg:appl_id:'||coalesce(APPL_ID_V,'NULL'));
	
	--------------------------------------------------------------------------------
	-- Select all the statements present in the package cache generated by the SP call
	--------------------------------------------------------------------------------
	if (p_expln_src = 'section') then
		set stmt1 = 'SELECT executable_id, TOTAL_ACT_TIME '|| 
        ',NUM_EXEC_WITH_METRICS, SECTION_TYPE, SECTION_NUMBER '||
        ',PACKAGE_SCHEMA, PACKAGE_NAME '|| 
		' FROM '||
		'TABLE (MON_GET_PKG_CACHE_STMT(null, null, null, -1)) as tf '||
		'where (tf.package_schema,tf.package_name) in '||
		'(select '||
		'   varchar(d.bschema,20) as pkgschema, '||
		'   varchar(d.bname,40) as pkgname '||
		'from SYSCAT.STATEMENTS AS S, '||
		'SYSCAT.ROUTINEDEP AS D, '||
		'SYSCAT.ROUTINES   AS R '||
		'WHERE  D.BTYPE = ''K'' '||
		'AND R.SPECIFICNAME = D.ROUTINENAME '||
		'AND R.ROUTINESCHEMA = D.ROUTINESCHEMA '||
		'AND S.PKGSCHEMA = D.BSCHEMA '||
		'AND S.PKGNAME = D.BNAME '||
		'AND R.ROUTINESCHEMA = '''||coalesce(p_rtn_schema,'NULL')||''' '||
		'AND R.ROUTINENAME = '''||coalesce(p_rtn_name,'NULL')||''' '||
		') and TOTAL_ACT_TIME > 0 '||
		'order by 2 desc'
		||case when p_max_stmts=0 
		       then '' 
		       else ' fetch first '||coalescE(p_max_stmts,'NULL')||' rows only' 
		   end
		;
	elseif (p_expln_src = 'activity') then
        insert into db2EXFMT_STMTS values (current timestamp,'#Activity stmt1');
		set stmt1 = 'select uow_id, first_activity_id, first_use_time from( '
                    || 'SELECT distinct UOW_ID, '
                    || ' first_value(activity_id) over(partition by uow_id,'||colset1||' order by STMT_FIRST_USE_TIME) as first_activity_id, '
                    || ' first_value(STMT_FIRST_USE_TIME) over(partition by uow_id,'||colset1||' order by STMT_FIRST_USE_TIME) as first_use_time '
                    || ' FROM ACTIVITYSTMT_'
		    || p_evmon_in 
		    || ' where appl_id = ''' 
		    || appl_id_v 
		    || ''') as a order by first_use_time '
		    ||case when p_max_stmts=0 
		           then '' 
		           else ' fetch first '||p_max_stmts||' rows only' 
		       end
  	    ;
  	else 
  		insert into db2EXFMT_STMTS values (current timestamp,'#unknown src:'||coalesce(p_expln_src,'NULL'));
  		return;
	end if;
	
  	insert into db2EXFMT_STMTS values (current timestamp,'#sql:'||coalesce(stmt1,'NULL'));
	
  	prepare s1 from stmt1;
	IF (rcode < 0) THEN
	  set errorLabel = 'PREPARE S1:  ' || SQL_MESSAGE_TEXT;
	  SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT = errorLabel;
	  insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	  RETURN;
	END IF;
	
	OPEN C1;
	IF (rcode < 0) THEN
	  set errorLabel = 'OPEN C1:  ' || SQL_MESSAGE_TEXT;
	  SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT = errorLabel;
	  insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	  RETURN;
	END IF;
	
	if (p_expln_src = 'section') then
	  FETCH C1 INTO EXEC_ID, 
	    TOT_ACT_TIME,
    	NUM_EXEC_WITH_METRICS,
    	SECTION_TYPE,
    	SECTION_NUMBER,
    	PACKAGE_SCHEMA,
    	PACKAGE_NAME
	  ;
	else 
	  FETCH C1 INTO UOW_ID_V, ACTIVITY_ID_V, first_use_time_v;
	end if;
	  
	IF (rcode < 0) THEN
	  set errorLabel = 'FETCH C1 FIRST:  ' || SQL_MESSAGE_TEXT;
	  SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT = errorLabel;
	  insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	  RETURN;
	END IF;
	
	WHILE (at_end = 0) DO
	  set i = i + 1;
	  if (p_expln_src = 'section') then
            insert into db2EXFMT_STMTS values (current timestamp,
              '#sectinfo:'||i
              ||',TOTAL_ACT_TIME:'||coalesce(TOT_ACT_TIME,-1)
              ||',NUM_EXEC_WITH_METRICS:'||coalesce(NUM_EXEC_WITH_METRICS,-1)
              ||',SECTION_TYPE:'||coalesce(SECTION_TYPE,'')
              ||',SECTION_NUMBER:'||coalesce(SECTION_NUMBER,-1)
              ||',PACKAGE_SCHEMA:'||coalesce(PACKAGE_SCHEMA,'NULL')
              ||',PACKAGE_NAME:'||coalesce(PACKAGE_NAME,'NULL')
             );
		  CALL EXPLAIN_FROM_SECTION (
		    EXEC_ID ,'M', p_evmon_in, -1, 
		    EXPLAIN_SCHEMA_IN, 
		    EXPLAIN_REQUESTOR, 
		    EXPLAIN_TIME, 
		    SOURCE_NAME, 
		    SOURCE_SCHEMA, 
		    SOURCE_VERSION 
		  );
	  elseif (p_expln_src = 'activity') then
            insert into db2EXFMT_STMTS values (current timestamp,
              '#actinfo:'||i
              ||',APPL_ID_v:'||coalesce(APPL_ID_v,'NULL')
              ||',UOW_ID_V:'||coalesce(UOW_ID_V,0)
              ||',ACTIVITY_ID_V:'||coalesce(ACTIVITY_ID_V,0)
              ||',first_use_time:'||coalesce(''||first_use_time_v,'NULL')
              ||',p_evmon_in:'||coalesce(p_evmon_in,'NULL')
              ||',EXPLAIN_SCHEMA_IN:'||coalesce(EXPLAIN_SCHEMA_IN,'NULL')
             );
		  CALL EXPLAIN_FROM_ACTIVITY (
		  	APPL_ID_v, 
		  	UOW_ID_V,
		  	ACTIVITY_ID_V,
		  	p_evmon_in,
            EXPLAIN_SCHEMA_IN,
            EXPLAIN_REQUESTOR,
            EXPLAIN_TIME, 
            SOURCE_NAME, 
            SOURCE_SCHEMA, 
            SOURCE_VERSION
          );
	  end if;
	  
	  if (rcode = -20503 OR rcode = -20501) then
	    set rcode = 0;
	  end if;
	  
	  IF (rcode < 0) THEN
	    set errorLabel = 'EXPLAIN_FROM_'||p_expln_src
	      ||' '|| varchar(rcode) || ' ' || SQL_MESSAGE_TEXT;
	    SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT= errorLabel;
  	    insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	    RETURN;
	  END IF;
	  
	  insert into db2EXFMT_STMTS values (current timestamp,
	    '#explninfo:'||i
	    ||',EXPLAIN_REQUESTOR:'||coalesce(EXPLAIN_REQUESTOR,'NULL')
    	||',EXPLAIN_TIME:'||coalesce(''||EXPLAIN_TIME,'NULL')
    	||',SOURCE_NAME:'||coalesce(SOURCE_NAME,'NULL')
    	||',SOURCE_SCHEMA:'||coalesce(SOURCE_SCHEMA,'NULL')
    	||',SOURCE_VERSION:'||coalesce(SOURCE_VERSION,'NULL')
	  );
	  if (p_expln_src = 'section') then
		  FETCH C1 INTO EXEC_ID, 
		    TOT_ACT_TIME,
	    	NUM_EXEC_WITH_METRICS,
	    	SECTION_TYPE,
	    	SECTION_NUMBER,
	    	PACKAGE_SCHEMA,
	    	PACKAGE_NAME
		  ;
	  else 
		  FETCH C1 INTO UOW_ID_V, ACTIVITY_ID_V;
	  end if;
	  IF (rcode < 0 ) THEN
	    set errorLabel = 'FETCH C1:  ' || SQL_MESSAGE_TEXT;
	    SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT = errorLabel;
  	    insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	    RETURN;
	  END IF;
	END WHILE;
    commit;
	--------------------------------------------------------------------------------
	-- Create the db2exfmt commands to format each statement in the explain tables
	--------------------------------------------------------------------------------
	-- set explain_schema = rtrim(EXPLAIN_SCHEMA_IN);
	set stmt1 = 'SELECT explain_time, execution_time, source_name, source_schema from ' 
	    || rtrim(EXPLAIN_SCHEMA_IN) || '.explain_instance order by explain_time';
	SET at_end = 0;
	set db2exfmt_run = '';
	set dbname = (values current server);
	insert into db2EXFMT_STMTS values (current timestamp,'#msg:dbname:'||dbname);
	prepare s2 from stmt1;
	IF (rcode < 0) THEN
	  set errorLabel = 'PREPARE S2:  ' || SQL_MESSAGE_TEXT;
	  SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT = errorLabel;
	  insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	  RETURN;
	END IF;
	OPEN C2;
	IF (rcode < 0) THEN
	  set errorLabel = 'OPEN C2:  ' || SQL_MESSAGE_TEXT;
	  SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT = errorLabel;
	  insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	  RETURN;
	END IF;
	
	FETCH C2 INTO explain_time, execution_time, source_name, source_schema;
	IF (rcode < 0) THEN
	  set errorLabel = 'FETCH C2 FIRST:  ' || SQL_MESSAGE_TEXT;
	  SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT = errorLabel;
	  insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	  RETURN;
	END IF;
    set i = 0;
	
	WHILE (at_end = 0) DO
	  set i = i + 1;
	  insert into db2EXFMT_STMTS values (current timestamp,'#exfmt:'||i);
	  set db2exfmt_run = 'db2exfmt -d ' || coalesce(dbname,'NULL') 
	        || ' -1 -w '
	        || coalesce(varchar(explain_time),'NULL') 
	        || ' -o ' 
	        || coalesce(varchar(execution_time)||'_','') 
	        || coalesce(rtrim(source_schema),'NULL') 
	        || '_' || coalesce(source_name,'NULL') 
	        || '_' || i 
	        || '.exfmt'
	  ;
	  insert into db2EXFMT_STMTS values (current timestamp,db2exfmt_run);
	  FETCH C2 INTO explain_time, execution_time, source_name, source_schema;
	  IF (rcode < 0 ) THEN
	    set errorLabel = 'FETCH C2:  ' || SQL_MESSAGE_TEXT;
	    SIGNAL SQLSTATE '71000' SET MESSAGE_TEXT = errorLabel;
  	    insert into db2EXFMT_STMTS values (current timestamp,'#err:'||errorLabel);
	    RETURN;
	  END IF;
	END WHILE;
	commit;
	--------------------------------------------------------------------------------      
	-- Completion
	insert into db2EXFMT_STMTS values (
	   current timestamp,
	   'db2 connect to '|| coalesce(dbname,'NULL')
	);
	
	set stmt1 = 'select a.appl_id,' 
       ||'a.uow_id,' 
       ||'a.activity_id,'
       ||'dec((a.act_exec_time / 1e6),8,3) exec_time_secs,' 
       ||'a.time_created, '
       ||'a.time_started, '
       ||'a.time_completed, '||colset2||',' 
       ||'varchar(s.stmt_text,200) stmt_text, ' 
       ||'length(s.section_env) as section_len '
	||'from '
  		||'ACTIVITY_ACTEVMON a, '
  		||'ACTIVITYSTMT_ACTEVMON s '
	||'where a.appl_id = '''||APPL_ID_v||'''' 
	||' and a.appl_id = s.appl_id '
	||' and a.uow_id = s.uow_id '
	||' and a.activity_id = s.activity_id '
	||' and a.partition_number = a.COORD_PARTITION_NUM '
	||'order by 1,2,4 desc '
	;
	insert into db2EXFMT_STMTS values (
	   current timestamp,
	   'db2 "'||stmt1||'" > db2exfmtTiming.txt'
	);
	
	SET stmt1='select a.appl_id, a.uow_id, '
		||'count(*) num_execs,'
		||'dec((min(a.act_exec_time) / 1e6),8,3) as min_etime,'
		||'dec((avg(a.act_exec_time) / 1e6),8,3) as avg_etime,'
		||'dec((max(a.act_exec_time) / 1e6),8,3) as max_etime,'
                || colset1
		||' from '
		||' ACTIVITY_ACTEVMON a,'
		||' ACTIVITYSTMT_ACTEVMON s'
		||' where a.appl_id = '''||APPL_ID_v||'''' 
		||' and a.appl_id = s.appl_id '
		||' and a.uow_id = s.uow_id '
		||' and a.activity_id = s.activity_id '
		||' and a.partition_number = a.COORD_PARTITION_NUM'
		||' group by a.appl_id, a.uow_id, '||colset1
		||' order by avg_etime desc'
	;
	insert into db2EXFMT_STMTS values (
	   current timestamp,
	   'db2 "'||stmt1||'" > db2exfmtTimingAgg.txt'
	);
	
	SET errorLabel = 'Success';
	insert into db2EXFMT_STMTS values (current timestamp,'#msg:'||errorLabel);
	insert into db2EXFMT_STMTS values (current timestamp,
	  'tar -czf db2exfmt_'
	  ||coalesce(dbname,'NULL')
	  ||'_'||current_timestamp
	  ||'.tgz db2exfmt*.* *.exfmt'
    );
end 
@  	
EOF
    echo "Executing setup SQL from file db2exfmtsetup.sql"
  	db2 connect to $DB
  	db2 -td@ -v -f db2exfmtsetup.sql >  db2exfmtsetup.log 2>&1
  	exit 0
fi

db2 -v connect to $DB
db2 -v "truncate db2EXFMT_STMTS immediate"
db2 -v "truncate ACTIVITY_ACTEVMON immediate"
db2 -v "truncate ACTIVITYMETRICS_ACTEVMON immediate"
db2 -v "truncate ACTIVITYSTMT_ACTEVMON immediate"
db2 -v "truncate ACTIVITYVALS_ACTEVMON immediate"
db2 -v "truncate CONTROL_ACTEVMON immediate"
db2 -v "delete from explain_instance"

if [ "$MODE" == "actuals" ]
then
 db2 -v "call wlm_set_conn_env(null, '<collectactdata>with details, section</collectactdata><collectactpartition>ALL</collectactpartition><collectsectionactuals>base</collectsectionactuals>')" 
else	
 db2 -v "call wlm_set_conn_env(null, '<collectactdata>with details, section</collectactdata><collectactpartition>ALL</collectactpartition>')"
fi	

db2 -v "SET EVENT MONITOR ACTEVMON STATE 1"
if [[ "$SQL" =~ ^db2.* ]]; then
  # the "SQL" is an actual db2 CLI command that will be executed "as is"
  # use if you need to explain all statements executed by a statement, script or application that
  # can be executed as a command (shell script)
  $SQL
else
  db2 -v "$SQL"
fi
db2 -v "SET EVENT MONITOR ACTEVMON STATE 0"
db2 -v "call wlm_set_conn_env(null, '<collectactdata>none</collectactdata>')"

db2 -v "call explain_from_section(${RTN_SCHEMA},${RTN_NAME},0,'activity','ACTEVMON')"
db2 -x "select stmt from DB2EXFMT_STMTS ORDER BY INS_TS" >> db2exfmtall.sh
chmod a+x db2exfmtall.sh
./db2exfmtall.sh > db2exfmtall.log 2>&1
rm *.exfmt db2exfmt*.txt db2exfmt*.log db2exfmtall.sh 
