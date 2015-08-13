PS Checker
==========

Simple web app to pull PostgreSQL JSON-formatted data into Google Chart

Installation
------------

Everything is self-contained in here, so as long as you have at least `git`,
`make`, `sed`, and a C compiler (`gcc` on FreeBSD, `cc` on Linux/OS X) in your
`$PATH`, all you should need to do is the following:

```
make
make run
```

The `make` step will build a copy of PostgreSQL 9.4.4 with [multicorn][] and
[pgosquery][] installed and a pre-built database cluster in `.db`, as well as
Ruby 2.2.2 and Python 2.7.10. It will compile and install a custom background
worker to periodically check the CPU consumption of various groups of
processes, and put them into the stats table.

The `make run` starts up the database, which kicks off the process monitoring,
and a web frontend which can query the stats and display the results in a
[Google-Chart][]-powered form, which automatically updates every second
(roughly how often the default `ps_checker` BGWorker kicks off).

The build process is not written to be run without a web connection;
similarly, the stylesheets and the majority of the JS code required to display
the output in the browser simply references a CDN source, rather than copying
it down locally. At the very least, the [Google-Chart][] [TOS][] will not
allow for downloaded use of the code.

In short: you can't really run this without a web connection.

Additionally, while I've tried to make sure that everything, once compiled,
will still show a "clean" repository, the `make` stage for fixing semantic
versioning in `pgxnclient` results in modifications in that repository. If
this really bugs you, you can run the following:

```
(cd vendor/pgxnclient && git clean -fdx && git reset --hard HEAD)
```

To completely remove everything and start fresh again, run the following
command (NOTE: this empties your database entirely as well as removes all
compiled code):

```
make clean
```

Purpose
-------

This project can be used to demo an easy way to interact with live PostgreSQL
data using Google Chart, via the PostgreSQL JSON/JSONB datatypes. It includes
both a complex background worker/FDW interaction that updates real-time system
statistics, as well as showcases a few charts that could have real-world
analogues to actual scientific data — it is written as a "presentation" of
sorts for colleagues at the National Institute on Aging.

Along the way, I used it as an opportunity to get my feet wet in a few new
skills as well:

  * How to write and compile PostgreSQL-ready C code
  * How to create and/or load a PostgreSQL background worker
  * How to work with PostgreSQL foreign data wrappers/multicorn
  * How to write a workable Makefile

There aren't really many practical production-level applications for this
code; as far as monitoring tools, there are obviously a ridiculous number of
them out there already, the barest of which eclipses this project's
functionality entirely.

Compatibility
-------------

As everything is self-contained, most of the dependencies should be met so
long as you have appropriate build tools available. I have only tested
building this on a Mac OS X 10.10 ("Yosemite") system, but I believe it should
be possible to build it on both Linux and FreeBSD as well.

Credits
-------

A large part of the `ps_checker` code is more-or-less copied from the
`worker_spi` example in PostgreSQL's contrib directory, so thank you to the
author for writing it as a useful guide, as well as for the feature!

License
-------

PostgreSQL license. See [LICENSE.MD][].

-----

[multicorn]:    http://multicorn.org/
[pgosquery]:    https://github.com/shish/pgosquery
[Google-Chart]: https://developers.google.com/chart/?hl=en
[LICENSE.md]:   LICENSE.md
