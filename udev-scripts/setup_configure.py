#!/usr/bin/python

import re
import os
import sys
import socket
import logging
import traceback
import json
import xml.etree.ElementTree as ET
from glob import glob
from time import sleep
from itertools import chain
from argparse import ArgumentParser
from subprocess import check_call
from subprocess import check_output
from subprocess import CalledProcessError

NESTED_VM_DATA="/workspace/nested_data.json"


def runcmd(cmd):
    return check_call(cmd, shell=True)


def runcmd2(cmd):
    try:
        return check_call(cmd, shell=True)
    except CalledProcessError:
        return 1


def runcmd_output(cmd):
    return check_output(cmd, shell=True).decode()


def start_kmemleak():
    """Make sure kmemleak thread is running if supported. ignore errors."""
    if os.path.exists('/sys/kernel/debug/kmemleak'):
        scan=180
        print("Set kmemleak scan thread to %s seconds" % scan)
        runcmd("echo scan=%s > /sys/kernel/debug/kmemleak" % scan)
    else:
        print("kmemleak not supported")


class Host(object):
    def __init__(self, name):
        self.name = name
        self.PNics = []


class SetupConfigure(object):
    MLNXToolsPath = '/opt/mellanox/ethtool/sbin:/opt/mellanox/iproute2/sbin:/opt/verutils/bin/'

    def ParseArgs(self):
        parser = ArgumentParser(prog=self.__class__.__name__)
        parser.add_argument('--second-server', '-s', help='Second server config', action='store_true')
        parser.add_argument('--dpdk', help='Add DPDK=1 to configuration file', action='store_true')
        parser.add_argument('--sw-steering-mode', help='Configure software steering mode', action='store_true')
        parser.add_argument('--bluefield', help='Setup configuration for bluefield host', action='store_true')
        parser.add_argument('--vdpa', help='Setup configuration for vdpa host', action='store_true')
        parser.add_argument('--steering-mode', choices=['sw', 'fw'], help='Configure steering mode')
        parser.add_argument('--skip-kmemleak', help='Skip enabling kmemleak scan', action='store_true')

        self.args = parser.parse_args()

    def set_ovs_service(self):
        self.ID = ''
        try:
            with open("/etc/os-release", 'r') as f:
                for line in f.readlines():
                    line = line.strip().split('=')
                    if line[0] == 'ID':
                        self.ID = line[1].strip('"')
                        break
            # lsb_release lib doesnt always exists
            # self.is_ubuntu = lsb_release.get_os_release()['ID'].lower() == 'ubuntu'
        except:
            pass

        if self.ID:
            self.Logger.info(self.ID)

        if self.ID == 'ubuntu':
            self.ovs_service = "openvswitch-switch"
        else:
            self.ovs_service = "openvswitch"

    def Run(self):
        try:
            self.flow_steering_mode = None

            if not self.args.skip_kmemleak:
                start_kmemleak()
            self.set_ovs_service()
            self.StopOVS()
            self.ReloadModules()

            self.host = Host(socket.gethostbyname(socket.gethostname()))

            self.UpdatePATHEnvironmentVariable()

            self.LoadPFInfo()
            if not self.host.PNics:
                self.Logger.error("Cannot find PNics")
                return 1

            self.DestroyVFs()
            self.CreateVFs()
            self.LoadVFInfo()
            self.SetVFMACs()
            self.UnbindVFs()

            if not self.args.bluefield:
                self.ConfigureSteeringMode()
                self.ConfigureSwitchdev()
                self.LoadRepInfo()

            self.BringUpDevices()

            if self.args.dpdk or self.args.vdpa:
                self.configure_hugepages()

            self.ConfigureOVS()
            if self.args.bluefield:
                self.ConfigureBfOVS()
            self.BindVFs()
            self.UpdateVFInfo()

            if self.args.second_server:
                return

            self.CreateConfFile()

        except:
            self.Logger.error(str(traceback.format_exc()))
            return 1

        return 0

    def ReloadModules(self):
        self.Logger.info("Reload modules")
        # workaround because udev rules changed in jenkins script but didn't take affect
        runcmd2('modprobe -rq act_ct')
        runcmd2('modprobe -rq cls_flower')
        runcmd2('modprobe -rq mlx5_fpga_tools')
        runcmd2('modprobe -rq mlx5_vdpa')
        runcmd2('modprobe -rq mlx5_ib')
        runcmd2('modprobe -rq mlx5_core')
        runcmd2('modprobe -aq mlx5_ib mlx5_core')
        sleep(5)

    def UpdatePATHEnvironmentVariable(self):
        os.environ['PATH'] = self.MLNXToolsPath + os.pathsep + os.environ.get('PATH')
        with open('/etc/profile.d/zz_dev_reg_env.sh', 'w') as f:
            f.write('if [[ ! "$PATH" =~ "/opt/mellanox" ]]; then\n')
            f.write('    PATH="%s:$PATH"\n' % self.MLNXToolsPath)
            f.write('fi\n')

    def LoadPFInfo(self):
        pnics = []
        for net in sorted(glob('/sys/class/net/*')):
            device = os.path.join(net, 'device')

            if not os.path.exists(device):
                continue

            # if physfn exists its a VF
            if os.path.exists(os.path.join(device, 'physfn')):
                continue

            driver = os.path.basename(os.readlink(os.path.join(device, 'driver')))
            if 'mlx5' not in driver:
                continue

            bus = os.path.basename(os.readlink(device))
            if not bus:
                continue

            PFName = os.path.basename(net)

            port_name = self.get_port_name(PFName)
            if port_name and not re.match(r'p\d+', port_name):
                continue

            PFInfo = {
                      'vfs'    : [],
                      'sw_id'  : None,
                      'topoID' : None,
                      'name'   : PFName,
                      'bus'    : bus,
                     }

            self.Logger.info("Found PF %s", PFName)
            pnics.append(PFInfo)

        self.host.PNics = sorted(pnics, key=lambda k: k['bus'])

    def LoadVFInfo(self):
        for PFInfo in self.host.PNics:
            vfs = []
            for vfID in sorted(glob('/sys/class/net/%s/device/virtfn*/net/*' % PFInfo['name'])):
                nameOutput = os.path.basename(vfID)
                device = os.path.join(vfID, 'device')
                busOutput = os.path.basename(os.readlink(device))

                VFInfo = {
                            'rep'  : None,
                            'name' : nameOutput,
                            'bus'  : busOutput,
                        }

                self.Logger.info('PF %s VF %s', PFInfo['name'], nameOutput)
                vfs.append(VFInfo)

            PFInfo['vfs'] = sorted(vfs, key=lambda k: k['bus'])
            if len(PFInfo['vfs']) == 0:
                raise RuntimeError("Cannot find VFs for PF %s" % PFInfo['name'])

    def UpdateVFInfo(self):
        self.LoadVFInfo()
        if not self.args.bluefield:
            self.LoadRepInfo()

    def get_switch_id(self, port):
        try:
            with open('/sys/class/net/%s/phys_switch_id' % port, 'r') as f:
                sw_id = f.read().strip()
        except IOError:
            sw_id = ''
        return sw_id

    def get_port_name(self, port):
        try:
            with open('/sys/class/net/%s/phys_port_name' % port, 'r') as f:
                port_name = f.read().strip()
        except IOError:
            try:
                port_number = runcmd_output(
                    'devlink port show %s -j 2> /dev/null| jq .[][].port' % port).strip()

                if port_number != '':
                    port_name = 'p%s' % port_number
                else:
                    port_name = ''
            except CalledProcessError:
                port_name = ''

        return port_name

    def get_port_info(self, port):
        return (self.get_switch_id(port), self.get_port_name(port))

    def get_pf_info(self, sw_id, port_index):
        for PNic in self.host.PNics:
            if PNic['sw_id'] == sw_id and PNic['port_index'] == port_index:
                return PNic
        return None

    def LoadRepInfo(self):
        for PFInfo in self.host.PNics:
            (sw_id, port_name) = self.get_port_info(PFInfo['name'])

            if not sw_id or not port_name:
                raise RuntimeError('Failed get phys switch id or port name for %s' % PFInfo['name'])

            PFInfo['sw_id'] = sw_id
            PFInfo['port_index'] = int(re.search('p(\d+)', port_name).group(1))

        devinfos = []
        for pnic in self.host.PNics:
            devinfos.append(pnic['name'])
            devinfos += [vf['name'] for vf in pnic['vfs']]

        for net in sorted(glob('/sys/class/net/*')):
            repName = os.path.basename(net)
            if repName in devinfos:
                continue

            (sw_id, port_name) = self.get_port_info(repName)
            if not sw_id or not port_name:
                continue

            self.Logger.info("Load rep info rep %s", repName)
            pfIndex = int(re.search('pf(\d+)vf\d+', port_name).group(1)) & 0x7
            vfIndex = int(re.search('(?:pf\d+vf)?(\d+)', port_name).group(1))
            PFInfo = self.get_pf_info(sw_id, pfIndex)
            if not PFInfo:
                continue

            if vfIndex >= len(PFInfo['vfs']):
                raise RuntimeError("Cannot find relevant VF for rep %s" % repName)

            PFInfo['vfs'][vfIndex]['rep'] = repName

    def DestroyVFs(self):
        for PFInfo in self.host.PNics:
            if not os.path.exists("/sys/class/net/%s/device/sriov_numvfs" % PFInfo['name']):
                continue
            self.Logger.info('Destroying VFs over %s' % PFInfo['name'])
            runcmd('echo 0 > /sys/class/net/%s/device/sriov_numvfs' % PFInfo['name'])
            sleep(2)

    def CreateVFs(self):
        for PFInfo in self.host.PNics:
            self.Logger.info('Creating 2 VFs over %s' % PFInfo['name'])
            runcmd('echo 2 > /sys/class/net/%s/device/sriov_numvfs' % PFInfo['name'])
            sleep(2)

    def SetVFMACs(self):
        for PFInfo in self.host.PNics:
            for VFInfo in PFInfo['vfs']:
                splitedBus = [int(x, 16) for x in VFInfo['bus'].replace('.', ':').split(':')[1:]]
                splitedIP = [int(x) for x in self.host.name.split('.')[-2:]]
                VFInfo['mac'] = 'e4:%02x:%02x:%02x:%02x:%02x' % tuple(splitedIP + splitedBus)
                vfIndex = PFInfo['vfs'].index(VFInfo)
                self.Logger.info('Setting MAC %s on %s vf %d (bus %s)' % (VFInfo['mac'], PFInfo['name'], vfIndex, VFInfo['bus']))
                command = 'ip link set %s vf %d mac %s' % (PFInfo['name'], vfIndex, VFInfo['mac'])
                runcmd(command)

    def UnbindVFs(self):
        for PFInfo in self.host.PNics:
            for VFBus in map(lambda VFInfo: VFInfo['bus'], PFInfo['vfs']):
                self.Logger.info('Unbind %s' % VFBus)
                runcmd2('echo %s > /sys/bus/pci/drivers/mlx5_core/unbind' % VFBus)

    @property
    def req_flow_steering_mode(self):
        if self.args.sw_steering_mode:
            return 'smfs'

        if not self.args.steering_mode:
            return None

        if self.args.steering_mode == 'sw':
            mode = 'smfs'
        elif self.args.steering_mode == 'fw':
            mode = 'dmfs'
        else:
            raise RuntimeError('Invalid steering mode %s' % self.args.steering_mode)

        return mode

    def get_steering_mode(self, PFInfo=None):
        if not PFInfo:
            PFInfo = self.host.PNics[0]

        sysfs = '/sys/class/net/%s/compat/devlink/steering_mode' % PFInfo['name']
        if os.path.exists(sysfs):
            with open(sysfs) as f:
                return f.read().strip()

        try:
            out = runcmd_output('devlink -j dev param show pci/%s name flow_steering_mode | jq -r ".[][][].values[].value"' % PFInfo['bus']).strip()
        except CalledProcessError:
            return None

        return out

    def set_steering_mode(self, PFInfo, mode):
        if os.path.exists('/sys/class/net/%s/compat/devlink/steering_mode' % PFInfo['name']):
            runcmd_output("echo %s > /sys/class/net/%s/compat/devlink/steering_mode" % (mode, PFInfo['name']))
            return

        # try to set the mode only if kernel supports flow_steering_mode parameter
        try:
            runcmd_output('devlink dev param set pci/%s name flow_steering_mode value "%s" cmode runtime' % (PFInfo['bus'], mode))
        except CalledProcessError:
            self.Logger.warning("The kernel does not support devlink flow_steering_mode param. Skipping.")

    def ConfigureSteeringMode(self):
        self.flow_steering_mode = self.get_steering_mode()
        if not self.flow_steering_mode:
            self.Logger.warning("Failed to get flow steering mode.")
            return

        self.Logger.info("Current steering mode is %s" % self.flow_steering_mode)

        mode = self.req_flow_steering_mode
        if not mode:
            return

        for PFInfo in self.host.PNics:
            self.Logger.info("Setting %s steering mode to %s" % (PFInfo['name'], mode))
            self.set_steering_mode(PFInfo, mode)

        self.flow_steering_mode = self.get_steering_mode()

    def ConfigureSwitchdev(self):
        for PFInfo in self.host.PNics:
            self.Logger.info("Changing %s to switchdev mode" % (PFInfo['name']))

            if os.path.exists('/sys/class/net/%s/compat/devlink/mode' % PFInfo['name']):
                cmd = "echo switchdev > /sys/class/net/%s/compat/devlink/mode" % PFInfo['name']
            elif os.path.exists('/sys/kernel/debug/mlx5/%s/compat/mode' % PFInfo['bus']):
                cmd = "echo switchdev > /sys/kernel/debug/mlx5/%s/compat/mode" % PFInfo['bus']
            else:
                cmd = "devlink dev eswitch set pci/%s mode switchdev" % PFInfo['bus']

            runcmd_output(cmd)

        sleep(5)

    def StopOVS(self):
        runcmd_output("systemctl stop %s" % self.ovs_service)

    def RestartOVS(self):
        runcmd_output("systemctl restart %s" % self.ovs_service)

    def ConfigureOVS(self):
        self.Logger.info("Setting [hw-offload=true] configuration to OVS" )
        self.RestartOVS()
        runcmd_output('ovs-vsctl set Open_vSwitch . other_config:hw-offload=true')
        self.RestartOVS()

    def ConfigureBfOVS(self):
        self.Logger.info("Setting [hw-offload=true] configuration to BF OVS")
        bf_ip, _ = self.get_cloud_player_bf_ips()
        runcmd_output('ssh %s "systemctl restart openvswitch-switch;'
                      'ovs-vsctl set Open_vSwitch . other_config:hw-offload=true;'
                      'systemctl restart openvswitch-switch;"' % bf_ip)

    def get_reps(self):
        reps = []
        for PFInfo in self.host.PNics:
            reps.append(PFInfo['name'])
            for VFInfo in PFInfo['vfs']:
                if VFInfo['rep']:
                    reps.append(VFInfo['rep'])
        return reps

    def BringUpDevices(self):
        self.Logger.info("Bring up devices")
        reps = self.get_reps()
        for devName in reps:
            runcmd2('ethtool -K %s hw-tc-offload on' % devName)
            runcmd2('ip link set dev %s up' % devName)

    def BindVFs(self):
        for VFInfo in chain.from_iterable(map(lambda PFInfo: PFInfo['vfs'], self.host.PNics)):
            self.Logger.info("Binding %s" % VFInfo['bus'])
            runcmd2('echo %s > /sys/bus/pci/drivers/mlx5_core/bind' % VFInfo['bus'])
        # might need a second to let udev rename
        sleep(1)

    def get_nested_vm_data(self):
        try:
            with open(NESTED_VM_DATA) as json_file:
                return json.load(json_file)
        except IOError:
            self.Logger.error('Failed to read %s' % path)
            raise RuntimeError('Failed to read %s ' % path)

    def findTagIndex(self, tree, tag):
        i = 0
        for child in tree.iter():
            i += 1
            if (child.tag == tag):
                return i
        return -1

    def getLastIndex(self, devices, tag):
        count = 0
        found = False
        for child in devices:
            count += 1
            if (child.tag == tag):
                found = True
            elif (found == True):
                return count - 1
        return -1

    def set_sysconfig_openvswitch_user(self):
        runcmd2("sed -i '/OVS_USER_ID=\"openvswitch:hugetlbfs\"/c\OVS_USER_ID=\"root:root\"' /etc/sysconfig/openvswitch")

    def vdpa_vm_init(self, vm_num, vm_name):
        nic1 = self.host.PNics[0]
        orig_xml_file="/tmp/orig_vm%s.xml" % vm_num
        xml_file = '/tmp/vdpa_vm%s.xml' % vm_num

        if os.path.exists(xml_file):
            # assume we already defined vdpa into the vm
            self.Logger.info("vdpa vm %s already configured" % vm_name)
            return

        runcmd_output("virsh dumpxml %s > %s" % (vm_name, xml_file))
        runcmd_output("cp %s %s" % (xml_file, orig_xml_file))
        runcmd2("virsh destroy %s &> /dev/null" % vm_name)

        tree = ET.parse(xml_file)
        root = tree.getroot()

        # Add memoryBack block
        memBack=ET.Element('memoryBacking')
        HugePages = ET.SubElement(memBack, 'hugepages')
        memIndex = self.findTagIndex(root, 'memory')
        root.insert(memIndex, memBack)

        # Modify cpu block
        cpu = root.find('cpu')
        cpuAttrib = cpu.attrib.copy()
        for attrib in cpuAttrib:
            cpu.attrib.pop(attrib)
        cpu.set('match','exact')
        cpu.set('mode','custom')
        cpu.set('check','full')
        cpuNuma = ET.SubElement(cpu, 'numa')
        cpuNumaSubElem = ET.SubElement(cpuNuma, 'cell', id='0', cpus='0-1', memory='2097152', unit='KiB', memAccess='shared')

        # Add vdpa interface
        devices = root.find('devices')
        sock_path = '/tmp/sock%s' % vm_num
        idx = self.getLastIndex(devices, 'interface')
        interface = ET.Element('interface', type='vhostuser')
        interfaceSource = ET.SubElement(interface, 'source', type='unix', path=sock_path, mode='server')
        interfaceModel = ET.SubElement(interface, 'model', type='virtio')
        devices.insert(idx, interface)

        out = ET.ElementTree(root)
        out.write(xml_file)
        runcmd_output("virsh define %s &> /dev/null" % xml_file)
        self.Logger.info("Initialized VM %s XML under %s", vm_name, xml_file)

    def get_cloud_player_vm(self, vm_num):
        data = self.get_nested_vm_data()
        i = 1
        for vm in data:
            if vm['parent_ip'] == self.host.name:
                if i == vm_num:
                    return vm
                i += 1
        return None

    def get_cloud_player_ip(self):
        cloud_player_1_ip = ''
        cloud_player_2_ip = ''
        try:
            with open('/workspace/cloud_tools/.setup_info', 'r') as f:
                for line in f.readlines():
                    if 'CLOUD_PLAYER_1_IP' in line:
                        cloud_player_1_ip = line.strip().split('=')[1]
                    if 'CLOUD_PLAYER_2_IP' in line:
                        cloud_player_2_ip = line.strip().split('=')[1]
        except IOError:
            self.Logger.error('Failed to read cloud_tools/.setup_info')

        if cloud_player_2_ip == self.host.name:
            cloud_player_ip = cloud_player_1_ip
        else:
            cloud_player_ip = cloud_player_2_ip

        return cloud_player_ip

    def get_cloud_player_bf_ips(self):
        cloud_player_1_ip = ''
        cloud_player_1_bf_ip = ''
        cloud_player_2_bf_ip = ''
        try:
            with open('/workspace/cloud_tools/.setup_info', 'r') as f:
                for line in f.readlines():
                    if 'CLOUD_PLAYER_1_IP' in line:
                        cloud_player_1_ip = line.strip().split('=')[1]
                    if 'CLOUD_PLAYER_1_ARM_IP' in line:
                        cloud_player_1_bf_ip = line.strip().split('=')[1]
                    if 'CLOUD_PLAYER_2_ARM_IP' in line:
                        cloud_player_2_bf_ip = line.strip().split('=')[1]
        except IOError:
            self.Logger.error('Failed to read cloud_tools/.setup_info')
            raise RuntimeError('Failed to read cloud_tools/.setup_info')

        if cloud_player_1_ip == self.host.name:
            return cloud_player_1_bf_ip, cloud_player_2_bf_ip

        return cloud_player_2_bf_ip, cloud_player_1_bf_ip

    def CreateConfFile(self):
        conf = 'PATH="%s:$PATH"' % self.MLNXToolsPath

        nic1 = self.host.PNics[0]
        rep = nic1['vfs'][0]['rep']
        rep2 = nic1['vfs'][1]['rep']

        if self.args.bluefield:
            rep = "eth2"
            rep2 = "eth3"

        if not rep or not rep2:
            raise RuntimeError('Cannot find representors')

        conf += '\nNIC=%s' % nic1['name']
        conf += '\nVF=%s' % nic1['vfs'][0]['name']
        conf += '\nVF1=%s' % nic1['vfs'][0]['name']
        conf += '\nVF2=%s' % nic1['vfs'][1]['name']
        conf += '\nREP=%s' % rep
        conf += '\nREP2=%s' % rep2
        conf += '\nREMOTE_NIC=%s' % nic1['name']
        conf += '\nB2B=1'

        # rest of the nics
        i = 2
        for nic in self.host.PNics[1:]:
            conf += '\nNIC%d=%s' % (i, nic['name'])
            conf += '\nREMOTE_NIC%d=%s' % (i, nic['name'])
            i += 1

        conf += '\nREMOTE_SERVER=%s' % self.get_cloud_player_ip()

        if os.path.exists(NESTED_VM_DATA):
            vm1 = self.get_cloud_player_vm(1)
            vm2 = self.get_cloud_player_vm(2)
            conf += '\nNESTED_VM_IP1=%s' % vm1['ip']
            conf += '\nNESTED_VM_IP2=%s' % vm2['ip']
            conf += '\nNESTED_VM_NAME1=%s' % vm1['domain_name']
            conf += '\nNESTED_VM_NAME2=%s' % vm2['domain_name']

            if self.args.vdpa:
                conf += '\nVDPA=1'
                self.set_sysconfig_openvswitch_user()
                self.vdpa_vm_init(1, vm1['domain_name'])
                self.vdpa_vm_init(2, vm2['domain_name'])

        if self.flow_steering_mode:
            conf += '\nSTEERING_MODE=%s' % self.flow_steering_mode

        if self.args.dpdk:
            conf += '\nDPDK=1'

        if self.args.bluefield:
            conf += '\nBF_NIC=%s' % "enp3s0f0np0"
            conf += '\nBF_HOST_NIC=%s' % "eth0"
            conf += '\nBF_IP=%s\nREMOTE_BF_IP=%s' % self.get_cloud_player_bf_ips()

        config_file = "/workspace/dev_reg_conf.sh"
        self.Logger.info("Create config file %s" % config_file)
        with open(config_file, 'w+') as f:
            f.write(conf)
        # just for easy copy paste
        self.Logger.info("export CONFIG=%s" % config_file)

    def configure_hugepages(self):
        if self.args.vdpa:
            nr_hugepages = 4096
        else:
            nr_hugepages = 2048
        self.Logger.info("Allocating %s hugepages", nr_hugepages)
        runcmd('echo %s > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages' % nr_hugepages)

    @property
    def Logger(self):
        if not hasattr(self, 'logger'):
            self.logger = logging
            self.logger.getLogger().setLevel(logging.INFO)
            self.logger.basicConfig(format='%(levelname)-7s: %(message)s')

        return self.logger


if __name__ == "__main__":
    setupConfigure = SetupConfigure()
    setupConfigure.ParseArgs()
    sys.exit(setupConfigure.Run())
