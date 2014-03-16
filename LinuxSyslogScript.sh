#!/bin/bash

# Author:		Alaa Ali <contact.alaa@gmail.com>
# LinkedIn:		http://www.linkedin.com/in/alaaalii
# Created on:	March 16, 2014
# Feel free to do anything you want with the script. Just give credit where credit is due =).

#Check if the script is being run as root.
if [ "$(whoami)" != "root" ]; then
    echo "You must run $(basename $0) as root."
    exit
fi

LICENSE="LinuxSyslogScript, Copyright (C) 2014 Alaa Ali

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.  

This script is maintained here: https://github.com/alaaalii/LinuxSyslogScript"

USAGE="Usage: ./$(basename $0) [options]

$(basename $0) is a script used to configure your Linux machine to send authentication
and/or audit logs to an external (syslog) server through the syslog daemon.

If the script is run without specifying the remote IP address, you will be prompted to enter it.
If the script is run without specifying any \"send\" arguments (--audit or --auth), you will
be prompted to choose which logs to send. If you pass one or more \"send\" arguments, the script
will assume that you only want to send that and you will not be prompted while the script is running
to choose other log types. 

Options include:
      --audit		   Send audit daemon logs.
      --auth		   Send authentication logs.
  -h, --help		   Print this help message.
      --remoteip=X.X.X.X   The IP address to which you want this server to send logs to.
  -l, --license		   Show license information.
  -q, --quiet		   Do not display any messages (except ERROR messages).
  -qq			   Same as -q, but implies -y.
  -y, --yes		   Assume Yes to all \"Continue?\" questions and do not display prompts.

This script works by editing the syslog.conf or rsyslog.conf file to add the necessary line to send
logs. If audit logs are chosen to be sent, it will also edit the file /etc/audisp/plugins.d/syslog.conf.
The script takes a backup of any file before editing it.

LinuxSyslogScript, Copyright (C) 2014 Alaa Ali
LinuxSyslogScript comes with ABSOLUTELY NO WARRANTY; for details, pass the -l option to the script.
This is free software, and you are welcome to redistribute it
under certain conditions; pass the -l option to the script for details.

This script is maintained here: https://github.com/alaaalii/LinuxSyslogScript"

for i in "$@"
do
	case $i in
		--audit)
			SAUDIT=1
			SARGS=1
			shift
			;;
		--auth)
			SAUTH=1
			SARGS=1
			shift
			;;
		-h|--help)
			echo "$USAGE"
			exit
			;;
		-l|--license)
			echo "$LICENSE"
			exit
			;;
		-q|--quiet)
			SHHH=1
			shift
			;;
		-qq)
			SHHH=1
			SKIPCONT="y"
			shift
			;;
		--remoteip=*)
			EXTIP="${i#*=}"
			shift
			;;
		-y|--yes)
			SKIPCONT="y"
			shift
			;;
		*)
			echo "Unknown option \"$i\"."
			echo
			echo "$USAGE"
			exit
			;;
	esac
done

#Initiating the log file.
LOGFILE=$(basename $0 .sh).$(date +%Y-%m-%d).log

cat <<EOF >> $LOGFILE
#======================================================#
$(date)
Start log:

EOF

function logit {
    TIMEDATE=$(date +"%a %b %e %Y %T")
	LLEVEL=$1
    LOG=$2
    if [ "$LLEVEL" == 1 ]; then
		if [ "$SHHH" != 1 ]; then
			echo -e "[INFO]\t$LOG"
		fi
		echo -e "$TIMEDATE   [INFO]\t$LOG" >> $LOGFILE
	elif [ "$LLEVEL" == 2 ]; then
		if [ "$SHHH" != 1 ]; then
			echo -e "[WARN]\t$LOG"
		fi
		echo -e "$TIMEDATE   [WARN]\t$LOG" >> $LOGFILE
	elif [ "$LLEVEL" == 3 ]; then
		echo -e "[ERROR]\t$LOG"
		echo -e "$TIMEDATE   [ERROR]\t$LOG" >> $LOGFILE
	elif [ "$LLEVEL" == 4 ]; then
		echo -e "$TIMEDATE   [INPUT]\t$LOG" >> $LOGFILE
    fi
}

#Defining some global variables.
SYSPIDF=/var/run/syslogd.pid
RHELV=$(cat /etc/redhat-release 2> /dev/null | sed s/.*release\ // | sed s/\ .*// | cut -c1)
SYSCONF=/etc/syslog.conf
RSYSCONF=/etc/rsyslog.conf
AUDITLOG=/var/log/audit/audit.log
AUDISP=/etc/audisp/plugins.d/syslog.conf
AUDITRULES=/etc/audit/audit.rules
BASENAME=$(basename $0)

#--------------------------------------------- START CHECKS ---------------------------------------------#

#Checking if either syslog or rsyslog is installed.
#By default, RHEL should at least have syslog installed, so this part should rarely be true.
if [ ! -e $SYSCONF -a ! -e $RSYSCONF ]; then
    logit 3 "A syslog daemon is not installed on this machine."
	logit 3 "Please install syslog or rsyslog in order to run this script."
	exit 1
fi

#Finding out if a syslog daemon is running using the pid file.
#This will only output a warning because we are going to restart the daemon during the configuration anyways.
if [ ! -e $SYSPIDF ]; then
    logit 2 "$SYSPIDF does not exist."
	logit 2 "A syslog daemon is not running on this machine. It will be started at the end of the script."
	echo
fi

#Finding out which syslog daemon is actually installed (syslog or rsyslog).
#The script will first check which one is running.
#If none are running, it will fall back to check which .conf file exists, checking for rsyslog first because both can exist.
if cat $SYSPIDF 2> /dev/null | xargs ps -p 2> /dev/null | grep -q rsyslog; then
    DAEMON=rsyslog
elif cat $SYSPIDF 2> /dev/null | xargs ps -p 2> /dev/null | grep -q syslog; then
    DAEMON=syslog
elif [ -e $RSYSCONF ]; then
	DAEMON=rsyslog
elif [ -e $SYSCONF ]; then
	DAEMON=syslog
else
    logit 3 "Could not determine which syslog daemon is installed. The script will now exit."
	exit 1
fi
logit 1 "Found $DAEMON daemon."
CONF=/etc/$DAEMON.conf
echo

#Check if audit.log exists (this is basically checking if auditd daemon is installed).
#If it doesn't, set AUDITDNI (audit daemon not installed) to 1. This will be referenced later.
if [ ! -e "$AUDITLOG" ]; then
    AUDITDNI=1
fi

#Check if the audit syslog plugin is installed.
#If it's not, set AUDITSPNI (audit syslog plugin not installed) to 1. This will be referenced later.
if [ ! -e "$AUDISP" ]; then
    AUDITSPNI=1
fi

#--------------------------------------------- END CHECKS ---------------------------------------------#

#--------------------------------------------- START FUNCTIONS ---------------------------------------------#

function takeBACKUP {
#Taking a backup of the file passed to this function.
if [ $2 == "beforeconfig" ]; then
    logit 1 "Taking a backup of $1 right before applying configuration."
elif [ $2 == "beforeremove" ]; then
	logit 1 "Taking a backup of $1 right before removing previous configuration."
fi

logit 1 "The backup will be saved as $1.`date +%Y-%m-%d_%H-%M-%S`.$2."
cp $1 $1.$(date +%Y-%m-%d_%H-%M-%S).$2
logit 1 "Done!"
echo
}

function restartSERVICE {
logit 1 "Restarting $1."
/etc/init.d/$1 restart &> /dev/null

#If something went wrong with restarting the service, echo the below error messages.
if [ $? -eq 0 ]; then
    logit 1 "Done!"
else
	logit 2 "Unable to restart the $1 service."
    logit 2 "Please restart it manually after the script ends by executing /etc/init.d/$1 restart."
	#This variable is only going to be used if the user ran the script in quiet mode.
	#They will be notified that a service could not be restarted, and that they need to look at the log file for more info.
	UNABLETORESTART=1
fi
echo
}

function enableAUDISP {
#Taking a backup of the current audisp file.
takeBACKUP $AUDISP "beforeconfig"

#Enabling the auditd syslog plugin to direct logs to syslog.
logit 1 "Enabling the auditd syslog plugin."
sed -i 's/active = no/active = yes/' $AUDISP
#check to see if it couldn't edit the file.
if grep -q 'active = yes' "$AUDISP"; then
	logit 1 "Done!"
else
	logit 2 "Unable to enable the auditd syslog plugin."
	logit 2 "Audit logs will not be sent."
fi
echo
}

function removePREVIOUS {
#Taking a backup of the current file before removing the configuration.
takeBACKUP $1 "beforeremove"

logit 1 "Removing previous script configuration from $1."
sed -i '/###Added using .* - AA###/,+2d' $1
#sed -i 's/active = yes/active = no/' $AUDISP
#sed -i '/audit_logs_wa/d;/boot_log_wa/d;/secure_log_wa/d;/fstab_wa/d;/shadow_wa/d;/consoleperms1_wa/d;/consoleperms2_wa/d;/sshd_config_wa/d;/vsftpd_users_wa/d;/ftpd_users_wa/d;/initd_wxa/d;/xinetd_wxa/d' $AUDITRULES
logit 1 "Done!"
echo
}

function editCONF {
#Taking a backup of the current .conf file.
takeBACKUP $1 "beforeconfig"

#Adding the configuration to the conf file.
logit 1 "Adding the configuration to $1."
cat <<EOF >> $1

###Added using $BASENAME - AA###
###$LOGTYPETEXT - AA###
$LOGTYPE                              @$EXTIP
EOF

#If the string "###Added using .* - AA###" cannot be found in the conf file,
#i.e. if the script couldn't edit the file and/or something went wrong, output the below error messages.
#Hopefully, this shouldn't really happen since we're running as root and the file exists.
if ! grep -q '###Added using .* - AA###' "$1"; then
    logit 3 "Unable to add the configuration to $1."
    logit 3 "Is $1 editable?"
    logit 3 "Quitting script."
    exit 1
fi
logit 1 "Done!"
echo
}

#--------------------------------------------- END FUNCTIONS ---------------------------------------------#

#Start of the actual script.
if [ ! "$RHELV" == "" ]; then
	logit 1 "Red Hat version $RHELV detected."
fi
echo

if [ "$EXTIP" == "" ]; then
	logit 4 "Asking the user to type the IP address that they want this server to send logs to."
	read -p "Type the IP address that you want this server to send logs to: " EXTIP
	logit 4 "User typed: $EXTIP."
fi

#Validating that the entered value for EXTIP is a valid IP address.
if [[ ! "$EXTIP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    logit 3 "The value you entered is not a valid IP address."
	logit 3 "Quitting script."
	exit 1
fi
echo

#The script has been designed in this way (i.e. ask the user for different kinds of logs separately) to allow for future expansion of the script,
#instead of giving them one choice between a list of log types.
#First, check if the user passed the --auth argument when running the script.
if [ "$SAUTH" == 1 ]; then
	LOGTYPE="$LOGTYPE,authpriv.info"
	LOGTYPETEXT="$LOGTYPETEXT & authentication"
#If they didn't pass that argument (i.e. SAUTH!=1), and there are no other "send" arguments passed (such as --audit) (i.e. SARGS!=1),
#then ask them if they want to send auth logs.
elif [ "$SARGS" != 1 ]; then
	logit 4 "Asking the user if they want to send authentication logs."
	echo "Do you want to send authentication logs?"
	select SELECTION in "Yes" "No"; do
		case $SELECTION in
			"Yes" )
				LOGTYPE="$LOGTYPE,authpriv.info"
				LOGTYPETEXT="$LOGTYPETEXT & authentication"
				break
				;;
			"No" )
				break
				;;
		esac
	done
	logit 4 "User selected: $SELECTION."
	echo
fi

if [ "$SAUDIT" == 1 ]; then
	#If the user wants to send audit logs, we need to check if the audit daemon and the audit syslog plugin are installed or not.
	if [ "$AUDITDNI" != 1 -a "$AUDITSPNI" != 1 ]; then
		LOGTYPE="$LOGTYPE,user.info"
		LOGTYPETEXT="$LOGTYPETEXT & audit"
		ENABLEAUDIT=1
	#If one of them is not installed, echo the below messages.
	elif [ "$AUDITDNI" == 1 ]; then
		logit 2 "Audit logs cannot be sent because you do not have the audit daemon (auditd) installed."
		UNABLETOSENDAUDIT=1
	elif [ "$AUDITSPNI" == 1 ]; then
		logit 2 "Audit logs cannot be sent because you do not have the audit daemon syslog plugin (audisp) installed."
		UNABLETOSENDAUDIT=1
	fi
elif [ "$SARGS" != 1 ]; then
	#If no other "send" arguments are passed, then show the user the option to send audit logs only if the audit daemon and
	#syslog plugin are installed.
	if [ "$AUDITDNI" != 1 -a "$AUDITSPNI" != 1 ]; then
		logit 4 "Asking the user if they want to send audit daemon logs."
		echo "Do you want to send audit daemon logs?"
		select SELECTION in "Yes" "No"; do
			case $SELECTION in
				"Yes" )
					LOGTYPE="$LOGTYPE,user.info"
					LOGTYPETEXT="$LOGTYPETEXT & audit"
					ENABLEAUDIT=1
					break
					;;
				"No" )
					break
					;;
			esac
		done
		logit 4 "User selected: $SELECTION."
	fi
fi
echo

#Checking if, at this point, there are logs to send or not.
if [ "$LOGTYPE" == "" ]; then
	logit 3 "No logs have been configured to be sent."
	logit 3 "Quitting script."
	exit 1
fi

#Sanitizing LOGTYPE because there's a leading comma.
LOGTYPE=$(echo $LOGTYPE | sed 's/^,//')
#Sanitizing LOGTYPETEXT because there's a leading ampersand and white space.
LOGTYPETEXT="$(echo $LOGTYPETEXT | sed 's/^& //') logs"

if [ "$SKIPCONT" != "y" ]; then
    #asking to proceed.
    read -p "Continue? [y/n]: " CONT
    if [ "$CONT" != "y" ]; then
        logit 4 "User chose to quit script."
        logit 3 "Quitting script."
        exit
    fi
    echo
fi

#Checking if the script was ran before.
if grep -q '###Added using .* - AA###' "$CONF"; then
    logit 1 "This script was ran before."
	logit 1 "To continue, the previous configuration has to be removed".
	echo
	if [ "$SKIPCONT" != "y" ]; then
	    logit 4 "Asking the user to remove the previous configuration."
	    read -p "Remove the previous configuration? [y/n]: " CONT
	    logit 4 "User typed: $CONT."
        if [ "$CONT" != "y" ]; then
            logit 3 "Quitting script."
            exit
        fi
        echo
	fi
    removePREVIOUS $CONF
	#Commenting out the below line because there is no need to restart the syslog daemon since we are going to
	#restart it after applying the actual configuration anyways.
	#restartSERVICE $(basename $CONF .conf)
fi

#If the user chose to send audit logs, we have to enable the audit syslog plugin.
#However, only call the functions if the audit syslog plugin is not already enabled.
if [ "$ENABLEAUDIT" == 1 ]; then
	if grep -q 'active = no' "$AUDISP"; then
		#Calling function to enable the audit syslog plugin.
		enableAUDISP
		#Calling function to restart the audit daemon.
		restartSERVICE auditd
	fi
fi
	
#Calling function to edit the conf file.
editCONF $CONF
#Calling function to restart the service.
restartSERVICE $(basename $CONF .conf)

echo
#If the user chose to run quietly (-q or -qq) and there were warning messages because of being unable to restart a service
#or send audit logs (because the required components are not installed (auditd and audisp)), echo the below messages.
if [ "$SHHH" == 1 ]; then
	#echo "ALL DONE!"
	if [ "$UNABLETORESTART" == 1 -o "$UNABLETOSENDAUDIT" == 1 ]; then
		if [ "$UNABLETORESTART" == 1 ]; then
			echo "[WARN]  One of the services could not be restarted."
		fi
		if [ "$UNABLETOSENDAUDIT" == 1 ]; then
			echo "[WARN]  Audit logs cannot be sent because you do not have one of the required components installed."
		fi
		echo "[WARN]  Please see the log file that was created in the working directory for [WARN] messages for more info."
	fi
fi
logit 1 "ALL DONE!"
logit 1 "This machine is now configured to send $LOGTYPETEXT to $EXTIP using the $DAEMON daemon." 
logit 1 "Please confirm that the server you're sending logs to is actually receiving them."
logit 1 "If it's not, a troubleshooting step would be to double check that UDP port 514 is open on that server."