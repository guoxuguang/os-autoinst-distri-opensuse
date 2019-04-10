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

# Summary: Test VM snapshot using virsh (create - restore - delete)
# Maintainer: Leon Guo <xguo@suse.com>
 
use strict;
use warnings;
use testapi;
use base "virt_autotest_base";

sub run {

    my $guest = script_output("virsh list --all| sed -n 3p | awk {'print \$2'}");

    record_info "List", "Guest list";
    assert_script_run "virsh list --all | grep $guest";

    record_info "Create", "snapshot-create";
    assert_script_run "virsh snapshot-create-as --domain $guest";

    record_info "snapshot-list", "snapshot-list";
    assert_script_run "virsh snapshot-list --domain $guest";

    record_info "snapshot-info", "snapshot-info";
    assert_script_run "virsh snapshot-info --domain $guest --current";

    record_info "Revert", "snapshot-revert";
    assert_script_run "virsh snapshot-revert --domain $guest --current";
 
    record_info "snapshot-current", "snapshot-current";
    assert_script_run "virsh snapshot-current --domain $guest";

    record_info "Delete", "snapshot-delete";
    assert_script_run "virsh snapshot-delete --domain $guest --current";

    record_info "Check", "snapshot-list";
    assert_script_run "virsh snapshot-list --domain $guest";
}

1;

