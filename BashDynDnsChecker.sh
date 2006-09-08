#!/bin/bash
# version 0.0.4
#####################################################################################
# licensed under the                                                                #
# The MIT License                                                                   #
#                                                                                   #
# Copyright (c) <2006> <florian[at]klien[dot]cx>                                    #
#                                                                                   #
# Permission is hereby granted, free of charge, to any person obtaining a copy of   #
# this software and associated documentation files (the "Software"), to deal in the #
# Software without restriction, including without limitation the rights to use,     #
# copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the   #
# Software, and to permit persons to whom the Software is furnished to do so,       #
# subject to the following conditions:                                              #
#                                                                                   #
#                                                                                   #
# The above copyright notice and this permission notice shall be included in all    #
# copies or substantial portions of the Software.                                   #
#                                                                                   #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR        #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS  #
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR    #
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN #
# AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION   #
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                   #
#                                                                                   #
# ################################################################################# #
#                                                                                   #
# BashDynDnsChecker (bddc)                                                          #
#                                                                                   #
# This is a dyndns check and synchronizing script                                   #
# the executables it needs are:                                                     #
# grep, curl, echo, sed, ifconfig, date, tail, cut, cat and rm                      #
# which should be available in every linux system.                                  #
#                                                                                   #
# copyright 2006 by florian klien                                                   #
# florian[at]klien[dot]cx                                                           #
#                                                                                   #
# actually supports ip reception from ifconfig, an external url (by http)           #
# and parsing from a router (actually just DLink DI-624 because i don't             #
# have access to other router to find out where/what to parse for the ip)           #
# feel free to send me the matching parse string for any other router.              #
#                                                                                   #
# actually supports dyndns synchronization with afraid.org                          #
#                                                                                   #
# it needs to be called in crontab as a cronjob, or any other similar               #
# perpetual program.                                                                #
#                                                                                   #
# exit codes:                                                                       #
# 0 -> everything went fine                                                         #
# 1 -> some error occured during runtime                                            #
# 2 -> some config error was caught                                                 #
#                                                                                   #
#####################################################################################
# change to your needs                                                              #
#####################################################################################

# executable paths
sed=sed
grep=grep
egrep=egrep
cat=cat
cut=cut
ifconfig=ifconfig
date=date
tail=tail
echo=echo
curl=/usr/bin/curl

######################
# change logging level
# 3 -> log whenever a check is done
# 2 -> log when ip changes
# 1 -> log errors
# 0 -> log nothing
LOGGING=3
LOGFILE=/var/log/ddchecker.log

# turn silent mode on (no echo while running, mostly used for debugging [1 is silent])
SILENT=0

#################################
# mode of ip checking
# 1 -> output of ifconfig
# 2 -> remote website
# 3 -> router info over http
CHECKMODE=2

#################################
# ad 1: your internet interface
inet_if=eth0

#################################
# ad 2: remote url to get ip from over http
check_url=http://whatismyip.com

#################################
# ad 3: router model
# 1 -> DLink DI-624
# 2 -> Netgear-TA612V
# 3 -> WGT-624
ROUTER=1
router_tmp_file=/tmp/router_tmp_file

#-------DLink-DI-624---------
# ad 1: DLink DI-624 conf
dlink_user=ADMIN
dlink_passwd=PASSWD
dlink_ip=192.168.0.1
# this helps parsing (do not change)
dlink_url=st_devic.html
dlink_mode=WAN
dlink_wan_mode=PPTP
#------/Dlink-DI-624---------

#-------Netgear-TA612V--------
# ad 2: Netgear-TA612V conf
netgear1_user=ADMIN
netgear1_passwd=PASSWD
netgear1_ip=192.168.0.1
# this helps parsing (do not change)
netgear1_url=s_status.htm
#------/Netgear-TA612V--------

#-------WGT-624--------
# ad 3: WGT 624 conf
wgt624_user=ADMIN
wgt624_passwd=PASSWD
wgt624_ip=192.168.0.1
# this helps parsing (do not change)
wgt624_url=RST_status.htm
#-------/WGT-624-------
#################################


#####################
# mode of syndication
# 1 -> use afraid.org url
# 2 -> use dyndns.org
# T -> testing option (doing nothing)
IPSYNMODE=2


#------------afraid.org-----------------
# ad 1: your update url using afraid.org
# enter your syndication url from afraid.org
afraid_url=http://freedns.afraid.org/dynamic/update.php...........................
#-----------/afraid.org-----------------


#------------dyndns.org----------------
# ad 2: your data you got at dyndns.org
dyndnsorg_username=bddc
dyndnsorg_passwd=test12
dyndnsorg_hostnameS=bddctest.dyndns.org
#--do not edit-----
dyndnsorg_wildcard=NOCHG
dyndnsorg_mail=NOCHG
dyndnsorg_backmx=NOCHG
dyndnsorg_offline=NO
#for testing
dyndnsorg_ip=
#-----------/dyndns.org----------------



# cache file for ip address
ip_cache=/tmp/ipaddr.cache

# the url that needs the dyndns (has no sense in this release)
my_url=your.domain.com

###################################################################################
# End of editspace, just go further if you know what you are doing                #
###################################################################################

login_data_valid () {
  	if [ "$1" == "ADMIN" -o "$2" == "PASSWD" ]; then
  	           if [ $SILENT -eq 0 ]; then
                $echo "ERROR: check the login settings for your router"
            fi
            if [ $LOGGING -ge 1 ]; then
                $echo "[`$date +%d/%b/%Y:%T`] | ERROR: check the login settings for your router" >> $LOGFILE 
            fi
            return 0;
        fi
  return 1;
}


case "$CHECKMODE" in
	# ifconfig mode
    1)
        feedback=`$ifconfig | $grep $inet_if`
        if [ -z '$feedback' ]; then
            if [ $SILENT -eq 0 ]; then
                $echo "ERROR: internet interface is down!"
            fi
            if [ $LOGGING -ge 1 ]; then
                $echo "[`$date +%d/%b/%Y:%T`] | ERROR: internet interface ($inet_if) is down!" >> $LOGFILE && exit 1 
            fi
        fi
        current_ip=`$ifconfig ${inet_if} | grep 'inet ' | $sed 's/[^0-9]*//;s/ .*//'`;
        ;;
    # remote website mode 
    2)
    	# only edit if you know what you do!
    	# edit to a form that only the ip remains when you get the html file
		# in this format: '123.123.132.132'
        current_ip=`$curl -s -A 'bashdyndnschecker (bddc)' $check_url | $egrep -e ^[\ \t]*\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}| $sed 's/ //g'`
        ;;
    
	# router per http mode
    3)   
        case $ROUTER in
        # DLink DI-624
            1)
             	login_data_valid ${dlink_user} ${dlink_passwd}
             	loginIsValid=$?
	          	if [ $loginIsValid ]; then
                	exit 2
               	fi
                string=`$curl -s --anyauth -u ${dlink_user}:${dlink_passwd} -o "${router_tmp_file}" http://${dlink_ip}/${dlink_url}`
                line=`$grep -A 20 ${netgear1_mode} ${router_tmp_file} | $grep onnected`
                line2=${line#"                    PPTP "}
                disconnected=${line2:0:9} # cutting Connected out of file
                if [ "$disconnected" != "Connected" ]; then
                    if [ $SILENT -eq 0 ]; then
                        $echo "ERROR: DLink DI-624 internet interface is down!"
                    fi
                    if [ $LOGGING -ge 1 ]; then
                        $echo "[`$date +%d/%b/%Y:%T`] | ERROR: DLink DI-624 Internet interface is down!" >> $LOGFILE && exit 1
                    fi 
                fi
                current_ip=`$grep -A 30 ${dlink_mode} ${router_tmp_file} | $grep -A 9 ${dlink_wan_mode} | $tail -n 1 | $cut -d " " -f 21`
                rm ${router_tmp_file}
             ;;
             
             # Netgear-TA612V
             2)
             	login_data_valid ${netgear1_user} ${netgear1_passwd}
             	loginIsValid=$?
	          	if [ $loginIsValid ]; then
                	exit 2
               	fi
               	string=`$curl -s --anyauth -u ${netgear1_user}:${netgear1_passwd} -o "${router_tmp_file}" http://${netgear1_ip}/${netgear1_url}`
               	current_ip=`grep -A 20 'Internet Port' ${router_tmp_file} | grep -A 1 'IP Address'|egrep -e \([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\} | sed 's/<[^>]*>//g;/</N;'|sed 's/^[^0-9]*//;s/[^0-9]*$//'`
               if [ -z "$current_ip" ]; then
                    if [ $SILENT -eq 0 ]; then
                        $echo "ERROR: Netgear-TA612V internet interface is down!"
                    fi
                    if [ $LOGGING -ge 1 ]; then
                        $echo "[`$date +%d/%b/%Y:%T`] | ERROR: Netgear-TA612V Internet interface is down!" >> $LOGFILE && exit 1
                    fi 
                fi
                rm ${router_tmp_file}
             ;;
             
             # WGT 624
             3)
             	login_data_valid ${wgt624_user} ${wgt624_passwd}
             	loginIsValid=$?
	          	if [ $loginIsValid ]; then
                	exit 2
               	fi
                string=`$curl -s --anyauth -u ${wgt624_user}:${wgt624_passwd} -o "${router_tmp_file}" http://${wgt624_ip}/${wgt624_url}`
                current_ip=`$grep -A 20 'Internet Port' ${router_tmp_file}| $grep -A 1 'IP Address' | $egrep -e \([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\} | $sed 's/<[^>]*>//g;/</N;'| $sed 's/^[^0-9]*//;s/[^0-9]*$//'`
               if [ "$current_ip" == "0.0.0.0" ]; then
                    if [ $SILENT -eq 0 ]; then
                        $echo "ERROR: WGT 624 internet interface is down!"
                    fi
                    if [ $LOGGING -ge 1 ]; then
                        $echo "[`$date +%d/%b/%Y:%T`] | ERROR: WGT 624 Internet interface is down!" >> $LOGFILE && exit 1
                    fi 
                fi
          	 rm ${router_tmp_file}
             ;;
        esac
        
        ;;
esac


#---------IP-syndication-part--------------------


old_ip=`$cat $ip_cache`
if [ "$current_ip" != "$old_ip" ]
    then
    $echo $current_ip > $ip_cache
    
    case $IPSYNMODE in
        # afraid.org
        1)
        	# afraid.org gets IP over the http request of your url
            afraid_feedback=`$curl -s $afraid_url`
            checker=$afraid_feedback
            checker=${checker:0:5}
            if [ "ERROR" = $checker ]; then
                if [ $LOGGING -ge "1" ]; then
                    $echo "[`$date +%d/%b/%Y:%T`] | afraid.org: ${afraid_feedback}" >> $LOGFILE && exit 1
                fi 
                if [ $SILENT -eq "0" ]; then
                    $echo "afraid.org: ${afraid_feedback}"
                fi
            fi
            ;;
    
    # dyndns.org
        2)
	    dyndnsorg_ip=$current_ip;
	    dyndnsorg_feedback=`$curl -s http://${dyndynorg_username}:${dyndnsorg_passwd}@members.dyndns.org/nic/update?system=dyndns&hostname=${dyndnsorg_hostnameS}&myip=${dyndnsorg_ip}&wildcard=${dyndnsorg_wildcard}&mx=${dyndnsorg_mail}&backmx=${dyndnsorg_backmx}&offline=${dyndnsorg_offline}`
#            echo $dyndnsorg_feedback
            if [ -n `echo $dyndnsorg_feedback|grep badagent` ]; then
                if [ $SILENT -eq "0" ]; then
                    $echo "dyndns.org: ${dyndnsorg_feedback}"
                fi
                if [ $LOGGING -ge "1" ]; then
                    $echo "[`$date +%d/%b/%Y:%T`] | dyndns.org: ${dyndnsorg_feedback}" >> $LOGFILE && exit 1
                fi 
            fi
	    if [ -n `echo $dyndnsorg_feedback|grep abuse` ]; then
                if [ $SILENT -eq "0" ]; then
                    $echo "dyndns.org: ${dyndnsorg_feedback}"
                fi
                if [ $LOGGING -ge "1" ]; then
                    $echo "[`$date +%d/%b/%Y:%T`] | dyndns.org: ${dyndnsorg_feedback}" >> $LOGFILE && exit 1
                fi 
            fi
	    if [ -n `echo $dyndnsorg_feedback|grep notfqdn` ]; then
                if [ $SILENT -eq "0" ]; then
                    $echo "dyndns.org: ${dyndnsorg_feedback}"
                fi
                if [ $LOGGING -ge "1" ]; then
                    $echo "[`$date +%d/%b/%Y:%T`] | dyndns.org: ${dyndnsorg_feedback}" >> $LOGFILE && exit 1
                fi 
            fi
	    if [ -n `echo $dyndnsorg_feedback|grep badauth` ]; then
                if [ $SILENT -eq "0" ]; then
                    $echo "dyndns.org: ${dyndnsorg_feedback}"
                fi
                if [ $LOGGING -ge "1" ]; then
                    $echo "[`$date +%d/%b/%Y:%T`] | dyndns.org: ${dyndnsorg_feedback}" >> $LOGFILE && exit 1
                fi 
            fi
	    if [ $SILENT -eq "0" ]; then
                $echo $dyndnsorg_feedback "dyndnsorg update end"
            fi
   	    ;;
        T)
            # testing option for scripting, that you dont get banned from a service
         	if [ $SILENT -eq "0" ]; then
			   $echo "Doing nothing as well :)"
            fi
            ;;
    esac
    
    #logging
    if [ $LOGGING -ge "2" ]
        then
        $echo "[`$date +%d/%b/%Y:%T`] | ip changed: $current_ip" >> $LOGFILE
    fi 
    if [ $SILENT -eq "0" ]
        then
        $echo "[`$date +%d/%b/%Y:%T`] | ip changed: $current_ip"
    fi
    #/logging
fi

if [ $LOGGING -ge "3" ]
    then
    $echo "[`$date +%d/%b/%Y:%T`] | current ip: $current_ip" >> $LOGFILE
fi
if [ $SILENT -eq "0" ]
    then
    $echo "[`$date +%d/%b/%Y:%T`] | current ip: $current_ip"
fi
exit 0 