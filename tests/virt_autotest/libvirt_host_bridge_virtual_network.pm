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

# Summary: Managing Virtual Networks with virsh included
# the following priorities 4 types of virtual network:
# P1 HOST bridge network
# P2 NAT based network
# P3 Routed network
# P4 Isolated network
#
#   This test does the following
#    - Create or define 4 types of virtual network
#    - Start the created virtual network
#    - Confirm 4 types of virtual network
#    - Stop the created virtual network
#    - Destroy or undefine 4 types of virtual network
#
# Maintainer: Leon Guo <xguo@suse.com>

use base "virt_feature_test_base";
use virt_utils;
use set_config_as_glue;
use virtual_network_utils;
use strict;
use warnings;
use testapi;
use utils;

our $virt_host_bridge = 'br0';
sub run_test {
    my ($self) = @_;
    #Prepare VM HOST SERVER Network Interface Configuration
    #for libvirt virtual network testing
    prepare_network($virt_host_bridge);

    #Debug br123
    restore_standalone;

    #Install required packages
    zypper_call '-t in iptables iputils bind-utils sshpass';

    #Prepare Guests 
    foreach my $guest (keys %xen::guests) {
        #Archive deployed Guests
        assert_script_run("virsh dumpxml $guest");
        save_screenshot;
        assert_script_run("virsh dumpxml $guest > /tmp/$guest.xml");
        upload_logs "/tmp/$guest.xml";
	#Start installed Guests
        assert_script_run("virsh start $guest", 60);
        #Get the Guest IP Address for bootup guest
        my $mac_guest = script_output("virsh domiflist $guest|grep br123|grep -oE \"[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}\"");
	script_retry "journalctl | grep DHCPACK | grep $mac_guest | grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"", delay => 60, retry => 3, timeout => 60;
	my $gi_guest = script_output("journalctl | grep DHCPACK | grep $mac_guest | grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
        #Copy the VM host SSH Key to guest systems
        #File get-settings was installed from qa_lib_virtauto package
	if (get_var("VIRT_PRJ1_GUEST_INSTALL")) {
	    my $get_settings_path = "/usr/share/qa/virtautolib/lib/get-settings.sh";
	    my $vmpasswd = script_output("$get_settings_path vm.pass");
	    assert_script_run("sshpass -p " . $vmpasswd . " ssh-copy-id -f root\@$gi_guest");
	}
	else {
	    exec_and_insert_password("ssh-copy-id -o StrictHostKeyChecking=no -f root\@$gi_guest");
	}
        #Prepare the new guest network interface files for libvirt virtual network
        assert_script_run("ssh root\@$gi_guest 'cp /etc/sysconfig/network/ifcfg-eth0 /etc/sysconfig/network/ifcfg-eth1;cp /etc/sysconfig/network/ifcfg-eth0 /etc/sysconfig/network/ifcfg-eth2'");
	assert_script_run("ssh root\@$gi_guest 'rcnetwork restart'", 60);
        #REDEFINE GUEST NETWORK INTERFACE
        assert_script_run("virsh detach-interface $guest bridge --mac $mac_guest");
        assert_script_run("virsh dumpxml $guest > $guest.xml");
        assert_script_run("virsh destroy $guest");
        assert_script_run("virsh undefine $guest");
        assert_script_run("virsh define $guest.xml");
        assert_script_run("virsh start $guest");
        assert_script_run("rm -rf $guest.xml");
    }

    #Destroy existed br123 network interface
    destroy_standalone;
    restart_libvirtd;

##P1:BRIDGE - USING AN EXISTING BRIDGE ON VM HOST SERVER
    my $wait_script               = "180";
    my $vnet_host_bridge_cfg_name = "vnet_host_bridge.xml";
    my $vnet_host_bridge_cfg_url  = data_url("virt_autotest/$vnet_host_bridge_cfg_name");
    my $download_cfg_script = "curl -s -o ~/$vnet_host_bridge_cfg_name $vnet_host_bridge_cfg_url";
    script_output($download_cfg_script, $wait_script, type_command => 0, proceed_on_failure => 0);

    #Create HOST BRIDGE NETWORK
    assert_script_run("sed -i -e 's/BRI/$virt_host_bridge/' $vnet_host_bridge_cfg_name");
    assert_script_run("virsh net-create $vnet_host_bridge_cfg_name");
    assert_script_run("virsh net-list --all|grep vnet_host_bridge");
    save_screenshot;
    upload_logs "$vnet_host_bridge_cfg_name";
    assert_script_run("rm -rf $vnet_host_bridge_cfg_name");

    my $gi_host_bridge = '';
    foreach my $guest (keys %xen::guests) {
        record_info "$guest", "HOST BRIDGE NETWORK for $guest";
        assert_script_run("virsh attach-interface $guest network vnet_host_bridge --live");
        #Get the Guest IP Address from HOST BRIDGE NETWORK
        if (get_var("XEN") || check_var("HOST_HYPERVISOR", "xen")) {
            my $mac_host_bridge = script_output("virsh domiflist $guest|grep vnet_host_bridge|grep -oE \"[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}\"");
            script_retry "arp | grep $mac_host_bridge | awk \'{print \$1}\'", delay => 60, retry => 3, timeout => 60;
            $gi_host_bridge = script_output("arp | grep $mac_host_bridge | awk \'{print \$1}\'");
        }
        else {
            script_retry "virsh domifaddr $guest --source arp | grep vnet0| grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"", delay => 150, retry => 5, timeout => 150;
            $gi_host_bridge = script_output("virsh domifaddr $guest --source arp | grep vnet0| grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
        }
        #Confirm HOST BRIDGE NETWORK
        assert_script_run("ssh root\@$gi_host_bridge 'ping -c2 -W1 openqa.suse.de'", 60);
        save_screenshot;
        assert_script_run("virsh detach-interface $guest bridge --current");
    }
    #Destroy HOST BRIDGE NETWORK
    assert_script_run("virsh net-destroy vnet_host_bridge");
    save_screenshot;

    #Restore Network setting
    restore_network($virt_host_bridge);
}

sub post_fail_hook {
    my ($self) = @_;

    #Restart libvirtd service
    restart_libvirtd;

    #Destroy created virtual networks
    destroy_vir_network;

    #Restore br123 for virt_autotest
    restore_standalone;

    #Restore Guest systems
    restore_guests;

    #Restore Network setting
    restore_network($virt_host_bridge);
}

1;
