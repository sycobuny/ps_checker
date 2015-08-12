#include "postgres.h"
#include "miscadmin.h"
#include "postmaster/bgworker.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "storage/lwlock.h"
#include "storage/proc.h"
#include "storage/shmem.h"

#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "pgstat.h"
#include "utils/snapmgr.h"
#include "tcop/utility.h"

#define PS_CHECKER_NAPTIME_VARNAME "ps_checker.sleep"
#define PS_CHECKER_NAPTIME_SHORTDEF \
    "How long to sleep between polling osquery.processes"
#define PS_CHECKER_NAPTIME_LONGDEF \
    "This variable should define the total number of seconds that the " \
    "background worker will wait before awakening and polling the " \
    "`processes` table imported from osquery. The minimum value is 1, and " \
    "maximum value is 60. The default is 1."
#define PS_CHECKER_NAPTIME_DEFAULT 1
#define PS_CHECKER_NAPTIME_MIN     1
#define PS_CHECKER_NAPTIME_MAX     60
#define PS_CHECKER_NAPTIME_CONTEXT PGC_POSTMASTER

#define PS_CHECKER_BGW_FLAGS \
    BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION

#define PS_CHECKER_BGW_NAME "ps_checker"

#define PS_CHECKER_QUERY \
    "INSERT INTO stats (process_family, cpu_percent) " \
    "SELECT pattern, SUM(cpu_percent) " \
    "FROM " \
    "    processes INNER JOIN " \
    "    monitored_processes ON " \
    "    name ~~* ('%%' || pattern || '%%') " \
    "GROUP BY pattern"
