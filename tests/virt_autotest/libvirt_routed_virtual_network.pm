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

sub run_test {
    my ($self) = @_;
##P3:ROUTED NETWORK
    my $wait_script         = "180";
    my $vnet_routed_cfg_name= "vnet_routed.xml";
    my $vnet_routed_cfg_url = data_url("virt_autotest/$vnet_routed_cfg_name");
    my $download_cfg_script = "curl -s -o ~/$vnet_routed_cfg_name $vnet_routed_cfg_url";
    script_output($download_cfg_script, $wait_script, type_command => 0, proceed_on_failure => 0);

    #Create and Start ROUTED NETWORK
    assert_script_run("virsh net-create vnet_routed.xml");
    save_screenshot;
    upload_logs "vnet_routed.xml";
    assert_script_run("rm -rf vnet_routed.xml");

    my $gi_vnet_routed;
    foreach my $guest (keys %xen::guests) {
        record_info "$guest", "ROUTED NETWORK for $guest";
        assert_script_run("virsh attach-interface $guest network vnet_routed --live");
        #Get the Guest IP Address from ROUTED NETWORK
        if (get_var("XEN") || check_var("HOST_HYPERVISOR", "xen")) {
            my $mac_routed = script_output("virsh domiflist $guest | grep vnet_routed | grep -oE \"[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}\"");
            script_retry "arp | grep $mac_routed | awk \'{print \$1}\'", delay => 60, retry => 3, timeout => 60;
            $gi_vnet_routed = script_output("arp | grep $mac_routed | awk \'{print \$1}\'");
        }
        else {
            script_retry "journalctl | grep dnsmasq-dhcp| tail -1| grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"", delay => 60, retry => 3, timeout => 60;
            $gi_vnet_routed = script_output("journalctl | grep dnsmasq-dhcp| tail -1| grep -oE \"([0-9]{1,3}[\.]){3}[0-9]{1,3}\"");
        }
        #Confirm ROUTED NETWORK
        #TODO
        #There should be added the static routes to LAN router, but we have not permission
        #to modify LAN router.So, before confirm routed network setting, confirm current
        #routed netwrok WITHOUT testing ping from guest to external
        assert_script_run("ssh root\@$gi_vnet_routed 'ip a'", 60);
        save_screenshot;
        assert_script_run("virsh detach-interface $guest network --current");
    }
    #Destroy ROUTED NETWORK
    assert_script_run("virsh net-destroy vnet_routed");
    save_screenshot;
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
}

1;
