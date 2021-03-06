#
# Copyright 2010 Red Hat, Inc.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 3 of
# the License, or (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this software; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA, or see the FSF site: http://www.fsf.org.

require 'rubygems'
require 'boxgrinder-build/helpers/guestfs-helper'
require 'boxgrinder-core/helpers/exec-helper'
require 'boxgrinder-core/helpers/log-helper'

module BoxGrinder
  class ApplianceCustomizeHelper

    def initialize( config, appliance_config, disk, options = {} )
      @config           = config
      @appliance_config = appliance_config
      @disk             = disk

      @log          = options[:log]         || LogHelper.new
      @exec_helper  = options[:exec_helper] || ExecHelper.new( { :log => @log } )
    end

    def customize
      @guestfs_helper = GuestFSHelper.new( @disk, :log => @log ).run
      @guestfs = @guestfs_helper.guestfs

      yield @guestfs, @guestfs_helper

      @guestfs_helper.clean_close
    end
  end
end
