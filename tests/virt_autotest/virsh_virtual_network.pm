# SUSE's openQA tests
#
# Copyright (C) 2019 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

# Summary: Managing Virtual Networks with virsh for 4 different types will be included:
# - NAT based network
# - Using an existing bridge on VM host server
# - Isolated network
# - Routed network
# Maintainer: Leon Guo <xguo@suse.com>

use base "consoletest";
use strict;
use warnings;
use testapi;
use utils;
use set_config_as_glue;
use version_utils 'is_sle';


our $virt_host_bridge = 'br0';

sub prepare_network {

     my $config_path  = "/etc/sysconfig/network/ifcfg-br0";
     if (script_run("[[ -f $config_path ]]") != 0){
         assert_script_run("ip link add name $virt_host_bridge type bridge");
         assert_script_run("ip link set dev $virt_host_bridge up");
         my $bridge_setup = <<'EOF';
#!/bin/bash
ACTIVE_NET=$(ip a|awk -F': ' '/state UP/ {print $2}'|head -n1)
interface="BOOTPROTO='none'\nSTARTMODE='auto'"
bridge="BOOTPROTO='dhcp'\nBRIDGE='yes'\nBRIDGE_FORWARDDELAY='0'\nBRIDGE_PORTS='$ACTIVE_NET'\nBRIDGE_STP='off'\nSTARTMODE='auto'"
> /etc/sysconfig/network/ifcfg-br0.new
echo -e $bridge >/etc/sysconfig/network/ifcfg-br0
echo -e $interface >/etc/sysconfig/network/ifcfg-$ACTIVE_NET
cat /etc/sysconfig/network/ifcfg-br0
cat /etc/sysconfig/network/ifcfg-$ACTIVE_NET
systemctl restart network.service;
EOF
         script_output($bridge_setup, 900);
     }

}

sub restore_standalone {

    my $standalone_path  = "/usr/share/qa/qa_test_virtualization/shared/standalone";
    if (script_run("[[ -f $standalone_path ]]") == 0){
        assert_script_run("source /usr/share/qa/qa_test_virtualization/shared/standalone",60);
    }

}

sub destroy_standalone {

    my $cleanup_path  = "/usr/share/qa/qa_test_virtualization/cleanup";
    if (script_run("[[ -f $cleanup_path ]]") == 0){
        assert_script_run("source /usr/share/qa/qa_test_virtualization/cleanup",60);
    }

}

sub restart_libvirtd {

    if (is_sle('>11')) {
        systemctl 'restart libvirtd';
    }
    else {
        script_run("service libvirtd restart");
    }

}

sub restore_guests {

    my $wait_script        = "30";
    my $get_vm_hostnames   = "virsh list  --all | grep sles | awk \'{print \$2}\'";
    my $vm_hostnames       = script_output($get_vm_hostnames, $wait_script, type_command => 0, proceed_on_failure => 0);
    my @vm_hostnames_array = split(/\n+/, $vm_hostnames);
    foreach (@vm_hostnames_array)
    {
        script_run("virsh destroy $_");
        script_run("virsh undefine $_");
        script_run("virsh define $_.xml");
	upload_logs "$_.xml";
    }

}

sub restore_network {

    my $network_mark  = "/etc/sysconfig/network/ifcfg-br0.new";
    if (script_run("[[ -f $network_mark ]]") == 0){
        assert_script_run("ip link set dev $virt_host_bridge down",60);
        my $bridge_destroy = <<'EOF';
#!/bin/bash
ACTIVE_NET=$(ip a|awk -F': ' '/state UP/ {print $2}'|head -n1)
interface="BOOTPROTO='dhcp'\nSTARTMODE='auto'"
echo -e $interface >/etc/sysconfig/network/ifcfg-$ACTIVE_NET
cat /etc/sysconfig/network/ifcfg-$ACTIVE_NET
rm -rf /etc/sysconfig/network/ifcfg-br0*
systemctl restart network.service;
EOF
         script_output($bridge_destroy, 900);
    }

}


sub run {

     #Prepare VM HOST SERVER Network Interface Configuration
     #for libvirt virtual network testing 
     prepare_network;

     # Remove SSH old files and Generate the key pair
     assert_script_run "rm -rf ~/.ssh/* || true;ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa";
 
     # Install required packages
     zypper_call '-t in iptables iputils bind-utils sshpass';

     # Guest SSH Setup
     my $gi_guest = '';
     foreach my $guest (keys %xen::guests) {
	 #Archive deployed Guests
         assert_script_run("virsh dumpxml $guest > $guest.xml");
         record_info "$guest", "Establishing SSH connection to $guest";
         assert_script_run("virsh start $guest", 60);
         save_screenshot;
         $gi_guest = script_output("sleep 40;journalctl | grep dhcp| tail -1| grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
	 #Copy the VM host SSH Key to guest systems
         assert_script_run("sshpass -p novell ssh-copy-id -f root\@$gi_guest", 60);
	 #Prepare the new guest network interface files for libvirt virtual netwok
         assert_script_run("ssh root\@$gi_guest 'cp /etc/sysconfig/network/ifcfg-eth0 /etc/sysconfig/network/ifcfg-eth1;cp /etc/sysconfig/network/ifcfg-eth0 /etc/sysconfig/network/ifcfg-eth2'");
     }

#NAT BASED NETWORK
##Prepare Test
     die "There was not the default(NAT) virtual network" if (script_run('virsh net-list --all | grep default') != 0);
     
     foreach my $guest (keys %xen::guests) {
         record_info "virsh-virtual_network", "NAT BASED NETWORK";
	 #Define and start NAT BASED NETWORK
     	 assert_script_run("virsh net-info default");
     	 assert_script_run("virsh net-dumpxml default |tee vnet_nated.xml");
     	 assert_script_run("virsh net-undefine default");
     	 assert_script_run("virsh net-define vnet_nated.xml");
	 assert_script_run("virsh net-start default");
	 upload_logs "vnet_nated.xml";
     	 save_screenshot;
     	 assert_script_run("virsh attach-interface $guest network default --live",60);
         assert_script_run("ssh root\@$gi_guest 'rcnetwork restart'", 60);
     	 save_screenshot;
	 my $gi_vnet_nated = script_output("sleep 60; journalctl | grep dnsmasq-dhcp| tail -1| grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
	 #Destroy br123 test environment
	 assert_script_run("virsh detach-interface $guest bridge --current");
	 destroy_standalone;
	 restart_libvirtd;
	 save_screenshot;
	 #Test NAT BASED NETWORK
         assert_script_run("ssh root\@$gi_vnet_nated 'rcnetwork restart'", 60);
         assert_script_run("ssh root\@$gi_vnet_nated 'ip a'", 60);
	 assert_script_run("ssh root\@$gi_vnet_nated 'ping -c2 -W1 openqa.suse.de'",60);
     	 save_screenshot;
         #Destroy NATed Network
         assert_script_run("virsh detach-interface $guest network --current");
         assert_script_run("virsh net-destroy default");
     }

##BRIDGE - USING AN EXISTING BRIDGE ON VM HOST SERVER
##Prepare Test
my $vnet_host_bridge = <<'EOF';
<network>
<name>vnet_host_bridge</name>
<forward mode="bridge"/>
<bridge name="BRI"/>
</network>
EOF
     foreach my $guest (keys %xen::guests) {
          record_info "virsh-virtual_network", "BRIDGE - USING AN EXISTING BRIDGE ON VM HOST SERVER";
	  #Create HOST BRIDGE NETWORK
          assert_script_run("echo '$vnet_host_bridge' >> vnet_host_bridge.xml");
          assert_script_run("sed -i -e 's/BRI/$virt_host_bridge/' vnet_host_bridge.xml");
          assert_script_run("virsh net-create vnet_host_bridge.xml");
          assert_script_run("virsh net-list --all|grep vnet_host_bridge");
          assert_script_run("virsh attach-interface $guest network vnet_host_bridge --live");
	  upload_logs "vnet_host_bridge.xml";
          save_screenshot;
	  my $gi_host_bridge = script_output("virsh domifaddr $guest --source arp|grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
          assert_script_run("ssh root\@$gi_host_bridge 'rcnetwork restart'",60);
          assert_script_run("ssh root\@$gi_host_bridge 'ip a'",60);
	  #Confirm HOST BRIDGE NETWORK
          assert_script_run("ssh root\@$gi_host_bridge 'ping -c2 -W1 openqa.suse.de'",60);
          save_screenshot;
	  #Destroy HOST BRIDGE NETWORK
	  assert_script_run("virsh detach-interface $guest bridge --current");
	  assert_script_run("virsh net-destroy vnet_host_bridge");
     }
    
##ISOLATED NETWORK
##Prepare Test
my $vnet_isolated = <<'EOF';
<network>
 <name>vnet_isolated</name>
 <bridge name="virbr1"/>
 <ip address="192.168.152.1" netmask="255.255.255.0">
  <dhcp>
   <range start="192.168.152.2" end="192.168.152.254" />
  </dhcp>
 </ip>
</network>
EOF
     foreach my $guest (keys %xen::guests) {
         record_info "virsh-virtual_network", "ISOLATED NETWORK";
	 #Create ISOLATED NETWORK
         assert_script_run("echo '$vnet_isolated' >> vnet_isolated.xml");
         assert_script_run("virsh net-create vnet_isolated.xml");
	 upload_logs "vnet_isolated.xml";
         save_screenshot;
         assert_script_run("virsh attach-interface $guest network vnet_isolated --live");
         my $gi_vnet_isolated = script_output("sleep 30;journalctl | grep nsmasq-dhcp| tail -1| grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
	 #Confirm ISOLATED NETWORK
         assert_script_run("ssh root\@$gi_vnet_isolated 'ip a'");
         assert_script_run("! ssh root\@$gi_vnet_isolated 'ping -c2 -W1 openqa.suse.de'");
         save_screenshot;
	 #Destroy ISOLATED NETWORK
         assert_script_run("virsh detach-interface $guest network --current");
         assert_script_run("virsh net-destroy vnet_isolated");
     }
    
##ROUTED NETWORK
##Prepare Test
my $vnet_routed = <<'EOF';
<network>
 <name>vnet_routed</name>
 <bridge name="virbr2"/>
 <forward mode="route"/>
 <ip address="192.168.129.1" netmask="255.255.255.0">                                                   <dhcp>
      <range start="192.168.129.2" end="192.168.129.254" />                                             </dhcp>
 </ip>
</network>
EOF
     foreach my $guest (keys %xen::guests) {
         record_info "virsh-virtual_network.xml", "ROUTED NETWORK";                           
	 #Create and Start ROUTED NETWORK
         assert_script_run("echo '$vnet_routed' >> vnet_routed.xml"); 
         assert_script_run("virsh net-create vnet_routed.xml");
	 upload_logs "vnet_routed.xml";
         assert_script_run("virsh attach-interface $guest network vnet_routed --live");
         my $gi_vnet_routed = script_output("sleep 30;journalctl | grep dnsmasq-dhcp| tail -1| grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
	 #Confirm created ROUTED NETWORK
         assert_script_run("iptables -w --table filter --list-rules",60); 
         assert_script_run("ip route",60); 
         assert_script_run("route -v",60); 
         assert_script_run("ssh root\@$gi_vnet_routed 'ip a'",60); 
         assert_script_run("ssh root\@$gi_vnet_routed 'route -v'",60); 
         assert_script_run("ssh root\@$gi_vnet_routed 'traceroute openqa.suse.de'",60); 
         assert_script_run("ssh root\@$gi_vnet_routed 'ping -c2 -W1 openqa.suse.de'",60); 
         save_screenshot;
	 #Destroy created ROUTED NETWORK
         assert_script_run("virsh detach-interface $guest network --current");
	 assert_script_run("virsh net-destroy vnet_routed");
     }
    
     #Restore Guest systems
     restore_guests;

     #Restrore br123 for virt_autotest
     restore_standalone;

     #Restrore Network setting
     restore_network;


}

sub post_fail_hook {
    my ($self) = @_;

    #Restart libvirtd service
    restart_libvirtd;

    #Restore Guest systems
    restore_guests;

    #Destroy created virtual networks
    my $get_vnet_name     = "virsh net-list --all| tail -2| head -1| awk \'{print \$1}\'";
    my $vnet_name         = script_output($get_vnet_name, 30, type_command => 0, proceed_on_failure => 0);
    my @vnet_name_array = split(/\n+/, $vnet_name);
    foreach (@vnet_name_array)
    {
	script_run("virsh net-destroy $_");
    }

    #Restrore br123 for virt_autotest
    restore_standalone;

    #Restrore Network setting
    restore_network;

    $self->SUPER::post_fail_hook;

}

1;
