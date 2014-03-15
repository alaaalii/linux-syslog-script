#!/bin/bash

#Check if the script is being run as root
if [ "$(whoami)" != "root" ]; then
    echo "[ERROR] You must run $(basename $0) as root."
    exit
fi

if [ "$1" == "-y" -o "$1" == "--yes" ]; then
    SKIPCONT="y"
fi

#logging
# choiceslogfile=QRADAR-RedHat-syslog.`date +%Y-%m-%d_%H-%M-%S`.choices.log
# logfile=QRADAR-RedHat-syslog.`date +%Y-%m-%d_%H-%M-%S`.log
# mkfifo ${logfile}.pipe
# tee < ${logfile}.pipe $logfile &
# exec &> ${logfile}.pipe
# rm ${logfile}.pipe
LOGFILE=$(basename $0 .sh).$(date +%Y-%m-%d_%H-%M-%S).log

function logit {

    TIMEDATE=$(date +"%a %b %e %Y %T")
	LLEVEL=$1
    LOG=$2
    if [ "$LLEVEL" == 1 ]; then
        echo -e "[INFO]\t$LOG"
		echo -e "$TIMEDATE   [INFO]\t$LOG" >> $LOGFILE
	elif [ "$LLEVEL" == 2 ]; then
		echo -e "[WARN]\t$LOG"
		echo -e "$TIMEDATE   [WARN]\t$LOG" >> $LOGFILE
	elif [ "$LLEVEL" == 3 ]; then
		echo -e "[ERROR]\t$LOG"
		echo -e "$TIMEDATE   [ERROR]\t$LOG" >> $LOGFILE
	elif [ "$LLEVEL" == 4 ]; then
		echo -e "$TIMEDATE   [INPUT]\t$LOG" >> $LOGFILE
    fi
	
}

#description
echo "Description:"
echo "------------"

if [ "$SKIPCONT" != "y" ]; then
    #Asking to proceed.
	read -p "Continue? [y/n]: " CONT
    if [ "$CONT" != "y" ]; then
        logit 4 "User chose to quit script."
        logit 3 "Quitting script."
        exit
    fi
    echo
fi

#Defining global variables.
SYSPIDF=/var/run/syslogd.pid
RHELV=$(cat /etc/redhat-release 2&> /dev/null | sed s/.*release\ // | sed s/\ .*// | cut -c1)
SYSCONF=/etc/syslog.conf
RSYSCONF=/etc/rsyslog.conf
AUDITLOG=/var/log/audit/audit.log
AUDISP=/etc/audisp/plugins.d/syslog.conf
AUDITRULES=/etc/audit/audit.rules

### CHECKS BEFORE BEGINNING ###

#Checking if either syslog or rsyslog is installed.
#By default, RHEL should at least have syslog installed, so this part should rarely be true.
if [ ! -e $SYSCONF -a ! -e $RSYSCONF ]; then
    logit 3 "A syslog daemon is not installed on this machine."
	logit 3 "Please install syslog or rsyslog in order to run this script."
	exit
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
#If none are running, it will fall back to check which .conf file exists.
if cat $SYSPIDF 2&> /dev/null | xargs ps -p 2&> /dev/null | grep -q rsyslog; then
    DAEMON=rsyslog
elif cat $SYSPIDF 2&> /dev/null | xargs ps -p 2&> /dev/null | grep -q syslog; then
    DAEMON=syslog
elif [ -e $RSYSCONF ]; then
	DAEMON=rsyslog
elif [ -e $SYSCONF ]; then
	DAEMON=syslog
else
    logit 3 "Could not determine which syslog daemon is installed. The script will now exit."
	exit
fi
logit 1 "Found $DAEMON daemon."
CONF=/etc/$DAEMON.conf
echo

#Check if audit.log exists (basically, check if auditd daemon is installed).
#If it doesn't, set AUDITDNI (audit daemon not installed) to 1.
#This will be referenced later.
if [ ! -e "$AUDITLOG" ]; then
    AUDITDNI=1
fi

#Check if the audit syslog plugin is installed.
#If it's not, set AUDITSPNI (audit syslog plugin not installed) to 1.
#This will be referenced later.
if [ ! -e "$AUDISP" ]; then
    AUDITSPNI=1
fi

### START FUNCTIONS ###

function takeBACKUP {

#Taking a backup of the file passed to this function.
if [ $2 == "beforeconfig" ]; then
    logit 1 "Taking a backup of $1 right before applying configuration."
elif [ $2 == "beforeremove" ]; then
	logit 1 "Taking a backup of $1 right before remove previous configuration."
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
fi
echo

}

function enableAUDISP {

#Taking a backup of the current audisp file.
takeBACKUP $AUDISP "beforeconfig"
echo

#Enabling the auditd syslog plugin to direct logs to syslog.
logit 1 "Enabling the auditd syslog plugin."
echo
if grep -q 'active = no' "$AUDISP"; then
	sed -i 's/active = no/active = yes/' $AUDISP
	#check to see if it couldn't edit the file.
	if ! grep -q 'active = yes' "$AUDISP"; then
		logit 2 "Unable to enable the auditd syslog plugin."
		logit 2 "Audit logs will not be sent."
		echo
	fi
	logit 1 "Done!"
elif grep -q 'active = yes' "$AUDISP"; then
	logit 1 "It's already enabled."
fi
echo

}

function addAUDITrules {

#checking if the audit rules file exists.
if [ ! -e "$AUDITRULES" ]; then
    echo
    echo "[ERROR] $AUDITRULES does not exist."
    echo
    echo "[ERROR] Please ensure that the audit daemon is installed properly and run the script again."
    echo
    echo "[ERROR] Quitting script."
    exit
fi

echo
echo "Adding audit rules to $AUDITRULES."

#start adding rules

if [ -d '/var/log/audit' ]; then
	echo "-w /var/log/audit -p wa -k audit_logs_wa" >> $AUDITRULES
fi
if [ -e '/var/log/boot.log' ]; then
	echo "-w /var/log/boot.log -p wa -k boot_log_wa" >> $AUDITRULES
fi
if [ -e '/var/log/secure' ]; then
	echo "-w /var/log/secure -p wa -k secure_log_wa" >> $AUDITRULES
fi
if [ -e '/etc/fstab' ]; then
	echo "-w /etc/fstab -p wa -k fstab_wa" >> $AUDITRULES
fi
if [ -e '/etc/shadow' ]; then
	echo "-w /etc/shadow -p wa -k shadow_wa" >> $AUDITRULES
fi
if [ -e '/etc/security/console.perms' ]; then
	echo "-w /etc/security/console.perms -p wa -k consoleperms1_wa" >> $AUDITRULES
fi
if [ -e '/etc/security/console.perms.d/50-default.perms' ]; then
	echo "-w /etc/security/console.perms.d/50-default.perms -p wa -k consoleperms2_wa" >> $AUDITRULES
fi
if [ -e '/etc/ssh/sshd_config' ]; then
	echo "-w /etc/ssh/sshd_config -p wa -k sshd_config_wa" >> $AUDITRULES
fi
if [ -e '/etc/vsftpd/ftpusers' ]; then
	echo "-w /etc/vsftpd/ftpusers -p wa -k vsftpd_users_wa" >> $AUDITRULES
fi
if [ -e '/etc/ftpusers' ]; then
	echo "-w /etc/ftpusers -p wa -k ftpd_users_wa" >> $AUDITRULES
fi
if [ -d '/etc/rc.d/init.d/' ]; then
	echo "-w /etc/rc.d/init.d -p wxa -k initd_wxa" >> $AUDITRULES
fi
if [ -d '/etc/xinetd.d/' ]; then
	echo "-w /etc/xinetd.d/ -p wxa -k xinetd_wxa" >> $AUDITRULES
fi

echo "Done!"

}

function removePREVIOUS {

#Taking a backup of the current file before removing the configuration.
takeBACKUP $1 "beforeremove"
echo

logit 1 "Removing previous script configuration from $1."
sed -i '/###Added using the RedHatSyslog Script - AAA###/,+2d' $1
#sed -i 's/active = yes/active = no/' $AUDISP
#sed -i '/audit_logs_wa/d;/boot_log_wa/d;/secure_log_wa/d;/fstab_wa/d;/shadow_wa/d;/consoleperms1_wa/d;/consoleperms2_wa/d;/sshd_config_wa/d;/vsftpd_users_wa/d;/ftpd_users_wa/d;/initd_wxa/d;/xinetd_wxa/d' $AUDITRULES
logit 1 "Done!"
echo

}

function editCONF {

#Checking if the conf file exists.
#This shouldn't really be matched by now with all the previous checks, but there's no harm in putting it in.
if [ ! -e "$1" ]; then
    logit 3 "$1 does not exist."
    logit 3 "The script will now quit."
    exit
fi

#Taking a backup of the current .conf file.
takeBACKUP $1 "beforeconfig"

#taking a backup of the current audit rules file
# echo
# echo "Taking a backup of the current audit rules file."
# echo "It will be saved as $AUDITRULES.`date +%Y-%m-%d_%H-%M-%S`.bak."
# cp $AUDITRULES $AUDITRULES.`date +%Y-%m-%d_%H-%M-%S`.bak
# echo "Done!"
# echo

#check if previous SSIEM configuration exists
# echo "Checking if previous Symantec SIEM configuration exists."
# if grep -qiE 'adcb0314|adcb0315' "$RSYSCONF"; then
	# echo "Previous Symantec SIEM configuration exists. This will be now be removed."
	# sed -i '/adcb0314/d;/adcb0315/d' $RSYSCONF
	# echo "Done!"
	# echo
# fi

#check if the script was ran before.
# echo "Checking if previous QRadar configuration exists."
# if grep -qiE '### QRadar ###|QRadar using Linux Script|Enabling auditd monitoring' "$RSYSCONF"; then
    # echo
    # echo "Previous QRadar configuration exists."
	# echo
    # deletepreviousSIX
# else
    # echo "It doesn't exist."
# fi

####### END CHECKS #######

#Adding the configuration to the conf file.

logit 1 "Adding the configuration to $1."
echo
cat <<EOF >> $1

###Added using the RedHatSyslog Script - AAA###
###$LOGCHOICE - AAA###
$LOGTYPE                              @$EXTIP
EOF

#If the string "###Added using the RedHatSyslog Script - AAA###" cannot be found in the conf file,
#i.e. if the script couldn't edit the file and/or something went wrong, output the below error messages.
#Hopefully, this shouldn't really happen since we're running as root.
if ! grep -q '###Added using the RedHatSyslog Script - AAA###' "$1"; then
    logit 3 "Unable to add the configuration to $1."
    logit 3 "Is $1 editable?"
    logit 3 "Quitting script."
    exit
fi
logit 1 "Done!"
echo

}

### END FUNCTIONS ###

#Start of the actual script.
if [ ! "$RHELV" == "" ]; then
	logit 1 "Red Hat version $RHELV detected."
fi
echo
logit 4 "Asking the user to type the IP address that they want this server to send logs to."
read -p "Type the IP address that you want this server to send logs to: " EXTIP
logit 4 "User typed: $EXTIP."

#Validating that the entered value is a valid IP address.
if [[ ! "$EXTIP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    logit 3 "The value you entered is not a valid IP address."
	logit 3 "Quitting script."
	exit
fi
echo

if [ "$AUDITDNI" == 1 -o "$AUDITSPNI" == 1 ]; then
	if [ "$AUDITDNI" == 1 ]; then
	    logit 2 "The audit daemon (auditd) is not installed. You will not get the option to send audit logs."
	elif [ "$AUDITSPNI" == 1 ]; then
	    logit 2 "The audit daemon syslog plugin (audisp) is not installed. You will not get the option to send audit logs."
	fi
    OPTIONS=("Authentication logs" "Quit script")
	echo
else
	OPTIONS=("Authentication logs" "Audit daemon logs" "Authentication and audit daemon logs" "Quit script")
fi

logit 4 "Asking the user to pick the type of logs they want to send."
echo "What type of logs do you want to send?"
echo
select LOGCHOICE in "${OPTIONS[@]}"; do
#select LOGCHOICE in "Authentication logs" "Audit daemon logs" "Authentication and audit daemon logs"; do
    case $LOGCHOICE in
        "Authentication logs" )
		    LOGTYPE=authpriv.info
		    break
		    ;;
        "Audit daemon logs" )
		    LOGTYPE=user.info
			ENABLEAUDIT=1
		    break
			;;
        "Authentication and audit daemon logs" )
		    LOGTYPE=authpriv.info,user.info
			ENABLEAUDIT=1
			break
			;;
		"Quit script" )
		    logit 4 "User chose to quit script."
		    logit 1 "Quitting script"
			exit
			break
			;;
    esac
done
echo
logit 4 "User picked: $LOGCHOICE."
logit 1 "The script will now configure $(awk -v VAR="$LOGCHOICE" 'BEGIN {print tolower(VAR)}') to be sent to $EXTIP."
#Fancy, eh? It converts the variable to lower case. God bless the people of the Internet.
echo

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
if grep -q '###Added using the RedHatSyslog Script - AAA###' "$CONF"; then
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
	restartSERVICE $(basename $CONF .conf)
fi

#If the user chose to send audit logs, we have to enable the audit syslog plugin.
if [ "$ENABLEAUDIT" == 1 ]; then
    #Calling function to enable the audit syslog plugin.
    enableAUDISP
	#Calling function to restart the audit daemon.
	restartSERVICE auditd
fi

#Calling function to edit the conf file.
editCONF $CONF
#Calling function to restart the service.
restartSERVICE $(basename $CONF .conf)

echo
logit 1 "ALL DONE!"
logit 1 "This machine is now configured to send $(awk -v VAR="$LOGCHOICE" 'BEGIN {print tolower(VAR)}') to $EXTIP using the $DAEMON daemon." 
logit 1 "Please confirm that the server you're sending logs to is actually receiving them."
logit 1 "If it's not, a troubleshooting step would be to double check that UDP port 514 is open on that server."