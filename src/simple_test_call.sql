-- db2procExplnAct.sh -d sample -m actuals -rs SYSPROC -rn ADMIN_MOVE_TABLE -sf simple_test_call.sql
-- db2procExplnAct.sh -d sample -m actuals -rs SYSPROC -rn ADMIN_MOVE_TABLE -st "CALL SYSPROC.ADMIN_MOVE_TABLE('DB2INST1','EMPLOYEE','','','','','','','','EMPLOYEE2','COPY')"
CALL SYSPROC.ADMIN_MOVE_TABLE('DB2INST1','EMPLOYEE','','','','','','','','EMPLOYEE2','COPY')
