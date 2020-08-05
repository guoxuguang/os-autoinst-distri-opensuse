#!/bin/bash

#Usage and help info for the script
function help_usage()
{
        echo "script usage: $(basename $0) [-s Start Monitor for guest console] [-e End of Monitor for guest console ] [-h help]"
}

#Quit if there are less than one argument
if [ $# -eq 0 ];then
        help_usage
        exit 1
fi

#PREPARATION
##CONFIG PART
START_MONITOR="0"
END_MONITOR="0"
LOG_DIR="/tmp/virt_logs_residence"
MONITOR_LOCKED_FILE="/tmp/GUEST_CONSOLE_COLLECTOR_SEMAPHORE"
timestamp="`date '+%Y%m%d%H%M%S'`"
###CHECK EXISTED GUEST
vm_guestnames_types="sles"
get_vm_guestnames_inactive=`virsh list --inactive | grep -E "${vm_guestnames_types}" | awk '{print $2}'`
vm_guestnames_inactive_array=$(echo -e ${get_vm_guestnames_inactive})
get_vm_guestnames=`virsh list  --all | grep -E "${vm_guestnames_types}" | awk '{print $2}'`
vm_guestnames_array=$(echo -e ${get_vm_guestnames})
vmguest=""
vmguest_failed="0"

#Parse input arguments. -s or -e must have values
while getopts "seh" OPTION; do
  case "${OPTION}" in
    s)
      START_MONITOR="1"
      ;;
    e)
      END_MONITOR="1"
      ;;
    h)
      help_usage
      exit 1
      ;;
    *)
      help_usage
      exit 1
      ;;
  esac
done

#FUNCTION PART
function get_console()
{

local vmguest=$1

expect -c "
set timeout 30

##hide echo
log_user 0
spawn -noecho virsh console ${vmguest}

#wait connection
sleep 3
send \"\r\n\r\n\r\n\"

#condition expect
expect {
        \"*login:\" {
                send \"root\r\"
                exp_continue
        }
        -nocase "password:" {
                send \"novell\r\"
                exp_continue
        }
        \"*:~ #\" {
                send -- \"ip route get 1\r\"
                exp_continue
        }
        \"*:~ #\" {
                send -- \"exit\r\"
                exp_continue                
        }         
}

## -1 means never timeout
set timeout -1

#submatch for output
expect -re {dev.*\s([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})[^0-9]}

if {![info exists expect_out(1,string)]} {
        puts \"Match did not happen :(\"
        exit 1
}

set output \$expect_out(buffer)
expect eof

puts \"\$output\"
"

}


function open_console()
{
        #open guest console
        for vmguest in ${vm_guestnames_state_running_array[@]};do
                get_console ${vmguest} >> ${LOG_DIR}/${vmguest}_console_${timestamp} 2>&1 &
        done 
}

function close_console()
{
        #close guest console
        echo "kill PIDs $(basename $0)"
        pid=`ps aux | grep "$(basename $0) -s" | grep -v "grep"| awk '{print $2}'`
        if [[ -n $pid ]];then
            #echo $pid
            kill -9 $pid >> /dev/null 2>&1;sync
        else
            echo "PIDs was killed"
        fi        
        
        echo "Kill all associated "virsh cnsole" processes"
        ps aux | grep "virsh console" | grep -v "grep" >> /dev/null 2>&1
        while [[ $? -eq 0 ]];    
        do
            sleep 10
            sub_pid=`ps aux | grep "expect -c" | grep -v "grep"| awk '{print $2}'`
            if [[ -n $sub_pid ]];then 
                kill -9 $sub_pid >> /dev/null 2>&1;sync
            else
                break
            fi    
        done        
}



function end_monitor()
{
        #end of monitor for guest console
		if [ -f ${MONITOR_LOCKED_FILE} ];then
            echo "End of Monitor for guest console"	
            #UNLOCK Monitor for guest console	    
            > ${MONITOR_LOCKED_FILE} ; rm -rf ${MONITOR_LOCKED_FILE}
            #Kill Pids from Monitor for guest console
            close_console
        fi
}

function start_monitor()
{
        #start monitor for guest console
        get_vm_guestnames_state_running=`virsh list --state-running | grep -E "${vm_guestnames_types}" | awk '{print $2}'`
        vm_guestnames_state_running_array=$(echo -e ${get_vm_guestnames_state_running})  

        while :
        do
		    if [ -f ${MONITOR_LOCKED_FILE} ];then
                #Check with LOCK-UP status
                cat ${MONITOR_LOCKED_FILE} | grep "LOCKED"                
                if [ $? -eq 0 ];then
                    #KEEP LOCK-UP status
                    #To let just only one virsh console with one vm guest as backgroup PID			        
			       
			        #Check with background PID of virsh console
			        for vmguest in ${vm_guestnames_array[@]};do
			            virsh list --state-running | grep ${vmguest}
			                if [[ $? -eq 0 ]];then
			                    ps aux | grep "virsh console ${vmguest}"
                                if [[ $? -ne 0 ]];then
                                    get_console ${vmguest} >> ${LOG_DIR}/${vmguest}_console_${timestamp} 2>&1 &
                                fi
			                else			                    
			                    virsh list --inactive | grep ${vmguest}
			                    if [[ $? -eq 0 ]];then
			                        echo "${vmguest} is not running now"
			                        echo "No any output from virsh console ${vmguest}"
			                    fi                            
			                fi
			        done
			    else
                    #SETUP UNLOCKED
			        echo "UNLOCK Monitor for $(basename $0)!"
			        exit			        
			    fi
		    else
			    echo "Create LOCK-UP for $(basename $0)"
			    echo "LOCKED" > ${MONITOR_LOCKED_FILE}
                open_console
		    fi
	    done
}

function check_guest()
{

     for vmguest in ${vm_guestnames_array[@]};do
            echo -e ${vm_guestnames_inactive_array[*]} | grep ${vmguest} >> /dev/null 2>&1
            if [[ $? -eq 0 ]];then
                 virsh start ${vmguest}
                 vmguest_failed=$((${vmguest_failed} | $(echo $?)))
                 
                 #Quit if at least one vm guest failed to start up as normal
                if [[ ${vmguest_failed} -ne 0 ]];then
                    echo "Fail to boot up ${vmguest} as normal. Please investigate.\n"
                    exit 1
                fi
            fi
    done
}

##MAIN PART
if [[ ! -d ${LOG_DIR} ]]; then
     mkdir -p ${LOG_DIR}
fi
     
if [[ ${START_MONITOR} -eq 1 ]];then
     ##Install required packages
     zypper_cmd="zypper --non-interactive in psmisc procps coreutils expect"
     echo -e "${zypper_cmd} will be executed\n"
     ${zypper_cmd} >> /dev/null 2>&1

    #Check with the existed guest status
    check_guest
    
    #Start Monitor fpr guest console
    echo "Start Monitore in background for guest console"
    start_monitor >> /dev/null 2>&1 &
fi

if [[ ${END_MONITOR} -eq 1 ]];then
     end_monitor
fi

exit 0
