# Slooo: A Fail-slow Fault Injection Testing Framework

Slooo is a Xonsh-based fault injection framework for distributed systems.

Slooo is a part of [the DepFast project](https://tianyin.github.io/pub/depfast-hotos.pdf) in which we evaluate the fail-slow fault tolerance of a quorum system using fault injection, e.g., slowing down a node by adding delays and creating contention on the CPU/memory/disk.

Doing such fault injection requires a lot of scripting. Some are application specific (e.g., scripts to start and terminate the system) and some are generic (e.g., injecting certain types of faults).

We wrote a lot of shell scripts for fast scripting, but soon we ran into maintenance hell, especially every time there is a major reorgs of the team (members leaving and joining). After many rounds of energy draining and time wasting, we decided to write a more structured, reusable framework to minimize the overhead.

The choice of using [Xonsh](https://xon.sh/) comes from the following considerations:
* We still need shell scripts for the ease of integration. Specifically, many of the scripts of the system under test are in shell.
* We want high-level languages which can build some abstractions and reusable code.

Xonsh serves both – it is a chimera of Python and Shell.

We have used Slooo to test a number of quorum systems, including RethinkDB, MongoDB, TiDB, and Copilot.

The test can be done in a "pseudo-distributed" mode and in cloud environments. The former runs all the tests on one machine and the latter runs the tests in a cloud platform. Currently, we only support Azure Cloud (which sponsored the DepFast project).

Please checkout the [tutorial](https://github.com/xlab-uiuc/slooo/blob/main/tutorial.md) on how to write fault-injection tests using Slooo.
