/*******************************************************************************

    Test for AsyncIO.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH.
        All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE_BOOST.txt for details.
        Alternatively, this file may be distributed under the terms of the Tango
        3-Clause BSD License (see LICENSE_BSD.txt for details).

*******************************************************************************/

module integrationtest.asyncio.main;

import ocean.transition;

import core.sys.posix.sys.stat;
import ocean.core.Test;
import ocean.sys.ErrnoException;
import ocean.util.app.DaemonApp;
import ocean.task.Scheduler;
import ocean.task.Task;
import ocean.util.aio.AsyncIO;
import ocean.io.device.File;
import ocean.util.test.DirectorySandbox;
import core.memory;
import core.stdc.stdio;
import integrationtest.asyncio.curl;

class AsyncIOUsingApp: DaemonApp
{
    AsyncIO async_io;

    static class CurlContext: AsyncIO.Context
    {
        CURL curl;
    }

	AsyncIO.Context makeContext ()
	{
        GC.disable();
		auto ctx = new CurlContext;
        GC.enable();
		ctx.curl = curl_easy_init();

        if (ctx.curl)
        {
            FILE* dev_null = fopen("/dev/null", "w+");
            curl_easy_setopt(ctx.curl, CURLoption.WRITEDATA, dev_null);
        }

        return ctx.curl? ctx : null;
	}

    this ( )
    {

        istring name = "Application";
        istring desc = "Testing async IO";

        DaemonApp.OptionalSettings settings;
        settings.scheduler_config.worker_fiber_limit = 6_000;
        settings.scheduler_config.task_queue_limit = 6_000;
        settings.scheduler_config.suspended_task_limit = 6_000;
        settings.use_task_ext = true;

        super(name, desc, VersionInfo.init, settings);
    }

    class MyTask: Task
    {
        private void curlGetSomething (AsyncIO.Context ctx)
        {
           GC.disable();
           auto curl_context = cast(CurlContext)ctx;
           GC.enable();
           curl_easy_setopt(curl_context.curl, CURLoption.URL, "http://example.com".ptr);

           /* example.com is redirected, so we tell libcurl to follow redirection */ 
           curl_easy_setopt(curl_context.curl, CURLoption.FOLLOWLOCATION, 1L);

           auto res = curl_easy_perform(curl_context.curl);
           if (res == 0)
           {
               long resp;
               curl_easy_getinfo(curl_context.curl, CurlInfo.CURLINFO_RESPONSE_CODE, &resp);
               printf("HTTP remote party status: %d\n", resp);
           }
        }

        void run ()
        {
            this.outer.async_io.blocking.callDelegate(&this.curlGetSomething);
        }
    }

    Task[] arr;

    // Called after arguments and config file parsing.
    override protected int run ( Arguments args, ConfigParser config )
    {
        this.async_io = new AsyncIO(theScheduler.epoll, 5_000, &makeContext);

        for (int i  = 0; i < 5_000; i++)
            arr ~= new MyTask;

        foreach (t; arr)
            theScheduler.schedule(t);

        //theSchedler.processEvents();
        //theScheduler.shutdown();
        return 0; // return code to OS
    }
}

version(UnitTest) {} else
void main(istring[] args)
{
    curl_global_init(CURL_GLOBAL_DEFAULT);

    initScheduler(SchedulerConfiguration.init);
    theScheduler.exception_handler = (Task t, Exception e) {
        throw e;
    };

    auto sandbox = DirectorySandbox.create(["etc", "log", "var"]);

    File.set("etc/config.ini", "[LOG.Root]\n" ~
               "console = false\n\n");

    auto app = new AsyncIOUsingApp;
    auto ret = app.main(args);
}
