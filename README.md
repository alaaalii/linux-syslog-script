LinuxSyslogScript
=================

```
Usage: ./LinuxSyslogScript.sh [options]

LinuxSyslogScript is a script used to configure your Linux machine to send authentication
and/or audit logs to an external (syslog) server through the syslog daemon.

If the script is run without specifying the remote IP address, you will be prompted to enter it.
If the script is run without specifying any "send" arguments (--audit or --auth), you will
be prompted to choose which logs to send. If you pass one or more "send" arguments, the script
will assume that you only want to send that and you will not be prompted while the script is running
to choose other log types. 

Options include:
      --audit		           Send audit daemon logs.
      --auth		           Send authentication logs.
  -h, --help		           Print this help message.
      --remoteip=X.X.X.X       The IP address to which you want this server to send logs to.
  -l, --license		           Show license information.
  -q, --quiet		           Do not display any messages (except ERROR messages).
  -qq			               Same as -q, but implies -y.
  -y, --yes		               Assume Yes to all "Continue?" questions and do not display prompts.

This script works by editing the syslog.conf or rsyslog.conf file to add the necessary line to send
logs. If audit logs are chosen to be sent, it will also edit the file /etc/audisp/plugins.d/syslog.conf.
The script takes a backup of any file before editing it.

LinuxSyslogScript, Copyright (C) 2014 Alaa Ali
LinuxSyslogScript comes with ABSOLUTELY NO WARRANTY; for details, pass the -l option to the script.
This is free software, and you are welcome to redistribute it
under certain conditions; pass the -l option to the script for details.

This script is maintained here: https://github.com/alaaalii/LinuxSyslogScript
```
