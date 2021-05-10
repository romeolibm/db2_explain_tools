# db2_explain_tools

A set of tools for generating bulk explain statements in a DB2 database 

# The db2procEplnAct.sh script

A script used to generate explain from activity statements for all statements 
executed by a stored procedure call including sestion actuals by using a 
session enabled event monitor for activities (minimal possible impact for 
performance for this type of explain plan generation) 

# Command syntax

```
db2procEplnAct.sh <db-name> <mode:base|actuals> "<SP call SQL>"
```
Where

* db-name is the database name where the SP call will be execued and explain data will be collected
* mode:base|actuals is one of the keywords 'base' or 'actuals'
  * base basic explains are collected without including section actuals
  * actuals full exlain data including section actuals will be collected
* SP call - is the SQL call statement to be executed
  
# Use Cases

If the database name is SAMPLE

* Setup

This will create an event monitor for activities and one for package cache and a helpper stored procedure 
in the database you will use the script on.

```
db2procEplnAct.sh SAMPLE _setup_
```

* Execute a stored procedure call and collect explain plans for its statements
```
db2procEplnAct.sh SAMPLE base "call my_proc('param1','param2',?)"
```
The command will create a .tgz archive with a name pattern:
```
db2exfmt_<db-name>_<current-timestamp>.tgz
```
