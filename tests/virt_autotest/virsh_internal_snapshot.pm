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

# Summary: Test VM internal snapshot using virsh (create - restore - delete)
# Maintainer: Leon Guo <xguo@suse.com>

use base "virt_feature_test_base";
use strict;
use warnings;
use testapi;
use set_config_as_glue;
use utils;
use virt_utils;
use virt_autotest::common;
use virt_autotest::utils;

sub run_test {
    my ($self) = @_;

    # Except failur to ensure call post_fail_hook here
    die "ensure call parent post_fail_hook for virsh snapshot management";
    #Snapshots are supported on KVM VM Host Servers only
    return unless is_kvm_host;

    foreach my $guest (keys %virt_autotest::common::guests) {
        my $type = check_guest_disk_type($guest);
        next if ($type == 1);
        record_info "virsh-snapshot", "Cleaning in case of rerun";
        if (script_run("virsh snapshot-list $guest | grep internal-snapshot-$guest-01") == 0) {
            assert_script_run "virsh snapshot-delete $guest --snapshotname internal-snapshot-$guest-01";
        }
        if (script_run("virsh snapshot-list $guest | grep internal-snapshot-$guest-02") == 0) {
            assert_script_run "virsh snapshot-delete $guest --snapshotname internal-snapshot-$guest-02";
        }
        record_info "virsh-snapshot", "Creating Internal Snapshot";
        assert_script_run "virsh snapshot-create-as $guest --name internal-snapshot-$guest-01";
        assert_script_run "virsh snapshot-current $guest | grep internal-snapshot-$guest-01";
        assert_script_run "virsh snapshot-list $guest | grep internal-snapshot-$guest-01";
        assert_script_run "virsh snapshot-create-as $guest --name internal-snapshot-$guest-02";
        assert_script_run "virsh snapshot-list $guest | grep internal-snapshot-$guest-02";

        record_info "virsh-snapshot", "Starting Internal Snapshot";
        assert_script_run "virsh snapshot-list $guest --tree| grep internal-snapshot-$guest-01";
        assert_script_run "virsh snapshot-revert $guest --snapshotname internal-snapshot-$guest-01";
        assert_script_run "virsh snapshot-info $guest --snapshotname internal-snapshot-$guest-01| grep 'Current.*yes'";
        assert_script_run "virsh snapshot-info $guest --snapshotname internal-snapshot-$guest-02| grep 'Current.*no'";
        assert_script_run "virsh snapshot-revert $guest --snapshotname internal-snapshot-$guest-02";
        assert_script_run "virsh snapshot-info $guest --snapshotname internal-snapshot-$guest-02| grep 'Current.*yes'";
        assert_script_run "virsh snapshot-info $guest --snapshotname internal-snapshot-$guest-01| grep 'Current.*no'";
        assert_script_run "virsh snapshot-list $guest --tree| grep internal-snapshot-$guest-01";

        record_info "virsh-snapshot", "Deleting Internal Snapshot";
        assert_script_run "virsh snapshot-delete $guest --snapshotname internal-snapshot-$guest-01";
        assert_script_run("! virsh snapshot-list $guest | grep internal-snapshot-$guest-01");
        assert_script_run "virsh snapshot-delete $guest --snapshotname internal-snapshot-$guest-02";
        assert_script_run("! virsh snapshot-list $guest | grep internal-snapshot-$guest-02");
    }
}

1;
