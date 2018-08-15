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
import ocean.io.Stdout;

class AsyncIOUsingApp: DaemonApp
{
    AsyncIO async_io;
	AsyncIO.Context makeContext ()
	{
		auto ctx = new CurlContext;
		ctx.curl = curl_easy_init();

        if (ctx.curl)
        {
            FILE* dev_null = fopen("/dev/null", "w+");
            curl_easy_setopt(ctx.curl, CURLoption.WRITEDATA, dev_null);
        }

        return ctx.curl? ctx : null;
	}

    this ()
    {
        istring name = "Application";
        istring desc = "Testing async IO";

        DaemonApp.OptionalSettings settings;
        settings.scheduler_config.worker_fiber_limit = 5_000;
        settings.scheduler_config.task_queue_limit = 50_000;
        settings.scheduler_config.suspended_task_limit = 50_000;
        settings.use_task_ext = true;

        super(name, desc, VersionInfo.init, settings);
    }

    int count;

    class MyTask: Task
    {
        char[] recv_buffer;
        size_t received;

        private void curlGetSomething (AsyncIO.Context ctx)
        {
           auto curl_context = cast(CurlContext)ctx;

           curl_easy_setopt(curl_context.curl, CURLoption.URL, "http://example.com".ptr);

           curl_easy_setopt(curl_context.curl, CURLoption.FOLLOWLOCATION, 1L);
           curl_easy_setopt(curl_context.curl, CURLoption.WRITEFUNCTION, &MyTask.write_data);
           curl_easy_setopt(curl_context.curl, CURLoption.WRITEDATA, cast(void*)this);

           auto res = curl_easy_perform(curl_context.curl);
           if (res == 0)
           {
               long resp;
               curl_easy_getinfo(curl_context.curl, CurlInfo.CURLINFO_RESPONSE_CODE, &resp);
           }
        }

        private static extern(C) void write_data(void* buffer, size_t size, size_t nmemb, void* task_ptr)
        {
            auto task = cast(MyTask)task_ptr;
            task.recv_buffer[task.received..task.received+nmemb] = cast(char[])buffer[0..nmemb];
            task.received += nmemb;
        }

        override void run ()
        {
            recv_buffer.length = 15_000;

            this.outer.async_io.blocking.callDelegate(&this.curlGetSomething);
            this.outer.count++;

            // request is here finished
            Stdout.formatln("Response body: {}", recv_buffer[0..received]);

            if (this.outer.count % 1000 == 0)
                printf("Done %d requests.\n", this.outer.count);

            if (this.outer.count == 10_000)
            {
                theScheduler.shutdown();
                Stdout.formatln("Destroying asyncio").flush;
                this.outer.async_io.destroy();
                Stdout.formatln("Destroyed asyncio").flush;
            }
        }
    }

    Task[] arr;

    import core.sys.posix.pthread;

    // Called after arguments and config file parsing.
    override protected int run ( Arguments args, ConfigParser config )
    {
        this.async_io = new AsyncIO(theScheduler.epoll, 500, &makeContext);

        for (int i  = 0; i < 10_000; i++)
            arr ~= new MyTask;

        foreach (t; arr)
            theScheduler.schedule(t);

        //theSchedler.processEvents();
        //theScheduler.shutdown();
        return 0; // return code to OS
    }
}

    class CurlContext: AsyncIO.Context
    {
        CURL curl;
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

    auto app = new AsyncIOUsingApp();
    auto ret = app.main(args);
}
