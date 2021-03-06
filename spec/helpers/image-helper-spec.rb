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

require 'boxgrinder-build/helpers/image-helper'

module BoxGrinder
  describe ImageHelper do

    before(:each) do
      @config = mock('Config')

      @appliance_config = mock('ApplianceConfig')

      @appliance_config.stub!(:name).and_return('full')
      @appliance_config.stub!(:os).and_return(OpenCascade.new({:name => 'fedora', :version => '14'}))
      @appliance_config.stub!(:hardware).and_return(
          OpenCascade.new({
                              :partitions =>
                                  {
                                      '/' => {'size' => 2, 'type' => 'ext4'},
                                      '/home' => {'size' => 3, 'type' => 'ext3'},
                                  },
                              :arch => 'i686',
                              :base_arch => 'i386',
                              :cpus => 1,
                              :memory => 256,
                          })
      )

      @helper = ImageHelper.new(@config, @appliance_config, :log => Logger.new('/dev/null'))

      @log = @helper.instance_variable_get(:@log)
      @exec_helper = @helper.instance_variable_get(:@exec_helper)
    end

    it "should mount image with one root partition" do
      @helper.should_receive(:calculate_disk_offsets).with('disk.raw').and_return(['0'])
      FileUtils.should_receive(:mkdir_p).with('mount_dir')
      @helper.should_receive(:get_loop_device).and_return('/dev/loop0')
      @exec_helper.should_receive(:execute).with("losetup -o 0 /dev/loop0 'disk.raw'")
      @exec_helper.should_receive(:execute).with('e2label /dev/loop0').and_return('/')
      @exec_helper.should_receive(:execute).with("mount /dev/loop0 'mount_dir'")
      @helper.should_receive(:sleep).with(2)

      @helper.mount_image('disk.raw', 'mount_dir').should == {"/"=>"/dev/loop0"}
    end

    it "should mount image with two partitions with support for new livecd-tools partitions labels starting with '_'" do
      @helper.should_receive(:calculate_disk_offsets).with('disk.raw').and_return(['322', '562'])
      FileUtils.should_receive(:mkdir_p).with('mount_dir')
      @helper.should_receive(:get_loop_device).and_return('/dev/loop0')
      @exec_helper.should_receive(:execute).with("losetup -o 322 /dev/loop0 'disk.raw'")
      @exec_helper.should_receive(:execute).with('e2label /dev/loop0').and_return('_/home')
      @helper.should_receive(:get_loop_device).and_return('/dev/loop1')
      @exec_helper.should_receive(:execute).with("losetup -o 562 /dev/loop1 'disk.raw'")
      @exec_helper.should_receive(:execute).with('e2label /dev/loop1').and_return('_/')

      @exec_helper.should_receive(:execute).with("mount /dev/loop1 'mount_dir'")
      @exec_helper.should_receive(:execute).with("mount /dev/loop0 'mount_dir/home'")
      @helper.should_receive(:sleep).with(2)

      @helper.mount_image('disk.raw', 'mount_dir').should == {"/"=>"/dev/loop1", "/home"=>"/dev/loop0"}
    end

    it "should umount the image" do
      @exec_helper.should_receive(:execute).ordered.with('umount -d /dev/loop0')
      @exec_helper.should_receive(:execute).ordered.with('umount -d /dev/loop1')
      FileUtils.should_receive(:rm_rf).with('mount_dir')

      @helper.should_receive(:sleep).with(2)

      @helper.umount_image('disk.raw', 'mount_dir', {"/"=>"/dev/loop1", "/home"=>"/dev/loop0"})
    end

    it "should get free loop device" do
      @exec_helper.should_receive(:execute).with('losetup -f 2>&1').and_return("/dev/loop0\n")

      @helper.get_loop_device.should == '/dev/loop0'
    end

    it "shouldn't get free loop device because there are no free loop devices left" do
      @exec_helper.should_receive(:execute).with('losetup -f 2>&1').and_raise('boom')

      begin
        @helper.get_loop_device
        raise "Shouldn't raise"
      rescue => e
        e.message.should == "No free loop devices available, please free at least one. See 'losetup -d' command."
      end
    end

    it "should calculate disks offsets" do
      @helper.should_receive(:get_loop_device).and_return('/dev/loop0')
      @exec_helper.should_receive(:execute).ordered.with("losetup /dev/loop0 'disk.raw'")
      @exec_helper.should_receive(:execute).ordered.with("parted /dev/loop0 'unit B print' | grep -e '^ [0-9]' | awk '{ print $2 }'").and_return("0B\n1234B\n")
      @exec_helper.should_receive(:execute).ordered.with('losetup -d /dev/loop0')
      @helper.should_receive(:sleep).with(1)

      @helper.calculate_disk_offsets('disk.raw').should == ["0", "1234"]
    end

    it "should create a new empty disk image" do
      @exec_helper.should_receive(:execute).with("dd if=/dev/zero of='disk.raw' bs=1 count=0 seek=10240M")

      @helper.create_disk('disk.raw', 10)
    end

    describe ".create_filesystem" do

      it "should create default filesystem on selected device" do
        @exec_helper.should_receive(:execute).with("mke2fs -T ext4 -L '/' -F /dev/loop0")

        @helper.create_filesystem('/dev/loop0')
      end

      it "should create ext4 filesystem on selected device" do
        @appliance_config.should_receive(:hardware).and_return(
            OpenCascade.new({
                                :partitions =>
                                    {
                                        '/' => {'size' => 2, 'type' => 'ext3'},
                                        '/home' => {'size' => 3, 'type' => 'ext3'},
                                    },
                                :arch => 'i686',
                                :base_arch => 'i386',
                                :cpus => 1,
                                :memory => 256,
                            })
        )

        @exec_helper.should_receive(:execute).with("mke2fs -T ext3 -L '/' -F /dev/loop0")

        @helper.create_filesystem('/dev/loop0')
      end

      it "should create ext4 filesystem on selected device with a label" do
        @exec_helper.should_receive(:execute).with("mke2fs -T ext4 -L '/home' -F /dev/loop0")

        @helper.create_filesystem('/dev/loop0', :type => 'ext4', :label => '/home')
      end

      it "should create ext4 filesystem on selected device with a label" do
        lambda {
          @helper.create_filesystem('/dev/loop0', :type => 'ext256', :label => '/home')
        }.should raise_error(RuntimeError, "Unsupported filesystem specified: ext256")
      end
    end

    describe ".sync_files" do
      it "should sync files" do
        @exec_helper.should_receive(:execute).with("rsync -Xura from_dir/* 'to_dir'")
        @helper.sync_files('from_dir', 'to_dir')
      end

      it "should sync files with a space in path" do
        @exec_helper.should_receive(:execute).with("rsync -Xura from\\ /dir/* 'to_dir'")
        @helper.sync_files('from /dir', 'to_dir')
      end
    end

    describe ".customize" do
      it "should customize the disk image using GuestFS" do
        guestfs = mock('GuestFS')
        guestfs.should_receive(:abc)

        guestfs_helper = mock(GuestFSHelper)
        guestfs_helper.should_receive(:customize).with(:ide_disk => false).ordered.and_yield(guestfs, guestfs_helper)
        guestfs_helper.should_receive(:def)

        GuestFSHelper.should_receive(:new).with('disk.raw', :log => @log).and_return(guestfs_helper)

        @helper.customize('disk.raw') do |guestfs, guestfs_helper|
          guestfs.abc
          guestfs_helper.def
        end
      end

      it "should customize the disk image using GuestFS and selectind ide_disk option for RHEL/CentOS 5" do
        @appliance_config.stub!(:os).and_return(OpenCascade.new({:name => 'rhel', :version => '5'}))

        guestfs = mock('GuestFS')
        guestfs.should_receive(:abc)

        guestfs_helper = mock(GuestFSHelper)
        guestfs_helper.should_receive(:customize).with(:ide_disk => true).ordered.and_yield(guestfs, guestfs_helper)
        guestfs_helper.should_receive(:def)

        GuestFSHelper.should_receive(:new).with('disk.raw', :log => @log).and_return(guestfs_helper)

        @helper.customize('disk.raw') do |guestfs, guestfs_helper|
          guestfs.abc
          guestfs_helper.def
        end
      end
    end

    describe ".convert_disk" do
      it "should not convert the disk because it's in RAW format already" do
        @exec_helper.should_receive(:execute).with("qemu-img info 'a/disk'").and_return("image: build/appliances/x86_64/fedora/13/f13-basic/fedora-plugin/f13-basic-sda.qcow2\nfile format: raw\nvirtual size: 2.0G (2147483648 bytes)\ndisk size: 531M\ncluster_size: 65536")
        @exec_helper.should_receive(:execute).with("cp 'a/disk' 'destination'")
        @helper.convert_disk('a/disk', :raw, 'destination')
      end

      it "should convert disk from vmdk to RAW format" do
        @exec_helper.should_receive(:execute).with("qemu-img info 'a/disk'").and_return("image: build/appliances/x86_64/fedora/13/f13-basic/fedora-plugin/f13-basic-sda.vmdk\nfile format: vmdk\nvirtual size: 2.0G (2147483648 bytes)\ndisk size: 531M\ncluster_size: 65536")
        @exec_helper.should_receive(:execute).with("qemu-img convert -f vmdk -O raw 'a/disk' 'destination'")
        @helper.convert_disk('a/disk', :raw, 'destination')
      end

      it "should convert disk from raw to vmdk format using old qemu-img" do
        @exec_helper.should_receive(:execute).with("qemu-img info 'a/disk'").and_return("image: build/appliances/x86_64/fedora/13/f13-basic/fedora-plugin/f13-basic-sda.vmdk\nfile format: raw\nvirtual size: 2.0G (2147483648 bytes)\ndisk size: 531M\ncluster_size: 65536")
        @helper.should_receive(:`).with("qemu-img --help | grep '\\-6'").and_return('something')

        @exec_helper.should_receive(:execute).with("qemu-img convert -f raw -O vmdk -6 'a/disk' 'destination'")
        @helper.convert_disk('a/disk', :vmdk, 'destination')
      end

      it "should convert disk from raw to vmdk format using new qemu-img" do
        @exec_helper.should_receive(:execute).with("qemu-img info 'a/disk'").and_return("image: build/appliances/x86_64/fedora/13/f13-basic/fedora-plugin/f13-basic-sda.vmdk\nfile format: raw\nvirtual size: 2.0G (2147483648 bytes)\ndisk size: 531M\ncluster_size: 65536")
        @helper.should_receive(:`).with("qemu-img --help | grep '\\-6'").and_return('')

        @exec_helper.should_receive(:execute).with("qemu-img convert -f raw -O vmdk -o compat6 'a/disk' 'destination'")
        @helper.convert_disk('a/disk', :vmdk, 'destination')
      end

      it "should do nothing because destination already exists" do
        File.should_receive(:exists?).with('destination').and_return(true)
        @helper.convert_disk('a/disk', :vmdk, 'destination')
      end
    end
  end
end

