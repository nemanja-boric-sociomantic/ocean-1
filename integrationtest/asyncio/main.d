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

class AsyncIOUsingApp: DaemonApp
{
    DefaultAsyncIO async_io;

    this ( )
    {

        istring name = "Application";
        istring desc = "Testing async IO";

        DaemonApp.OptionalSettings settings;
        settings.use_task_ext = true;

        super(name, desc, VersionInfo.init, settings);
    }

    /// counter value to set from the working thread
    int counter;

    /// Callback called from another thread to set the counter
    private void setCounter ()
    {
        this.counter++;
    }

    // Called after arguments and config file parsing.
    override protected int run ( Arguments args, ConfigParser config )
    {
        this.async_io = new DefaultAsyncIO(theScheduler.epoll, 10);

        // open a new file
        auto f = new File("var/output.txt", File.ReadWriteAppending);

        char[] buf = "Hello darkness, my old friend.".dup;
        this.async_io.blocking.write(buf, f.fileHandle());

        buf[] = '\0';
        this.async_io.blocking.pread(buf, f.fileHandle(), 0);

        test!("==")(buf[], "Hello darkness, my old friend.");
        test!("==")(f.length, buf.length);

        this.async_io.blocking.callDelegate(&setCounter);
        test!("==")(this.counter, 1);

        theScheduler.shutdown();
        return 0; // return code to OS
    }
}

version(UnitTest) {} else
void main(istring[] args)
{

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
