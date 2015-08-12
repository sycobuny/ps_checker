#include "ps_checker.h"

PG_MODULE_MAGIC;

void _PG_init(void);
void ps_checker_main(Datum);

static          int          ps_checker_naptime = PS_CHECKER_NAPTIME_DEFAULT;
static volatile sig_atomic_t got_sighup         = false;
static volatile sig_atomic_t got_sigterm        = false;

static void
ps_checker_sighup(SIGNAL_ARGS)
{
    int save_errno = errno;

    got_sighup = true;
    if (MyProc)
        SetLatch(&MyProc->procLatch);

    errno = save_errno;
}

static void
ps_checker_sigterm(SIGNAL_ARGS)
{
    int save_errno = errno;

    got_sigterm = true;
    if (MyProc)
        SetLatch(&MyProc->procLatch);

    errno = save_errno;
}

void
ps_checker_main(Datum main_arg)
{
    StringInfoData buf;

    pqsignal(SIGHUP,  ps_checker_sighup);
    pqsignal(SIGTERM, ps_checker_sigterm);
    BackgroundWorkerUnblockSignals();

    initStringInfo(&buf);
    appendStringInfo(&buf, PS_CHECKER_QUERY);

    BackgroundWorkerInitializeConnection("postgres", NULL);

    while (!got_sigterm)
    {
        int rc;

        rc = WaitLatch(
            &MyProc->procLatch,
            WL_LATCH_SET | WL_TIMEOUT | WL_POSTMASTER_DEATH,
            ps_checker_naptime * 1000L
        );
        ResetLatch(&MyProc->procLatch);

        if (rc & WL_POSTMASTER_DEATH)
            proc_exit(1);

        if (got_sighup)
        {
            got_sighup = false;
            ProcessConfigFile(PGC_SIGHUP);
        }

        SetCurrentStatementStartTimestamp();
        StartTransactionCommand();
        SPI_connect();
        PushActiveSnapshot(GetTransactionSnapshot());
        pgstat_report_activity(STATE_RUNNING, buf.data);

        SPI_execute(buf.data, false, 0);

        SPI_finish();
        PopActiveSnapshot();
        CommitTransactionCommand();
        pgstat_report_activity(STATE_IDLE, NULL);
    }

    proc_exit(1);
}

void
_PG_init(void)
{
    BackgroundWorker worker;

    DefineCustomIntVariable(
        PS_CHECKER_NAPTIME_VARNAME, PS_CHECKER_NAPTIME_SHORTDEF,
        PS_CHECKER_NAPTIME_LONGDEF, &ps_checker_naptime,
        PS_CHECKER_NAPTIME_DEFAULT, PS_CHECKER_NAPTIME_MIN,
        PS_CHECKER_NAPTIME_MAX,     PS_CHECKER_NAPTIME_CONTEXT,

        /* I honestly don't know what the following variables mean. That's
         * probably a bad thing.
         */
        0, NULL, NULL, NULL
    );

    if (!process_shared_preload_libraries_in_progress)
        return;

    worker.bgw_flags        = PS_CHECKER_BGW_FLAGS;
    worker.bgw_start_time   = BgWorkerStart_RecoveryFinished;
    worker.bgw_restart_time = BGW_NEVER_RESTART;
    worker.bgw_main         = ps_checker_main;
    worker.bgw_notify_pid   = 0;
    worker.bgw_main_arg     = Int32GetDatum(0);

    sprintf(worker.bgw_name, PS_CHECKER_BGW_NAME);

    RegisterBackgroundWorker(&worker);
}
