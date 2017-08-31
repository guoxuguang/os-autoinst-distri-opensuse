# Copyright (C) 2017 SUSE LLC
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

# Summary: Test module is used to accept license during SLE 15 installation
#          Should be improved to be more product specific
# Maintainer: Rodion Iafarov <riafarov@suse.com>

use strict;
use base "y2logsstep";
use testapi;

sub run {
    my ($self) = @_;
    assert_screen 'license-agreement';
    $self->verify_license_has_to_be_accepted;
    send_key $cmd{next};
}

1;
# vim: set sw=4 et:
